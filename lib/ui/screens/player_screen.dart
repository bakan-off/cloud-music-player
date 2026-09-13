import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/audio/audio_manager.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/star_rating_bar.dart';

class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audio = AudioManager.instance;

    return StreamBuilder<Track?>(
      stream: audio.currentTrackStream,
      initialData: audio.currentTrack,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data;
        if (track == null) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton()),
            body: Center(
              child: Text(
                'Ничего не воспроизводится',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }

        return StreamBuilder<PlayerState>(
          stream: audio.player.playerStateStream,
          builder: (context, playerStateSnapshot) {
            final playerState = playerStateSnapshot.data;
            final isPlaying = playerState?.playing ?? false;

            if (isPlaying) {
              if (!_rotationController.isAnimating) {
                _rotationController.repeat();
              }
            } else {
              _rotationController.stop();
            }

            return Scaffold(
              backgroundColor: AppTheme.bgDark,
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                  onPressed: () => Navigator.pop(context),
                ),
                title: const Text('Сейчас играет', style: TextStyle(fontSize: 16)),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: Icon(
                      track.isCached ? Icons.download_done_rounded : Icons.download_rounded,
                      color: track.isCached ? AppTheme.successColor : AppTheme.textSecondary,
                    ),
                    tooltip: track.isCached ? 'Закэшировано (Оффлайн)' : 'Скачать для оффлайна',
                    onPressed: () async {
                      await ref.read(libraryProvider.notifier).toggleCache(track);
                    },
                  ),
                ],
              ),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Column(
                    children: [
                      const Spacer(),

                      // Vinyl / Album artwork
                      Center(
                        child: AnimatedBuilder(
                          animation: _rotationController,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _rotationController.value * 2 * 3.14159265,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 250,
                            height: 250,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.black,
                                  const Color(0xFF1E2433),
                                  Colors.black,
                                  AppTheme.primaryColor.withOpacity(0.3),
                                ],
                                stops: const [0.0, 0.7, 0.95, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withOpacity(isPlaying ? 0.35 : 0.1),
                                  blurRadius: 36,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primaryColor,
                                ),
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Track Metadata
                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.getTrackTitleStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.artist,
                        textAlign: TextAlign.center,
                        style: AppTheme.getTrackArtistStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Offline / Cloud Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: track.isCached
                              ? AppTheme.successColor.withOpacity(0.15)
                              : AppTheme.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: track.isCached
                                ? AppTheme.successColor.withOpacity(0.4)
                                : AppTheme.primaryColor.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              track.isCached ? Icons.check_circle_rounded : Icons.cloud_queue_rounded,
                              size: 14,
                              color: track.isCached ? AppTheme.successColor : AppTheme.primaryAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              track.isCached ? 'Оффлайн кэш' : 'Стриминг из облака',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: track.isCached ? AppTheme.successColor : AppTheme.primaryAccent,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Rating Stars Widget
                      Column(
                        children: [
                          StarRatingBar(
                            rating: track.rating,
                            size: 36,
                            onRatingChanged: (newRating) {
                              ref.read(libraryProvider.notifier).updateTrackRating(track, newRating);
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.rating == 0
                                ? 'Нажмите на звезду для оценки'
                                : 'Оценка: ${track.rating} / 5',
                            style: TextStyle(
                              fontSize: 13,
                              color: track.rating == 1
                                  ? AppTheme.dangerColor
                                  : AppTheme.textSecondary,
                              fontWeight: track.rating == 1 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (track.rating == 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Трек будет удален при очистке 1★',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.dangerColor.withOpacity(0.8),
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Progress Bar
                      StreamBuilder<Duration>(
                        stream: audio.player.positionStream,
                        builder: (context, posSnapshot) {
                          final position = posSnapshot.data ?? Duration.zero;
                          final duration = audio.player.duration ?? Duration.zero;
                          final buffered = audio.player.bufferedPosition;

                          return ProgressBar(
                            progress: position,
                            buffered: buffered,
                            total: duration,
                            progressBarColor: AppTheme.primaryAccent,
                            baseBarColor: AppTheme.dividerDark,
                            bufferedBarColor: AppTheme.dividerDark.withOpacity(0.5),
                            thumbColor: AppTheme.primaryAccent,
                            thumbRadius: 7,
                            timeLabelTextStyle: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                            onSeek: (newPos) {
                              audio.player.seek(newPos);
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Playback Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Shuffle
                          StreamBuilder<bool>(
                            stream: audio.isShuffleStream,
                            initialData: audio.isShuffle,
                            builder: (context, shuffleSnapshot) {
                              final isShuffle = shuffleSnapshot.data ?? false;
                              return IconButton(
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: isShuffle ? AppTheme.primaryAccent : AppTheme.textSecondary,
                                ),
                                tooltip: 'Случайный порядок',
                                onPressed: () => audio.toggleShuffle(),
                              );
                            },
                          ),

                          // Previous
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, size: 36),
                            color: AppTheme.textPrimary,
                            onPressed: () => audio.skipToPrevious(),
                          ),

                          // Play / Pause
                          GestureDetector(
                            onTap: () => audio.playOrPause(),
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.primaryColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withOpacity(0.4),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),

                          // Next
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, size: 36),
                            color: AppTheme.textPrimary,
                            onPressed: () => audio.skipToNext(),
                          ),

                          // Repeat Mode
                          StreamBuilder<PlayerRepeatMode>(
                            stream: audio.repeatModeStream,
                            initialData: audio.repeatMode,
                            builder: (context, repeatSnapshot) {
                              final mode = repeatSnapshot.data ?? PlayerRepeatMode.off;
                              IconData icon = Icons.repeat_rounded;
                              Color color = AppTheme.textSecondary;
                              if (mode == PlayerRepeatMode.all) {
                                color = AppTheme.primaryAccent;
                              } else if (mode == PlayerRepeatMode.one) {
                                icon = Icons.repeat_one_rounded;
                                color = AppTheme.primaryAccent;
                              }

                              return IconButton(
                                icon: Icon(icon, color: color),
                                tooltip: 'Режим повтора',
                                onPressed: () => audio.toggleRepeatMode(),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
