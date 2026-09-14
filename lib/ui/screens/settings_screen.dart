import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/audio/voice_notifier.dart';
import '../../core/update/update_service.dart';
import '../../providers/font_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/theme_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isChecking = false;
  bool _isDownloading = false;
  bool _voiceAlertsEnabled = true;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  AppUpdateInfo? _updateInfo;
  File? _downloadedApk;
  String? _checkStatusMessage;

  @override
  void initState() {
    super.initState();
    _voiceAlertsEnabled = VoiceNotifier.instance.isEnabled;
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isChecking = true;
      _checkStatusMessage = null;
    });

    final info = await UpdateService.instance.checkForUpdate();

    if (!mounted) return;

    setState(() {
      _isChecking = false;
      _updateInfo = info;
      if (info == null) {
        _checkStatusMessage = 'Не удалось получить данные с GitHub. Проверьте подключение к интернету.';
      } else if (!info.isUpdateAvailable) {
        _checkStatusMessage = 'У вас установлена самая свежая версия приложения (${info.currentVersion}).';
      }
    });
  }

  Future<void> _startDownloadAndInstall(AppUpdateInfo info) async {
    if (info.apkDownloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('В релизе не найден установочный APK файл.'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = info.apkSize;
      _downloadedApk = null;
    });

    try {
      final file = await UpdateService.instance.downloadApk(
        info.apkDownloadUrl,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _downloadedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _downloadedApk = file;
      });

      // Launch Android package installer
      await _installApk(file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка скачивания: $e'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
    }
  }

  Future<void> _installApk(File file) async {
    final result = await UpdateService.instance.installApk(file);
    if (!mounted) return;

    if (result.message.isNotEmpty && result.type.name != 'done') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Статус установщика: ${result.message}'),
          backgroundColor: AppTheme.primaryAccent,
        ),
      );
    }
  }

  Future<void> _clearAllCache() async {
    final libraryState = ref.read(libraryProvider);
    final cachedTracks = libraryState.tracks.where((t) => t.isCached).toList();

    if (cachedTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кэш уже пуст')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить весь кэш?'),
        content: Text(
          'Будет удалено ${cachedTracks.length} локальных аудиофайлов. Сами треки останутся в медиатеке для стриминга из облака.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final track in cachedTracks) {
        await AudioManager.instance.deleteTrackCache(track);
      }
      await ref.read(libraryProvider.notifier).loadTracks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Очищено ${cachedTracks.length} треков из оффлайн-кэша.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final cachedTracks = libraryState.tracks.where((t) => t.isCached).toList();
    final totalCacheBytes = cachedTracks.fold<int>(0, (sum, t) => sum + t.actualFileSize);
    final formattedCacheSize = totalCacheBytes > 0
        ? '${(totalCacheBytes / (1024 * 1024)).toStringAsFixed(1)} МБ'
        : '0 МБ';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section: Themes & Fonts
          _buildSectionHeader('ОФОРМЛЕНИЕ И ТЕМЫ'),
          _buildThemeCard(),
          const SizedBox(height: 14),
          _buildFontCard(),

          const SizedBox(height: 24),

          // Section: Network & Voice Alerts
          _buildSectionHeader('СЕТЬ И ОПОВЕЩЕНИЯ'),
          _buildNetworkVoiceAlertCard(),

          const SizedBox(height: 24),

          // Section: Updates
          _buildSectionHeader('ОБНОВЛЕНИЕ ПРИЛОЖЕНИЯ'),
          _buildUpdateCard(),

          const SizedBox(height: 24),

          // Section: Storage & Cache
          _buildSectionHeader('ПАМЯТЬ И КЭШ'),
          _buildStorageCard(cachedTracks.length, formattedCacheSize),

          const SizedBox(height: 24),

          // Section: About
          _buildSectionHeader('О ПРОЕКТЕ'),
          _buildAboutCard(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildNetworkVoiceAlertCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerDark),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.record_voice_over_rounded,
                  color: AppTheme.primaryAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Голос при потере связи',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Озвучивать «Нет сигнала» и «Есть сигнал» при обрыве Wi-Fi и автоматически продолжать стрим',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _voiceAlertsEnabled,
                activeTrackColor: AppTheme.primaryAccent,
                onChanged: (val) async {
                  setState(() {
                    _voiceAlertsEnabled = val;
                  });
                  await VoiceNotifier.instance.setEnabled(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.dividerDark.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    side: BorderSide(color: AppTheme.dividerDark),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text(
                    'Тест: «Нет сигнала»',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () async {
                    try {
                      await VoiceNotifier.instance.testNoSignal();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔊 Проиграно: «Нет сигнала»'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ошибка звука: $e'),
                            backgroundColor: AppTheme.dangerColor,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    side: BorderSide(color: AppTheme.dividerDark),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  label: const Text(
                    'Тест: «Есть сигнал»',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () async {
                    try {
                      await VoiceNotifier.instance.testSignalRestored();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔊 Проиграно: «Есть сигнал»'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ошибка звука: $e'),
                            backgroundColor: AppTheme.dangerColor,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard() {
    final currentPreset = ref.watch(themeProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Цветовая палитра',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Выберите визуальное оформление плеера',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ...AppTheme.allPalettes.map((palette) {
            final isSelected = palette.preset == currentPreset;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? palette.primaryColor.withValues(alpha: 0.12)
                    : AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? palette.primaryColor : AppTheme.dividerDark,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  ref.read(themeProvider.notifier).setPreset(palette.preset);
                },
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.bgDark,
                    border: Border.all(color: palette.primaryColor, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.primaryAccent,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  palette.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? palette.primaryAccent : AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  palette.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: palette.primaryAccent,
                        size: 22,
                      )
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFontCard() {
    final currentFontPreset = ref.watch(fontProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.font_download_rounded, color: AppTheme.primaryAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                'Шрифт текста песен',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Выберите визуальный стиль шрифта для названий треков и авторов',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ...AppTheme.allFonts.map((font) {
            final isSelected = font.preset == currentFontPreset;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.12)
                    : AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppTheme.primaryAccent : AppTheme.dividerDark,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                onTap: () {
                  ref.read(fontProvider.notifier).setPreset(font.preset);
                },
                leading: Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
                  size: 20,
                ),
                title: Text(
                  font.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppTheme.primaryAccent : AppTheme.textPrimary,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      font.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Live preview container showing track title & artist in this font
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.cardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.dividerDark.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'Любимая песня • Знаменитый артист',
                        style: AppTheme.getTrackTitleStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppTheme.primaryAccent : AppTheme.textPrimary,
                          customPreset: font.preset,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUpdateCard() {
    final info = _updateInfo;
    final hasUpdate = info != null && info.isUpdateAvailable;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUpdate ? AppTheme.primaryAccent : AppTheme.dividerDark,
          width: hasUpdate ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (hasUpdate ? AppTheme.primaryAccent : AppTheme.primaryColor)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasUpdate ? Icons.system_update_rounded : Icons.info_outline_rounded,
                  color: hasUpdate ? AppTheme.primaryAccent : AppTheme.textSecondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Текущая версия',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'v${UpdateService.currentVersion}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isChecking)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: _isDownloading ? null : _checkForUpdates,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Проверить'),
                ),
            ],
          ),

          if (_checkStatusMessage != null && !hasUpdate) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_updateInfo != null && !_updateInfo!.isUpdateAvailable
                        ? AppTheme.successColor
                        : AppTheme.dangerColor)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _updateInfo != null && !_updateInfo!.isUpdateAvailable
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _updateInfo != null && !_updateInfo!.isUpdateAvailable
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _checkStatusMessage!,
                      style: TextStyle(
                        fontSize: 13,
                        color: _updateInfo != null && !_updateInfo!.isUpdateAvailable
                            ? AppTheme.successColor
                            : AppTheme.dangerColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Update available details block
          if (hasUpdate) ...[
            const SizedBox(height: 16),
            Divider(color: AppTheme.dividerDark),
            const SizedBox(height: 12),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ДОСТУПНО ОБНОВЛЕНИЕ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.successColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'v${info.latestVersion}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ],
            ),

            if (info.formattedSize.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Размер: ${info.formattedSize}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],

            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.dividerDark),
                ),
                child: Text(
                  info.releaseNotes,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Download progress or Action button
            if (_isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Скачивание обновления...',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      Text(
                        '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      minHeight: 8,
                      backgroundColor: AppTheme.surfaceDark,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_totalBytes > 0)
                    Text(
                      '${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} МБ',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                ],
              ),
            ] else if (_downloadedApk != null) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _installApk(_downloadedApk!),
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: const Text(
                    'Установить обновление',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _startDownloadAndInstall(info),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text(
                    'Скачать и обновить',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStorageCard(int count, String size) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerDark),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.sd_storage_rounded,
                  color: AppTheme.successColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Оффлайн треки',
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count треков • $size',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (count > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.dangerColor,
                  side: BorderSide(color: AppTheme.dangerColor),
                ),
                onPressed: _clearAllCache,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Очистить весь оффлайн-кэш'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_video_rounded, color: AppTheme.primaryAccent, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cloud Music Player',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Персональный облачный плеер',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Воспроизведение музыки напрямую из публичных папок Google Диска и Яндекс.Диска без подписок, ограничений и авторизации. Поддержка оффлайн-кэша, рейтингов 1–5 звезд и быстрой очистки.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: AppTheme.dividerDark),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Clipboard.setData(
                const ClipboardData(text: UpdateService.githubRepoUrl),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Ссылка на GitHub скопирована в буфер обмена'),
                  backgroundColor: AppTheme.primaryAccent,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, size: 20, color: AppTheme.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'github.com/bakan-off/cloud-music-player',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.primaryAccent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Скопировать ссылку',
                    onPressed: () {
                      Clipboard.setData(
                        const ClipboardData(text: UpdateService.githubRepoUrl),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Ссылка на GitHub скопирована'),
                          backgroundColor: AppTheme.primaryAccent,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
