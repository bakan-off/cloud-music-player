import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceNotifier {
  static final VoiceNotifier instance = VoiceNotifier._internal();
  VoiceNotifier._internal() {
    _loadPreference();
  }

  static const String _prefKey = 'prefs_network_voice_alerts';
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isEnabled = true;
  bool _isPlaying = false;

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
  Future<String> _ensureLocalAudioFile(String assetPath) async {
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
    if (!_isEnabled || _isPlaying) return;
    await _playAssetWithWait('assets/audio/no_signal.wav');
  }

  Future<void> playSignalRestored() async {
    if (!_isEnabled || _isPlaying) return;
    await _playAssetWithWait('assets/audio/signal_restored.wav');
  }

  /// Explicit test method for Settings screen preview (ignores _isEnabled)
  Future<void> testNoSignal() async {
    await _playAssetWithWait('assets/audio/no_signal.wav', isTest: true);
  }

  /// Explicit test method for Settings screen preview (ignores _isEnabled)
  Future<void> testSignalRestored() async {
    await _playAssetWithWait('assets/audio/signal_restored.wav', isTest: true);
  }

  Future<void> _playAssetWithWait(String assetPath, {bool isTest = false}) async {
    if ((!_isEnabled && !isTest) || _isPlaying) return;
    try {
      _isPlaying = true;
      final filePath = await _ensureLocalAudioFile(assetPath);
      final mediaItem = MediaItem(
        id: assetPath,
        title: assetPath.contains('no_signal') ? 'Нет сигнала' : 'Есть сигнал',
        artist: 'Cloud Player',
      );
      final source = AudioSource.file(
        filePath,
        tag: mediaItem,
      );

      await _audioPlayer.stop();
      await _audioPlayer.setAudioSource(source);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play();

      // Wait until playback completes (max 4 seconds)
      await _audioPlayer.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 4), onTimeout: () => _audioPlayer.playerState);
    } catch (e) {
      debugPrint('VoiceNotifier error: $e');
      if (isTest) rethrow;
    } finally {
      _isPlaying = false;
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
