import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/features/auth/models/auth_session_model.dart';
import 'package:nusacommerce_mobile/features/pos/utils/pos_financial_calculator.dart';

void main() {
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
}
