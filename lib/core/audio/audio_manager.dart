import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../models/track.dart';
import '../storage/db_helper.dart';

enum PlayerRepeatMode { off, all, one }

class AudioManager {
  static final AudioManager instance = AudioManager._internal();
  AudioManager._internal() {
    _initAudioPlayer();
  }

  final AudioPlayer _player = AudioPlayer();
  AudioPlayer get player => _player;

  final List<Track> _originalQueue = [];
  final List<Track> _playbackQueue = [];
  int _currentIndex = -1;

  bool _isShuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;

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
  PlayerRepeatMode get repeatMode => _repeatMode;
  List<Track> get queue => List.unmodifiable(_playbackQueue);

  void _initAudioPlayer() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
    });
  }

  void _handleTrackCompleted() {
    if (_repeatMode == PlayerRepeatMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else if (hasNext) {
      skipToNext();
    } else if (_repeatMode == PlayerRepeatMode.all && _playbackQueue.isNotEmpty) {
      playTrackAtIndex(0);
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

  /// Sets a new queue and plays the track at [startIndex]
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
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
      await playTrackAtIndex(_currentIndex);
    }
  }

  Future<void> playTrackAtIndex(int index) async {
    if (index < 0 || index >= _playbackQueue.length) return;
    _currentIndex = index;
    final track = _playbackQueue[_currentIndex];
    _currentTrackController.add(track);

    try {
      if (track.isCached) {
        await _player.setFilePath(track.localCachePath!);
      } else {
        await _player.setUrl(track.streamUrl);
      }
      await _player.play();
    } catch (e) {
      // If cached file was moved/deleted or stream failed, try alternative
      if (track.isCached && track.streamUrl.isNotEmpty) {
        try {
          await _player.setUrl(track.streamUrl);
          await _player.play();
        } catch (_) {}
      }
    }
  }

  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (currentTrack == null && _playbackQueue.isNotEmpty) {
        await playTrackAtIndex(0);
      } else {
        await _player.play();
      }
    }
  }

  Future<void> skipToNext() async {
    if (_playbackQueue.isEmpty) return;
    var nextIndex = _currentIndex + 1;
    if (nextIndex >= _playbackQueue.length) {
      if (_repeatMode == PlayerRepeatMode.all) {
        nextIndex = 0;
      } else {
        return;
      }
    }
    await playTrackAtIndex(nextIndex);
  }

  Future<void> skipToPrevious() async {
    if (_playbackQueue.isEmpty) return;

    // If played more than 3 seconds, restart current track
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    var prevIndex = _currentIndex - 1;
    if (prevIndex < 0) {
      if (_repeatMode == PlayerRepeatMode.all) {
        prevIndex = _playbackQueue.length - 1;
      } else {
        prevIndex = 0;
      }
    }
    await playTrackAtIndex(prevIndex);
  }

  Future<void> toggleShuffle() async {
    _isShuffle = !_isShuffle;
    final curTrack = currentTrack;

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

      _downloadingProgress.remove(trackId);
      _downloadProgressController.add(Map.from(_downloadingProgress));

      final updated = track.copyWith(localCachePath: savePath);
      await DBHelper.instance.updateCachePath(track.id, savePath);
      _updateTrackInQueues(updated);
      if (currentTrack?.id == track.id) {
        _currentTrackController.add(updated);
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
  }

  /// Removes tracks from queues (e.g. when 1-star tracks are deleted)
  void removeTracks(List<String> trackIds) {
    final idsSet = trackIds.toSet();
    final wasPlayingDeleted = currentTrack != null && idsSet.contains(currentTrack!.id);

    _originalQueue.removeWhere((t) => idsSet.contains(t.id));
    _playbackQueue.removeWhere((t) => idsSet.contains(t.id));

    if (wasPlayingDeleted) {
      if (_playbackQueue.isNotEmpty) {
        playTrackAtIndex(0);
      } else {
        _player.stop();
        _currentIndex = -1;
        _currentTrackController.add(null);
      }
    } else if (currentTrack != null) {
      _currentIndex = _playbackQueue.indexWhere((t) => t.id == currentTrack!.id);
    }

    _queueController.add(_playbackQueue);
  }

  void dispose() {
    _player.dispose();
    _currentTrackController.close();
    _queueController.close();
    _isShuffleController.close();
    _repeatModeController.close();
    _downloadProgressController.close();
  }
}
