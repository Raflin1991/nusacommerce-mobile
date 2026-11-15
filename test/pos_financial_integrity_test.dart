import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/config/business_vertical_config.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/barcode_service.dart';
import 'package:nusacommerce_mobile/core/hardware/printer_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/features/auth/models/auth_session_model.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:nusacommerce_mobile/features/pos/utils/pos_financial_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Kasbon DP Parsial & Plafon Kredit Guard', () {
    test('calculates balanceDue accurately with partial DP within credit limit', () {
      final result = PosFinancialCalculator.computeKasbonDp(
        grandTotal: 500000,
        downPayment: 150000,
        creditLimit: 1000000,
        outstandingBalance: 600000, // remaining plafon = 400.000
      );

      expect(result.downPayment, 150000);
      expect(result.paidTotal, 150000);
      expect(result.balanceDue, 350000);
      expect(result.availableCredit, 400000);
      expect(result.isWithinCreditLimit, isTrue);
      expect(result.minimumRequiredDp, 100000);
      expect(result.validationError, isNull);
    });

    test('blocks checkout and computes minimumRequiredDp when balanceDue exceeds plafon', () {
      final result = PosFinancialCalculator.computeKasbonDp(
        grandTotal: 500000,
        downPayment: 50000,
        creditLimit: 500000,
        outstandingBalance: 200000, // remaining plafon = 300.000 -> min DP = 200.000
      );

      expect(result.balanceDue, 450000);
      expect(result.availableCredit, 300000);
      expect(result.isWithinCreditLimit, isFalse);
      expect(result.minimumRequiredDp, 200000);
      expect(result.validationError, isNotNull);
    });

    test('deducts storeCreditUsed alongside downPayment toward plafon limit', () {
      final result = PosFinancialCalculator.computeKasbonDp(
        grandTotal: 500000,
        downPayment: 100000,
        storeCreditUsed: 100000,
        creditLimit: 500000,
        outstandingBalance: 200000, // plafon = 300.000, balanceDue = 300.000 -> pas!
      );

      expect(result.storeCreditUsed, 100000);
      expect(result.paidTotal, 200000);
      expect(result.balanceDue, 300000);
      expect(result.isWithinCreditLimit, isTrue);
      expect(result.validationError, isNull);
    });

    test('rejects negative DP or DP above grandTotal', () {
      final neg = PosFinancialCalculator.computeKasbonDp(
        grandTotal: 250000,
        downPayment: -10000,
        creditLimit: 0,
        outstandingBalance: 0,
      );
      expect(neg.validationError, isNotNull);

      final over = PosFinancialCalculator.computeKasbonDp(
        grandTotal: 250000,
        downPayment: 300000,
        creditLimit: 0,
        outstandingBalance: 0,
      );
      expect(over.validationError, isNotNull);
    });
  });

  group('Dynamic Multi-Tender Split Payment (3+ Methods)', () {
    test('validates 3-tender split payment matching grandTotal exactly', () {
      final res = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 500000,
        tenderAmounts: const [100000, 150000, 250000],
      );

      expect(res.tendersTotal, 500000);
      expect(res.paidTotal, 500000);
      expect(res.remainingDue, 0);
      expect(res.overpayment, 0);
      expect(res.isExactMatch, isTrue);
      expect(res.hasValidNonZeroLines, isTrue);
    });

    test('validates 3-tender split combined with Customer Store Credit', () {
      final res = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 450000,
        tenderAmounts: const [100000, 150000, 100000],
        storeCreditAmount: 100000,
      );

      expect(res.tendersTotal, 350000);
      expect(res.storeCreditAmount, 100000);
      expect(res.paidTotal, 450000);
      expect(res.remainingDue, 0);
      expect(res.isExactMatch, isTrue);
    });

    test('detects remainingDue when split tenders fall short or exceed total', () {
      final shortRes = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 300000,
        tenderAmounts: const [100000, 120000, 50000],
      );
      expect(shortRes.isExactMatch, isFalse);
      expect(shortRes.remainingDue, 30000);
      expect(shortRes.overpayment, 0);

      final overRes = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 300000,
        tenderAmounts: const [100000, 150000, 100000],
      );
      expect(overRes.isExactMatch, isFalse);
      expect(overRes.overpayment, 50000);
    });

    test('rejects split line with zero amount unless fully covered by store credit', () {
      final zeroLine = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 200000,
        tenderAmounts: const [200000, 0],
      );
      expect(zeroLine.hasValidNonZeroLines, isFalse);
      expect(zeroLine.isExactMatch, isFalse);
    });
  });

  group('Prorated Split Bill F&B Calculation (Tax + Service Charge)', () {
    test('prorates subtotal, tax, and service charge accurately on item split', () {
      final parentItems = [
        {
          'sale_item_id': 10,
          'quantity': 2,
          'unit_price': 50000,
          'line_subtotal': 100000,
          'discount_amount': 10000,
          'tax_amount': 9000,
        },
        {
          'sale_item_id': 11,
          'quantity': 1,
          'unit_price': 100000,
          'line_subtotal': 100000,
          'discount_amount': 0,
          'tax_amount': 10000,
        },
      ];

      // Split 1 unit of item 10 (half of item 10's 100k subtotal -> 25% of parent 200k subtotal)
      final splitRes = PosFinancialCalculator.calculateProratedSplitBill(
        parentItems: parentItems,
        itemsToSplit: [
          {'sale_item_id': 10, 'quantity': 1},
        ],
        parentServiceCharge: 20000, // 25% = 5.000
      );

      expect(splitRes.childSubtotal, 50000);
      expect(splitRes.childDiscount, 5000);
      expect(splitRes.childTax, 4500);
      expect(splitRes.childServiceCharge, 5000);
      // (50000 - 5000) + 4500 + 5000 = 54500
      expect(splitRes.childGrandTotal, 54500);

      expect(splitRes.parentRemainingSubtotal, 150000);
      expect(splitRes.parentRemainingServiceCharge, 15000);
      // (150000 - 5000) + 14500 + 15000 = 174500
      expect(splitRes.parentRemainingGrandTotal, 174500);
    });
  });

  group('1-Click Item Exchange Delta & Cascade Entitlements', () {
    test('computes additional payment vs surplus refund/deposit correctly', () {
      final upgrade = PosFinancialCalculator.calculateExchangeDelta(
        returnedItemsTotal: 150000,
        replacementItemsTotal: 225000,
      );
      expect(upgrade.additionalPaymentDue, 75000);
      expect(upgrade.refundOrDepositSurplus, 0);

      final downgrade = PosFinancialCalculator.calculateExchangeDelta(
        returnedItemsTotal: 200000,
        replacementItemsTotal: 140000,
      );
      expect(downgrade.additionalPaymentDue, 0);
      expect(downgrade.refundOrDepositSurplus, 60000);
    });

    test('parses Cascade entitlements & gates starter vs enterprise modules', () {
      final starterSession = AuthSessionModel.fromApiData({
        'user': {'id': 1, 'name': 'Owner Starter', 'email': 'owner@starter.id', 'role': 'owner'},
        'tenant': {'name': 'Toko Starter', 'subdomain': 'starter', 'plan_name': 'Starter'},
        'entitlements': {
          'tier': 'starter',
          'active_modules': ['cash_debt', 'crm'],
          'hidden_modules': ['online_store', 'accounting', 'hr'],
        },
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'MAIN', 'pos_mode': 'retail'},
        'available_stores': [],
      });

      expect(starterSession.tier, 'starter');
      expect(starterSession.hasModule('cash_debt'), isTrue);
      expect(starterSession.isModuleGated('cash_debt'), isFalse);
      expect(starterSession.hasModule('crm'), isTrue);
      expect(starterSession.hasModule('loyalty'), isTrue); // crm <-> loyalty alias
      expect(starterSession.hasModule('online_store'), isFalse);
      expect(starterSession.isModuleGated('online_store'), isTrue);
      expect(starterSession.isModuleGated('accounting'), isTrue);
      expect(starterSession.isModuleGated('hr'), isTrue);

      // JSON persistence roundtrip preserves tier & module gates
      final restored = AuthSessionModel.fromJson(starterSession.toJson());
      expect(restored.tier, 'starter');
      expect(restored.isModuleGated('online_store'), isTrue);
      expect(restored.hasModule('crm'), isTrue);
    });
  });

  group('Phase 2-4 Enterprise Hardening, Hardware Routing & Multi-Vertical Tests', () {
    test('test_reprint_receipt_watermark_present', () {
      final printer = PrinterService();
      final store = {
        'name': 'Toko Nusa Utama',
        'address': 'Jl. Jend. Sudirman No. 1',
        'phone': '021-5550199',
      };
      final sale = {
        'number': '#INV-REPRINT-007',
        'sale_datetime': '15-11-2026 14:20',
        'cashier_name': 'Siti Kasir',
        'customer': {'name': 'Budi'},
        'items': [
          {
            'product_name': 'Kopi Susu Gula Aren',
            'quantity': 2,
            'unit_code': 'cup',
            'unit_price': 20000,
            'line_total': 40000,
          },
        ],
        'subtotal': 40000,
        'grand_total': 40000,
        'paid_total': 50000,
        'change_returned': 10000,
        'payment_methods': ['Tunai'],
      };

      final originalText = printer.formatReceiptText(
        storeProfile: store,
        sale: sale,
        isReprint: false,
      );
      expect(originalText.contains('SALINAN / REPRINT'), isFalse);

      final reprintText = printer.formatReceiptText(
        storeProfile: store,
        sale: sale,
        isReprint: true,
        reprintCount: 2,
      );
      expect(reprintText.contains('*** SALINAN / REPRINT KE-2 ***'), isTrue);
      expect(reprintText.contains('Tgl/Jam Cetak:'), isTrue);
      expect(reprintText.contains('Kasir: Siti Kasir'), isTrue);
    });

    test('test_tiered_volume_discount_recalculation', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = PosCubit(
        apiClient: ApiClient(
          secureStorage: const FlutterSecureStorage(),
          prefs: prefs,
        ),
        offlineDb: OfflineDatabase(prefs),
      );

      const retailProduct = ProductModel(
        id: 501,
        name: 'Air Mineral 600ml',
        sku: 'AM-600',
        barcode: '8991234567890',
        sellingPrice: 10000,
        stock: 100,
        volumeTiers: [
          ProductVolumeTier(minQuantity: 5, tierPrice: 9200),
          ProductVolumeTier(minQuantity: 10, tierPrice: 8500),
        ],
      );

      cubit.addToCart(retailProduct, quantity: 2);
      expect(cubit.state.cart.single.unitPrice, 10000);
      expect(cubit.state.cart.single.lineTotal, 20000);

      // Crossing qty >= 10 must automatically trigger tierPrice 8.500
      cubit.changeCartItemQuantity(0, 10);
      expect(cubit.state.cart.single.unitPrice, 8500);
      expect(cubit.state.cart.single.lineTotal, 85000);

      // Dropping back to qty 5 triggers tierPrice 9.200; dropping to 3 reverts to base price 10.000
      cubit.updateCartItemQuantity(0, 5);
      expect(cubit.state.cart.single.unitPrice, 9200);
      expect(cubit.state.cart.single.lineTotal, 46000);

      cubit.updateCartItemQuantity(0, 3);
      expect(cubit.state.cart.single.unitPrice, 10000);
      expect(cubit.state.cart.single.lineTotal, 30000);

      await cubit.close();
    });

    test('test_cash_drawer_kick_condition_cash_only', () {
      // 100% Non-Cash QRIS -> MUST NOT kick cash drawer
      expect(
        PrinterService.shouldKickCashDrawer(
          payments: const [
            {'method': 'QRIS Dinamis', 'amount': 150000},
          ],
          paymentMethods: const ['QRIS Dinamis'],
        ),
        isFalse,
      );

      // 100% Card EDC / Transfer -> MUST NOT kick cash drawer
      expect(
        PrinterService.shouldKickCashDrawer(
          payments: const [
            {'method': 'Transfer BCA', 'amount': 75000},
            {'method': 'EDC Debit', 'amount': 75000},
          ],
          paymentMethods: const ['Transfer BCA', 'EDC Debit'],
        ),
        isFalse,
      );

      // Kasbon 0 DP -> MUST NOT kick cash drawer
      expect(
        PrinterService.shouldKickCashDrawer(
          payments: const [],
          paymentMethods: const ['Tunai'],
          isKasbonZeroDp: true,
        ),
        isFalse,
      );

      // Reprint even of Cash sale -> MUST NOT kick cash drawer
      expect(
        PrinterService.shouldKickCashDrawer(
          payments: const [
            {'method': 'Tunai', 'amount': 100000},
          ],
          paymentMethods: const ['Tunai'],
          isReprint: true,
        ),
        isFalse,
      );

      // Positive Cash component in single or split tender -> MUST kick cash drawer
      expect(
        PrinterService.shouldKickCashDrawer(
          payments: const [
            {'method': 'QRIS', 'amount': 100000},
            {'method': 'Tunai', 'amount': 50000},
          ],
          paymentMethods: const ['QRIS', 'Tunai'],
        ),
        isTrue,
      );
    });

    test('test_workshop_and_pharmacy_metadata_preserved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = PosCubit(
        apiClient: ApiClient(
          secureStorage: const FlutterSecureStorage(),
          prefs: prefs,
        ),
        offlineDb: OfflineDatabase(prefs),
      );
      final printer = PrinterService();
      final store = {'name': 'Nusa Vertical Store', 'address': 'Jakarta', 'phone': '021-999'};

      // 1. Workshop Vertical Metadata
      await cubit.setBusinessVertical(BusinessVertical.workshop);
      cubit.setVerticalMetadata({
        'nopol': 'B 9876 ABC',
        'kendaraan': 'Honda PCX 160',
        'kilometer': '24500',
      });
      expect(cubit.state.verticalMetadata['nopol'], 'B 9876 ABC');
      expect(cubit.state.verticalMetadata['kendaraan'], 'Honda PCX 160');
      expect(cubit.state.verticalMetadata['kilometer'], '24500');

      final workshopReceipt = printer.formatReceiptText(
        storeProfile: store,
        sale: {
          'number': '#WS-001',
          'vertical_metadata': cubit.state.verticalMetadata,
          'items': const [
            {'product_name': 'Ganti Oli MPX2', 'quantity': 1, 'unit_price': 65000, 'line_total': 65000},
          ],
          'subtotal': 65000,
          'grand_total': 65000,
          'paid_total': 65000,
        },
      );
      expect(workshopReceipt.contains('No. Polisi: B 9876 ABC'), isTrue);
      expect(workshopReceipt.contains('Kendaraan: Honda PCX 160'), isTrue);
      expect(workshopReceipt.contains('Kilometer (KM): 24500'), isTrue);

      // 2. Pharmacy Vertical Metadata + FEFO Batch/ED
      await cubit.setBusinessVertical(BusinessVertical.pharmacy);
      cubit.setVerticalMetadata({
        'doctor_name': 'dr. Andi Wijaya',
        'doctor_sip': '503/SIP/2026',
        'patient_name': 'Tn. Budi',
      });
      expect(cubit.state.verticalMetadata['doctor_name'], 'dr. Andi Wijaya');
      expect(cubit.state.verticalMetadata['doctor_sip'], '503/SIP/2026');
      expect(cubit.state.verticalMetadata['patient_name'], 'Tn. Budi');

      final pharmacyReceipt = printer.formatReceiptText(
        storeProfile: store,
        sale: {
          'number': '#RX-001',
          'vertical_metadata': cubit.state.verticalMetadata,
          'items': const [
            {
              'product_name': 'Amoxicillin 500mg',
              'quantity': 1,
              'unit_code': 'strip',
              'unit_price': 18000,
              'line_total': 18000,
              'batch_number': 'BCH-FEFO-22',
              'expiry_date': '2027-12-31',
            },
          ],
          'subtotal': 18000,
          'grand_total': 18000,
          'paid_total': 20000,
          'change_returned': 2000,
        },
      );
      expect(pharmacyReceipt.contains('Dokter: dr. Andi Wijaya'), isTrue);
      expect(pharmacyReceipt.contains('No. SIP: 503/SIP/2026'), isTrue);
      expect(pharmacyReceipt.contains('Pasien: Tn. Budi'), isTrue);
      expect(pharmacyReceipt.contains('Batch: BCH-FEFO-22 | ED: 2027-12-31'), isTrue);

      // 3. Barcode 350ms Debounce Verification
      BarcodeService.resetDebounce();
      final t0 = DateTime(2026, 11, 15, 10, 0, 0, 0);
      expect(BarcodeService.shouldAcceptScan('8991002003004', now: t0), isTrue);
      expect(
        BarcodeService.shouldAcceptScan('8991002003004', now: t0.add(const Duration(milliseconds: 200))),
        isFalse,
      );
      expect(
        BarcodeService.shouldAcceptScan('8991002003004', now: t0.add(const Duration(milliseconds: 400))),
        isTrue,
      );

      await cubit.close();
    });
  });
}
