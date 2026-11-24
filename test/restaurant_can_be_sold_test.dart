import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';

void main() {
  group('Restaurant can_be_sold & Kit BOM Mobile Parity', () {
    test('ProductModel.fromJson & isSellableInPos enforce can_be_sold and kit parity', () {
      final rawMaterial = ProductModel.fromJson({
        'id': 10,
        'name': 'Beras Pandan Wangi',
        'sku': 'RAW-BERAS-01',
        'type': 'simple',
        'selling_price': 0,
        'cost_price': 14000,
        'stock': 25.0,
        'track_stock': true,
        'can_be_sold': false,
        'is_visible_online': false,
        'category': {'id': 4, 'name': 'Bahan Baku Dapur'},
      });

      final kitMenu = ProductModel.fromJson({
        'id': 20,
        'name': 'Nasi Goreng Spesial',
        'sku': 'MENU-NASGOR-01',
        'type': 'kit',
        'selling_price': 35000,
        'cost_price': 6500,
        'stock': 0.0,
        'track_stock': false,
        'can_be_sold': true,
        'is_visible_online': true,
        'category': {'id': 1, 'name': 'Makanan Utama'},
      });

      expect(rawMaterial.canBeSold, isFalse);
      expect(rawMaterial.isVisibleOnline, isFalse);
      expect(rawMaterial.isSellableInPos, isFalse,
          reason: 'Raw material with stock > 0 must still be hidden from POS when canBeSold=false');

      expect(kitMenu.canBeSold, isTrue);
      expect(kitMenu.isVisibleOnline, isTrue);
      expect(kitMenu.isSellableInPos, isTrue,
          reason: 'Kit recipe menu must appear in POS even when own stock counter is 0');
    });

    test('PosState.filteredProducts & posCategories exclude non-sellable raw materials', () {
      const beras = ProductModel(
        id: 1,
        name: 'Beras',
        sku: 'RAW-1',
        barcode: 'RAW-1',
        type: 'simple',
        sellingPrice: 0,
        costPrice: 14000,
        stock: 50,
        categoryId: 4,
        categoryName: 'Bahan Baku Dapur',
        canBeSold: false,
        isVisibleOnline: false,
      );
      const nasgor = ProductModel(
        id: 2,
        name: 'Nasi Goreng Spesial',
        sku: 'MENU-1',
        barcode: 'MENU-1',
        type: 'kit',
        sellingPrice: 35000,
        costPrice: 6500,
        stock: 0,
        trackStock: false,
        categoryId: 1,
        categoryName: 'Makanan Utama',
        canBeSold: true,
        isVisibleOnline: true,
      );

      const state = PosState(
        allProducts: [beras, nasgor],
        categories: [
          {'id': 0, 'name': 'Semua'},
          {'id': 1, 'name': 'Makanan Utama'},
          {'id': 4, 'name': 'Bahan Baku Dapur'},
        ],
      );

      expect(state.filteredProducts.map((p) => p.id).toList(), equals([2]));
      expect(state.posCategories.map((c) => c['id']).toList(), equals([0, 1]));
      expect(state.allProducts.length, equals(2),
          reason: 'Inventory & Purchasing retain all products including raw materials');
    });

    testWidgets('can_be_sold SwitchListTile renders cleanly on 360x640 / <=300px narrow modal with ZERO overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool canBeSold = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setModalState) => SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Dapat Dijual (POS & Toko Online)',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Matikan untuk bahan baku dapur agar tidak muncul di kasir POS maupun etalase online.',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          value: canBeSold,
                          onChanged: (v) => setModalState(() => canBeSold = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Dapat Dijual (POS & Toko Online)'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(canBeSold, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
