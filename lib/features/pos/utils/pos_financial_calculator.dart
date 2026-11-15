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
  final double cashChangeReturned;
  final bool isExactMatch;
  final bool isValidWithCashChange;
  final bool hasValidNonZeroLines;
  final List<double> effectiveRecordedAmounts;

  bool get isValidCheckout => isExactMatch || isValidWithCashChange;

  const MultiTenderValidation({
    required this.grandTotal,
    required this.tendersTotal,
    required this.storeCreditAmount,
    required this.paidTotal,
    required this.remainingDue,
    required this.overpayment,
    this.cashChangeReturned = 0.0,
    required this.isExactMatch,
    this.isValidWithCashChange = false,
    required this.hasValidNonZeroLines,
    this.effectiveRecordedAmounts = const [],
  });
}

class OrderTotalsBreakdown {
  final List<double> roundedLineTotals;
  final double subtotal;
  final double discountTotal;
  final double netSubtotal;
  final double serviceChargeAmount;
  final double taxAmount;
  final double grandTotal;

  const OrderTotalsBreakdown({
    required this.roundedLineTotals,
    required this.subtotal,
    required this.discountTotal,
    required this.netSubtotal,
    required this.serviceChargeAmount,
    required this.taxAmount,
    required this.grandTotal,
  });
}

class VoidReversalSummary {
  final double restoredStoreCredit;
  final double reversedCashInDrawer;
  final double reversedNonCashTotal;
  final double reversedCreditBalanceDue;
  final Map<int, double> restoredPhysicalStockByProduct;

