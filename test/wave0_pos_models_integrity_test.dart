import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/constants/api_endpoints.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';

void main() {
  group('Wave 0.5 — Zero Fabricated POS Catalog Data', () {
    test('ProductModel.fromJson does not fabricate Lusin/Dus conversions or Rak Utama A1 shelf', () {
      final product = ProductModel.fromJson({
        'id': 101,
        'name': 'Iga Bakar Madu Kemang',
        'sku': 'MN-IGA-BAKAR',
        'barcode': '8991000101',
        'selling_price': 118000,
        'cost_price': 55000,
        'stock': 15,
        'unit': {'id': 1, 'code': 'porsi', 'name': 'Porsi'},
      });

      expect(product.unitConversions, isEmpty);
      expect(product.shelfLocation, isNull);
    });

    test('ProductVariantModel.fromJson defaults missing stock to 0.0 instead of 20.0', () {
      final variant = ProductVariantModel.fromJson({
        'id': 501,
        'name': 'Large Cup 16oz',
        'sku': 'MN-KOPI-LRG',
        'selling_price': 34000,
      });

      expect(variant.stock, equals(0.0));
    });

    test('ApiEndpoints defaultBaseUrl contains no legacy sambalengine domain', () {
      expect(ApiEndpoints.defaultBaseUrl.contains('sambalengine'), isFalse);
      expect(ApiEndpoints.vpsServerUrl.contains('sambalengine'), isFalse);
    });
  });
}
