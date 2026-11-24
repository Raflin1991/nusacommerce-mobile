import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'nusa_theme_tokens.dart';

class AppTheme {
  AppTheme._();

  static TextStyle _textStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    List<FontFeature>? fontFeatures,
  }) {
    if (!GoogleFonts.config.allowRuntimeFetching) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        fontFeatures: fontFeatures,
      );
    }
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: fontFeatures,
    );
  }

  static ThemeData forMode(NusaThemeMode mode) {
    switch (mode) {
      case NusaThemeMode.warmLinenDark:
        return darkTheme;
      case NusaThemeMode.outdoorHighContrast:
        return outdoorHighContrastTheme;
      case NusaThemeMode.warmLinenLight:
        return lightTheme;
    }
  }

  static ThemeData get lightTheme => _buildTheme(
        tokens: NusaThemeTokens.warmLinenLight,
        brightness: Brightness.light,
      );

  static ThemeData get darkTheme => _buildTheme(
        tokens: NusaThemeTokens.warmLinenDark,
        brightness: Brightness.dark,
      );

  static ThemeData get outdoorHighContrastTheme => _buildTheme(
        tokens: NusaThemeTokens.outdoorHighContrast,
        brightness: Brightness.light,
      );

  static ThemeData _buildTheme({
    required NusaThemeTokens tokens,
    required Brightness brightness,
  }) {
    final seedTheme =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final baseTextTheme = GoogleFonts.config.allowRuntimeFetching
        ? GoogleFonts.plusJakartaSansTextTheme(seedTheme.textTheme)
        : seedTheme.textTheme;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.accent,
      onPrimary: Colors.white,
      secondary: tokens.positive,
      onSecondary: Colors.white,
      error: tokens.danger,
      onError: Colors.white,
      surface: tokens.bgSurface,
      onSurface: tokens.textPrimary,
      outline: tokens.borderDefault,
      surfaceContainerHighest: tokens.bgElevated,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: tokens.bgPage,
      primaryColor: tokens.accent,
      colorScheme: colorScheme,
      dividerColor: tokens.borderSubtle,
      extensions: [tokens],
      textTheme: baseTextTheme.copyWith(
        displayLarge: _textStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: tokens.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        headlineMedium: _textStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: tokens.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        titleLarge: _textStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
        titleMedium: _textStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
        bodyLarge: _textStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: tokens.textPrimary,
        ),
        bodyMedium: _textStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: tokens.textSecondary,
        ),
        labelSmall: _textStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tokens.textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bgSurface,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _textStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: tokens.textPrimary,
        ),
      ),
      cardTheme: CardTheme(
        color: tokens.bgSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.bgElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: _textStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: tokens.textTertiary,
        ),
        labelStyle: _textStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: tokens.accent,
            width: tokens.isHighContrast ? 2.2 : 1.8,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: _textStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.textPrimary,
          side: BorderSide(color: tokens.borderDefault, width: tokens.borderWidth),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  /// Helper style for tabular currency amounts so digits align vertically.
  /// When [color] is omitted, inherits [DefaultTextStyle] (`tokens.textPrimary`)
  /// so Dark Mode and Outdoor High-Contrast automatically maintain WCAG AA contrast.
  static TextStyle moneyStyle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w800,
    Color? color,
  }) {
    return _textStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}