  const VoidReversalSummary({
    required this.restoredStoreCredit,
    required this.reversedCashInDrawer,
    required this.reversedNonCashTotal,
    required this.reversedCreditBalanceDue,
    required this.restoredPhysicalStockByProduct,
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

  /// A.1: Clamp discount strictly within [0, maxSubtotal] so grand total never goes negative.
  static double clampDiscount(double discountAmount, double maxSubtotal) {
    final safeMax = math.max(0.0, maxSubtotal.roundToDouble());
    if (discountAmount.isNaN || discountAmount.isInfinite) return 0.0;
    return discountAmount.clamp(0.0, safeMax).roundToDouble();
  }

  /// A.1: Compute grand total with discount clamped to subtotal.
  static double computeClampedGrandTotal({
    required double subtotal,
    required double discountAmount,
  }) {
    final safeSub = math.max(0.0, subtotal.roundToDouble());
    final clampedDisc = clampDiscount(discountAmount, safeSub);
    return math.max(0.0, (safeSub - clampedDisc).roundToDouble());
  }

  /// A.2: Consistent Rupiah rounding across line items, subtotal, discount, service charge, and PPN tax.
  static OrderTotalsBreakdown computeOrderTotalsWithTaxAndService({
    required List<double> rawLineTotals,
    double discountTotal = 0.0,
    double serviceChargePercent = 0.0,
    double taxPercent = 0.0,
  }) {
    final roundedLines = rawLineTotals.map((l) => math.max(0.0, l.roundToDouble())).toList();
    final subtotal = roundedLines.fold<double>(0.0, (sum, l) => sum + l).roundToDouble();
    final clampedDiscount = clampDiscount(discountTotal, subtotal);
    final netSubtotal = math.max(0.0, subtotal - clampedDiscount).roundToDouble();
    final serviceChargeAmount =
        ((netSubtotal * math.max(0.0, serviceChargePercent)) / 100.0).roundToDouble();
    final taxAmount =
        (((netSubtotal + serviceChargeAmount) * math.max(0.0, taxPercent)) / 100.0).roundToDouble();
    final grandTotal = (netSubtotal + serviceChargeAmount + taxAmount).roundToDouble();

    return OrderTotalsBreakdown(
      roundedLineTotals: roundedLines,
      subtotal: subtotal,
      discountTotal: clampedDiscount,
      netSubtotal: netSubtotal,
      serviceChargeAmount: serviceChargeAmount,
      taxAmount: taxAmount,
      grandTotal: grandTotal,
    );
  }

  /// C.3: Laundry decimal weight * (base rate + express surcharge) rounded cleanly.
  static double computeLaundryLineTotal({
    required double weightKg,
    required double baseRatePerKg,
    double expressSurchargePerKg = 0.0,
    double discountAmount = 0.0,
  }) {
    final unitRate = math.max(0.0, baseRatePerKg + expressSurchargePerKg);
    final gross = (math.max(0.0, weightKg) * unitRate).roundToDouble();
    final clampedDisc = clampDiscount(discountAmount, gross);
    return (gross - clampedDisc).roundToDouble();
  }

  /// A.4: Compute store credit restoration, cash drawer reversal, non-cash reversal, and physical stock returns on sale void.
  static VoidReversalSummary computeVoidReversal(Map<String, dynamic> sale) {
    double restoredStoreCredit = (sale['store_credit_amount'] as num?)?.toDouble() ?? 0.0;
    double reversedCashInDrawer = 0.0;
    double reversedNonCashTotal = 0.0;
    final double reversedCreditBalanceDue = (sale['balance_due'] as num?)?.toDouble() ?? 0.0;

    bool isCashLabel(String raw) {
      final lower = raw.trim().toLowerCase();
      return lower == 'cash' || lower.contains('tunai');
    }

    bool isStoreCreditLabel(String raw) {
      final lower = raw.trim().toLowerCase();
      return lower == 'store_credit' || lower.contains('deposit') || lower.contains('saldo');
    }

    final payments = (sale['payments'] as List<dynamic>? ?? []);
    if (payments.isNotEmpty) {
      for (final raw in payments) {
        if (raw is! Map) continue;
        final amt = (raw['amount'] as num?)?.toDouble() ?? 0.0;
        if (amt <= 0) continue;
        final label = (raw['method_code'] ?? raw['code'] ?? raw['method'] ?? raw['name'] ?? raw['reference'] ?? '').toString();
        if (isStoreCreditLabel(label)) {
          restoredStoreCredit += amt;
        } else if (isCashLabel(label)) {
          reversedCashInDrawer += amt;
        } else {
          reversedNonCashTotal += amt;
        }
      }
    } else {
      final methods = (sale['payment_methods'] as List<dynamic>? ?? []);
      final grand = (sale['grand_total'] as num?)?.toDouble() ?? 0.0;
      final paid = (sale['paid_total'] as num?)?.toDouble() ?? grand;
      final netCashCollected = math.max(0.0, paid - ((sale['change_returned'] as num?)?.toDouble() ?? 0.0));
      if (methods.any((m) => isCashLabel(m.toString()))) {
        reversedCashInDrawer = netCashCollected;
      } else {
        reversedNonCashTotal = netCashCollected;
      }
    }

    final restoredPhysicalStock = <int, double>{};
    final items = (sale['items'] as List<dynamic>? ?? []);
    for (final raw in items) {
      if (raw is! Map) continue;
      if (raw['is_exchange_return'] == true) continue;
      final productId = (raw['product_id'] as num?)?.toInt();
      if (productId == null || productId <= 0) continue;

      final typeStr = (raw['product_type'] ?? raw['type'] ?? '').toString().toLowerCase();
      final catStr = (raw['category_name'] ?? '').toString().toLowerCase();
      final nameStr = (raw['product_name'] ?? '').toString().toLowerCase();
      final isService = raw['is_service'] == true ||
          typeStr == 'service' ||
          typeStr == 'jasa' ||
          typeStr == 'digital' ||
          catStr.contains('jasa') ||
          catStr.contains('servis') ||
          nameStr.startsWith('jasa ');
      if (isService) continue;

      final qty = (raw['quantity'] as num?)?.toDouble() ?? 0.0;
      final mult = (raw['multiplier'] as num?)?.toDouble() ?? 1.0;
      final restoreQty = qty * mult;
      if (restoreQty > 0) {
        restoredPhysicalStock[productId] = (restoredPhysicalStock[productId] ?? 0.0) + restoreQty;
      }
    }

    return VoidReversalSummary(
      restoredStoreCredit: restoredStoreCredit.roundToDouble(),
      reversedCashInDrawer: reversedCashInDrawer.roundToDouble(),
      reversedNonCashTotal: reversedNonCashTotal.roundToDouble(),
      reversedCreditBalanceDue: reversedCreditBalanceDue.roundToDouble(),
      restoredPhysicalStockByProduct: restoredPhysicalStock,
    );
  }

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
    List<String>? tenderMethodCodes,
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

    double cashChangeReturned = 0.0;
    bool isValidWithCashChange = false;
    final effectiveRecordedAmounts = tenderAmounts.map((a) => math.max(0.0, a)).toList();

    if (overpayment > 0.5 &&
        hasValidNonZeroLines &&
        tenderMethodCodes != null &&
        tenderMethodCodes.length == tenderAmounts.length) {
      double cashTotal = 0.0;
      double nonCashTotal = 0.0;
      for (int i = 0; i < tenderAmounts.length; i++) {
        final code = tenderMethodCodes[i].trim().toLowerCase();
        final amt = math.max(0.0, tenderAmounts[i]);
        if (code == 'cash' || code.contains('tunai')) {
          cashTotal += amt;
        } else {
          nonCashTotal += amt;
        }
      }
      final netTargetAfterStoreCredit = math.max(0.0, normalizedGrand - normalizedStoreCredit);
      if (nonCashTotal <= netTargetAfterStoreCredit + 0.5 && cashTotal >= overpayment - 0.5) {
        cashChangeReturned = overpayment;
        isValidWithCashChange = true;
        double remainingChangeToDeduct = overpayment;
        for (int i = 0; i < effectiveRecordedAmounts.length && remainingChangeToDeduct > 0; i++) {
          final code = tenderMethodCodes[i].trim().toLowerCase();
          if (code == 'cash' || code.contains('tunai')) {
            final avail = effectiveRecordedAmounts[i];
            final deduct = math.min(avail, remainingChangeToDeduct);
            effectiveRecordedAmounts[i] = (avail - deduct).roundToDouble();
            remainingChangeToDeduct -= deduct;
          }
        }
      }
    }

    return MultiTenderValidation(
      grandTotal: normalizedGrand,
      tendersTotal: tendersTotal,
      storeCreditAmount: normalizedStoreCredit,
      paidTotal: paidTotal,
      remainingDue: remainingDue,
      overpayment: overpayment,
      cashChangeReturned: cashChangeReturned,
      isExactMatch: isExactMatch,
      isValidWithCashChange: isValidWithCashChange,
      hasValidNonZeroLines: hasValidNonZeroLines,
      effectiveRecordedAmounts: effectiveRecordedAmounts,
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
