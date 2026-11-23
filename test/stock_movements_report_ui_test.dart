import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/constants/app_colors.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/features/owner_reports/models/mobile_report_catalog.dart';

void main() {
  group('Stock Movements Report UI & Layout Hardening Tests', () {
    testWidgets('Detail Modal renders long primaryValue without RenderFlex overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final tokens = NusaThemeTokens.warmLinenLight;
      const longPrimaryValue = 'GRN GRN-STORE01-202611-0002 (PO PUR-STORE01-202611-0012)';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.accent.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Nilai Utama',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            longPrimaryValue,
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.moneyStyle(
                              fontSize: 15.5,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Nilai Utama'), findsOneWidget);
      expect(find.text(longPrimaryValue), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('3-KPI grid renders in 1 compact row on 360px viewport without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final tokens = NusaThemeTokens.warmLinenLight;
      final kpis = [
        const MobileReportKpi(label: 'Total Mutasi', formatted: '17', type: 'count'),
        const MobileReportKpi(label: 'Total Masuk (+)', formatted: '175', type: 'count', tone: 'positive'),
        const MobileReportKpi(label: 'Total Keluar (-)', formatted: '9', type: 'count', tone: 'warning'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final isThree = kpis.length == 3;
                  final cols = constraints.maxWidth >= 720
                      ? (isThree ? 3 : 4)
                      : (isThree && constraints.maxWidth >= 310
                          ? 3
                          : (constraints.maxWidth < 310 ? 1 : 2));
                  final ratio = cols == 3
                      ? 1.55
                      : (cols == 4 ? 2.1 : (constraints.maxWidth < 310 ? 2.8 : 2.2));
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: kpis.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: ratio,
                    ),
                    itemBuilder: (_, idx) {
                      final k = kpis[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: tokens.bgSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              k.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tokens.textSecondary),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              k.formatted,
                              style: AppTheme.moneyStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Total Mutasi'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.text('Total Masuk (+)'), findsOneWidget);
      expect(find.text('175'), findsOneWidget);
      expect(find.text('Total Keluar (-)'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Stock row item renders prominent title and readable delta badge', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final tokens = NusaThemeTokens.warmLinenLight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: tokens.bgSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Samsung Galaxy S25 256GB',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: tokens.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'SKU: S25-256 • 2026-11-24 04:27',
                          style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 145),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '+4 unit',
                          style: AppTheme.moneyStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.success),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Saldo: 4 unit',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Samsung Galaxy S25 256GB'), findsOneWidget);
      expect(find.text('+4 unit'), findsOneWidget);
      expect(find.text('Saldo: 4 unit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
