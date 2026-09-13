import 'package:cloud_music_player/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.isNewerVersion', () {
    test('detects patch bump', () {
      expect(UpdateService.isNewerVersion('1.0.2', '1.0.1'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.2', '1.0.1'), isTrue);
    });

    test('detects minor bump', () {
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('v1.2.0', 'v1.0.1'), isTrue);
    });

    test('detects major bump', () {
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('same version returns false', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.1'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.1', '1.0.1'), isFalse);
    });

    test('older version returns false', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(UpdateService.isNewerVersion('v0.9.5', '1.0.1'), isFalse);
    });
  });
}
