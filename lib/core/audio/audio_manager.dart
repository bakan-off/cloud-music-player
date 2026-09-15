import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/track.dart';
import '../network/network_monitor.dart';
import '../storage/db_helper.dart';
import 'voice_notifier.dart';

enum PlayerRepeatMode { off, all, one }

class AudioManager {
  static final AudioManager instance = AudioManager._internal();
  AudioManager._internal() {
    _initAudioPlayer();
  }

  final AudioPlayer _player = AudioPlayer();
  AudioPlayer get player => _player;

  ConcatenatingAudioSource? _playlist;
  ConcatenatingAudioSource? get playlist => _playlist;

  final List<Track> _originalQueue = [];
  final List<Track> _playbackQueue = [];
  int _currentIndex = -1;

  bool _isShuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;

  // Network interruption & voice alert tracking
  bool _pausedByNetworkLoss = false;
  bool _userIntentPlaying = false;
  bool _isVoiceAlertPlaying = false;
  bool get isVoiceAlertPlaying => _isVoiceAlertPlaying;
  Timer? _reconnectWatchdog;
  Timer? _networkLossTimeoutTimer;
  Duration _interruptedPosition = Duration.zero;
  int _interruptedIndex = -1;
  final _waitingForNetworkController = StreamController<bool>.broadcast();
  Stream<bool> get waitingForNetworkStream => _waitingForNetworkController.stream;
  bool get isWaitingForNetwork => _pausedByNetworkLoss;

  void _cancelReconnectAttempts() {
    _pausedByNetworkLoss = false;
    _reconnectWatchdog?.cancel();
    _networkLossTimeoutTimer?.cancel();
    _waitingForNetworkController.add(false);
  }

  final _currentTrackController = StreamController<Track?>.broadcast();
  final _queueController = StreamController<List<Track>>.broadcast();
  final _isShuffleController = StreamController<bool>.broadcast();
  final _repeatModeController = StreamController<PlayerRepeatMode>.broadcast();
  final _downloadProgressController = StreamController<Map<String, double>>.broadcast();

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;
  Stream<List<Track>> get queueStream => _queueController.stream;
  Stream<bool> get isShuffleStream => _isShuffleController.stream;
  Stream<PlayerRepeatMode> get repeatModeStream => _repeatModeController.stream;
  Stream<Map<String, double>> get downloadProgressStream => _downloadProgressController.stream;

  final Map<String, double> _downloadingProgress = {};

  Track? get currentTrack => (_currentIndex >= 0 && _currentIndex < _playbackQueue.length)
      ? _playbackQueue[_currentIndex]
      : null;

  bool get isShuffle => _isShuffle;
  bool get userIntentPlaying => _userIntentPlaying;
  PlayerRepeatMode get repeatMode => _repeatMode;
  List<Track> get queue => List.unmodifiable(_playbackQueue);

