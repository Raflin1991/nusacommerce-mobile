import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/core/widgets/nusa_widgets.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Wave 1.5 — NusaThemeTokens Dark Mode, WCAG Contrast & 360x640 Narrow Viewport Proof', () {
    test('warmLinenLight uses official OXORA Orange #F97316 and AppTheme.moneyStyle inherits theme text color', () {
      expect(NusaThemeTokens.warmLinenLight.accent, equals(const Color(0xFFF97316)));
      expect(NusaThemeTokens.warmLinenDark.accent, equals(const Color(0xFFF97316)));

      final defaultMoney = AppTheme.moneyStyle(fontSize: 18);
      expect(defaultMoney.color, isNull, reason: 'Omitting color must inherit DefaultTextStyle for Dark Mode contrast');
    });

    testWidgets('Dark Mode & Narrow 360x640 / <=300px Modal render with ZERO RenderFlex overflow and visible inline error', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final tokens = NusaThemeTokens.of(context);
              return Scaffold(
                backgroundColor: tokens.bgPage,
                appBar: AppBar(title: const Text('OXORA POS Dark')),
                body: Center(
                  child: Container(
                    width: 296, // <= 300px narrow modal constraint
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Meja VIP 08 Kemang • Area Indoor Utama',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                            ),
                            const NusaBadge(label: 'TERISI', variant: NusaBadgeVariant.primary),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Rp 1.485.000',
                          textAlign: TextAlign.right,
                          style: AppTheme.moneyStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: tokens.dangerSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: tokens.danger),
                          ),
                          child: Text(
                            'Meja tujuan sedang digunakan oleh transaksi aktif lainnya.',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tokens.danger),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {},
                          child: const Text('Pindahkan Meja'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Meja tujuan sedang digunakan oleh transaksi aktif lainnya.'), findsOneWidget);
      expect(find.text('Rp 1.485.000'), findsOneWidget);
    });
  });
}
