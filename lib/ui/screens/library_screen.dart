import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/audio_manager.dart';
import '../../core/storage/db_helper.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/star_rating_bar.dart';
import 'settings_screen.dart';

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
          PopupMenuButton<TrackSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Сортировка (${libraryState.sortOption.label})',
            initialValue: libraryState.sortOption,
            onSelected: (opt) => notifier.setSortOption(opt),
            itemBuilder: (context) => TrackSortOption.values.map((opt) {
              final isSelected = libraryState.sortOption == opt;
              IconData icon;
              switch (opt) {
                case TrackSortOption.dateAddedDesc:
                  icon = Icons.access_time_rounded;
                  break;
                case TrackSortOption.dateAddedAsc:
                  icon = Icons.history_rounded;
                  break;
                case TrackSortOption.titleAsc:
                  icon = Icons.sort_by_alpha_rounded;
                  break;
                case TrackSortOption.titleDesc:
                  icon = Icons.sort_by_alpha_rounded;
                  break;
                case TrackSortOption.artistAsc:
                  icon = Icons.person_rounded;
                  break;
                case TrackSortOption.ratingDesc:
                  icon = Icons.star_rounded;
                  break;
                case TrackSortOption.durationDesc:
                  icon = Icons.timer_outlined;
                  break;
              }
              return PopupMenuItem<TrackSortOption>(
                value: opt,
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        opt.label,
                        style: TextStyle(
                          color: isSelected ? AppTheme.primaryAccent : AppTheme.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_rounded, size: 18, color: AppTheme.primaryAccent),
                  ],
                ),
              );
            }).toList(),
          ),
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
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
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textSecondary),
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

          // Folder Filter Chips (if more than 1 folder exists)
          if (libraryState.savedFolders.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Icon(Icons.folder_outlined, size: 18, color: AppTheme.textSecondary),
                    ),
                    _buildFilterChip(
                      label: 'Все папки',
                      isSelected: libraryState.selectedFolderUrl == null,
                      onSelected: () => notifier.setSelectedFolder(null),
                    ),
                    ...libraryState.savedFolders.map((f) {
                      final name = (f['name'] as String?)?.trim();
                      final displayName = (name != null && name.isNotEmpty) ? name : 'Папка';
                      final count = f['trackCount'] ?? 0;
                      final url = f['url'] as String;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: _buildFilterChip(
                          label: '$displayName ($count)',
                          isSelected: libraryState.selectedFolderUrl == url,
                          onSelected: () => notifier.setSelectedFolder(url),
                          selectedColor: AppTheme.primaryAccent.withOpacity(0.25),
                        ),
                      );
                    }),
                  ],
                ),
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
                  label: 'Новые (${libraryState.newTracksCount})',
                  isSelected: libraryState.ratingFilter == -1,
                  onSelected: () => notifier.setRatingFilter(-1),
                  icon: Icons.auto_awesome_rounded,
                  iconColor: AppTheme.primaryAccent,
                  selectedColor: AppTheme.primaryAccent.withOpacity(0.25),
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

          // Action bar (Shuffle All & Track Count)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: Row(
              children: [
                Text(
                  'Найдено: ${libraryState.filteredTracks.length}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  '• ${libraryState.sortOption.label}',
                  style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.7), fontSize: 11),
                ),
                const Spacer(),
                if (libraryState.filteredTracks.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(Icons.shuffle_rounded, size: 18, color: AppTheme.primaryAccent),
                    label: Text(
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
                ? Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : libraryState.filteredTracks.isEmpty
                    ? _buildEmptyState(context, libraryState)
                    : Scrollbar(
                        interactive: true,
                        thumbVisibility: true,
                        child: ListView.builder(
                          itemCount: libraryState.filteredTracks.length,
                          itemBuilder: (context, index) {
                            final track = libraryState.filteredTracks[index];
                            return _buildTrackTile(context, ref, track, libraryState.filteredTracks, index);
                          },
                        ),
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
    IconData? icon,
    Color? iconColor,
    Color? selectedColor,
  }) {
    return ChoiceChip(
      avatar: icon != null ? Icon(icon, size: 15, color: iconColor ?? Colors.white) : null,
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
            style: AppTheme.getTrackTitleStyle(
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
                  style: AppTheme.getTrackArtistStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (track.isCached) ...[
                const SizedBox(width: 4),
                Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.successColor),
                const SizedBox(width: 2),
                Text('Кэш', style: TextStyle(fontSize: 10, color: AppTheme.successColor)),
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
                icon: Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
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
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.dangerColor),
                        const SizedBox(width: 10),
                        const Text('Удалить из медиатеки'),
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              state.searchQuery.isNotEmpty || state.ratingFilter != null
                  ? 'Попробуйте изменить поисковый запрос или сбросить фильтр звезд'
                  : 'Добавьте публичную ссылку на облако или откройте локальные треки во вкладке «Импорт»',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
