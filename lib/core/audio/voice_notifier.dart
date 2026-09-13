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
    try {
      _isPlaying = true;
      await _audioPlayer.setAsset('assets/audio/no_signal.wav');
      await _audioPlayer.play();
    } catch (_) {
    } finally {
      _isPlaying = false;
    }
  }

  Future<void> playSignalRestored() async {
    if (!_isEnabled || _isPlaying) return;
    try {
      _isPlaying = true;
      await _audioPlayer.setAsset('assets/audio/signal_restored.wav');
      await _audioPlayer.play();
    } catch (_) {
    } finally {
      _isPlaying = false;
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
