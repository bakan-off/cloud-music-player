import 'package:cloud_music_player/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme & Presets', () {
    test('all 5 presets are defined and distinct', () {
      expect(AppTheme.allPalettes.length, 5);
      final presets = AppTheme.allPalettes.map((p) => p.preset).toSet();
      expect(presets.length, 5);
    });

    test('getPalette returns correct palette for each preset', () {
      for (final preset in AppThemePreset.values) {
        final palette = AppTheme.getPalette(preset);
        expect(palette.preset, preset);
        expect(palette.title.isNotEmpty, true);
        expect(palette.description.isNotEmpty, true);
      }
    });

    test('buildThemeData sets matching colorScheme and background', () {
      final amoled = AppTheme.getPalette(AppThemePreset.amoled);
      final themeData = AppTheme.buildThemeData(amoled);
      expect(themeData.scaffoldBackgroundColor, amoled.bgDark);
      expect(themeData.colorScheme.primary, amoled.primaryColor);
    });

    test('all 4 font options are defined with valid properties', () {
      expect(AppTheme.allFonts.length, 4);
      for (final font in AppTheme.allFonts) {
        expect(font.title.isNotEmpty, true);
        expect(font.description.isNotEmpty, true);
        expect(font.fontFamily, isNotNull);
      }
    });

    test('getTrackTitleStyle and getTrackArtistStyle return configured font styles', () {
      AppTheme.setFont(AppFontPreset.condensed);
      final titleStyle = AppTheme.getTrackTitleStyle();
      expect(titleStyle.fontFamily, 'sans-serif-condensed');
      final artistStyle = AppTheme.getTrackArtistStyle();
      expect(artistStyle.fontFamily, 'sans-serif-condensed');

      AppTheme.setFont(AppFontPreset.serif);
      final serifTitle = AppTheme.getTrackTitleStyle();
      expect(serifTitle.fontFamily, 'serif');
    });
  });
}
