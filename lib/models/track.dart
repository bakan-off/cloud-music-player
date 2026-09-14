import 'dart:io';

class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String streamUrl;
  final String cloudPath;
  final String? localCachePath;
  final int rating; // 0 (unrated) or 1 to 5 stars
  final int fileSize;
  final String sourceType; // 'yandex_public', 'direct_url', 'local_file'
  final DateTime addedAt;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs = 0,
    required this.streamUrl,
    required this.cloudPath,
    this.localCachePath,
    this.rating = 0,
    this.fileSize = 0,
    this.sourceType = 'yandex_public',
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  bool get isCached => localCachePath != null && localCachePath!.isNotEmpty;
  bool get hasRating => rating > 0;

  /// Returns recorded fileSize or reads real file size directly from disk if cached
  int get actualFileSize {
    if (fileSize > 0) return fileSize;
    if (isCached && localCachePath != null) {
      try {
        final f = File(localCachePath!);
        if (f.existsSync()) {
          return f.lengthSync();
        }
      } catch (_) {}
    }
    return 0;
  }

  String get effectivePlayUri => (isCached ? localCachePath : streamUrl) ?? streamUrl;

  String get formattedDuration {
    if (durationMs <= 0) return '--:--';
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get formattedSize {
    final size = actualFileSize;
    if (size <= 0) return '';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? streamUrl,
    String? cloudPath,
    String? localCachePath,
    bool clearCachePath = false,
    int? rating,
    int? fileSize,
    String? sourceType,
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      streamUrl: streamUrl ?? this.streamUrl,
      cloudPath: cloudPath ?? this.cloudPath,
      localCachePath: clearCachePath ? null : (localCachePath ?? this.localCachePath),
      rating: rating ?? this.rating,
      fileSize: fileSize ?? this.fileSize,
      sourceType: sourceType ?? this.sourceType,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'streamUrl': streamUrl,
      'cloudPath': cloudPath,
      'localCachePath': localCachePath,
      'rating': rating,
      'fileSize': fileSize,
      'sourceType': sourceType,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Неизвестный трек',
      artist: map['artist'] as String? ?? 'Неизвестный исполнитель',
      album: map['album'] as String?,
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      streamUrl: map['streamUrl'] as String? ?? '',
      cloudPath: map['cloudPath'] as String? ?? '',
      localCachePath: map['localCachePath'] as String?,
      rating: (map['rating'] as num?)?.toInt() ?? 0,
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      sourceType: map['sourceType'] as String? ?? 'yandex_public',
      addedAt: map['addedAt'] != null
          ? DateTime.tryParse(map['addedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
