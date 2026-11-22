import 'package:flutter/material.dart';

/// OXO.ID Official Enterprise Color Palette & CDO Warm Linen Design Tokens
/// Synchronized 1:1 with `resources/css/tokens.css` (Gelombang 5 Mobile Parity).
class AppColors {
  AppColors._();

  // Primary Brand Colors (Artisanal Terracotta Accent — `--accent`)
  static const Color primary = Color(0xFFEA580C);
  static const Color primaryDark = Color(0xFFC2410C);
  static const Color primaryLight = Color(0xFFFED7AA);
  static const Color primarySoft = Color(0xFFFFF1E6);

  // Editorial Stone Obsidian & Warm Stone Ink (`--text-primary` / `--text-secondary`)
  static const Color navyDark = Color(0xFF1C1917);
  static const Color navyMid = Color(0xFF292524);
  static const Color slate800 = Color(0xFF292524);
  static const Color slate700 = Color(0xFF44403C);
  static const Color slate600 = Color(0xFF57534E);
  static const Color slate500 = Color(0xFF78716C);
  static const Color slate400 = Color(0xFFA8A29E);
  static const Color slate200 = Color(0xFFE7E5E4);
  static const Color slate100 = Color(0xFFF5F3EF);

  // Surface & Canvas (`--bg-page` / `--bg-surface` / `--border-subtle`)
  static const Color background = Color(0xFFFAF8F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE7E5E4);
  static const Color divider = Color(0xFFF5F3EF);

  // Semantic Status — Refined Emerald Success & WhatsApp (`--positive`)
  static const Color success = Color(0xFF10B981);
  static const Color successDark = Color(0xFF059669);
  static const Color successSoft = Color(0xFFECFDF5);
  static const Color whatsapp = Color(0xFF25D366);

  // Semantic Status — Refined Amber Warning & Buku Bon (`--warning`)
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3C7);

  // Semantic Status — Crimson Danger (Void, Low Stock, Expired FEFO — `--danger`)
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerDark = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEE2E2);

  // Accent Violet (Inventory / Taxonomy highlights)
  static const Color purple = Color(0xFF7C3AED);
  static const Color purpleSoft = Color(0xFFEDE9FE);

  // Gradients (Warm Terracotta & Deep Stone Obsidian)
  static const LinearGradient heroBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEA580C),
      Color(0xFFC2410C),
      Color(0xFF9A3412),
    ],
  );

  static const LinearGradient executiveNavyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF292524),
      Color(0xFF1C1917),
    ],
  );

  static const LinearGradient heroNavyGradient = executiveNavyGradient;

  static const LinearGradient promoAmberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFBEB),
      Color(0xFFFEF3C7),
    ],
  );

  static List<BoxShadow> get cardShadow => [
        const BoxShadow(
          color: Color(0x081C1917),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get floatingCartShadow => [
        const BoxShadow(
          color: Color(0x141C1917),
          blurRadius: 16,
          offset: Offset(0, -4),
        ),
      ];
}
