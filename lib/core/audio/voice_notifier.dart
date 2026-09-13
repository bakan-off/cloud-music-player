import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_manager.dart';

class VoiceNotifier {
  static final VoiceNotifier instance = VoiceNotifier._internal();
  VoiceNotifier._internal() {
    _loadPreference();
  }

  static const String _prefKey = 'prefs_network_voice_alerts';
  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  /// Copies bundled asset into local application support directory so ExoPlayer
  /// can read it directly from disk without local HTTP proxy / network stack.
  Future<String> ensureLocalAudioFile(String assetPath) async {
    final dir = await getApplicationSupportDirectory();
    final fileName = p.basename(assetPath);
    final localFile = File('${dir.path}/$fileName');
    if (!await localFile.exists() || (await localFile.length()) == 0) {
      final data = await rootBundle.load(assetPath);
      await localFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return localFile.path;
  }

  Future<void> playNoSignal() async {
    if (!_isEnabled) return;
    await AudioManager.instance.playVoiceAlert('assets/audio/no_signal.wav');
  }

  Future<void> playSignalRestored() async {
    if (!_isEnabled) return;
    await AudioManager.instance.playVoiceAlert('assets/audio/signal_restored.wav');
  }

  /// Explicit test method for Settings screen preview (ignores _isEnabled)
  Future<void> testNoSignal() async {
    await AudioManager.instance.playVoiceAlert('assets/audio/no_signal.wav', isTest: true);
  }

  /// Explicit test method for Settings screen preview (ignores _isEnabled)
  Future<void> testSignalRestored() async {
    await AudioManager.instance.playVoiceAlert('assets/audio/signal_restored.wav', isTest: true);
  }

  void dispose() {}
}
