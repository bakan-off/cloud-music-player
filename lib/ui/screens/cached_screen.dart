import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/audio_manager.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/star_rating_bar.dart';

class CachedScreen extends ConsumerWidget {
  const CachedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryProvider);
    final cachedTracks = libraryState.tracks.where((t) => t.isCached).toList();
    final audio = AudioManager.instance;

    final totalBytes = cachedTracks.fold<int>(0, (sum, t) => sum + t.fileSize);
    final formattedTotalSize = totalBytes > 0
        ? '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '0 MB';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Оффлайн кэш'),
        actions: [
          if (cachedTracks.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: AppTheme.dangerColor),
              tooltip: 'Очистить весь кэш',
              onPressed: () => _confirmClearAllCache(context, ref, cachedTracks),
            ),
        ],
      ),
      body: Column(
        children: [
          // Storage Info Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.dividerDark),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.offline_pin_rounded, color: AppTheme.successColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cachedTracks.length} треков доступно без интернета',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Занято на устройстве: $formattedTotalSize',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Shuffle button
          if (cachedTracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Слушать оффлайн на шаффле'),
                  onPressed: () async {
                    if (!audio.isShuffle) {
                      await audio.toggleShuffle();
                    }
                    await audio.setQueue(cachedTracks, startIndex: 0);
                  },
                ),
              ),
            ),

          const SizedBox(height: 8),

          // List of cached tracks
          Expanded(
            child: cachedTracks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_download_outlined,
                            size: 64,
                            color: AppTheme.textSecondary.withOpacity(0.4),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Нет сохраненных треков',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Чтобы слушать музыку без интернета, нажмите кнопку скачивания рядом с треком в медиатеке.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: cachedTracks.length,
                    itemBuilder: (context, index) {
                      final track = cachedTracks[index];

                      return StreamBuilder<Track?>(
                        stream: audio.currentTrackStream,
                        initialData: audio.currentTrack,
                        builder: (context, snapshot) {
                          final isCurrent = snapshot.data?.id == track.id;

                          return ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? AppTheme.primaryColor.withOpacity(0.25)
                                    : AppTheme.cardDark,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isCurrent ? AppTheme.primaryAccent : AppTheme.dividerDark,
                                ),
                              ),
                              child: Icon(
                                isCurrent ? Icons.volume_up_rounded : Icons.check_circle_rounded,
                                color: isCurrent ? AppTheme.primaryAccent : AppTheme.successColor,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                color: isCurrent ? AppTheme.primaryAccent : AppTheme.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${track.artist} • ${track.formattedSize}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StarRatingBar(
                                  rating: track.rating,
                                  size: 16,
                                  onRatingChanged: (newRating) {
                                    ref.read(libraryProvider.notifier).updateTrackRating(track, newRating);
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline_rounded, color: AppTheme.textSecondary, size: 20),
                                  tooltip: 'Удалить из памяти',
                                  onPressed: () async {
                                    await ref.read(libraryProvider.notifier).toggleCache(track);
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              await audio.setQueue(cachedTracks, startIndex: index);
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllCache(BuildContext context, WidgetRef ref, List<Track> cachedTracks) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить весь кэш?'),
        content: Text('Будут удалены оффлайн-файлы для всех ${cachedTracks.length} треков. Сами треки останутся в медиатеке.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            onPressed: () async {
              Navigator.pop(ctx);
              for (final t in cachedTracks) {
                await ref.read(libraryProvider.notifier).toggleCache(t);
              }
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }
}
