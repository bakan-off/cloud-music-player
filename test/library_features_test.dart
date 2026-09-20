import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_music_player/core/storage/db_helper.dart';
import 'package:cloud_music_player/models/track.dart';
import 'package:cloud_music_player/providers/library_provider.dart';

void main() {
  group('DBHelper.cleanTitleString', () {
    test('removes file extensions and underscores', () {
      expect(DBHelper.cleanTitleString('Queen_-_Bohemian_Rhapsody.mp3'), 'Queen - Bohemian Rhapsody');
      expect(DBHelper.cleanTitleString('Song_Name.flac'), 'Song Name');
      expect(DBHelper.cleanTitleString('Audio_Track.m4a'), 'Audio Track');
    });

    test('removes quality and video tags', () {
      expect(DBHelper.cleanTitleString('Linkin Park - Numb [320kbps]'), 'Linkin Park - Numb');
      expect(DBHelper.cleanTitleString('Adele - Hello (Official Video)'), 'Adele - Hello');
      expect(DBHelper.cleanTitleString('Coldplay - Yellow [Official Audio]'), 'Coldplay - Yellow');
      expect(DBHelper.cleanTitleString('Imagine Dragons - Believer (Lyric Video)'), 'Imagine Dragons - Believer');
    });
  });

  group('Track model folderUrl and serialization', () {
    test('Track correctly serializes and deserializes folderUrl', () {
      final now = DateTime.now();
      final track = Track(
        id: 'track-1',
        title: 'Song A',
        artist: 'Artist A',
        durationMs: 180000,
        streamUrl: 'https://example.com/1.mp3',
        cloudPath: 'Music/1.mp3',
        fileSize: 5000000,
        sourceType: 'cloud',
        addedAt: now,
        folderUrl: 'https://disk.yandex.ru/d/test12345',
        rating: 5,
      );

      final map = track.toMap();
      expect(map['folderUrl'], 'https://disk.yandex.ru/d/test12345');

      final deserialized = Track.fromMap(map);
      expect(deserialized.folderUrl, 'https://disk.yandex.ru/d/test12345');
      expect(deserialized.id, 'track-1');
      expect(deserialized.rating, 5);
    });
  });

  group('Track Sorting and Filtering logic in LibraryState', () {
    final t1 = Track(
      id: '1',
      title: 'Alpha Song',
      artist: 'Charlie',
      durationMs: 100000,
      streamUrl: 'http://a',
      cloudPath: 'a',
      fileSize: 100,
      sourceType: 'cloud',
      addedAt: DateTime.now().subtract(const Duration(days: 20)),
      folderUrl: 'https://cloud/folderA',
      rating: 4,
    );

    final t2 = Track(
      id: '2',
      title: 'Beta Song',
      artist: 'Alice',
      durationMs: 300000,
      streamUrl: 'http://b',
      cloudPath: 'b',
      fileSize: 100,
      sourceType: 'cloud',
      addedAt: DateTime.now().subtract(const Duration(days: 1)),
      folderUrl: 'https://cloud/folderB',
      rating: 5,
    );

    final t3 = Track(
      id: '3',
      title: 'Gamma Song',
      artist: 'Bob',
      durationMs: 200000,
      streamUrl: 'http://c',
      cloudPath: 'c',
      fileSize: 100,
      sourceType: 'cloud',
      addedAt: DateTime.now().subtract(const Duration(days: 2)),
      folderUrl: 'https://cloud/folderA',
      rating: 1,
    );

    test('Sort by date added descending (newest first)', () {
      final state = LibraryState(
        tracks: [t1, t2, t3],
        sortOption: TrackSortOption.dateAddedDesc,
      );
      final sorted = state.filteredTracks;
      expect(sorted.first.id, '2'); // 1 day ago
      expect(sorted[1].id, '3');    // 2 days ago
      expect(sorted.last.id, '1');  // 20 days ago
    });

    test('Sort by rating descending (highest stars first)', () {
      final state = LibraryState(
        tracks: [t1, t2, t3],
        sortOption: TrackSortOption.ratingDesc,
      );
      final sorted = state.filteredTracks;
      expect(sorted[0].rating, 5);
      expect(sorted[1].rating, 4);
      expect(sorted[2].rating, 1);
    });

    test('Sort by title A-Z', () {
      final state = LibraryState(
        tracks: [t3, t1, t2],
        sortOption: TrackSortOption.titleAsc,
      );
      final sorted = state.filteredTracks;
      expect(sorted.map((t) => t.title).toList(), ['Alpha Song', 'Beta Song', 'Gamma Song']);
    });

    test('Filter by folder', () {
      final state = LibraryState(
        tracks: [t1, t2, t3],
        selectedFolderUrl: 'https://cloud/folderA',
      );
      final filtered = state.filteredTracks;
      expect(filtered.length, 2);
      expect(filtered.every((t) => t.folderUrl == 'https://cloud/folderA'), isTrue);
    });

    test('Filter by "Новые" (ratingFilter == -1)', () {
      final state = LibraryState(
        tracks: [t1, t2, t3],
        ratingFilter: -1,
      );
      final filtered = state.filteredTracks;
      // t2 and t3 are within 14 days, t1 is 20 days ago
      expect(filtered.length, 2);
      expect(filtered.map((t) => t.id), containsAll(['2', '3']));
      expect(filtered.map((t) => t.id), isNot(contains('1')));
    });
  });

  group('Ratings JSON Export / Import format', () {
    test('JSON serialization matches expected structure', () {
      final data = [
        {
          'id': 't1',
          'title': 'Song 1',
          'artist': 'Artist 1',
          'rating': 5,
        },
        {
          'id': 't2',
          'title': 'Song 2',
          'artist': 'Artist 2',
          'rating': 1,
        },
      ];

      final encoded = jsonEncode(data);
      final decoded = jsonDecode(encoded);
      expect(decoded is List, isTrue);
      expect(decoded.length, 2);
      expect(decoded[0]['rating'], 5);
      expect(decoded[1]['rating'], 1);
    });
  });
}
