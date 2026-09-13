import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/theme/app_theme.dart';

class FontNotifier extends StateNotifier<AppFontPreset> {
  static const String _fontPrefKey = 'prefs_app_font_preset_key';

  FontNotifier() : super(AppFontPreset.modern) {
    _loadSavedPreset();
  }

  Future<void> _loadSavedPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_fontPrefKey);
      if (saved != null) {
        final matched = AppFontPreset.values.firstWhere(
          (p) => p.name == saved,
          orElse: () => AppFontPreset.modern,
        );
        state = matched;
        AppTheme.setFont(matched);
      }
    } catch (_) {}
  }

  Future<void> setPreset(AppFontPreset preset) async {
    state = preset;
    AppTheme.setFont(preset);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fontPrefKey, preset.name);
    } catch (_) {}
  }
}

final fontProvider = StateNotifierProvider<FontNotifier, AppFontPreset>((ref) {
  return FontNotifier();
});
