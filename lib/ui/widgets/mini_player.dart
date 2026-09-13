import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/audio/audio_manager.dart';
import '../../models/track.dart';
import '../screens/player_screen.dart';
import '../theme/app_theme.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = AudioManager.instance;

    return StreamBuilder<Track?>(
      stream: audio.currentTrackStream,
      initialData: audio.currentTrack,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data;
        if (track == null) return const SizedBox.shrink();

        return StreamBuilder<PlayerState>(
          stream: audio.player.playerStateStream,
          builder: (context, playerSnapshot) {
            final isPlaying = playerSnapshot.data?.playing ?? false;

            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) => const FullPlayerScreen(),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: AppTheme.dividerDark, width: 0.8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mini progress line on top
                    StreamBuilder<Duration>(
                      stream: audio.player.positionStream,
                      builder: (context, posSnapshot) {
                        final pos = posSnapshot.data?.inMilliseconds.toDouble() ?? 0.0;
                        final duration = audio.player.duration?.inMilliseconds.toDouble() ?? 1.0;
                        final progress = (pos / (duration > 0 ? duration : 1.0)).clamp(0.0, 1.0);

                        return ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 2.5,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                          ),
                        );
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          // Artwork Thumbnail
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.dividerDark),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: AppTheme.primaryAccent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title and Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (track.isCached)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4.0),
                                        child: Icon(
                                          Icons.check_circle_rounded,
                                          size: 14,
                                          color: AppTheme.successColor,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                    if (track.rating > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.star_rounded,
                                            size: 14,
                                            color: track.rating == 1
                                                ? AppTheme.dangerColor
                                                : AppTheme.starColor,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${track.rating}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: track.rating == 1
                                                  ? AppTheme.dangerColor
                                                  : AppTheme.starColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Controls
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 28,
                              color: AppTheme.primaryAccent,
                            ),
                            onPressed: () => audio.playOrPause(),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.skip_next_rounded,
                              size: 26,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: () => audio.skipToNext(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
