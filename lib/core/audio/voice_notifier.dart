import 'dart:async';
import 'package:just_audio/just_audio.dart';
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

  Future<void> playNoSignal() async {
    if (!_isEnabled || _isPlaying) return;
    await _playAssetWithWait('assets/audio/no_signal.wav');
  }

  Future<void> playSignalRestored() async {
    if (!_isEnabled || _isPlaying) return;
    await _playAssetWithWait('assets/audio/signal_restored.wav');
  }

  Future<void> _playAssetWithWait(String assetPath) async {
    try {
      _isPlaying = true;
      await _audioPlayer.stop();
      await _audioPlayer.setAsset(assetPath);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.play();
      // Wait until playback completes (or max 3s timeout)
      await _audioPlayer.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 3), onTimeout: () => _audioPlayer.playerState);
    } catch (_) {
    } finally {
      _isPlaying = false;
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
