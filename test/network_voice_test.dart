import 'package:cloud_music_player/core/network/network_monitor.dart';
import 'package:cloud_music_player/core/audio/voice_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Network & Voice Notifier Tests', () {
    test('VoiceNotifier singleton initialized with default true', () {
      final notifier = VoiceNotifier.instance;
      expect(notifier, isNotNull);
      expect(notifier.isEnabled, isTrue);
    });

    test('VoiceNotifier setEnabled updates state and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = VoiceNotifier.instance;
      await notifier.setEnabled(false);
      expect(notifier.isEnabled, isFalse);
      await notifier.setEnabled(true);
      expect(notifier.isEnabled, isTrue);
    });

    test('NetworkMonitor singleton exists and provides streams', () {
      final monitor = NetworkMonitor.instance;
      expect(monitor, isNotNull);
      expect(monitor.onStatusChanged, isNotNull);
      expect(monitor.onConnectionLost, isNotNull);
      expect(monitor.onConnectionRestored, isNotNull);
    });
  });
}
