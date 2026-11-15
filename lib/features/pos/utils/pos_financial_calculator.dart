import 'dart:math' as math;

class KasbonDpComputation {
  final double grandTotal;
  final double downPayment;
  final double storeCreditUsed;
  final double paidTotal;
  final double balanceDue;
  final double availableCredit;
  final bool hasCreditLimit;
  final bool isWithinCreditLimit;
  final double minimumRequiredDp;
  final String? validationError;

  const KasbonDpComputation({
    required this.grandTotal,
    required this.downPayment,
    required this.storeCreditUsed,
    required this.paidTotal,
    required this.balanceDue,
    required this.availableCredit,
    required this.hasCreditLimit,
    required this.isWithinCreditLimit,
    required this.minimumRequiredDp,
    this.validationError,
  });
}

class MultiTenderValidation {
  final double grandTotal;
  final double tendersTotal;
  final double storeCreditAmount;
  final double paidTotal;
  final double remainingDue;
  final double overpayment;
  final bool isExactMatch;
  final bool hasValidNonZeroLines;

  const MultiTenderValidation({
    required this.grandTotal,
    required this.tendersTotal,
    required this.storeCreditAmount,
    required this.paidTotal,
    required this.remainingDue,
    required this.overpayment,
    required this.isExactMatch,
    required this.hasValidNonZeroLines,
  });
}

class SplitBillCalculationResult {
  final double childSubtotal;
  final double childDiscount;
  final double childTax;
  final double childServiceCharge;
  final double childGrandTotal;
  final double parentRemainingSubtotal;
  final double parentRemainingServiceCharge;
  final double parentRemainingGrandTotal;

  const SplitBillCalculationResult({
    required this.childSubtotal,
    required this.childDiscount,
    required this.childTax,
    required this.childServiceCharge,
    required this.childGrandTotal,
    required this.parentRemainingSubtotal,
    required this.parentRemainingServiceCharge,
    required this.parentRemainingGrandTotal,
  });
}

class ExchangeComputationResult {
  final double returnedItemsTotal;
  final double replacementItemsTotal;
  final double netDifference;
  final double additionalPaymentDue;
  final double refundOrDepositSurplus;

  const ExchangeComputationResult({
    required this.returnedItemsTotal,
    required this.replacementItemsTotal,
    required this.netDifference,
    required this.additionalPaymentDue,
    required this.refundOrDepositSurplus,
  });
}

/// Pure financial calculation engine shared by PaymentCheckoutScreen, PosCubit,
/// and unit tests in `test/pos_financial_integrity_test.dart`.
class PosFinancialCalculator {
  PosFinancialCalculator._();

  static KasbonDpComputation computeKasbonDp({
    required double grandTotal,
    required double downPayment,
    required double creditLimit,
    required double outstandingBalance,
    double? availableCreditOverride,
    double storeCreditUsed = 0.0,
  }) {
    final normalizedGrand = math.max(0.0, grandTotal);
    final normalizedStoreCredit = storeCreditUsed.clamp(0.0, normalizedGrand);
    final maxDpAllowed = math.max(0.0, normalizedGrand - normalizedStoreCredit);

    String? error;
    if (downPayment < 0) {
      error = 'Nominal Uang Muka (DP) tidak boleh negatif.';
    } else if (downPayment > maxDpAllowed + 0.01) {
      error = 'Nominal Uang Muka (DP) melebihi total tagihan.';
    }

    final clampedDp = downPayment.clamp(0.0, maxDpAllowed);
    final paidTotal = (clampedDp + normalizedStoreCredit).clamp(0.0, normalizedGrand);
    final balanceDue = math.max(0.0, (normalizedGrand - paidTotal).roundToDouble());

    final hasLimit = creditLimit > 0;
    final availableCredit = availableCreditOverride ??
        (hasLimit ? math.max(0.0, creditLimit - outstandingBalance) : double.infinity);

    final isWithinLimit = !hasLimit || balanceDue <= availableCredit + 0.01;
    final minRequiredDp = hasLimit
        ? math.max(0.0, (normalizedGrand - normalizedStoreCredit - availableCredit).ceilToDouble())
        : 0.0;

    if (error == null && !isWithinLimit) {
      error =
          'Sisa tagihan kasbon melebihi sisa plafon kredit pelanggan. Tambahkan Uang Muka (DP) minimal Rp ${minRequiredDp.toStringAsFixed(0)}.';
    }

    return KasbonDpComputation(
      grandTotal: normalizedGrand,
      downPayment: clampedDp,
      storeCreditUsed: normalizedStoreCredit,
      paidTotal: paidTotal,
      balanceDue: balanceDue,
      availableCredit: availableCredit,
      hasCreditLimit: hasLimit,
      isWithinCreditLimit: isWithinLimit,
      minimumRequiredDp: minRequiredDp,
      validationError: error,
    );
  }

