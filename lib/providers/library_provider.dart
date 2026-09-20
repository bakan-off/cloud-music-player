import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/cloud/cloud_parser.dart';
import '../../core/storage/db_helper.dart';
import '../../models/track.dart';

enum TrackSortOption {
  dateAddedDesc, // Сначала новые
  dateAddedAsc,  // Сначала старые
  titleAsc,      // По названию (А → Я)
  titleDesc,     // По названию (Я → А)
  artistAsc,     // По исполнителю (А → Я)
  ratingDesc,    // По рейтингу (сначала 5★)
  durationDesc,  // По длительности
}

extension TrackSortOptionExtension on TrackSortOption {
  String get label {
    switch (this) {
      case TrackSortOption.dateAddedDesc:
        return 'Сначала новые';
      case TrackSortOption.dateAddedAsc:
        return 'Сначала старые';
      case TrackSortOption.titleAsc:
        return 'По названию (А → Я)';
      case TrackSortOption.titleDesc:
        return 'По названию (Я → А)';
      case TrackSortOption.artistAsc:
        return 'По исполнителю (А → Я)';
      case TrackSortOption.ratingDesc:
        return 'По рейтингу (сначала 5★)';
      case TrackSortOption.durationDesc:
        return 'По длительности';
    }
  }
}

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
  final int? ratingFilter; // null = all, 0 = unrated, 1..5 = stars, -1 = new tracks
  final String searchQuery;
  final int oneStarCount;
  final int oneStarTotalSize;
  final String? activeCloudUrl;
  final int? lastCloudCheckCount;
  final DateTime? lastSyncedAt;
  final TrackSortOption sortOption;
  final String? selectedFolderUrl;
  final List<Map<String, dynamic>> savedFolders;

  LibraryState({
    this.tracks = const [],
    this.isLoading = false,
    this.errorMessage,
    this.ratingFilter,
    this.searchQuery = '',
    this.oneStarCount = 0,
    this.oneStarTotalSize = 0,
    this.activeCloudUrl,
    this.lastCloudCheckCount,
    this.lastSyncedAt,
    this.sortOption = TrackSortOption.dateAddedDesc,
    this.selectedFolderUrl,
    this.savedFolders = const [],
  });

  int get newTracksCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final count = tracks.where((t) => t.addedAt.isAfter(cutoff)).length;
    return count > 0 ? count : (tracks.length > 30 ? 30 : tracks.length);
  }

  List<Track> get filteredTracks {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 14));
    final recentIn14Days = tracks.where((t) => t.addedAt.isAfter(cutoff)).toList();
    final List<String> newIds = recentIn14Days.isNotEmpty
        ? recentIn14Days.map((t) => t.id).toList()
        : (List<Track>.from(tracks)..sort((a, b) => b.addedAt.compareTo(a.addedAt)))
            .take(30)
            .map((t) => t.id)
            .toList();

    final filtered = tracks.where((track) {
      // 1. Folder filter
      if (selectedFolderUrl != null && selectedFolderUrl!.isNotEmpty) {
        if (track.folderUrl != selectedFolderUrl) return false;
      }
      // 2. Rating or "Новые" filter
      if (ratingFilter != null) {
        if (ratingFilter == -1) {
          if (!newIds.contains(track.id)) return false;
        } else if (ratingFilter == 0) {
          if (track.rating != 0) return false;
        } else if (ratingFilter! > 0) {
          if (track.rating != ratingFilter) return false;
        }
      }
      // 3. Search query
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final matchTitle = track.title.toLowerCase().contains(query);
        final matchArtist = track.artist.toLowerCase().contains(query);
        if (!matchTitle && !matchArtist) return false;
      }
      return true;
    }).toList();

    // 4. Sort
    switch (sortOption) {
      case TrackSortOption.dateAddedDesc:
        filtered.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case TrackSortOption.dateAddedAsc:
        filtered.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        break;
      case TrackSortOption.titleAsc:
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case TrackSortOption.titleDesc:
        filtered.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case TrackSortOption.artistAsc:
        filtered.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case TrackSortOption.ratingDesc:
        filtered.sort((a, b) {
          final r = b.rating.compareTo(a.rating);
          if (r != 0) return r;
          return b.addedAt.compareTo(a.addedAt);
        });
        break;
      case TrackSortOption.durationDesc:
        filtered.sort((a, b) => b.durationMs.compareTo(a.durationMs));
        break;
    }

    return filtered;
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
    int? oneStarTotalSize,
    String? activeCloudUrl,
    int? lastCloudCheckCount,
    DateTime? lastSyncedAt,
    TrackSortOption? sortOption,
    String? selectedFolderUrl,
    bool clearSelectedFolder = false,
    List<Map<String, dynamic>>? savedFolders,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      ratingFilter: clearRatingFilter ? null : (ratingFilter ?? this.ratingFilter),
      searchQuery: searchQuery ?? this.searchQuery,
      oneStarCount: oneStarCount ?? this.oneStarCount,
      oneStarTotalSize: oneStarTotalSize ?? this.oneStarTotalSize,
      activeCloudUrl: activeCloudUrl ?? this.activeCloudUrl,
      lastCloudCheckCount: lastCloudCheckCount ?? this.lastCloudCheckCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      sortOption: sortOption ?? this.sortOption,
      selectedFolderUrl: clearSelectedFolder ? null : (selectedFolderUrl ?? this.selectedFolderUrl),
      savedFolders: savedFolders ?? this.savedFolders,
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  static const String _sortOptionKey = 'prefs_library_sort_option_key';

  LibraryNotifier() : super(LibraryState()) {
    _initCloudFolder();
    _loadSavedPreferences();
    loadTracks();
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSort = prefs.getString(_sortOptionKey);
      if (savedSort != null) {
        final opt = TrackSortOption.values.firstWhere(
          (o) => o.name == savedSort,
          orElse: () => TrackSortOption.dateAddedDesc,
        );
        state = state.copyWith(sortOption: opt);
      }
    } catch (_) {}
  }

  Future<void> setSortOption(TrackSortOption option) async {
    state = state.copyWith(sortOption: option);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortOptionKey, option.name);
    } catch (_) {}
  }

  void setSelectedFolder(String? folderUrl) {
    if (folderUrl == null || folderUrl.isEmpty) {
      state = state.copyWith(clearSelectedFolder: true);
    } else {
      state = state.copyWith(selectedFolderUrl: folderUrl);
    }
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
          savedFolders: folders,
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
              final realSize = f.lengthSync();
              if (realSize > 0) {
                await DBHelper.instance.updateFileSize(t.id, realSize);
                syncedTracks.add(t.copyWith(fileSize: realSize));
                continue;
              }
            }
          } catch (_) {}
        }
        syncedTracks.add(t);
      }

      final oneStarCount = await DBHelper.instance.getOneStarCount();
      final oneStarSize = await DBHelper.instance.getOneStarTracksSize();
      final savedFolders = await DBHelper.instance.getSavedFolders();

      state = state.copyWith(
        tracks: syncedTracks,
        isLoading: false,
        oneStarCount: oneStarCount,
        oneStarTotalSize: oneStarSize,
        savedFolders: savedFolders,
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

  /// Imports from cloud URL or synchronizes additions and deletions for a specific folder
  Future<SyncResult> syncWithCloud({String? folderUrl, String? customName}) async {
    final targetUrl = folderUrl ?? state.activeCloudUrl;
    if (targetUrl == null || targetUrl.trim().isEmpty) {
      throw Exception('Нет ссылки на облако для синхронизации');
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cloudTracks = await CloudParser.parsePublicUrl(targetUrl.trim());
      final existingTracks = await DBHelper.instance.getAllTracks();
      final existingMap = {for (final t in existingTracks) t.id: t};

      // 1. Identify new tracks (preserve rating, cache, and original addedAt for existing ones)
      int addedCount = 0;
      final tracksToSave = <Track>[];
      final cloudIds = <String>{};

      for (final ct in cloudTracks) {
        cloudIds.add(ct.id);
        if (existingMap.containsKey(ct.id)) {
          final existing = existingMap[ct.id]!;
          tracksToSave.add(
            ct.copyWith(
              rating: existing.rating,
              localCachePath: existing.localCachePath,
              fileSize: existing.fileSize > 0 ? existing.fileSize : ct.fileSize,
              addedAt: existing.addedAt,
              folderUrl: targetUrl,
            ),
          );
        } else {
          tracksToSave.add(
            ct.copyWith(
              addedAt: DateTime.now(),
              folderUrl: targetUrl,
            ),
          );
          addedCount++;
        }
      }

      // 2. Identify removed tracks (belonged to THIS cloud folder but no longer present in cloud)
      int removedCount = 0;
      final removedIds = <String>[];
      for (final et in existingTracks) {
        final belongsToThisFolder = et.folderUrl == targetUrl ||
            (et.folderUrl == null &&
                (et.sourceType == 'google_drive' ||
                    et.cloudPath.contains('gdrive://') ||
                    et.sourceType == 'yandex_public'));

        if (belongsToThisFolder && !cloudIds.contains(et.id)) {
          removedIds.add(et.id);
          removedCount++;
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
      String folderName = customName?.trim() ?? '';
      if (folderName.isEmpty) {
        if (targetUrl.contains('drive.google.com')) {
          folderName = 'Google Диск (${cloudTracks.length} треков)';
        } else if (targetUrl.contains('yandex')) {
          folderName = 'Яндекс.Диск (${cloudTracks.length} треков)';
        } else {
          folderName = 'Облачная папка (${cloudTracks.length} треков)';
        }
      }

      await DBHelper.instance.savePublicFolder(targetUrl, folderName, cloudTracks.length);

      final updatedFolders = await DBHelper.instance.getSavedFolders();
      state = state.copyWith(
        activeCloudUrl: targetUrl,
        lastCloudCheckCount: cloudTracks.length,
        lastSyncedAt: now,
        savedFolders: updatedFolders,
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

  Future<void> deleteFolder(String folderUrl, {bool deleteTracks = false}) async {
    state = state.copyWith(isLoading: true);
    await DBHelper.instance.deletePublicFolder(folderUrl, deleteTracks: deleteTracks);
    if (state.selectedFolderUrl == folderUrl) {
      state = state.copyWith(clearSelectedFolder: true);
    }
    if (state.activeCloudUrl == folderUrl) {
      final remaining = await DBHelper.instance.getSavedFolders();
      state = state.copyWith(
        activeCloudUrl: remaining.isNotEmpty ? remaining.first['url'] as String? : null,
      );
    }
    await loadTracks();
  }

  Future<int> importFromPublicUrl(String url, {String? customName}) async {
    final result = await syncWithCloud(folderUrl: url, customName: customName);
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
    final oneStarSize = await DBHelper.instance.getOneStarTracksSize();
    state = state.copyWith(
      tracks: updatedTracks,
      oneStarCount: oneStarCount,
      oneStarTotalSize: oneStarSize,
    );
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

  /// Clean all track titles from technical tags and file extensions
  Future<int> cleanTrackTitles() async {
    state = state.copyWith(isLoading: true);
    final cleaned = await DBHelper.instance.cleanAllTrackTitles();
    await loadTracks();
    return cleaned;
  }

  /// Exports rated tracks as JSON string
  Future<String> exportRatingsJson() async {
    final data = await DBHelper.instance.exportRatingsData();
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'Cloud Music Player',
      'exportedAt': DateTime.now().toIso8601String(),
      'ratingsCount': data.length,
      'ratings': data,
    });
  }

  /// Imports ratings from JSON string and updates tracks in library
  Future<int> importRatingsFromJson(String jsonString) async {
    try {
      final decoded = json.decode(jsonString);
      List<dynamic> items;
      if (decoded is List) {
        items = decoded;
      } else if (decoded is Map && decoded['ratings'] is List) {
        items = decoded['ratings'] as List;
      } else {
        throw Exception('Неверный формат JSON резервной копии');
      }

      final updated = await DBHelper.instance.importRatingsData(items);
      await loadTracks();
      return updated;
    } catch (e) {
      rethrow;
    }
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier();
});
