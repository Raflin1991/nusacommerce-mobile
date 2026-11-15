/// Smart Barcode & Digital Scale Prefix 20/21 Parser for NusaCommerce POS
class ParsedBarcodeResult {
  final String rawBarcode;
  final bool isWeightScaleBarcode;
  final String? scalePlu;
  final double? weightKg;
  final double? embeddedPrice;

  const ParsedBarcodeResult({
    required this.rawBarcode,
    this.isWeightScaleBarcode = false,
    this.scalePlu,
    this.weightKg,
    this.embeddedPrice,
  });
}

class BarcodeService {
  BarcodeService._();

  static String? _lastScannedCode;
  static DateTime? _lastScannedAt;

  /// Phase 3.2: 350ms anti-double-scan debounce guard.
  /// Returns `false` if the identical barcode is scanned within `debounceMs`.
  static bool shouldAcceptScan(
    String rawCode, {
    DateTime? now,
    int debounceMs = 350,
  }) {
    final cleaned = rawCode.trim();
    if (cleaned.isEmpty) return false;
    final current = now ?? DateTime.now();
    if (_lastScannedCode == cleaned &&
        _lastScannedAt != null &&
        current.difference(_lastScannedAt!).inMilliseconds < debounceMs) {
      return false;
    }
    _lastScannedCode = cleaned;
    _lastScannedAt = current;
    return true;
  }

  static void resetDebounce() {
    _lastScannedCode = null;
    _lastScannedAt = null;
  }

  /// Parse standard EAN-13 / Code128 barcode or Digital Scale Barcode (Prefix 20 / 21).
  /// Format Prefix 20 (Weight): 20 + 5-digit PLU + 5-digit Weight (grams) + 1 check digit
  /// Format Prefix 21 (Price):  21 + 5-digit PLU + 5-digit Price (Rupiah) + 1 check digit
  static ParsedBarcodeResult parse(String code) {
    final cleaned = code.trim();

    if (cleaned.length == 13 && RegExp(r'^[0-9]{13}$').hasMatch(cleaned)) {
      final prefix = cleaned.substring(0, 2);
      if (prefix == '20') {
        final plu = cleaned.substring(2, 7);
        final grams = int.tryParse(cleaned.substring(7, 12)) ?? 0;
        final weightKg = grams > 0 ? grams / 1000.0 : 1.0;
        return ParsedBarcodeResult(
          rawBarcode: cleaned,
          isWeightScaleBarcode: true,
          scalePlu: plu,
          weightKg: weightKg,
        );
      } else if (prefix == '21') {
        final plu = cleaned.substring(2, 7);
        final price = double.tryParse(cleaned.substring(7, 12)) ?? 0;
        return ParsedBarcodeResult(
          rawBarcode: cleaned,
          isWeightScaleBarcode: true,
          scalePlu: plu,
          embeddedPrice: price,
        );
      }
    }

    return ParsedBarcodeResult(rawBarcode: cleaned);
  }
}
