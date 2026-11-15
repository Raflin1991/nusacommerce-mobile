import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/config/business_vertical_config.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/barcode_service.dart';
import 'package:nusacommerce_mobile/core/hardware/printer_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
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

  group('Phase 6 — Exhaustive Real-World Edge-Case Hardening (A-D)', () {
    Future<(PosCubit, ApiClient, OfflineDatabase)> createTestCubit() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      apiClient.dio.options.baseUrl = 'http://127.0.0.1:59999/api/v1';
      apiClient.dio.options.connectTimeout = const Duration(milliseconds: 50);
      apiClient.dio.options.receiveTimeout = const Duration(milliseconds: 50);
      final offlineDb = OfflineDatabase(prefs);
      final cubit = PosCubit(apiClient: apiClient, offlineDb: offlineDb);
      return (cubit, apiClient, offlineDb);
    }

    test('test_discount_exceeding_subtotal_clamped_to_zero', () {
      expect(PosFinancialCalculator.clampDiscount(150000, 100000), 100000);
      expect(PosFinancialCalculator.clampDiscount(-5000, 100000), 0);
      expect(
        PosFinancialCalculator.computeClampedGrandTotal(
          subtotal: 100000,
          discountAmount: 150000,
        ),
        0,
      );

      final item = CartItemModel(
        product: ProductModel.fromJson({
          'id': 10,
          'name': 'Kemeja Linen',
          'selling_price': 100000,
          'stock': 10,
        }),
        quantity: 1,
        unitPrice: 100000,
        discountAmount: 150000,
      );
      expect(item.effectiveDiscountAmount, 100000);
      expect(item.lineTotal, 0);
    });

    test('test_consistent_rupiah_rounding_with_ppn_and_service_charge', () {
      final breakdown = PosFinancialCalculator.computeOrderTotalsWithTaxAndService(
        rawLineTotals: const [33333.33, 66666.67],
        discountTotal: 15000,
        serviceChargePercent: 5,
        taxPercent: 11,
      );

      // Lines round to 33333 + 66667 = 100000 -> net 85000
      expect(breakdown.subtotal, 100000);
      expect(breakdown.discountTotal, 15000);
      expect(breakdown.netSubtotal, 85000);
      expect(breakdown.serviceChargeAmount, 4250);
      expect(breakdown.taxAmount, ((85000 + 4250) * 0.11).roundToDouble());
      expect(
        breakdown.grandTotal,
        breakdown.netSubtotal + breakdown.serviceChargeAmount + breakdown.taxAmount,
      );
    });

    test('test_mixed_split_payment_cash_and_transfer_with_overpayment_change', () {
      final validCashOver = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 150000,
        tenderAmounts: const [100000, 100000],
        tenderMethodCodes: const ['transfer', 'cash'],
      );
      expect(validCashOver.isValidWithCashChange, isTrue);
      expect(validCashOver.isValidCheckout, isTrue);
      expect(validCashOver.cashChangeReturned, 50000);
      expect(validCashOver.effectiveRecordedAmounts, const [100000, 50000]);

      final invalidNonCashOver = PosFinancialCalculator.validateMultiTenderPayments(
        grandTotal: 150000,
        tenderAmounts: const [100000, 100000],
        tenderMethodCodes: const ['transfer', 'qris'],
      );
      expect(invalidNonCashOver.isValidCheckout, isFalse);
      expect(invalidNonCashOver.cashChangeReturned, 0);
    });

    test('test_void_split_sale_restores_store_credit_and_reverses_tenders', () {
      final reversal = PosFinancialCalculator.computeVoidReversal({
        'store_credit_amount': 40000,
        'balance_due': 25000,
        'payments': const [
          {'method_code': 'transfer', 'amount': 60000, 'tendered_amount': 60000},
          {'method_code': 'cash', 'amount': 50000, 'tendered_amount': 100000},
        ],
        'items': const [
          {'product_id': 1, 'quantity': 2, 'multiplier': 1, 'is_service': false},
          {'product_id': 2, 'quantity': 1, 'multiplier': 1, 'is_service': true},
        ],
      });

      expect(reversal.restoredStoreCredit, 40000);
      expect(reversal.reversedNonCashTotal, 60000);
      expect(reversal.reversedCashInDrawer, 50000);
      expect(reversal.reversedCreditBalanceDue, 25000);
      expect(reversal.restoredPhysicalStockByProduct[1], 2);
      expect(reversal.restoredPhysicalStockByProduct.containsKey(2), isFalse);
    });

    test('test_multiple_held_carts_preserve_active_cart_on_resume', () async {
      final (cubit, _, _) = await createTestCubit();
      final itemA = ProductModel.fromJson({
        'id': 101,
        'name': 'Produk Antre A',
        'selling_price': 25000,
        'stock': 20,
      });
      final itemB = ProductModel.fromJson({
        'id': 102,
        'name': 'Produk Aktif B',
        'selling_price': 45000,
        'stock': 20,
      });

      cubit.addToCart(itemA, quantity: 2);
      cubit.selectCustomer({'id': 77, 'name': 'Budi Santoso'});
      await cubit.holdCurrentCart('Meja VIP 1');

      expect(cubit.state.cart, isEmpty);
      expect(cubit.state.heldCarts.length, 1);

      cubit.addToCart(itemB, quantity: 1);
      expect(cubit.searchHeldCarts('Budi').length, 1);

      // Resuming Cart A while Cart B is active auto-parks Cart B instead of overwriting it
      cubit.resumeHeldCart(0);
      expect(cubit.state.cart.length, 1);
      expect(cubit.state.cart.first.product.id, 101);
      expect(cubit.state.selectedCustomer?['name'], 'Budi Santoso');
      expect(cubit.state.heldCarts.length, 1);
      expect(
        (cubit.state.heldCarts.first['cart_items'] as List<CartItemModel>).first.product.id,
        102,
      );

      await cubit.close();
    });

    test('test_workshop_service_item_does_not_deduct_physical_stock', () async {
      final (cubit, _, _) = await createTestCubit();
      await cubit.setBusinessVertical(BusinessVertical.workshop);

      final sparepart = ProductModel.fromJson({
        'id': 1,
        'name': 'Busi Iridium',
        'selling_price': 50000,
        'stock': 10,
        'type': 'product',
      });
      final serviceItem = ProductModel.fromJson({
        'id': 2,
        'name': 'Jasa Servis Tune Up',
        'selling_price': 100000,
        'stock': 0,
        'type': 'service',
      });

      cubit.addToCart(sparepart, quantity: 1);
      cubit.addToCart(serviceItem, quantity: 1);
      cubit.reconcileCartWithLatestCatalog(refreshedProducts: [sparepart, serviceItem]);

      await cubit.completeCheckout(
        payments: const [
          {'payment_method_id': 1, 'amount': 150000, 'tendered_amount': 150000},
        ],
        paymentMethodNames: const ['Tunai'],
        paidTotal: 150000,
        changeReturned: 0,
        balanceDue: 0,
      );

      expect(cubit.state.allProducts.firstWhere((p) => p.id == 1).stock, 9.0);
      expect(cubit.state.allProducts.firstWhere((p) => p.id == 2).stock, 0.0);

      await cubit.close();
    });

    test('test_pharmacy_prescription_guard_detects_missing_doctor_info', () async {
      final (cubit, _, _) = await createTestCubit();
      await cubit.setBusinessVertical(BusinessVertical.pharmacy);

      final rxDrug = ProductModel.fromJson({
        'id': 301,
        'name': 'Amoxicillin 500mg',
        'selling_price': 22000,
        'stock': 50,
        'requires_prescription': true,
      });

      cubit.addToCart(rxDrug, quantity: 1);
      expect(cubit.state.hasUnfulfilledPrescriptionRequirement, isTrue);
      expect(cubit.validatePrescriptionRequirements(), isNotNull);

      cubit.setVerticalMetadata({
        'doctor_name': 'dr. Ratna Sari',
        'patient_name': 'Ny. Ani',
      });
      expect(cubit.state.hasUnfulfilledPrescriptionRequirement, isFalse);
      expect(cubit.validatePrescriptionRequirements(), isNull);

      await cubit.close();
    });

    test('test_laundry_decimal_weight_and_express_surcharge_calculation', () async {
      final (cubit, _, _) = await createTestCubit();
      await cubit.setBusinessVertical(BusinessVertical.laundry);

      final computed = PosFinancialCalculator.computeLaundryLineTotal(
        weightKg: 2.35,
        baseRatePerKg: 8000,
        expressSurchargePerKg: 5000,
      );
      expect(computed, 30550);

      final kiloProduct = ProductModel.fromJson({
        'id': 401,
        'name': 'Cuci Setrika Kiloan',
        'selling_price': 8000,
        'unit_code': 'kg',
        'sold_by_weight': true,
        'type': 'service',
      });
      cubit.addToCart(kiloProduct, quantity: 2.35);
      cubit.updateCartItemDetails(
        0,
        quantity: 2.35,
        unitPrice: 13000,
        notes: '[Express]',
      );

      expect(cubit.state.cart.first.quantity, 2.35);
      expect(cubit.state.cart.first.unitPrice, 13000);
      expect(cubit.state.cart.first.lineTotal, 30550);

      await cubit.close();
    });

    test('test_salon_multiple_stylists_per_cart_line', () async {
      final (cubit, _, _) = await createTestCubit();
      await cubit.setBusinessVertical(BusinessVertical.salon);

      final hairCare = ProductModel.fromJson({
        'id': 501,
        'name': 'Creambath & Hair Spa',
        'selling_price': 125000,
        'type': 'service',
      });

      cubit.addToCart(hairCare, quantity: 1, stylistName: 'Rina (Senior)');
      cubit.addToCart(hairCare, quantity: 1, stylistName: 'Budi (Kapster)');

      expect(cubit.state.cart.length, 2);
      expect(cubit.state.cart[0].stylistName, 'Rina (Senior)');
      expect(cubit.state.cart[1].stylistName, 'Budi (Kapster)');

      await cubit.close();
    });

    test('test_double_checkout_idempotency_mutex_prevents_duplicate_sale', () async {
      final (cubit, _, _) = await createTestCubit();
      final item = ProductModel.fromJson({
        'id': 601,
        'name': 'Parfum Eau De Parfum',
        'selling_price': 200000,
        'stock': 5,
      });

      cubit.addToCart(item, quantity: 1);
      cubit.reconcileCartWithLatestCatalog(refreshedProducts: [item]);

      const key = 'idem-uuid-1234-5678';
      final firstFuture = cubit.completeCheckout(
        payments: const [
          {'payment_method_id': 1, 'amount': 200000, 'tendered_amount': 200000},
        ],
        paymentMethodNames: const ['Tunai'],
        paidTotal: 200000,
        changeReturned: 0,
        balanceDue: 0,
        idempotencyKey: key,
      );

      // Concurrent invocation while firstFuture is still awaiting I/O must be rejected immediately
      await expectLater(
        () => cubit.completeCheckout(
          payments: const [
            {'payment_method_id': 1, 'amount': 200000, 'tendered_amount': 200000},
          ],
          paymentMethodNames: const ['Tunai'],
          paidTotal: 200000,
          changeReturned: 0,
          balanceDue: 0,
          idempotencyKey: 'different-key',
        ),
        throwsStateError,
      );

      final firstReceipt = await firstFuture;
      // Retrying with the exact same idempotencyKey returns the cached receipt with 1 sale recorded
      final retryReceipt = await cubit.completeCheckout(
        payments: const [
          {'payment_method_id': 1, 'amount': 200000, 'tendered_amount': 200000},
        ],
        paymentMethodNames: const ['Tunai'],
        paidTotal: 200000,
        changeReturned: 0,
        balanceDue: 0,
        idempotencyKey: key,
      );

      expect(retryReceipt['local_uuid'], firstReceipt['local_uuid']);
      expect(cubit.state.salesHistory.length, 1);
      expect(cubit.state.allProducts.firstWhere((p) => p.id == 601).stock, 4.0);

      await cubit.close();
    });
  });

  group('Standalone UMKM Day-0 Engine (Offline Trial, Vertical Seeding, Shifts, Debt Book & Profit)', () {
    test('test_create_local_trial_session_sets_standalone_flags_and_vertical', () {
      final session = AuthSessionModel.createLocalTrialSession(
        storeName: 'Kedai Kopi Nusantara',
        businessVertical: 'restaurant',
        openingCash: 150000,
      );

      expect(session.isLocalTrial, isTrue);
      expect(session.tenantName, 'Kedai Kopi Nusantara');
      expect(session.activeStore.preferredVerticalRaw, 'restaurant');

      final roundTripped = AuthSessionModel.fromJson(session.toJson());
      expect(roundTripped.isLocalTrial, isTrue);
      expect(roundTripped.activeStore.name, 'Kedai Kopi Nusantara');
      expect(roundTripped.activeStore.preferredVerticalRaw, 'restaurant');
    });

    test('test_vertical_sample_seeding_populates_products_with_hpp_and_stock', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final offlineDb = OfflineDatabase(prefs);

      await offlineDb.seedVerticalSampleProductsIfEmpty('pharmacy');
      final firstProducts = offlineDb.getCachedProducts();
      expect(firstProducts.length, greaterThanOrEqualTo(5));
      for (final p in firstProducts) {
        expect((p['selling_price'] as num).toDouble(), greaterThan(0));
        expect((p['cost_price'] as num).toDouble(), greaterThan(0));
      }

      // Calling seed again with a different vertical must not overwrite existing catalog
      await offlineDb.seedVerticalSampleProductsIfEmpty('retail');
      final afterSecondSeed = offlineDb.getCachedProducts();
      expect(afterSecondSeed.length, firstProducts.length);
      expect(afterSecondSeed.first['name'], firstProducts.first['name']);
    });

    test('test_local_shift_open_cash_mutation_and_blind_close_variance', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final offlineDb = OfflineDatabase(prefs);

      final opened = await offlineDb.openLocalShift(
        openingCash: 100000,
        cashierName: 'Siti',
      );
      expect(opened['status'], 'open');
      expect(opened['expected_cash'], 100000.0);

      await offlineDb.addLocalShiftCashEntry(
        type: 'pay_in',
        amount: 50000,
        reason: 'Tambah Uang Receh',
      );
      final afterOut = await offlineDb.addLocalShiftCashEntry(
        type: 'pay_out',
        amount: 20000,
        reason: 'Beli Plastik Kemasan',
      );
      expect(afterOut, isNotNull);
      expect(afterOut!['expected_cash'], 130000.0);

      final closed = await offlineDb.closeLocalShift(
        actualClosingCash: 125000,
        notes: 'Selisih Rp 5.000',
      );
      expect(closed, isNotNull);
      expect(closed!['status'], 'closed');
      expect(closed['expected_cash'], 130000.0);
      expect(closed['variance'], -5000.0);
    });

    test('test_local_debt_book_payable_expense_and_hpp_net_profit_report', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      apiClient.dio.options.baseUrl = 'http://127.0.0.1:59999/api/v1';
      apiClient.dio.options.connectTimeout = const Duration(milliseconds: 50);
      apiClient.dio.options.receiveTimeout = const Duration(milliseconds: 50);
      final offlineDb = OfflineDatabase(prefs);
      final cubit = PosCubit(apiClient: apiClient, offlineDb: offlineDb);

      final coffee = ProductModel.fromJson({
        'id': 701,
        'name': 'Kopi Arabika 250g',
        'selling_price': 60000,
        'cost_price': 35000,
        'stock': 10,
      });

      cubit.addToCart(coffee, quantity: 2);
      cubit.reconcileCartWithLatestCatalog(refreshedProducts: [coffee]);
      await cubit.completeCheckout(
        payments: const [
          {'payment_method_id': 1, 'amount': 120000, 'tendered_amount': 120000},
        ],
        paymentMethodNames: const ['Tunai'],
        paidTotal: 120000,
        changeReturned: 0,
        balanceDue: 0,
      );

      await offlineDb.addLocalExpense(
        category: 'Listrik & Air',
        amount: 15000,
        description: 'Token Listrik Kios',
        paymentMethod: 'QRIS',
      );

      final payable = await offlineDb.addLocalPayable(
        supplierName: 'UD Sumber Kopi',
        totalAmount: 200000,
        paidAmount: 50000,
      );
      expect(offlineDb.getLocalPayables().first['supplier']['name'], 'UD Sumber Kopi');
      expect(payable['balance_due'], 150000.0);

      await offlineDb.payLocalPayable(
        payableId: (payable['purchase_id'] as num).toInt(),
        amount: 50000,
        paymentMethod: 'Transfer Bank',
      );

      final report = offlineDb.computeLocalBusinessReport();
      expect(report['transactions_count'], 1);
      expect(report['net_sales'], 120000.0);
      expect(report['total_cogs'], 70000.0);
      expect(report['gross_profit'], 50000.0);
      expect(report['store_expenses'], 15000.0);
      expect(report['net_profit'], 35000.0);
      expect(report['total_payables'], 100000.0);

      await cubit.close();
    });

    test('test_local_trial_session_never_triggers_unauthorized_logout_or_cloud_sync', () async {
      SharedPreferences.setMockInitialValues({
        'nusa_mobile_bearer_token': '999.stale_expired_token',
      });
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      apiClient.dio.options.baseUrl = 'http://127.0.0.1:59999/api/v1';
      apiClient.dio.options.connectTimeout = const Duration(milliseconds: 50);
      apiClient.dio.options.receiveTimeout = const Duration(milliseconds: 50);

      expect(await apiClient.getToken(), '999.stale_expired_token');

      final offlineDb = OfflineDatabase(prefs);
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: offlineDb);

      await authCubit.startLocalTrialSession(
        storeName: 'Toko Mandiri Bebas Logout',
        businessVertical: 'retail',
        openingCash: 100000,
      );

      expect(await apiClient.getToken(), isNull);
      expect(authCubit.state.isAuthenticated, isTrue);
      expect(authCubit.state.session.isLocalTrial, isTrue);
      expect(authCubit.state.errorMessage, isNull);

      await posCubit.initializeCatalog(seedDefaultCart: false);
      await posCubit.syncWithCloud(force: true);

      expect(posCubit.state.allProducts, isNotEmpty);
      expect(authCubit.state.isAuthenticated, isTrue);
      expect(authCubit.state.errorMessage, isNull);

      // Re-checking session on restart restores Local Trial cleanly without logout
      final authCubit2 = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      await authCubit2.checkExistingSession();
      expect(authCubit2.state.isAuthenticated, isTrue);
      expect(authCubit2.state.session.isLocalTrial, isTrue);
      expect(authCubit2.state.errorMessage, isNull);

      await posCubit.close();
      await authCubit.close();
      await authCubit2.close();
    });
  });
}
