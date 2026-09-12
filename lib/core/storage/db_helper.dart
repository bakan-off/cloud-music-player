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

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
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
        addedAt TEXT NOT NULL
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

  Future<void> updateCachePath(String trackId, String? localCachePath) async {
    final db = await database;
    await db.update(
      'tracks',
      {'localCachePath': localCachePath},
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
}
