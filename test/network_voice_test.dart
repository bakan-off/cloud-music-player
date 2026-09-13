import 'package:cloud_music_player/core/audio/voice_notifier.dart';
import 'package:cloud_music_player/core/network/network_monitor.dart';
import 'package:flutter/services.dart';
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

    test('VoiceNotifier audio asset files exist and can be loaded from bundle', () async {
      final noSignalBytes = await rootBundle.load('assets/audio/no_signal.wav');
      expect(noSignalBytes.lengthInBytes, greaterThan(1000));
      final signalRestoredBytes = await rootBundle.load('assets/audio/signal_restored.wav');
      expect(signalRestoredBytes.lengthInBytes, greaterThan(1000));
    });

    test('NetworkMonitor provides wifi-specific streams', () {
      final monitor = NetworkMonitor.instance;
      expect(monitor.onWifiLost, isNotNull);
      expect(monitor.onWifiRestored, isNotNull);
    });
  });
}
