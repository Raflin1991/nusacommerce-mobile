import 'package:flutter/material.dart';

/// NusaCommerce Official Enterprise Color Palette & Design Tokens
/// Matched 1:1 with Papan Konsep UI KasirKu Modern-1.png & PRD v2.0.0
class AppColors {
  AppColors._();

  // Primary Brand Colors (Royal Blue)
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFFDBEAFE);
  static const Color primarySoft = Color(0xFFEFF6FF);

  // Executive Navy (Hero Cards & Owner Mode)
  static const Color navyDark = Color(0xFF0F172A);
  static const Color navyMid = Color(0xFF1E3A8A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);

  // Surface & Canvas
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);

  // Semantic Status — Emerald Success & WhatsApp
  static const Color success = Color(0xFF10B981);
  static const Color successDark = Color(0xFF059669);
  static const Color successSoft = Color(0xFFD1FAE5);
  static const Color whatsapp = Color(0xFF25D366);

  // Semantic Status — Amber Warning & Buku Bon (Receivables)
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFD97706);
  static const Color warningSoft = Color(0xFFFEF3C7);

  // Semantic Status — Danger Red (Void, Low Stock, Expired FEFO)
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerDark = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEE2E2);

  // Accent Purple (Low Stock / Inventory Badge on Home Mockup)
  static const Color purple = Color(0xFF7C3AED);
  static const Color purpleSoft = Color(0xFFEDE9FE);

  // Gradients
  static const LinearGradient heroBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF2563EB),
      Color(0xFF1D4ED8),
      Color(0xFF1E40AF),
    ],
  );

  static const LinearGradient executiveNavyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E3A8A),
      Color(0xFF0F172A),
    ],
  );

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
          color: Color(0x0D0F172A),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get floatingCartShadow => [
        const BoxShadow(
          color: Color(0x1F0F172A),
          blurRadius: 24,
          offset: Offset(0, -6),
        ),
      ];
}
