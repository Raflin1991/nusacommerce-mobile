import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/constants/app_colors.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/core/utils/currency_formatter.dart';
import 'package:nusacommerce_mobile/core/widgets/nusa_widgets.dart';

void main() {
  testWidgets('GRN Modal renders with ZERO overflow on narrow 300px viewport', (WidgetTester tester) async {
    // Set viewport explicitly to 300px width (simulating small mobile device)
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const tokens = NusaThemeTokens.warmLinenLight;
    double currentQty = 4.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.assignment_turned_in_rounded, color: AppColors.success, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Penerimaan Barang (GRN)',
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'PUR-STORE01-202611-0012 • PT Samsung Electronics Indonesia',
                              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Surat Jalan & Date Picker Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.bgPage,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    child: Column(
                      children: [
                        const TextField(
                          decoration: InputDecoration(
                            labelText: 'Nomor Surat Jalan / DO Supplier',
                            hintText: 'SJ-SAM-202611-7788',
                            prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: tokens.bgSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tokens.borderDefault),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tanggal Diterima Fisik',
                                      style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                                    ),
                                    const Text(
                                      '24-11-2026',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, color: AppColors.slate400),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header row: Rincian Diterima + Terima Semua + Reset 0
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Rincian Diterima',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {},
                        child: const Text('Terima Semua', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {},
                        child: const Text('Reset 0', style: TextStyle(fontSize: 11.5, color: AppColors.slate500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Item Card & Stepper
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.success.withOpacity(0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Samsung Galaxy S25 256GB',
                                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'SKU: S25-256 • Dipesan: 7 unit',
                                    style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.warningSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Sisa: 7 unit',
                                style: TextStyle(fontSize: 11, color: AppColors.warningDark, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Diterima:',
                                style: TextStyle(fontSize: 12, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              iconSize: 22,
                              onPressed: () {},
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Container(
                              width: 44,
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: tokens.bgPage,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: tokens.borderDefault),
                              ),
                              child: Text(
                                IdrCurrencyFormatter.formatQty(currentQty),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              iconSize: 22,
                              onPressed: () {},
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            const SizedBox(width: 4),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                minimumSize: const Size(36, 28),
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {},
                              child: const Text('Maks', style: TextStyle(fontSize: 10.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Summary Status Badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Penerimaan Sebagian',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warningDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Sisa barang dapat diterima pada GRN berikutnya',
                                style: TextStyle(fontSize: 10, color: AppColors.warningDark),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${IdrCurrencyFormatter.formatQty(currentQty)} unit',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.warningDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Submit Button
                  NusaButton(
                    label: 'Simpan Penerimaan Sebagian (GRN)',
                    variant: NusaButtonVariant.primary,
                    icon: Icons.inventory_rounded,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify all key widgets rendered
    expect(find.text('Penerimaan Barang (GRN)'), findsOneWidget);
    expect(find.text('Rincian Diterima'), findsOneWidget);
    expect(find.text('Samsung Galaxy S25 256GB'), findsOneWidget);
    expect(find.text('Penerimaan Sebagian'), findsOneWidget);
    expect(find.text('4 unit'), findsOneWidget);
    expect(find.text('Simpan Penerimaan Sebagian (GRN)'), findsOneWidget);

    // Verify NO overflow exceptions occurred
    expect(tester.takeException(), isNull);
  });
}
