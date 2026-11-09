import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Indonesian Rupiah Currency, Decimal Weight & POS Feedback Helper
class IdrCurrencyFormatter {
  IdrCurrencyFormatter._();

  static final NumberFormat _idrFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static final NumberFormat _plainNumberFormat = NumberFormat.decimalPattern('id_ID');

  /// Format number as "Rp 1.250.000"
  static String format(num? amount, {bool withSymbol = true}) {
    final value = (amount ?? 0).round();
    if (!withSymbol) {
      return _plainNumberFormat.format(value);
    }
    return _idrFormat.format(value);
  }

  /// Compact format for tight metric badges: "Rp 25,0 Jt" or "Rp 470.000"
  static String formatCompact(num? amount) {
    final value = (amount ?? 0).toDouble();
    if (value.abs() >= 1000000000) {
      return 'Rp ${(value / 1000000000).toStringAsFixed(1).replaceAll('.', ',')} M';
    }
    if (value.abs() >= 10000000) {
      return 'Rp ${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')} Jt';
    }
    return format(value);
  }

  /// Parse user input string like "Rp 20.000" or "20.000" into double
  static double parse(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return 0;
    return double.tryParse(digitsOnly) ?? 0;
  }

  /// Format quantity (supports integer pcs and 3-decimal kg weight items)
  static String formatQty(num qty, {String? unitCode}) {
    final isFractional = (qty % 1) != 0;
    final formatted = isFractional ? qty.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : qty.toInt().toString();
    if (unitCode != null && unitCode.isNotEmpty) {
      return '$formatted $unitCode';
    }
    return formatted;
  }
}

/// Haptic & Sound Feedback for Cashier Ergonomics
class PosFeedback {
  PosFeedback._();

  /// Trigger crisp tactile & audio beep when barcode is scanned or item added
  static Future<void> onScanSuccess() async {
    await HapticFeedback.mediumImpact();
    await SystemSound.play(SystemSoundType.click);
  }

  /// Trigger subtle tap feedback for quantity steppers (+ / -)
  static Future<void> onTapStepper() async {
    await HapticFeedback.selectionClick();
  }

  /// Trigger strong confirmation when payment checkout succeeds
  static Future<void> onCheckoutSuccess() async {
    await HapticFeedback.heavyImpact();
    await SystemSound.play(SystemSoundType.alert);
  }

  /// Trigger warning vibration when expired batch or credit limit blocks action
  static Future<void> onGuardBlocked() async {
    await HapticFeedback.vibrate();
  }
}
