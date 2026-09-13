import 'package:flutter/material.dart';

enum AppThemePreset {
  obsidian, // Electric Violet (Default)
  midnight, // Ocean Blue
  emerald,  // Emerald Mint
  sunset,   // Amber Sunset
  amoled,   // Pure OLED Black
}

enum AppFontPreset {
  modern,     // Modern Sans (Roboto / System Sans-Serif)
  condensed,  // Compact Condensed (sans-serif-condensed)
  serif,      // Classic Serif (serif)
  monospace,  // Retro Monospace (monospace)
}

class FontOption {
  final AppFontPreset preset;
  final String title;
  final String description;
  final String? fontFamily;
  final double letterSpacing;

  const FontOption({
    required this.preset,
    required this.title,
    required this.description,
    required this.fontFamily,
    this.letterSpacing = 0.0,
  });
}

class ThemePalette {
  final AppThemePreset preset;
  final String title;
  final String description;
  final Color primaryColor;
  final Color primaryAccent;
  final Color bgDark;
  final Color surfaceDark;
  final Color cardDark;
  final Color dividerDark;
  final Color starColor;
  final Color dangerColor;
  final Color successColor;
  final Color textPrimary;
  final Color textSecondary;

  const ThemePalette({
    required this.preset,
    required this.title,
    required this.description,
    required this.primaryColor,
    required this.primaryAccent,
    required this.bgDark,
    required this.surfaceDark,
    required this.cardDark,
    required this.dividerDark,
    this.starColor = const Color(0xFFFBBF24),
    this.dangerColor = const Color(0xFFEF4444),
    this.successColor = const Color(0xFF10B981),
    this.textPrimary = const Color(0xFFF8FAFC),
    this.textSecondary = const Color(0xFF94A3B8),
  });
}

class AppTheme {
  static const obsidianPalette = ThemePalette(
    preset: AppThemePreset.obsidian,
    title: 'Фиолетовый обсидиан',
    description: 'Глубокий темный стиль с неоново-фиолетовыми акцентами',
    primaryColor: Color(0xFF8B5CF6),
    primaryAccent: Color(0xFFA78BFA),
    bgDark: Color(0xFF0C0F17),
    surfaceDark: Color(0xFF141924),
    cardDark: Color(0xFF1C2232),
    dividerDark: Color(0xFF273142),
  );

  static const midnightPalette = ThemePalette(
    preset: AppThemePreset.midnight,
    title: 'Полуночный океан',
    description: 'Сапфировый космический стиль с лазурным свечением',
    primaryColor: Color(0xFF3B82F6),
    primaryAccent: Color(0xFF60A5FA),
    bgDark: Color(0xFF070D1E),
    surfaceDark: Color(0xFF0E172F),
    cardDark: Color(0xFF162344),
    dividerDark: Color(0xFF213360),
  );

  static const emeraldPalette = ThemePalette(
    preset: AppThemePreset.emerald,
    title: 'Изумрудный киберпанк',
    description: 'Свежий природный стиль с изумрудными и мятными тонами',
    primaryColor: Color(0xFF10B981),
    primaryAccent: Color(0xFF34D399),
    bgDark: Color(0xFF071510),
    surfaceDark: Color(0xFF0D221A),
    cardDark: Color(0xFF133126),
    dividerDark: Color(0xFF1D4637),
  );

  static const sunsetPalette = ThemePalette(
    preset: AppThemePreset.sunset,
    title: 'Закатный янтарь',
    description: 'Теплая ламповая гамма в золотых и кофейных тонах',
    primaryColor: Color(0xFFF59E0B),
    primaryAccent: Color(0xFFFBBF24),
    bgDark: Color(0xFF150F0A),
    surfaceDark: Color(0xFF20160F),
    cardDark: Color(0xFF2C1E15),
    dividerDark: Color(0xFF3E2B1E),
  );

  static const amoledPalette = ThemePalette(
    preset: AppThemePreset.amoled,
    title: 'AMOLED Черный',
    description: '100% черный фон для максимальной экономии батареи на OLED',
    primaryColor: Color(0xFFA855F7),
    primaryAccent: Color(0xFFC084FC),
    bgDark: Color(0xFF000000),
    surfaceDark: Color(0xFF0A0A0A),
    cardDark: Color(0xFF141414),
    dividerDark: Color(0xFF222222),
  );

  static const List<ThemePalette> allPalettes = [
    obsidianPalette,
    midnightPalette,
    emeraldPalette,
    sunsetPalette,
    amoledPalette,
  ];

