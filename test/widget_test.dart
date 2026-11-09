import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/hardware/barcode_service.dart';
import 'package:nusacommerce_mobile/core/utils/currency_formatter.dart';

void main() {
  group('NusaCommerce Mobile POS Core Unit Tests', () {
    test('IdrCurrencyFormatter formats Rupiah accurately', () {
      expect(IdrCurrencyFormatter.format(1250000), 'Rp 1.250.000');
      expect(IdrCurrencyFormatter.format(17000), 'Rp 17.000');
      expect(IdrCurrencyFormatter.parse('Rp 20.000'), 20000.0);
    });

    test('BarcodeService parses Prefix 20 Digital Scale Weight Barcode', () {
      // 20 + PLU (10007) + Weight 01500g (1.5kg) + Checksum (9)
      final parsed = BarcodeService.parse('2010007015009');
      expect(parsed.isWeightScaleBarcode, isTrue);
      expect(parsed.scalePlu, '10007');
      expect(parsed.weightKg, 1.5);
    });
  });
}
