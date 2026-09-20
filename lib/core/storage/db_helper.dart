import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/track.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cloud_player.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, fileName);

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );

    // Migration: ensure folderUrl exists on tracks
    try {
      await db.execute('ALTER TABLE tracks ADD COLUMN folderUrl TEXT');
    } catch (_) {}

    // Migration: ensure public_folders table exists
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS public_folders (
          url TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          trackCount INTEGER NOT NULL,
          lastSyncedAt TEXT NOT NULL
        )
      ''');
    } catch (_) {}

    // Automatically purge old demo tracks if any exist
    try {
      await db.delete(
        'tracks',
        where: "id LIKE 'demo_%' OR cloudPath LIKE 'demo/%' OR streamUrl LIKE '%soundhelix.com%'",
      );
    } catch (_) {}

    return db;
  }

  /// Automatically purges demo/test tracks from previous versions
  Future<int> purgeDemoTracks() async {
    try {
      final db = await database;
      return await db.delete(
        'tracks',
        where: "id LIKE 'demo_%' OR cloudPath LIKE 'demo/%' OR streamUrl LIKE '%soundhelix.com%'",
      );
    } catch (_) {
      return 0;
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        durationMs INTEGER NOT NULL,
        streamUrl TEXT NOT NULL,
        cloudPath TEXT NOT NULL,
        localCachePath TEXT,
        rating INTEGER NOT NULL,
        fileSize INTEGER NOT NULL,
        sourceType TEXT NOT NULL,
        addedAt TEXT NOT NULL,
        folderUrl TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE public_folders (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        trackCount INTEGER NOT NULL,
        lastSyncedAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> insertOrUpdateTrack(Track track) async {
    final db = await database;
    await db.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertTracks(List<Track> tracks) async {
    final db = await database;
    final batch = db.batch();
    for (final track in tracks) {
      batch.insert(
        'tracks',
        track.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore, // preserve existing ratings and cache
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Track>> getAllTracks() async {
    final db = await database;
    final maps = await db.query('tracks', orderBy: 'addedAt DESC');
    return maps.map((map) => Track.fromMap(map)).toList();
  }

  Future<List<Track>> getCachedTracks() async {
    final db = await database;
    final maps = await db.query(
      'tracks',
      where: 'localCachePath IS NOT NULL AND localCachePath != ""',
      orderBy: 'addedAt DESC',
    );
    return maps.map((map) => Track.fromMap(map)).toList();
  }

  Future<void> updateRating(String trackId, int rating) async {
    final db = await database;
    await db.update(
      'tracks',
      {'rating': rating},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> updateCachePath(String trackId, String? localCachePath, {int? fileSize}) async {
    final db = await database;
    final data = <String, dynamic>{'localCachePath': localCachePath};
    if (fileSize != null) {
      data['fileSize'] = fileSize;
    }
    await db.update(
      'tracks',
      data,
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> updateFileSize(String trackId, int fileSize) async {
    final db = await database;
    await db.update(
      'tracks',
      {'fileSize': fileSize},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<void> deleteTrack(String trackId) async {
    final db = await database;
    await db.delete(
      'tracks',
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  /// Deletes all tracks with rating = 1 and returns the list of deleted tracks
  /// so their cached audio files can be removed from disk.
  Future<List<Track>> deleteOneStarTracks() async {
    final db = await database;
    final oneStarRows = await db.query(
      'tracks',
      where: 'rating = 1',
    );
    final tracksToDelete = oneStarRows.map((m) => Track.fromMap(m)).toList();

    if (tracksToDelete.isNotEmpty) {
      await db.delete(
        'tracks',
        where: 'rating = 1',
      );
    }

    return tracksToDelete;
  }

  Future<int> getOneStarCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM tracks WHERE rating = 1');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getOneStarTracksSize() async {
    final db = await database;
    final oneStarRows = await db.query(
      'tracks',
      columns: ['localCachePath', 'fileSize'],
      where: 'rating = 1',
    );
    int total = 0;
    for (final row in oneStarRows) {
      final fs = (row['fileSize'] as num?)?.toInt() ?? 0;
      if (fs > 0) {
        total += fs;
      } else {
        final path = row['localCachePath'] as String?;
        if (path != null && path.isNotEmpty) {
          try {
            final f = File(path);
            if (f.existsSync()) total += f.lengthSync();
          } catch (_) {}
        }
      }
    }
    return total;
  }

  Future<void> savePublicFolder(String url, String name, int count) async {
    final db = await database;
    await db.insert(
      'public_folders',
      {
        'url': url,
        'name': name,
        'trackCount': count,
        'lastSyncedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSavedFolders() async {
    final db = await database;
    return await db.query('public_folders', orderBy: 'lastSyncedAt DESC');
  }

  Future<void> deletePublicFolder(String url, {bool deleteTracks = false}) async {
    final db = await database;
    await db.delete(
      'public_folders',
      where: 'url = ?',
      whereArgs: [url],
    );
    if (deleteTracks) {
      final tracks = await db.query(
        'tracks',
        where: 'folderUrl = ?',
        whereArgs: [url],
      );
      for (final t in tracks) {
        final cache = t['localCachePath'] as String?;
        if (cache != null && cache.isNotEmpty) {
          try {
            final f = File(cache);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
      }
      await db.delete(
        'tracks',
        where: 'folderUrl = ?',
        whereArgs: [url],
      );
    }
  }

  /// Exports all rated tracks as a list of maps
  Future<List<Map<String, dynamic>>> exportRatingsData() async {
    final db = await database;
    final rows = await db.query(
      'tracks',
      columns: ['id', 'title', 'artist', 'rating'],
      where: 'rating > 0',
      orderBy: 'rating DESC, title ASC',
    );
    return rows;
  }

  /// Imports ratings from a list of maps matching by ID or (title + artist)
  Future<int> importRatingsData(List<dynamic> items) async {
    final db = await database;
    final allTracks = await getAllTracks();
    final byId = {for (final t in allTracks) t.id: t};
    final byTitleArtist = {
      for (final t in allTracks) '${t.title.trim().toLowerCase()}|${t.artist.trim().toLowerCase()}': t
    };

    int updatedCount = 0;
    final batch = db.batch();

    for (final item in items) {
      if (item is! Map) continue;
      final rating = (item['rating'] as num?)?.toInt() ?? 0;
      if (rating < 1 || rating > 5) continue;

      final id = item['id'] as String?;
      final title = (item['title'] as String?)?.trim().toLowerCase();
      final artist = (item['artist'] as String?)?.trim().toLowerCase();

      String? targetTrackId;
      if (id != null && byId.containsKey(id)) {
        targetTrackId = id;
      } else if (title != null && artist != null) {
        final key = '$title|$artist';
        if (byTitleArtist.containsKey(key)) {
          targetTrackId = byTitleArtist[key]!.id;
        }
      }

      if (targetTrackId != null) {
        batch.update(
          'tracks',
          {'rating': rating},
          where: 'id = ?',
          whereArgs: [targetTrackId],
        );
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      await batch.commit(noResult: true);
    }
    return updatedCount;
  }

  static String cleanTitleString(String raw) {
    var title = raw;
    // Remove audio extensions
    title = title.replaceAll(RegExp(r'\.(mp3|m4a|flac|wav|aac|ogg)$', caseSensitive: false), '');
    // Replace underscores with spaces
    title = title.replaceAll('_', ' ');
    // Remove technical tags
    title = title.replaceAll(RegExp(r'\[(320\s*kbps|flac|hq|mp3|lossless|\d+p)\]', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\((official\s*(music\s*)?video|official\s*audio|lyrics?\s*(video)?|audio|video|clip|hd|remastered?)\)', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\[(official\s*(music\s*)?video|official\s*audio|lyrics?\s*(video)?|audio|video|clip|hd|remastered?)\]', caseSensitive: false), '');
    // Collapse extra spaces
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return title.isEmpty ? raw : title;
  }

  Future<int> cleanAllTrackTitles() async {
    final db = await database;
    final tracks = await getAllTracks();
    int cleaned = 0;
    final batch = db.batch();
    for (final t in tracks) {
      final newTitle = cleanTitleString(t.title);
      if (newTitle != t.title) {
        batch.update(
          'tracks',
          {'title': newTitle},
          where: 'id = ?',
          whereArgs: [t.id],
        );
        cleaned++;
      }
    }
    if (cleaned > 0) {
      await batch.commit(noResult: true);
    }
    return cleaned;
  }
}
