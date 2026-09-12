import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/db_helper.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../theme/app_theme.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _checkCountOnly() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'Пожалуйста, вставьте ссылку на папку или аудиофайл.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Проверка папки и подсчет аудиофайлов...';
      _isSuccess = false;
    });

    try {
      final count = await ref.read(libraryProvider.notifier).checkCloudFolderCount(url);
      setState(() {
        _isProcessing = false;
        _isSuccess = true;
        _statusMessage = 'В папке обнаружено: $count аудиофайлов (MP3/FLAC/M4A). Нажмите «Загрузить / Синхронизировать», чтобы сохранить их в плеер.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _isSuccess = false;
        _statusMessage = 'Ошибка проверки: $e';
      });
    }
  }

  Future<void> _importOrSyncUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'Пожалуйста, вставьте ссылку на папку или аудиофайл.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Подключение к облаку и синхронизация треков...';
      _isSuccess = false;
    });

    try {
      final result = await ref.read(libraryProvider.notifier).syncWithCloud(folderUrl: url);
      setState(() {
        _isProcessing = false;
        _isSuccess = true;
        _statusMessage = 'Синхронизация завершена!\n'
            '• Всего треков в облаке: ${result.totalCloudTracks}\n'
            '• Добавлено новых: ${result.addedTracks}\n'
            '• Удалено отсутствующих: ${result.removedTracks}';
        _urlController.clear();
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _isSuccess = false;
        _statusMessage = 'Ошибка: $e';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _urlController.text = data!.text!.trim();
    }
  }

  Future<void> _pickAndPreviewLocalFile() async {
    try {
      final count = await ref.read(libraryProvider.notifier).importLocalAudioFiles();
      if (count > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Добавлено $count локальных трек(ов)'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.dangerColor),
        );
      }
    }
  }

  Future<void> _loadDemoTracks() async {
    final demoTracks = [
      Track(
        id: 'demo_1',
        title: 'Lofi Study Beat',
        artist: 'Chill Audio Library',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        cloudPath: 'demo/lofi_1.mp3',
        durationMs: 372000,
        rating: 5,
        sourceType: 'direct_url',
      ),
      Track(
        id: 'demo_2',
        title: 'Deep Ambient Waves',
        artist: 'Relaxation Collective',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        cloudPath: 'demo/ambient_2.mp3',
        durationMs: 423000,
        rating: 4,
        sourceType: 'direct_url',
      ),
      Track(
        id: 'demo_3',
        title: 'Synthwave Night Drive',
        artist: 'Retro Beats',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
        cloudPath: 'demo/synth_3.mp3',
        durationMs: 345000,
        rating: 1, // 1 star demo
        sourceType: 'direct_url',
      ),
      Track(
        id: 'demo_4',
        title: 'Acoustic Guitar Morning',
        artist: 'Indie Artist',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
        cloudPath: 'demo/acoustic_4.mp3',
        durationMs: 302000,
        rating: 1, // 1 star demo
        sourceType: 'direct_url',
      ),
    ];

    await DBHelper.instance.insertTracks(demoTracks);
    await ref.read(libraryProvider.notifier).loadTracks();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Добавлено 4 тестовых трека (включая 1★ для проверки очистки)!'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить и синхронизировать'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Active Connected Cloud Folder
            if (libraryState.activeCloudUrl != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_done_rounded, color: AppTheme.successColor, size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Подключенная папка в облаке',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                        ),
                        if (_isProcessing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryAccent),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      libraryState.activeCloudUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'В облаке: ${libraryState.lastCloudCheckCount ?? libraryState.tracks.length} треков',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryAccent),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: const Text('Синхронизировать', style: TextStyle(fontSize: 12)),
                          onPressed: _isProcessing
                              ? null
                              : () async {
                                  setState(() {
                                    _isProcessing = true;
                                    _statusMessage = 'Синхронизация с облаком...';
                                  });
                                  try {
                                    final res = await ref.read(libraryProvider.notifier).syncWithCloud();
                                    setState(() {
                                      _isProcessing = false;
                                      _isSuccess = true;
                                      _statusMessage = 'Синхронизировано: в облаке ${res.totalCloudTracks} треков. '
                                          'Добавлено: ${res.addedTracks}, удалено: ${res.removedTracks}.';
                                    });
                                  } catch (e) {
                                    setState(() {
                                      _isProcessing = false;
                                      _isSuccess = false;
                                      _statusMessage = 'Ошибка: $e';
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Section 2: Input Cloud Link
            const Row(
              children: [
                Icon(Icons.add_link_rounded, color: AppTheme.primaryAccent, size: 24),
                SizedBox(width: 10),
                Text(
                  'Папка в облаке (Google Диск / Яндекс)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Вставьте публичную ссылку на открытую папку Google Drive или Яндекс.Диска. '
              'Авторизация и ключи API не требуются — приложение автоматически загрузит всю коллекцию.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'drive.google.com/drive/folders/... или disk.yandex.ru/d/...',
                prefixIcon: const Icon(Icons.link_rounded, color: AppTheme.textSecondary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded, color: AppTheme.primaryAccent),
                  tooltip: 'Вставить из буфера',
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                // Check Count Button
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.dividerDark),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.numbers_rounded, size: 18, color: AppTheme.textSecondary),
                    label: const Text(
                      'Проверить количество',
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    ),
                    onPressed: _isProcessing ? null : _checkCountOnly,
                  ),
                ),
                const SizedBox(width: 10),

                // Load / Sync Button
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(_isProcessing ? 'Загрузка...' : 'Загрузить в плеер'),
                    onPressed: _isProcessing ? null : _importOrSyncUrl,
                  ),
                ),
              ],
            ),

            if (_statusMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? AppTheme.successColor.withOpacity(0.15)
                      : AppTheme.dangerColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isSuccess
                        ? AppTheme.successColor.withOpacity(0.4)
                        : AppTheme.dangerColor.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: _isSuccess ? AppTheme.successColor : AppTheme.dangerColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: _isSuccess ? AppTheme.textPrimary : AppTheme.dangerColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),
            const Divider(color: AppTheme.dividerDark),
            const SizedBox(height: 24),

            // Section 3: Local Audio File
            const Row(
              children: [
                Icon(Icons.folder_open_rounded, color: AppTheme.primaryAccent, size: 24),
                SizedBox(width: 10),
                Text(
                  'Открыть локальный трек',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Выберите аудиофайлы на телефоне или компьютере, чтобы прослушать их, сразу выставить звезды рейтинга и сохранить в коллекцию.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppTheme.primaryAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.audio_file_rounded, color: AppTheme.primaryAccent),
                label: const Text(
                  'Выбрать файл(ы) на устройстве',
                  style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                ),
                onPressed: _pickAndPreviewLocalFile,
              ),
            ),

            const SizedBox(height: 32),
            const Divider(color: AppTheme.dividerDark),
            const SizedBox(height: 24),

            // Section 4: Demo / Test Pack
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: AppTheme.starColor, size: 24),
                SizedBox(width: 10),
                Text(
                  'Быстрый старт (Тестовые треки)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Хотите сразу протестировать воспроизведение, оффлайн-кэш, шаффл и очистку 1-звездочных треков? Добавьте готовый демо-набор в 1 клик.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.cardDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppTheme.dividerDark),
                  ),
                ),
                icon: const Icon(Icons.playlist_add_check_rounded, color: AppTheme.starColor),
                label: const Text(
                  'Добавить 4 тестовых трека',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
                onPressed: _loadDemoTracks,
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
