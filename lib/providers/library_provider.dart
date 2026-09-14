import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/cloud/cloud_parser.dart';
import '../../core/storage/db_helper.dart';
import '../../models/track.dart';

class SyncResult {
  final int totalCloudTracks;
  final int addedTracks;
  final int removedTracks;

  SyncResult({
    required this.totalCloudTracks,
    required this.addedTracks,
    required this.removedTracks,
  });
}

class LibraryState {
  final List<Track> tracks;
  final bool isLoading;
  final String? errorMessage;
  final int? ratingFilter; // null = all, 0 = unrated, 1..5 = specific stars
  final String searchQuery;
  final int oneStarCount;
  final String? activeCloudUrl;
  final int? lastCloudCheckCount;
  final DateTime? lastSyncedAt;

  LibraryState({
    this.tracks = const [],
    this.isLoading = false,
    this.errorMessage,
    this.ratingFilter,
    this.searchQuery = '',
    this.oneStarCount = 0,
    this.activeCloudUrl,
    this.lastCloudCheckCount,
    this.lastSyncedAt,
  });

  List<Track> get filteredTracks {
    return tracks.where((track) {
      if (ratingFilter != null) {
        if (ratingFilter == 0 && track.rating != 0) return false;
        if (ratingFilter! > 0 && track.rating != ratingFilter) return false;
      }
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final matchTitle = track.title.toLowerCase().contains(query);
        final matchArtist = track.artist.toLowerCase().contains(query);
        if (!matchTitle && !matchArtist) return false;
      }
      return true;
    }).toList();
  }

  LibraryState copyWith({
    List<Track>? tracks,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    int? ratingFilter,
    bool clearRatingFilter = false,
    String? searchQuery,
    int? oneStarCount,
    String? activeCloudUrl,
    int? lastCloudCheckCount,
    DateTime? lastSyncedAt,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      ratingFilter: clearRatingFilter ? null : (ratingFilter ?? this.ratingFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      oneStarCount: oneStarCount ?? this.oneStarCount,
      activeCloudUrl: activeCloudUrl ?? this.activeCloudUrl,
      lastCloudCheckCount: lastCloudCheckCount ?? this.lastCloudCheckCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier() : super(LibraryState()) {
    _initCloudFolder();
    loadTracks();
  }

  Future<void> _initCloudFolder() async {
    try {
      final folders = await DBHelper.instance.getSavedFolders();
      if (folders.isNotEmpty) {
        final f = folders.first;
        final url = f['url'] as String?;
        final count = (f['trackCount'] as num?)?.toInt();
        final syncedStr = f['lastSyncedAt'] as String?;
        state = state.copyWith(
          activeCloudUrl: url,
          lastCloudCheckCount: count,
          lastSyncedAt: syncedStr != null ? DateTime.tryParse(syncedStr) : null,
        );
      }
    } catch (_) {}
  }

  Future<void> loadTracks() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await DBHelper.instance.purgeDemoTracks();
      final tracks = await DBHelper.instance.getAllTracks();

      final syncedTracks = <Track>[];
      for (final t in tracks) {
        if (t.isCached && t.localCachePath != null && t.fileSize == 0) {
          try {
            final f = File(t.localCachePath!);
            if (f.existsSync()) {
              final sz = f.lengthSync();
              if (sz > 0) {
                await DBHelper.instance.updateFileSize(t.id, sz);
                syncedTracks.add(t.copyWith(fileSize: sz));
                continue;
              }
            }
          } catch (_) {}
        }
        syncedTracks.add(t);
      }

      final oneStarCount = await DBHelper.instance.getOneStarCount();
      state = state.copyWith(
        tracks: syncedTracks,
        isLoading: false,
        oneStarCount: oneStarCount,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Ошибка загрузки: $e');
    }
  }

  void setRatingFilter(int? rating) {
    if (rating == null) {
      state = state.copyWith(clearRatingFilter: true);
    } else {
      state = state.copyWith(ratingFilter: rating);
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Checks the exact count of audio tracks in a cloud folder without modifying the DB
  Future<int> checkCloudFolderCount(String url) async {
    final parsedTracks = await CloudParser.parsePublicUrl(url);
    state = state.copyWith(lastCloudCheckCount: parsedTracks.length);
    return parsedTracks.length;
  }

  /// Imports from cloud URL or synchronizes additions and deletions
  Future<SyncResult> syncWithCloud({String? folderUrl}) async {
    final targetUrl = folderUrl ?? state.activeCloudUrl;
    if (targetUrl == null || targetUrl.trim().isEmpty) {
      throw Exception('Нет сохраненной ссылки на облако для синхронизации');
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cloudTracks = await CloudParser.parsePublicUrl(targetUrl.trim());
      final existingTracks = await DBHelper.instance.getAllTracks();
      final existingMap = {for (final t in existingTracks) t.id: t};

      // 1. Identify new tracks (preserve rating and cache for existing ones)
      int addedCount = 0;
      final tracksToSave = <Track>[];
      final cloudIds = <String>{};

      for (final ct in cloudTracks) {
        cloudIds.add(ct.id);
        if (existingMap.containsKey(ct.id)) {
          // Keep existing ratings and local cache path
          final existing = existingMap[ct.id]!;
          tracksToSave.add(
            ct.copyWith(
              rating: existing.rating,
              localCachePath: existing.localCachePath,
            ),
          );
        } else {
          tracksToSave.add(ct);
          addedCount++;
        }
      }

      // 2. Identify removed tracks (belonged to this cloud source but not in cloud anymore)
      int removedCount = 0;
      final removedIds = <String>[];
      for (final et in existingTracks) {
        final isFromThisCloud = et.sourceType == 'google_drive' ||
            et.cloudPath.contains('gdrive://') ||
            et.sourceType == 'yandex_public';

        if (isFromThisCloud && !cloudIds.contains(et.id)) {
          removedIds.add(et.id);
          removedCount++;
          // Delete cached file if present
          if (et.localCachePath != null && et.localCachePath!.isNotEmpty) {
            try {
              final f = File(et.localCachePath!);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        }
      }

      // Apply DB operations
      for (final rId in removedIds) {
        await DBHelper.instance.deleteTrack(rId);
      }
      AudioManager.instance.removeTracks(removedIds);

      for (final t in tracksToSave) {
        await DBHelper.instance.insertOrUpdateTrack(t);
      }

      final now = DateTime.now();
      await DBHelper.instance.savePublicFolder(targetUrl, 'Облачная папка', cloudTracks.length);

      state = state.copyWith(
        activeCloudUrl: targetUrl,
        lastCloudCheckCount: cloudTracks.length,
        lastSyncedAt: now,
      );

      await loadTracks();

      return SyncResult(
        totalCloudTracks: cloudTracks.length,
        addedTracks: addedCount,
        removedTracks: removedCount,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<int> importFromPublicUrl(String url) async {
    final result = await syncWithCloud(folderUrl: url);
    return result.totalCloudTracks;
  }

  Future<int> importLocalAudioFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'flac', 'wav', 'ogg', 'aac'],
      allowMultiple: true,
    );

    if (result.isEmpty) return 0;

    state = state.copyWith(isLoading: true);
    final tracks = <Track>[];

    for (final file in result) {
      if (file.path != null) {
        final f = File(file.path!);
        final parsed = await CloudParser.scanLocalDirectory(f.parent);
        final matching = parsed.where((t) => t.localCachePath == file.path).toList();
        if (matching.isNotEmpty) {
          tracks.add(matching.first);
        }
      }
    }

    if (tracks.isNotEmpty) {
      await DBHelper.instance.insertTracks(tracks);
      await loadTracks();
    } else {
      state = state.copyWith(isLoading: false);
    }

    return tracks.length;
  }

  Future<void> updateTrackRating(Track track, int rating) async {
    await AudioManager.instance.updateTrackRating(track, rating);
    final updatedTracks = state.tracks.map((t) {
      return t.id == track.id ? t.copyWith(rating: rating) : t;
    }).toList();
    final oneStarCount = await DBHelper.instance.getOneStarCount();
    state = state.copyWith(tracks: updatedTracks, oneStarCount: oneStarCount);
  }

  Future<void> toggleCache(Track track) async {
    if (track.isCached) {
      await AudioManager.instance.deleteTrackCache(track);
    } else {
      await AudioManager.instance.downloadTrack(track);
    }
    await loadTracks();
  }

  /// Delete all tracks with 1 star (both from DB and local cache)
  Future<int> deleteOneStarTracks() async {
    state = state.copyWith(isLoading: true);
    try {
      final deleted = await DBHelper.instance.deleteOneStarTracks();
      final deletedIds = deleted.map((t) => t.id).toList();

      for (final t in deleted) {
        if (t.localCachePath != null && t.localCachePath!.isNotEmpty) {
          try {
            final f = File(t.localCachePath!);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }

      AudioManager.instance.removeTracks(deletedIds);
      await loadTracks();
      return deleted.length;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Ошибка удаления: $e');
      return 0;
    }
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier();
});