  static MultiTenderValidation validateMultiTenderPayments({
    required double grandTotal,
    required List<double> tenderAmounts,
    double storeCreditAmount = 0.0,
  }) {
    final normalizedGrand = math.max(0.0, grandTotal);
    final normalizedStoreCredit = storeCreditAmount.clamp(0.0, normalizedGrand);
    final tendersTotal = tenderAmounts.fold<double>(0.0, (sum, amt) => sum + math.max(0.0, amt));
    final paidTotal = tendersTotal + normalizedStoreCredit;

    final diff = normalizedGrand - paidTotal;
    final remainingDue = diff > 0.5 ? diff.roundToDouble() : 0.0;
    final overpayment = diff < -0.5 ? (-diff).roundToDouble() : 0.0;

    final hasPositiveTenders =
        tenderAmounts.any((a) => a > 0) && tenderAmounts.where((a) => a > 0).length == tenderAmounts.length;
    final fullyCoveredByStoreCredit =
        normalizedStoreCredit >= normalizedGrand - 0.5 && tenderAmounts.every((a) => a == 0);
    final hasValidNonZeroLines = hasPositiveTenders || fullyCoveredByStoreCredit;

    final isExactMatch = diff.abs() <= 0.5 && hasValidNonZeroLines;

    return MultiTenderValidation(
      grandTotal: normalizedGrand,
      tendersTotal: tendersTotal,
      storeCreditAmount: normalizedStoreCredit,
      paidTotal: paidTotal,
      remainingDue: remainingDue,
      overpayment: overpayment,
      isExactMatch: isExactMatch,
      hasValidNonZeroLines: hasValidNonZeroLines,
    );
  }

  /// Mirrors server-side `App\Actions\Restaurant\SplitBillAction` math:
  /// proportional line subtotal, discount, tax, and table service charge.
  static SplitBillCalculationResult calculateProratedSplitBill({
    required List<Map<String, dynamic>> parentItems,
    required List<Map<String, dynamic>> itemsToSplit,
    double parentServiceCharge = 0.0,
  }) {
    double origParentSubtotal = 0.0;
    double origParentDiscount = 0.0;
    double origParentTax = 0.0;

    for (final item in parentItems) {
      final qty = ((item['quantity'] as num?)?.toDouble() ?? 0.0);
      final unitPrice = ((item['unit_price'] as num?)?.toDouble() ?? 0.0);
      final lineSub = ((item['line_subtotal'] as num?)?.toDouble()) ?? (qty * unitPrice);
      final lineDisc = ((item['discount_amount'] as num?)?.toDouble() ?? 0.0);
      final lineTax = ((item['tax_amount'] as num?)?.toDouble() ?? 0.0);
      origParentSubtotal += lineSub;
      origParentDiscount += lineDisc;
      origParentTax += lineTax;
    }

    double childSubtotal = 0.0;
    double childDiscount = 0.0;
    double childTax = 0.0;

    for (final req in itemsToSplit) {
      final splitQty = ((req['quantity'] as num?)?.toDouble() ?? 0.0);
      if (splitQty <= 0) continue;

      Map<String, dynamic>? matched;
      if (req['sale_item_id'] != null) {
        final targetId = (req['sale_item_id'] as num).toInt();
        for (final item in parentItems) {
          final id = (item['sale_item_id'] ?? item['id']) as num?;
          if (id != null && id.toInt() == targetId) {
            matched = item;
            break;
          }
        }
      } else if (req['index'] != null) {
        final idx = (req['index'] as num).toInt();
        if (idx >= 0 && idx < parentItems.length) {
          matched = parentItems[idx];
        }
      }
      if (matched == null) continue;

      final origQty = ((matched['quantity'] as num?)?.toDouble() ?? 0.0);
      if (origQty <= 0) continue;

      final clampedSplitQty = math.min(splitQty, origQty);
      final ratio = clampedSplitQty / origQty;
      final unitPrice = ((matched['unit_price'] as num?)?.toDouble() ?? 0.0);
      final origLineSub = ((matched['line_subtotal'] as num?)?.toDouble()) ?? (origQty * unitPrice);
      final origLineDisc = ((matched['discount_amount'] as num?)?.toDouble() ?? 0.0);
      final origLineTax = ((matched['tax_amount'] as num?)?.toDouble() ?? 0.0);

      childSubtotal += (origLineSub * ratio);
      childDiscount += (origLineDisc * ratio);
      childTax += (origLineTax * ratio);
    }

    final childServiceCharge = (origParentSubtotal > 0 && parentServiceCharge > 0)
        ? (parentServiceCharge * (childSubtotal / origParentSubtotal))
        : 0.0;

    final childNetSubtotal = math.max(0.0, childSubtotal - childDiscount);
    final childGrandTotal = (childNetSubtotal + childTax + childServiceCharge).roundToDouble();

    final remSubtotal = math.max(0.0, origParentSubtotal - childSubtotal);
    final remDiscount = math.max(0.0, origParentDiscount - childDiscount);
    final remTax = math.max(0.0, origParentTax - childTax);
    final remServiceCharge = math.max(0.0, parentServiceCharge - childServiceCharge);
    final remGrandTotal = (math.max(0.0, remSubtotal - remDiscount) + remTax + remServiceCharge).roundToDouble();

    return SplitBillCalculationResult(
      childSubtotal: childSubtotal.roundToDouble(),
      childDiscount: childDiscount.roundToDouble(),
      childTax: childTax.roundToDouble(),
      childServiceCharge: childServiceCharge.roundToDouble(),
      childGrandTotal: childGrandTotal,
      parentRemainingSubtotal: remSubtotal.roundToDouble(),
      parentRemainingServiceCharge: remServiceCharge.roundToDouble(),
      parentRemainingGrandTotal: remGrandTotal,
    );
  }

  static ExchangeComputationResult calculateExchangeDelta({
    required double returnedItemsTotal,
    required double replacementItemsTotal,
  }) {
    final ret = math.max(0.0, returnedItemsTotal);
    final rep = math.max(0.0, replacementItemsTotal);
    final diff = (rep - ret).roundToDouble();

    return ExchangeComputationResult(
      returnedItemsTotal: ret,
      replacementItemsTotal: rep,
      netDifference: diff,
      additionalPaymentDue: diff > 0 ? diff : 0.0,
      refundOrDepositSurplus: diff < 0 ? diff.abs() : 0.0,
    );
  }
}
