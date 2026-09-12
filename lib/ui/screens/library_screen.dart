import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/storage/db_helper.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/star_rating_bar.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryProvider);
    final notifier = ref.read(libraryProvider.notifier);
    final audio = AudioManager.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Медиатека'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Синхронизировать с облаком',
            onPressed: () async {
              if (libraryState.activeCloudUrl != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Синхронизация с облаком...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                try {
                  final res = await notifier.syncWithCloud();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'В облаке: ${res.totalCloudTracks} треков (новых: ${res.addedTracks}, удалено: ${res.removedTracks})',
                        ),
                        backgroundColor: AppTheme.primaryColor,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка синхронизации: $e'),
                        backgroundColor: AppTheme.dangerColor,
                      ),
                    );
                  }
                }
              } else {
                await notifier.loadTracks();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск по названию или исполнителю...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                suffixIcon: libraryState.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 20),
                        onPressed: () => notifier.setSearchQuery(''),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (val) => notifier.setSearchQuery(val),
            ),
          ),

          // Rating Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'Все (${libraryState.tracks.length})',
                  isSelected: libraryState.ratingFilter == null,
                  onSelected: () => notifier.setRatingFilter(null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '5 ★',
                  isSelected: libraryState.ratingFilter == 5,
                  onSelected: () => notifier.setRatingFilter(5),
                  iconColor: AppTheme.starColor,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '4 ★',
                  isSelected: libraryState.ratingFilter == 4,
                  onSelected: () => notifier.setRatingFilter(4),
                  iconColor: AppTheme.starColor,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '3 ★',
                  isSelected: libraryState.ratingFilter == 3,
                  onSelected: () => notifier.setRatingFilter(3),
                  iconColor: AppTheme.starColor,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '2 ★',
                  isSelected: libraryState.ratingFilter == 2,
                  onSelected: () => notifier.setRatingFilter(2),
                  iconColor: AppTheme.starColor,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '1 ★ (${libraryState.oneStarCount})',
                  isSelected: libraryState.ratingFilter == 1,
                  onSelected: () => notifier.setRatingFilter(1),
                  iconColor: AppTheme.dangerColor,
                  selectedColor: AppTheme.dangerColor.withOpacity(0.25),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Без оценки',
                  isSelected: libraryState.ratingFilter == 0,
                  onSelected: () => notifier.setRatingFilter(0),
                ),
              ],
            ),
          ),

          // 1-Star Cleanup Banner if there are any 1-star tracks
          if (libraryState.oneStarCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.dangerColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.dangerColor.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_delete_rounded, color: AppTheme.dangerColor, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Треков с 1★: ${libraryState.oneStarCount}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.dangerColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () => _confirmDeleteOneStar(context, ref, libraryState.oneStarCount),
                    child: const Text('Удалить все 1★', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Action bar (Shuffle All & Track Count)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: Row(
              children: [
                Text(
                  'Найдено: ${libraryState.filteredTracks.length}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const Spacer(),
                if (libraryState.filteredTracks.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.shuffle_rounded, size: 18, color: AppTheme.primaryAccent),
                    label: const Text(
                      'Слушать на шаффле',
                      style: TextStyle(color: AppTheme.primaryAccent, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () async {
                      if (!audio.isShuffle) {
                        await audio.toggleShuffle();
                      }
                      await audio.setQueue(libraryState.filteredTracks, startIndex: 0);
                    },
                  ),
              ],
            ),
          ),

          // Track List
          Expanded(
            child: libraryState.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : libraryState.filteredTracks.isEmpty
                    ? _buildEmptyState(context, libraryState)
                    : ListView.builder(
                        itemCount: libraryState.filteredTracks.length,
                        itemBuilder: (context, index) {
                          final track = libraryState.filteredTracks[index];
                          return _buildTrackTile(context, ref, track, libraryState.filteredTracks, index);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
    Color? iconColor,
    Color? selectedColor,
  }) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : AppTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      backgroundColor: AppTheme.cardDark,
      selectedColor: selectedColor ?? AppTheme.primaryColor,
      side: BorderSide(
        color: isSelected
            ? (selectedColor ?? AppTheme.primaryColor)
            : AppTheme.dividerDark,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildTrackTile(
    BuildContext context,
    WidgetRef ref,
    Track track,
    List<Track> currentList,
    int index,
  ) {
    final audio = AudioManager.instance;

    return StreamBuilder<Track?>(
      stream: audio.currentTrackStream,
      initialData: audio.currentTrack,
      builder: (context, snapshot) {
        final isCurrent = snapshot.data?.id == track.id;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
              isCurrent ? Icons.volume_up_rounded : Icons.music_note_rounded,
              color: isCurrent ? AppTheme.primaryAccent : AppTheme.textSecondary,
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
              fontSize: 14,
            ),
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
              if (track.isCached) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.successColor),
                const SizedBox(width: 2),
                const Text('Кэш', style: TextStyle(fontSize: 10, color: AppTheme.successColor)),
              ],
            ],
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
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
                color: AppTheme.surfaceDark,
                onSelected: (val) async {
                  if (val == 'cache') {
                    await ref.read(libraryProvider.notifier).toggleCache(track);
                  } else if (val == 'delete') {
                    await DBHelper.instance.deleteTrack(track.id);
                    await ref.read(libraryProvider.notifier).loadTracks();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'cache',
                    child: Row(
                      children: [
                        Icon(
                          track.isCached ? Icons.delete_outline_rounded : Icons.download_rounded,
                          size: 18,
                          color: track.isCached ? AppTheme.dangerColor : AppTheme.successColor,
                        ),
                        const SizedBox(width: 10),
                        Text(track.isCached ? 'Удалить из кэша' : 'Скачать в оффлайн'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.dangerColor),
                        SizedBox(width: 10),
                        Text('Удалить из медиатеки'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          onTap: () async {
            await audio.setQueue(currentList, startIndex: index);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, LibraryState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music_rounded, size: 64, color: AppTheme.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              state.searchQuery.isNotEmpty || state.ratingFilter != null
                  ? 'Ничего не найдено по фильтрам'
                  : 'Медиатека пуста',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              state.searchQuery.isNotEmpty || state.ratingFilter != null
                  ? 'Попробуйте изменить поисковый запрос или сбросить фильтр звезд'
                  : 'Добавьте публичную ссылку на облако или откройте локальные треки во вкладке «Импорт»',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteOneStar(BuildContext context, WidgetRef ref, int count) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.dangerColor),
            SizedBox(width: 10),
            Text('Удаление 1★'),
          ],
        ),
        content: Text(
          'Вы уверены, что хотите удалить $count трек(ов) с 1 звездой?\n\n'
          'Они будут удалены из медиатеки и их оффлайн-файлы будут очищены с устройства.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerColor),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final deleted = await ref.read(libraryProvider.notifier).deleteOneStarTracks();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Успешно удалено $deleted трек(ов)'),
                    backgroundColor: AppTheme.dangerColor,
                  ),
                );
              }
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}
