import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../models/track.dart';

class CloudParser {
  static const _supportedAudioExtensions = {
    '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac', '.opus', '.wma'
  };

  /// Parses a public link (Google Drive, Yandex Disk, or direct stream)
  static Future<List<Track>> parsePublicUrl(String url) async {
    final cleanUrl = url.trim();

    if (cleanUrl.contains('drive.google.com')) {
      return await _fetchGoogleDriveFolder(cleanUrl);
    } else if (cleanUrl.contains('yadi.sk') || cleanUrl.contains('disk.yandex.')) {
      return await _fetchYandexPublicFolder(cleanUrl);
    } else if (_isDirectAudioUrl(cleanUrl)) {
      return [_createDirectUrlTrack(cleanUrl)];
    } else {
      // Fallback: attempt Yandex Disk API just in case, or throw readable error
      try {
        return await _fetchYandexPublicFolder(cleanUrl);
      } catch (e) {
        throw Exception('Не удалось распознать ссылку как публичную папку Google Drive / Яндекс.Диска или аудиофайл.');
      }
    }
  }

  static Future<List<Track>> _fetchGoogleDriveFolder(String url) async {
    // Extract folder ID
    String? folderId;
    final folderMatch = RegExp(r'/folders/([a-zA-Z0-9_\-]{25,})').firstMatch(url);
    if (folderMatch != null) {
      folderId = folderMatch.group(1);
    } else {
      final idParam = Uri.tryParse(url)?.queryParameters['id'];
      if (idParam != null && idParam.length >= 25) {
        folderId = idParam;
      }
    }

    // 1. First priority: Use Google Drive embedded folder view.
    // This official Google endpoint returns ALL files in a public folder (800+ files)
    // without pagination cutoff, and without requiring any API key or OAuth!
    if (folderId != null) {
      try {
        final embedUrl = 'https://drive.google.com/embeddedfolderview?id=$folderId#list';
        final embedResponse = await http.get(
          Uri.parse(embedUrl),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        );

        if (embedResponse.statusCode == 200) {
          final html = embedResponse.body;
          final regex = RegExp(
            r'id="entry-([a-zA-Z0-9_\-]{25,})"[\s\S]*?class="flip-entry-title">([^<]+)<\/div>',
            caseSensitive: false,
          );

          final tracks = <Track>[];
          final seenIds = <String>{};
          final matches = regex.allMatches(html);

          for (final m in matches) {
            final fileId = m.group(1);
            var rawName = m.group(2)?.trim() ?? '';
            if (fileId == null || seenIds.contains(fileId)) continue;

            rawName = rawName
                .replaceAll('&#39;', "'")
                .replaceAll('&amp;', '&')
                .replaceAll('&quot;', '"')
                .replaceAll('&lt;', '<')
                .replaceAll('&gt;', '>');

            final lower = rawName.toLowerCase();
            final isAudio = _supportedAudioExtensions.any((ext) => lower.endsWith(ext));

            if (isAudio) {
              seenIds.add(fileId);
              final parsed = _parseTitleAndArtist(rawName);
              final streamUrl = 'https://drive.usercontent.google.com/download?id=$fileId&export=download';

              tracks.add(
                Track(
                  id: fileId,
                  title: parsed['title']!,
                  artist: parsed['artist']!,
                  streamUrl: streamUrl,
                  cloudPath: 'gdrive://$fileId/$rawName',
                  sourceType: 'google_drive',
                ),
              );
            }
          }

          if (tracks.isNotEmpty) {
            return tracks;
          }
        }
      } catch (_) {
        // Fallback to other methods if embed fails
      }
    }

    // 2. Fallback: regular web scraping
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка доступа к Google Drive (${response.statusCode})');
    }

    final html = response.body;
    final rowRegex = RegExp(
      r'<tr[^>]+data-id="([a-zA-Z0-9_\-]{25,})"[^>]*>([\s\S]*?)<\/tr>',
      caseSensitive: false,
    );
    final nameRegex = RegExp(
      r'(?:aria-label|data-tooltip)="([^"]+?\.(?:mp3|wav|ogg|m4a|flac|aac|opus|wma))(?:\s+Audio)?',
      caseSensitive: false,
    );

    final tracks = <Track>[];
    final seenIds = <String>{};
    final matches = rowRegex.allMatches(html);

    for (final m in matches) {
      final fileId = m.group(1);
      final inner = m.group(2) ?? '';
      if (fileId == null || seenIds.contains(fileId)) continue;

      final nameMatch = nameRegex.firstMatch(inner);
      if (nameMatch != null) {
        seenIds.add(fileId);
        var rawName = nameMatch.group(1)!;
        // Decode HTML entities
        rawName = rawName
            .replaceAll('&#39;', "'")
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');

        final parsed = _parseTitleAndArtist(rawName);
        final streamUrl = 'https://drive.usercontent.google.com/download?id=$fileId&export=download';

        tracks.add(
          Track(
            id: fileId,
            title: parsed['title']!,
            artist: parsed['artist']!,
            streamUrl: streamUrl,
            cloudPath: 'gdrive://$fileId/$rawName',
            sourceType: 'google_drive',
          ),
        );
      }
    }

