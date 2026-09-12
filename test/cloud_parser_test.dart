import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_music_player/core/cloud/cloud_parser.dart';

void main() {
  test('CloudParser parses user Google Drive public folder', () async {
    const userUrl = 'https://drive.google.com/drive/folders/1E40QBUmoxhespI7NE3iLRXmQKVL1u_k1?usp=sharing';
    final tracks = await CloudParser.parsePublicUrl(userUrl);

    expect(tracks.isNotEmpty, isTrue);
    expect(tracks.length, greaterThanOrEqualTo(800));
    expect(tracks.first.sourceType, equals('google_drive'));
    expect(tracks.first.streamUrl, contains('drive.usercontent.google.com'));

    // Check one of the expected tracks
    final hasHitEmUp = tracks.any((t) => t.title.contains("Hit 'Em Up") || t.artist.contains('2Pac'));
    expect(hasHitEmUp, isTrue);
  });
}
