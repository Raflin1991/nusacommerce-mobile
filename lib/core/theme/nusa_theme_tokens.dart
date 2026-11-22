import 'package:flutter/material.dart';

/// Visual appearance modes aligned 1:1 with OXO.ID Web CDO Warm Linen
/// (`resources/css/tokens.css`) plus High-Contrast Outdoor POS ergonomics.
enum NusaThemeMode {
  warmLinenLight,
  warmLinenDark,
  outdoorHighContrast,
}

extension NusaThemeModeMeta on NusaThemeMode {
  String get storageKey {
    switch (this) {
      case NusaThemeMode.warmLinenLight:
        return 'light';
      case NusaThemeMode.warmLinenDark:
        return 'dark';
      case NusaThemeMode.outdoorHighContrast:
        return 'outdoor_hc';
    }
  }

  String get label {
    switch (this) {
      case NusaThemeMode.warmLinenLight:
        return 'Warm Linen (Terang)';
      case NusaThemeMode.warmLinenDark:
        return 'Mode Gelap (Dark)';
      case NusaThemeMode.outdoorHighContrast:
        return 'Kontras Tinggi (Outdoor POS)';
    }
  }

  String get shortLabel {
    switch (this) {
      case NusaThemeMode.warmLinenLight:
        return 'Terang';
      case NusaThemeMode.warmLinenDark:
        return 'Gelap';
      case NusaThemeMode.outdoorHighContrast:
        return 'Outdoor HC';
    }
  }

  IconData get icon {
    switch (this) {
      case NusaThemeMode.warmLinenLight:
        return Icons.wb_sunny_outlined;
      case NusaThemeMode.warmLinenDark:
        return Icons.dark_mode_outlined;
      case NusaThemeMode.outdoorHighContrast:
        return Icons.contrast_rounded;
    }
  }

  static NusaThemeMode fromStorageKey(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'dark':
        return NusaThemeMode.warmLinenDark;
      case 'outdoor_hc':
      case 'high_contrast':
      case 'outdoor':
        return NusaThemeMode.outdoorHighContrast;
      default:
        return NusaThemeMode.warmLinenLight;
    }
  }
}

/// Semantic Design Tokens (`ThemeExtension`) consumed by Mobile screens & widgets.
@immutable
class NusaThemeTokens extends ThemeExtension<NusaThemeTokens> {
  final NusaThemeMode mode;
  final Color bgPage;
  final Color bgSurface;
  final Color bgElevated;
  final Color borderSubtle;
  final Color borderDefault;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentDark;
  final Color accentSoft;
  final Color positive;
  final Color positiveSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final double borderWidth;
  final List<Color> heroGradientColors;
  final List<Color> accentGradientColors;

  const NusaThemeTokens({
    required this.mode,
    required this.bgPage,
    required this.bgSurface,
    required this.bgElevated,
    required this.borderSubtle,
    required this.borderDefault,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentDark,
    required this.accentSoft,
    required this.positive,
    required this.positiveSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.borderWidth,
    required this.heroGradientColors,
    required this.accentGradientColors,
  });

  bool get isDark => mode == NusaThemeMode.warmLinenDark;
  bool get isHighContrast => mode == NusaThemeMode.outdoorHighContrast;

