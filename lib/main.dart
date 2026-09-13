import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/font_provider.dart';
import 'providers/theme_provider.dart';
import 'ui/screens/main_navigation_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved theme and font preferences before running app
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme_preset_key');
    if (savedTheme != null) {
      final matched = AppThemePreset.values.firstWhere(
        (p) => p.name == savedTheme,
        orElse: () => AppThemePreset.obsidian,
      );
      AppTheme.setPreset(matched);
    }
    final savedFont = prefs.getString('prefs_app_font_preset_key');
    if (savedFont != null) {
      final matchedFont = AppFontPreset.values.firstWhere(
        (f) => f.name == savedFont,
        orElse: () => AppFontPreset.modern,
      );
      AppTheme.setFont(matchedFont);
    }
  } catch (_) {}

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.personal.cloudplayer.audio',
      androidNotificationChannelName: 'Cloud Player',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'mipmap/ic_launcher',
      notificationColor: const Color(0xFF8B5CF6),
    );
  }

  runApp(
    const ProviderScope(
      child: CloudMusicPlayerApp(),
    ),
  );
}

class CloudMusicPlayerApp extends ConsumerWidget {
  const CloudMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPreset = ref.watch(themeProvider);
    final currentFont = ref.watch(fontProvider);
    final palette = AppTheme.getPalette(currentPreset);

    return MaterialApp(
      title: 'Cloud Music Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildThemeData(palette, fontPreset: currentFont),
      home: const MainNavigationScreen(),
    );
  }
}

