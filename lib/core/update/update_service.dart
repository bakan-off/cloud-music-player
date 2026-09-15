import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseTitle;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSize;
  final String apkFileName;
  final bool isUpdateAvailable;
  final DateTime? publishedAt;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkSize,
    required this.apkFileName,
    required this.isUpdateAvailable,
    this.publishedAt,
  });

  String get formattedSize {
    if (apkSize <= 0) return '';
    return '${(apkSize / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

class UpdateService {
  static final UpdateService instance = UpdateService._internal();
  UpdateService._internal();

  static const String currentVersion = '1.0.10';
  static const String repoOwner = 'bakan-off';
  static const String repoName = 'cloud-music-player';
  static const String githubRepoUrl = 'https://github.com/$repoOwner/$repoName';
  static const String releasesApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  /// Check GitHub for latest release
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(releasesApiUrl),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'CloudMusicPlayer-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String? ?? '').trim();
      final latestVer = tagName.replaceAll(RegExp(r'^v'), '');
      final releaseName = data['name'] as String? ?? 'Cloud Music Player $tagName';
      final body = data['body'] as String? ?? '';
      final publishedStr = data['published_at'] as String?;
      final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;

      final assets = data['assets'] as List<dynamic>? ?? [];
      String apkDownloadUrl = '';
      int apkSize = 0;
      String apkFileName = '';

      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkFileName = name;
          apkDownloadUrl = asset['browser_download_url'] as String? ?? '';
          apkSize = (asset['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }

      final hasUpdate = isNewerVersion(latestVer, currentVersion);

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVer,
        releaseTitle: releaseName,
        releaseNotes: body,
        apkDownloadUrl: apkDownloadUrl,
        apkSize: apkSize,
        apkFileName: apkFileName,
        isUpdateAvailable: hasUpdate,
        publishedAt: publishedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Compares whether [latest] is strictly newer than [current]
  static bool isNewerVersion(String latest, String current) {
    final cleanLatest = latest.replaceAll(RegExp(r'[^0-9.]'), '');
    final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');

    final latestParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = max(latestParts.length, currentParts.length);
    while (latestParts.length < maxLen) {
      latestParts.add(0);
    }
    while (currentParts.length < maxLen) {
      currentParts.add(0);
    }

    for (int i = 0; i < maxLen; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// Downloads APK and streams progress (0.0 to 1.0)
  Future<File> downloadApk(
    String url, {
    required void Function(double progress, int received, int total) onProgress,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    final response = await client.send(request);

    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/update_cloud_player.apk');
    if (await apkFile.exists()) {
      try {
        await apkFile.delete();
      } catch (_) {}
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;
    final sink = apkFile.openWrite();

    try {
      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
        onProgress(progress, receivedBytes, totalBytes);
      }).asFuture();

      await sink.flush();
      await sink.close();
      return apkFile;
    } catch (e) {
      await sink.close();
      if (await apkFile.exists()) {
        try {
          await apkFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Launches the Android system package installer for the downloaded APK
  Future<OpenResult> installApk(File apkFile) async {
    return await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );
  }
}
