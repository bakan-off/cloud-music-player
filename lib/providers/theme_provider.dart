import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/theme/app_theme.dart';

const String _kThemePrefKey = 'app_theme_preset_key';

class ThemeNotifier extends StateNotifier<AppThemePreset> {
  ThemeNotifier() : super(AppTheme.currentPalette.preset) {
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_kThemePrefKey);
    if (savedName != null) {
      final matched = AppThemePreset.values.firstWhere(
        (p) => p.name == savedName,
        orElse: () => AppThemePreset.obsidian,
      );
      AppTheme.setPreset(matched);
      state = matched;
    }
  }

  Future<void> setPreset(AppThemePreset preset) async {
    AppTheme.setPreset(preset);
    state = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePrefKey, preset.name);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemePreset>((ref) {
  return ThemeNotifier();
});