  Future<void> _initAudioPlayer() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}

    _player.currentIndexStream.listen((index) {
      if (!_isVoiceAlertPlaying &&
          index != null &&
          index >= 0 &&
          index < _playbackQueue.length &&
          index != _currentIndex) {
        _currentIndex = index;
        final track = _playbackQueue[_currentIndex];
        _currentTrackController.add(track);
      }
    });

    _player.playingStream.listen((playing) {
      if (_isVoiceAlertPlaying) return;
      if (playing) {
        _userIntentPlaying = true;
      } else {
        // If playback stopped or was paused by user (notification, lock screen, bluetooth, etc.)
        // and NOT due to network loss, reset user play intent and cancel any reconnect watchdog.
        if (!_pausedByNetworkLoss) {
          _userIntentPlaying = false;
          _cancelReconnectAttempts();
        }
      }
    });

    Timer? bufferingWatchdog;
    _player.playerStateStream.listen((state) {
      if (_isVoiceAlertPlaying) return;
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      } else if (state.processingState == ProcessingState.buffering) {
        bufferingWatchdog?.cancel();
        final track = currentTrack;
        final isCloudStream = track != null && !track.isCached;
        if (isCloudStream && _userIntentPlaying && !_pausedByNetworkLoss) {
          // If buffering lasts more than 3 seconds on an active cloud stream, check internet
          bufferingWatchdog = Timer(const Duration(seconds: 3), () async {
            if (_player.processingState == ProcessingState.buffering &&
                !_pausedByNetworkLoss &&
                _userIntentPlaying &&
                !_isVoiceAlertPlaying) {
              final hasNet = await NetworkMonitor.instance.hasActualInternet();
              if (!hasNet && _userIntentPlaying && !_pausedByNetworkLoss) {
                await _handleNetworkLost();
              } else {
                // Secondary check: if still buffering after 3 more seconds (6s total)
                Timer(const Duration(seconds: 3), () async {
                  if (_player.processingState == ProcessingState.buffering &&
                      !_pausedByNetworkLoss &&
                      _userIntentPlaying &&
                      !_isVoiceAlertPlaying) {
                    await _handleNetworkLost();
                  }
                });
              }
            }
          });
        }
      } else {
        bufferingWatchdog?.cancel();
      }
    });

    _player.playbackEventStream.listen(
      (event) {},
      onError: (e) async {
        if (!_isVoiceAlertPlaying && _userIntentPlaying && !_pausedByNetworkLoss) {
          final track = currentTrack;
          if (track != null && !track.isCached) {
            await _handleNetworkLost();
          }
        }
      },
    );

    NetworkMonitor.instance.onConnectionLost.listen((_) {
      if (!_isVoiceAlertPlaying && _userIntentPlaying && !_pausedByNetworkLoss) {
        final track = currentTrack;
        if (track != null && !track.isCached) {
          _handleNetworkLost();
        }
      }
    });

    NetworkMonitor.instance.onConnectionRestored.listen((_) async {
      if (_pausedByNetworkLoss && _userIntentPlaying && !_isVoiceAlertPlaying) {
        final hasNet = await NetworkMonitor.instance.hasActualInternet();
        if (hasNet && _pausedByNetworkLoss && _userIntentPlaying) {
          await _handleNetworkRestored();
        }
      }
    });

    NetworkMonitor.instance.onWifiLost.listen((_) {
      if (!_isVoiceAlertPlaying && _userIntentPlaying && !_pausedByNetworkLoss) {
        final track = currentTrack;
        if (track != null && !track.isCached) {
          _handleNetworkLost();
        }
      }
    });

    NetworkMonitor.instance.onWifiRestored.listen((_) async {
      if (_pausedByNetworkLoss && _userIntentPlaying && !_isVoiceAlertPlaying) {
        final hasNet = await NetworkMonitor.instance.hasActualInternet();
        if (hasNet && _pausedByNetworkLoss && _userIntentPlaying) {
          await _handleNetworkRestored();
        }
      }
    });
  }

  /// Plays voice alert through the single unified AudioPlayer instance.
  /// Preserves music queue, position, and playback state without session conflicts.
  Future<void> playVoiceAlert(String assetPath, {bool isTest = false}) async {
    if (!VoiceNotifier.instance.isEnabled && !isTest) return;
    if (_isVoiceAlertPlaying) return;

    _isVoiceAlertPlaying = true;
    try {
      final wasPlaying = _player.playing;
      final savedPos = _player.position;
      final savedIdx = _currentIndex;

      if (wasPlaying) {
        try {
          await _player.pause();
        } catch (_) {}
      }

      final filePath = await VoiceNotifier.instance.ensureLocalAudioFile(assetPath);
      final isNoSignal = assetPath.contains('no_signal');
      final mediaItem = MediaItem(
        id: 'voice_alert_${p.basenameWithoutExtension(assetPath)}',
        title: isNoSignal ? 'Оповещение: Нет сигнала' : 'Оповещение: Есть сигнал',
        artist: 'Cloud Music Player',
      );
      final voiceSource = AudioSource.file(
        filePath,
        tag: mediaItem,
      );

      await _player.stop();
      await _player.setAudioSource(voiceSource);
      await _player.setVolume(1.0);
      await _player.play();

      // Wait until voice playback completes (max 4 seconds)
      await _player.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 4), onTimeout: () => _player.playerState);

      // If not waiting for network restoration, restore the user's music queue
      if (!_pausedByNetworkLoss &&
          _playbackQueue.isNotEmpty &&
          savedIdx >= 0 &&
          savedIdx < _playbackQueue.length) {
        await _loadPlaylistAndPlay(
          initialIndex: savedIdx,
          initialPosition: savedPos,
          play: wasPlaying,
        );
      }
    } catch (e) {
      debugPrint('AudioManager playVoiceAlert error: $e');
      if (isTest) rethrow;
    } finally {
      _isVoiceAlertPlaying = false;
    }
  }

  Future<void> _handleNetworkLost() async {
    if (_isVoiceAlertPlaying) return;
    if (!_userIntentPlaying) return;
    if (_pausedByNetworkLoss) return;

    // Safety guard: only interrupt if player is actually playing or actively buffering/loading.
    // If player is already paused, stopped, or idle, it means player is off - do nothing!
    final isPlayerActive = _player.playing ||
        _player.processingState == ProcessingState.buffering ||
        _player.processingState == ProcessingState.loading;
    if (!isPlayerActive) {
      _userIntentPlaying = false;
      return;
    }

    final track = currentTrack;
    if (track == null) {
      _userIntentPlaying = false;
      return;
    }
    // Do not interrupt offline cached tracks!
    if (track.isCached &&
        track.localCachePath != null &&
        File(track.localCachePath!).existsSync()) {
      return;
    }

    _pausedByNetworkLoss = true;
    _interruptedPosition = _player.position;
    _interruptedIndex = _currentIndex;
    _waitingForNetworkController.add(true);

    try {
      await _player.pause();
    } catch (_) {}

    // Play "Нет сигнала" and wait for audio completion
    await VoiceNotifier.instance.playNoSignal();

    // Start active background watchdog to detect reconnection while screen is off
    _startReconnectWatchdog();
    _startNetworkLossTimeout();
  }

  void _startNetworkLossTimeout() {
    _networkLossTimeoutTimer?.cancel();
    // After 3 minutes of no connection, automatically cancel reconnect attempts to prevent unexpected playback
    _networkLossTimeoutTimer = Timer(const Duration(minutes: 3), () {
      if (_pausedByNetworkLoss) {
        _cancelReconnectAttempts();
        _userIntentPlaying = false;
      }
    });
  }

  void _startReconnectWatchdog() {
    _reconnectWatchdog?.cancel();
    _reconnectWatchdog = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_pausedByNetworkLoss || !_userIntentPlaying) {
        timer.cancel();
        return;
      }
      final hasNet = await NetworkMonitor.instance.hasActualInternet();
      if (hasNet && _pausedByNetworkLoss && _userIntentPlaying) {
        timer.cancel();
        await _handleNetworkRestored();
      }
    });
  }

  Future<void> _handleNetworkRestored() async {
    if (!_pausedByNetworkLoss || !_userIntentPlaying) {
      _cancelReconnectAttempts();
      return;
    }
    _reconnectWatchdog?.cancel();
    _networkLossTimeoutTimer?.cancel();

    // Announce "Есть сигнал" and wait for audio completion before resuming music
    await VoiceNotifier.instance.playSignalRestored();

    _waitingForNetworkController.add(false);

    // Double check userIntentPlaying in case user intervened during voice alert
    if (_playbackQueue.isNotEmpty &&
        _interruptedIndex >= 0 &&
        _interruptedIndex < _playbackQueue.length &&
        _userIntentPlaying) {
      final savedPos = _interruptedPosition;
      final savedIdx = _interruptedIndex;
      _pausedByNetworkLoss = false;

      // Small delay to allow audio buffer to cleanly initialize
      await Future.delayed(const Duration(milliseconds: 300));

      try {
        await _loadPlaylistAndPlay(
          initialIndex: savedIdx,
          initialPosition: savedPos,
          play: true,
        );
      } catch (e) {
        if (_userIntentPlaying) {
          await Future.delayed(const Duration(seconds: 1));
          await _loadPlaylistAndPlay(
            initialIndex: savedIdx,
            initialPosition: savedPos,
            play: true,
          );
        }
      }
    } else {
      _pausedByNetworkLoss = false;
    }
  }

  void _handleTrackCompleted() {
    if (_repeatMode == PlayerRepeatMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else if (hasNext) {
      skipToNext();
    } else if (_repeatMode == PlayerRepeatMode.all && _playbackQueue.isNotEmpty) {
      playTrackAtIndex(0);
    } else {
      // Playlist finished and not looping
      _userIntentPlaying = false;
      _cancelReconnectAttempts();
    }
  }

  bool get hasNext {
    if (_playbackQueue.isEmpty) return false;
    return _currentIndex < _playbackQueue.length - 1 || _repeatMode == PlayerRepeatMode.all;
  }

  bool get hasPrevious {
    if (_playbackQueue.isEmpty) return false;
    return _currentIndex > 0 || _repeatMode == PlayerRepeatMode.all;
  }

  AudioSource _buildAudioSource(Track track) {
    final mediaItem = MediaItem(
      id: track.id,
      album: track.album?.isNotEmpty == true ? track.album! : 'Cloud Player',
      title: track.title,
      artist: track.artist.isNotEmpty ? track.artist : 'Cloud Music',
      duration: track.durationMs > 0 ? Duration(milliseconds: track.durationMs) : null,
    );

    if (track.isCached &&
        track.localCachePath != null &&
        File(track.localCachePath!).existsSync()) {
      return AudioSource.file(
        track.localCachePath!,
        tag: mediaItem,
      );
    } else {
      Uri uri;
      try {
        uri = Uri.parse(track.streamUrl);
      } catch (_) {
        uri = Uri.parse(Uri.encodeFull(track.streamUrl));
      }
      return AudioSource.uri(
        uri,
        tag: mediaItem,
      );
    }
  }

  Future<void> _loadPlaylistAndPlay({
    required int initialIndex,
    Duration initialPosition = Duration.zero,
    bool play = true,
  }) async {
    if (_playbackQueue.isEmpty) return;
    _currentIndex = initialIndex.clamp(0, _playbackQueue.length - 1);
    final track = _playbackQueue[_currentIndex];
    _currentTrackController.add(track);

    _playlist = ConcatenatingAudioSource(
      children: _playbackQueue.map(_buildAudioSource).toList(),
      useLazyPreparation: true,
    );

    try {
      await _player.setAudioSource(
        _playlist!,
        initialIndex: _currentIndex,
        initialPosition: initialPosition,
      );
      _syncLoopMode();
      if (play) {
        await _player.play();
      }
    } catch (e, stack) {
      debugPrint('AudioManager _loadPlaylistAndPlay error: $e\n$stack');
      if (play) {
        try {
          await _player.play();
        } catch (_) {}
      }
    }
  }

  /// Sets a new queue and plays the track at [startIndex]
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    _cancelReconnectAttempts();
    _userIntentPlaying = true;
    _originalQueue.clear();
    _originalQueue.addAll(tracks);
    _playbackQueue.clear();
    _playbackQueue.addAll(tracks);

    if (_isShuffle) {
      _applyShuffle(startIndex: startIndex);
    } else {
      _currentIndex = startIndex.clamp(0, _playbackQueue.length - 1);
    }

    _queueController.add(_playbackQueue);
    if (_playbackQueue.isNotEmpty && _currentIndex >= 0) {
      await _loadPlaylistAndPlay(initialIndex: _currentIndex);
    }
  }

  Future<void> playTrackAtIndex(int index) async {
    if (index < 0 || index >= _playbackQueue.length) return;
    _cancelReconnectAttempts();
    _userIntentPlaying = true;
    _currentIndex = index;
    final track = _playbackQueue[_currentIndex];
    _currentTrackController.add(track);

    if (_playlist != null && _playlist!.length == _playbackQueue.length) {
      try {
        await _player.seek(Duration.zero, index: index);
        await _player.play();
        return;
      } catch (_) {}
    }

    await _loadPlaylistAndPlay(initialIndex: index);
  }

  Future<void> playOrPause() async {
    if (_pausedByNetworkLoss) {
      // User explicitly interacted while waiting for network.
      // Cancel auto-resume and stay paused.
      _cancelReconnectAttempts();
      _userIntentPlaying = false;
      return;
    }
    if (_player.playing) {
      _userIntentPlaying = false;
      _cancelReconnectAttempts();
      await _player.pause();
    } else {
      _userIntentPlaying = true;
      if (currentTrack == null && _playbackQueue.isNotEmpty) {
        await playTrackAtIndex(0);
      } else {
        await _player.play();
      }
    }
  }

  Future<void> stop() async {
    _cancelReconnectAttempts();
    _userIntentPlaying = false;
    await _player.stop();
  }

  Future<void> skipToNext() async {
    if (_playbackQueue.isEmpty) return;
    _cancelReconnectAttempts();
    _userIntentPlaying = true;
    if (_player.hasNext) {
      await _player.seekToNext();
      await _player.play();
    } else if (_repeatMode == PlayerRepeatMode.all) {
      await _player.seek(Duration.zero, index: 0);
      await _player.play();
    }
  }

  Future<void> skipToPrevious() async {
    if (_playbackQueue.isEmpty) return;
    _cancelReconnectAttempts();
    _userIntentPlaying = true;

    // If played more than 3 seconds, restart current track
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      await _player.play();
    } else if (_repeatMode == PlayerRepeatMode.all) {
      await _player.seek(Duration.zero, index: _playbackQueue.length - 1);
      await _player.play();
    }
  }

  Future<void> toggleShuffle() async {
    _isShuffle = !_isShuffle;
    final curTrack = currentTrack;
    final isPlaying = _player.playing;
    final currentPos = _player.position;

    if (_isShuffle) {
      _applyShuffle(currentTrack: curTrack);
    } else {
      _playbackQueue.clear();
      _playbackQueue.addAll(_originalQueue);
      if (curTrack != null) {
        _currentIndex = _playbackQueue.indexWhere((t) => t.id == curTrack.id);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }

    _isShuffleController.add(_isShuffle);
    _queueController.add(_playbackQueue);

    if (_playbackQueue.isNotEmpty) {
      await _loadPlaylistAndPlay(
        initialIndex: _currentIndex,
        initialPosition: currentPos,
        play: isPlaying,
      );
    }
  }

  void _applyShuffle({int startIndex = 0, Track? currentTrack}) {
    final active = currentTrack ?? (_originalQueue.isNotEmpty ? _originalQueue[startIndex] : null);
    final rest = _originalQueue.where((t) => t.id != active?.id).toList();
    rest.shuffle(Random());

    _playbackQueue.clear();
    if (active != null) {
      _playbackQueue.add(active);
      _playbackQueue.addAll(rest);
      _currentIndex = 0;
    } else {
      _playbackQueue.addAll(rest);
      _currentIndex = _playbackQueue.isNotEmpty ? 0 : -1;
    }
  }

  void _syncLoopMode() {
    switch (_repeatMode) {
      case PlayerRepeatMode.off:
        _player.setLoopMode(LoopMode.off);
        break;
      case PlayerRepeatMode.all:
        _player.setLoopMode(LoopMode.all);
        break;
      case PlayerRepeatMode.one:
        _player.setLoopMode(LoopMode.one);
        break;
    }
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case PlayerRepeatMode.off:
        _repeatMode = PlayerRepeatMode.all;
        break;
      case PlayerRepeatMode.all:
        _repeatMode = PlayerRepeatMode.one;
        break;
      case PlayerRepeatMode.one:
        _repeatMode = PlayerRepeatMode.off;
        break;
    }
    _syncLoopMode();
    _repeatModeController.add(_repeatMode);
  }

  /// Updates track rating and synchronizes state in queue & player
  Future<void> updateTrackRating(Track track, int newRating) async {
    final updated = track.copyWith(rating: newRating);
    await DBHelper.instance.updateRating(track.id, newRating);

    _updateTrackInQueues(updated);
    if (currentTrack?.id == track.id) {
      _currentTrackController.add(updated);
    }
  }

  void _updateTrackInQueues(Track updated) {
    for (int i = 0; i < _originalQueue.length; i++) {
      if (_originalQueue[i].id == updated.id) {
        _originalQueue[i] = updated;
      }
    }
    for (int i = 0; i < _playbackQueue.length; i++) {
      if (_playbackQueue[i].id == updated.id) {
        _playbackQueue[i] = updated;
      }
    }
    _queueController.add(_playbackQueue);
  }

  /// Download track for offline playback
  Future<void> downloadTrack(Track track) async {
    if (track.isCached || track.streamUrl.isEmpty) return;

    final trackId = track.id;
    _downloadingProgress[trackId] = 0.01;
    _downloadProgressController.add(Map.from(_downloadingProgress));

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheFolder = Directory(p.join(appDir.path, 'music_cache'));
      if (!await cacheFolder.exists()) {
        await cacheFolder.create(recursive: true);
      }

      // Safe filename
      final safeName = '${track.id}.mp3';
      final savePath = p.join(cacheFolder.path, safeName);
      final file = File(savePath);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(track.streamUrl));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? track.fileSize;
      var receivedBytes = 0;
      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadingProgress[trackId] = receivedBytes / totalBytes;
          _downloadProgressController.add(Map.from(_downloadingProgress));
        }
      }).asFuture();

      await sink.flush();
      await sink.close();

      final downloadedSize = await file.length();
      final finalSize = downloadedSize > 0 ? downloadedSize : receivedBytes;

      _downloadingProgress.remove(trackId);
      _downloadProgressController.add(Map.from(_downloadingProgress));

      final updated = track.copyWith(
        localCachePath: savePath,
        fileSize: finalSize,
      );
      await DBHelper.instance.updateCachePath(track.id, savePath, fileSize: finalSize);
      _updateTrackInQueues(updated);
      if (currentTrack?.id == track.id) {
        _currentTrackController.add(updated);
      }

      final idx = _playbackQueue.indexWhere((t) => t.id == track.id);
      if (idx != -1 && _playlist != null && idx < _playlist!.length && idx != _currentIndex) {
        try {
          await _playlist!.removeAt(idx);
          await _playlist!.insert(idx, _buildAudioSource(updated));
        } catch (_) {}
      }
    } catch (e) {
      _downloadingProgress.remove(trackId);
      _downloadProgressController.add(Map.from(_downloadingProgress));
      rethrow;
    }
  }

  /// Deletes local cached file for a track
  Future<void> deleteTrackCache(Track track) async {
    if (track.localCachePath != null && track.localCachePath!.isNotEmpty) {
      try {
        final file = File(track.localCachePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    await DBHelper.instance.updateCachePath(track.id, null);
    final updated = track.copyWith(clearCachePath: true);
    _updateTrackInQueues(updated);
    if (currentTrack?.id == track.id) {
      _currentTrackController.add(updated);
    }

    final idx = _playbackQueue.indexWhere((t) => t.id == track.id);
    if (idx != -1 && _playlist != null && idx < _playlist!.length && idx != _currentIndex) {
      try {
        await _playlist!.removeAt(idx);
        await _playlist!.insert(idx, _buildAudioSource(updated));
      } catch (_) {}
    }
  }

  /// Removes tracks from queues (e.g. when 1-star tracks are deleted)
  Future<void> removeTracks(List<String> trackIds) async {
    final idsSet = trackIds.toSet();
    final wasPlayingDeleted = currentTrack != null && idsSet.contains(currentTrack!.id);

    _originalQueue.removeWhere((t) => idsSet.contains(t.id));
    _playbackQueue.removeWhere((t) => idsSet.contains(t.id));

    if (_playbackQueue.isEmpty) {
      await _player.stop();
      _playlist = null;
      _currentIndex = -1;
      _currentTrackController.add(null);
    } else if (wasPlayingDeleted) {
      await _loadPlaylistAndPlay(initialIndex: 0);
    } else {
      if (currentTrack != null) {
        _currentIndex = _playbackQueue.indexWhere((t) => t.id == currentTrack!.id);
      }
      await _loadPlaylistAndPlay(
        initialIndex: _currentIndex.clamp(0, _playbackQueue.length - 1),
        initialPosition: _player.position,
        play: _player.playing,
      );
    }

    _queueController.add(_playbackQueue);
  }

  void dispose() {
    _cancelReconnectAttempts();
    _waitingForNetworkController.close();
    _player.dispose();
    _currentTrackController.close();
    _queueController.close();
    _isShuffleController.close();
    _repeatModeController.close();
    _downloadProgressController.close();
  }
}