  /// 1:1 with `:root` in `resources/css/tokens.css` (CDO Warm Linen Light).
  static const NusaThemeTokens warmLinenLight = NusaThemeTokens(
    mode: NusaThemeMode.warmLinenLight,
    bgPage: Color(0xFFFAF8F5),
    bgSurface: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFF5F3EF),
    borderSubtle: Color(0xFFE7E5E4),
    borderDefault: Color(0xFFDEDBD7),
    textPrimary: Color(0xFF1C1917),
    textSecondary: Color(0xFF78716C),
    textTertiary: Color(0xFFA8A29E),
    accent: Color(0xFFEA580C),
    accentDark: Color(0xFFC2410C),
    accentSoft: Color(0xFFFFF1E6),
    positive: Color(0xFF059669),
    positiveSoft: Color(0xFFECFDF5),
    warning: Color(0xFFD97706),
    warningSoft: Color(0xFFFEF3C7),
    danger: Color(0xFFDC2626),
    dangerSoft: Color(0xFFFEE2E2),
    shimmerBase: Color(0xFFECE8E1),
    shimmerHighlight: Color(0xFFF7F5F0),
    borderWidth: 1.0,
    heroGradientColors: [Color(0xFF292524), Color(0xFF1C1917)],
    accentGradientColors: [Color(0xFFEA580C), Color(0xFFC2410C)],
  );

  /// 1:1 with `.dark` in `resources/css/tokens.css`.
  static const NusaThemeTokens warmLinenDark = NusaThemeTokens(
    mode: NusaThemeMode.warmLinenDark,
    bgPage: Color(0xFF08090A),
    bgSurface: Color(0xFF0D0E10),
    bgElevated: Color(0xFF131418),
    borderSubtle: Color(0xFF1C1D21),
    borderDefault: Color(0xFF26272D),
    textPrimary: Color(0xFFECECEE),
    textSecondary: Color(0xFF8A8F98),
    textTertiary: Color(0xFF5C5F66),
    accent: Color(0xFFF97316),
    accentDark: Color(0xFFEA580C),
    accentSoft: Color(0x24F97316),
    positive: Color(0xFF10B981),
    positiveSoft: Color(0x2410B981),
    warning: Color(0xFFF59E0B),
    warningSoft: Color(0x24EAB308),
    danger: Color(0xFFEF4444),
    dangerSoft: Color(0x24EF4444),
    shimmerBase: Color(0xFF1A1B1F),
    shimmerHighlight: Color(0xFF26272D),
    borderWidth: 1.0,
    heroGradientColors: [Color(0xFF1A1B1F), Color(0xFF0D0E10)],
    accentGradientColors: [Color(0xFFEA580C), Color(0xFF9A3412)],
  );

  /// High-Contrast Outdoor POS Mode (WCAG AAA sunlight readability, 1.8px crisp borders).
  static const NusaThemeTokens outdoorHighContrast = NusaThemeTokens(
    mode: NusaThemeMode.outdoorHighContrast,
    bgPage: Color(0xFFFFFFFF),
    bgSurface: Color(0xFFFFFFFF),
    bgElevated: Color(0xFFF5F0E6),
    borderSubtle: Color(0xFF1C1917),
    borderDefault: Color(0xFF000000),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF1C1917),
    textTertiary: Color(0xFF292524),
    accent: Color(0xFFC2410C),
    accentDark: Color(0xFF9A3412),
    accentSoft: Color(0xFFFFEDD5),
    positive: Color(0xFF047857),
    positiveSoft: Color(0xFFD1FAE5),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFEF3C7),
    danger: Color(0xFFB91C1C),
    dangerSoft: Color(0xFFFEE2E2),
    shimmerBase: Color(0xFFD6D3D1),
    shimmerHighlight: Color(0xFFF5F5F4),
    borderWidth: 1.8,
    heroGradientColors: [Color(0xFF000000), Color(0xFF1C1917)],
    accentGradientColors: [Color(0xFFC2410C), Color(0xFF7C2D12)],
  );

  static NusaThemeTokens forMode(NusaThemeMode mode) {
    switch (mode) {
      case NusaThemeMode.warmLinenDark:
        return warmLinenDark;
      case NusaThemeMode.outdoorHighContrast:
        return outdoorHighContrast;
      case NusaThemeMode.warmLinenLight:
        return warmLinenLight;
    }
  }

  /// Safely resolves active theme tokens even inside isolated widget tests.
  static NusaThemeTokens of(BuildContext context) {
    return Theme.of(context).extension<NusaThemeTokens>() ?? warmLinenLight;
  }

  @override
  NusaThemeTokens copyWith({
    NusaThemeMode? mode,
    Color? bgPage,
    Color? bgSurface,
    Color? bgElevated,
    Color? borderSubtle,
    Color? borderDefault,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentDark,
    Color? accentSoft,
    Color? positive,
    Color? positiveSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? shimmerBase,
    Color? shimmerHighlight,
    double? borderWidth,
    List<Color>? heroGradientColors,
    List<Color>? accentGradientColors,
  }) {
    return NusaThemeTokens(
      mode: mode ?? this.mode,
      bgPage: bgPage ?? this.bgPage,
      bgSurface: bgSurface ?? this.bgSurface,
      bgElevated: bgElevated ?? this.bgElevated,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentDark: accentDark ?? this.accentDark,
      accentSoft: accentSoft ?? this.accentSoft,
      positive: positive ?? this.positive,
      positiveSoft: positiveSoft ?? this.positiveSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      borderWidth: borderWidth ?? this.borderWidth,
      heroGradientColors: heroGradientColors ?? this.heroGradientColors,
      accentGradientColors: accentGradientColors ?? this.accentGradientColors,
    );
  }

  @override
  NusaThemeTokens lerp(ThemeExtension<NusaThemeTokens>? other, double t) {
    if (other is! NusaThemeTokens) return this;
    return NusaThemeTokens(
      mode: t < 0.5 ? mode : other.mode,
      bgPage: Color.lerp(bgPage, other.bgPage, t) ?? bgPage,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t) ?? bgSurface,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t) ?? bgElevated,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t) ?? borderDefault,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentDark: Color.lerp(accentDark, other.accentDark, t) ?? accentDark,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      positive: Color.lerp(positive, other.positive, t) ?? positive,
      positiveSoft: Color.lerp(positiveSoft, other.positiveSoft, t) ?? positiveSoft,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t) ?? warningSoft,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t) ?? dangerSoft,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t) ?? shimmerBase,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t) ?? shimmerHighlight,
      borderWidth: borderWidth + (other.borderWidth - borderWidth) * t,
      heroGradientColors: t < 0.5 ? heroGradientColors : other.heroGradientColors,
      accentGradientColors: t < 0.5 ? accentGradientColors : other.accentGradientColors,
    );
  }
}