    if (tracks.isEmpty) {
      // Check if it's a single file link
      final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_\-]{25,})').firstMatch(url);
      if (fileMatch != null) {
        final fileId = fileMatch.group(1)!;
        final streamUrl = 'https://drive.usercontent.google.com/download?id=$fileId&export=download';
        tracks.add(
          Track(
            id: fileId,
            title: 'Google Drive Audio',
            artist: 'Облачный трек',
            streamUrl: streamUrl,
            cloudPath: 'gdrive://$fileId',
            sourceType: 'google_drive',
          ),
        );
      }
    }

    return tracks;
  }

  static bool _isDirectAudioUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    return _supportedAudioExtensions.any((ext) => lower.endsWith(ext));
  }

  static Track _createDirectUrlTrack(String url) {
    final fileName = Uri.parse(url).pathSegments.isNotEmpty
        ? Uri.decodeComponent(Uri.parse(url).pathSegments.last)
        : 'Audio Stream';
    final parsed = _parseTitleAndArtist(fileName);
    final id = md5.convert(utf8.encode(url)).toString();

    return Track(
      id: id,
      title: parsed['title']!,
      artist: parsed['artist']!,
      streamUrl: url,
      cloudPath: url,
      sourceType: 'direct_url',
    );
  }

  static Future<List<Track>> _fetchYandexPublicFolder(String publicUrl, {String? subPath}) async {
    final tracks = <Track>[];
    var offset = 0;
    const limit = 200;
    int total = 0;

    do {
      var apiUrl = 'https://cloud-api.yandex.net/v1/disk/public/resources?public_key=${Uri.encodeComponent(publicUrl)}&limit=$limit&offset=$offset';
      if (subPath != null && subPath.isNotEmpty) {
        apiUrl += '&path=${Uri.encodeComponent(subPath)}';
      }

      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки из Яндекс.Диска (${response.statusCode}): ${response.body}');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      final embedded = data['_embedded'];
      if (embedded == null || embedded['items'] == null) {
        // It might be a single file
        if (data['type'] == 'file' && _isAudioItem(data)) {
          tracks.add(_yandexItemToTrack(data, publicUrl));
        }
        return tracks;
      }

      total = (embedded['total'] as num?)?.toInt() ?? 0;
      final items = embedded['items'] as List;
      for (final item in items) {
        if (item['type'] == 'file' && _isAudioItem(item)) {
          tracks.add(_yandexItemToTrack(item, publicUrl));
        } else if (item['type'] == 'dir') {
          // Fetch subfolder recursively
          try {
            final subPath = item['path'] as String?;
            if (subPath != null) {
              final subTracks = await _fetchYandexPublicFolder(publicUrl, subPath: subPath);
              tracks.addAll(subTracks);
            }
          } catch (_) {
            // Skip inaccessible subfolders gracefully
          }
        }
      }
      offset += items.length;
      if (items.isEmpty) break;
    } while (offset < total);

    return tracks;
  }

  static bool _isAudioItem(Map<String, dynamic> item) {
    final mime = (item['mime_type'] as String? ?? '').toLowerCase();
    final name = (item['name'] as String? ?? '').toLowerCase();

    if (mime.startsWith('audio/')) return true;
    return _supportedAudioExtensions.any((ext) => name.endsWith(ext));
  }

  static Track _yandexItemToTrack(Map<String, dynamic> item, String publicUrl) {
    final name = item['name'] as String? ?? 'Неизвестный трек';
    final parsed = _parseTitleAndArtist(name);
    final downloadUrl = item['file'] as String? ?? '';
    final path = item['path'] as String? ?? name;
    final size = (item['size'] as num?)?.toInt() ?? 0;

    // Stable ID based on public URL + path inside folder
    final id = md5.convert(utf8.encode('$publicUrl:$path')).toString();

    return Track(
      id: id,
      title: parsed['title']!,
      artist: parsed['artist']!,
      streamUrl: downloadUrl,
      cloudPath: path,
      fileSize: size,
      sourceType: 'yandex_public',
    );
  }

  /// Scans a local device/desktop directory for audio files
  static Future<List<Track>> scanLocalDirectory(Directory dir) async {
    final tracks = <Track>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final path = entity.path;
        final lower = path.toLowerCase();
        if (_supportedAudioExtensions.any((ext) => lower.endsWith(ext))) {
          final fileName = entity.uri.pathSegments.last;
          final parsed = _parseTitleAndArtist(fileName);
          final stat = await entity.stat();
          final id = md5.convert(utf8.encode(path)).toString();

          tracks.add(
            Track(
              id: id,
              title: parsed['title']!,
              artist: parsed['artist']!,
              streamUrl: path,
              cloudPath: path,
              localCachePath: path, // Already local
              fileSize: stat.size,
              sourceType: 'local_file',
            ),
          );
        }
      }
    }

    return tracks;
  }

  /// Extracts Title and Artist from common formats: "Artist - Title.mp3" or "01. Artist - Title.mp3"
  static Map<String, String> _parseTitleAndArtist(String rawFileName) {
    // Remove extension
    var clean = rawFileName;
    for (final ext in _supportedAudioExtensions) {
      if (clean.toLowerCase().endsWith(ext)) {
        clean = clean.substring(0, clean.length - ext.length);
        break;
      }
    }

    // Remove leading track numbers like "01. ", "01 - ", "1. "
    clean = clean.replaceFirst(RegExp(r'^\d+[\s\.\-_]+'), '').trim();

    if (clean.contains(' - ')) {
      final parts = clean.split(' - ');
      final artist = parts[0].trim();
      final title = parts.sublist(1).join(' - ').trim();
      return {'artist': artist.isNotEmpty ? artist : 'Неизвестный исполнитель', 'title': title.isNotEmpty ? title : clean};
    }

    return {
      'artist': 'Неизвестный исполнитель',
      'title': clean.isNotEmpty ? clean : 'Без названия',
    };
  }
}