  static const List<FontOption> allFonts = [
    FontOption(
      preset: AppFontPreset.modern,
      title: 'Современный',
      description: 'Чистый гротеск с отличной читаемостью и сбалансированным интервалом',
      fontFamily: 'sans-serif-medium',
      letterSpacing: -0.2,
    ),
    FontOption(
      preset: AppFontPreset.condensed,
      title: 'Компактный (Стильный)',
      description: 'Узкий динамичный шрифт, как в Spotify и Apple Music',
      fontFamily: 'sans-serif-condensed',
      letterSpacing: 0.1,
    ),
    FontOption(
      preset: AppFontPreset.serif,
      title: 'Классический (С засечками)',
      description: 'Элегантный виниловый стиль с книжными засечками',
      fontFamily: 'serif',
      letterSpacing: 0.0,
    ),
    FontOption(
      preset: AppFontPreset.monospace,
      title: 'Моноширинный (Ретро)',
      description: 'Винтажная эстетика студийных дек и магнитофонов',
      fontFamily: 'monospace',
      letterSpacing: -0.4,
    ),
  ];

  static ThemePalette currentPalette = obsidianPalette;
  static FontOption currentFont = allFonts[0];

  static void setPreset(AppThemePreset preset) {
    currentPalette = getPalette(preset);
  }

  static void setFont(AppFontPreset preset) {
    currentFont = allFonts.firstWhere((f) => f.preset == preset, orElse: () => allFonts[0]);
  }

  static FontOption getFont(AppFontPreset preset) {
    return allFonts.firstWhere((f) => f.preset == preset, orElse: () => allFonts[0]);
  }

  static TextStyle getTrackTitleStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    AppFontPreset? customPreset,
  }) {
    final font = customPreset != null ? getFont(customPreset) : currentFont;
    return TextStyle(
      fontFamily: font.fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.bold,
      color: color ?? textPrimary,
      letterSpacing: font.letterSpacing,
      height: height,
    );
  }

  static TextStyle getTrackArtistStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    AppFontPreset? customPreset,
  }) {
    final font = customPreset != null ? getFont(customPreset) : currentFont;
    return TextStyle(
      fontFamily: font.fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.normal,
      color: color ?? textSecondary,
      letterSpacing: font.letterSpacing * 0.5,
      height: height,
    );
  }

  static ThemePalette getPalette(AppThemePreset preset) {
    switch (preset) {
      case AppThemePreset.obsidian:
        return obsidianPalette;
      case AppThemePreset.midnight:
        return midnightPalette;
      case AppThemePreset.emerald:
        return emeraldPalette;
      case AppThemePreset.sunset:
        return sunsetPalette;
      case AppThemePreset.amoled:
        return amoledPalette;
    }
  }

  // Dynamic getters forwarding to currentPalette
  static Color get primaryColor => currentPalette.primaryColor;
  static Color get primaryAccent => currentPalette.primaryAccent;
  static Color get starColor => currentPalette.starColor;
  static Color get dangerColor => currentPalette.dangerColor;
  static Color get successColor => currentPalette.successColor;
  static Color get bgDark => currentPalette.bgDark;
  static Color get surfaceDark => currentPalette.surfaceDark;
  static Color get cardDark => currentPalette.cardDark;
  static Color get textPrimary => currentPalette.textPrimary;
  static Color get textSecondary => currentPalette.textSecondary;
  static Color get dividerDark => currentPalette.dividerDark;

  static ThemeData get darkTheme => buildThemeData(currentPalette);

  static ThemeData buildThemeData(ThemePalette palette, {AppFontPreset? fontPreset}) {
    final font = fontPreset != null ? getFont(fontPreset) : currentFont;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: font.fontFamily,
      scaffoldBackgroundColor: palette.bgDark,
      colorScheme: ColorScheme.dark(
        primary: palette.primaryColor,
        secondary: palette.primaryAccent,
        surface: palette.surfaceDark,
        error: palette.dangerColor,
        onPrimary: Colors.white,
        onSurface: palette.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surfaceDark,
        selectedItemColor: palette.primaryAccent,
        unselectedItemColor: palette.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
      cardTheme: CardThemeData(
        color: palette.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.dividerDark, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.cardDark,
        hintStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.dividerDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.dividerDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.primaryAccent, width: 1.5),
        ),
      ),
    );
  }
}
