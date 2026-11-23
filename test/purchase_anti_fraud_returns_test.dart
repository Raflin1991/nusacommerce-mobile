import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Anti Over-Return Fraud Guard & PO Goods Receipt (GRN)', () {
    late OfflineDatabase db;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = OfflineDatabase(prefs);

      // Seed initial product with stock = 10
      await db.addOrUpdateLocalProduct({
        'id': 101,
        'name': 'Beras Ramos 5kg',
        'sku': 'BRS-RAMOS-5K',
        'selling_price': 75000.0,
        'cost_price': 60000.0,
        'stock': 10.0,
      });
    });

    test('Draft PO does not increment stock until GRN receipt is confirmed', () async {
      // 1. Create a draft PO with 5 units of product 101
      final po = await db.addLocalPurchase(
        supplierId: 1,
        supplierName: 'PT Beras Jaya',
        invoiceNumber: 'INV-001',
        paymentMode: 'draft',
        isDraft: true,
        items: [
          {
            'product_id': 101,
            'product_name': 'Beras Ramos 5kg',
            'sku': 'BRS-RAMOS-5K',
            'quantity': 5.0,
            'unit_cost': 60000.0,
          }
        ],
      );

      final poId = (po['id'] as num).toInt();
      expect(po['status'], 'draft');
      expect(po['is_received'], false);
      expect(po['can_receive'], true);
      expect(po['is_returnable'], false);

      // Verify stock is still 10.0 (draft hasn't arrived)
      final p1 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p1['stock'], 10.0);

      // 2. Receive the PO goods (GRN confirmation)
      final receivedPo = await db.receiveLocalPurchase(purchaseId: poId);
      expect(receivedPo, isNotNull);
      expect(receivedPo!['status'], 'received');
      expect(receivedPo['is_received'], true);
      expect(receivedPo['is_returnable'], true);
      expect(receivedPo['can_receive'], false);
      expect(receivedPo['balance_due'], 300000.0); // Now payable/tempo

      // Stock must now be 10 + 5 = 15.0
      final p2 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p2['stock'], 15.0);

      // Stock movements must record GRN purchase
      final movements = db.getLocalStockMovements(productId: 101);
      expect(movements.any((m) => m['type'] == 'purchase'), true);
    });

    test('Anti Over-Return: Multiple returns cannot exceed received quantity and locks when exhausted', () async {
      // 1. Create a received PO with 10 units (paid)
      final po = await db.addLocalPurchase(
        supplierId: 1,
        supplierName: 'PT Pangan Makmur',
        invoiceNumber: 'INV-PM-001',
        paymentMode: 'paid',
        items: [
          {
            'product_id': 101,
            'product_name': 'Beras Ramos 5kg',
            'sku': 'BRS-RAMOS-5K',
            'quantity': 10.0,
            'unit_cost': 60000.0,
          }
        ],
      );
      final poId = (po['id'] as num).toInt();
      final poNumber = po['number'].toString();

      // Product stock increased from 10 to 20
      final pInit = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(pInit['stock'], 20.0);

      // 2. First return: return 4 units
      final ret1 = await db.addLocalPurchaseReturn(
        purchaseId: poId,
        purchaseNumber: poNumber,
        supplierName: 'PT Pangan Makmur',
        notes: 'Kemasan sobek',
        items: [
          {
            'product_id': 101,
            'quantity': 4.0,
            'unit_cost': 60000.0,
          }
        ],
      );
      expect(ret1['purchase_id'], poId);

      // Product stock should decrease from 20 to 16
      final p1 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p1['stock'], 16.0);

      // Verify original PO tracking updated
      final purchases1 = db.getLocalPurchases();
      final updatedPo1 = purchases1.firstWhere((p) => p['id'] == poId);
      final item1 = (updatedPo1['items'] as List).first;
      expect(item1['returned_quantity'], 4.0);
      expect(item1['returnable_quantity'], 6.0);
      expect(updatedPo1['is_fully_returned'], false);
      expect(updatedPo1['is_returnable'], true);

      // 3. Second return: return 6 units (all remaining)
      await db.addLocalPurchaseReturn(
        purchaseId: poId,
        purchaseNumber: poNumber,
        supplierName: 'PT Pangan Makmur',
        notes: 'Kutu beras',
        items: [
          {
            'product_id': 101,
            'quantity': 6.0,
            'unit_cost': 60000.0,
          }
        ],
      );

      // Product stock should decrease to 10
      final p2 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p2['stock'], 10.0);

      // Verify PO is now fully locked (is_fully_returned = true, is_returnable = false)
      final purchases2 = db.getLocalPurchases();
      final updatedPo2 = purchases2.firstWhere((p) => p['id'] == poId);
      final item2 = (updatedPo2['items'] as List).first;
      expect(item2['returned_quantity'], 10.0);
      expect(item2['returnable_quantity'], 0.0);
      expect(updatedPo2['is_fully_returned'], true);
      expect(updatedPo2['is_returnable'], false);
      expect(updatedPo2['status_label'], 'SEMUA BARANG DIRETUR');

      // 4. Third return attempt: must be REJECTED! (Fraud guard)
      expect(
        () async => await db.addLocalPurchaseReturn(
          purchaseId: poId,
          purchaseNumber: poNumber,
          supplierName: 'PT Pangan Makmur',
          notes: 'Percobaan retur berulang',
          items: [
            {
              'product_id': 101,
              'quantity': 1.0,
              'unit_cost': 60000.0,
            }
          ],
        ),
        throwsA(isA<StateError>()),
      );

      // Stock remains safely intact at 10.0
      final p3 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p3['stock'], 10.0);
    });

    test('Draft PO return attempt is strictly rejected by StateError', () async {
      final po = await db.addLocalPurchase(
        supplierId: 1,
        supplierName: 'PT Beras Jaya',
        paymentMode: 'draft',
        isDraft: true,
        items: [
          {
            'product_id': 101,
            'product_name': 'Beras Ramos 5kg',
            'sku': 'BRS-RAMOS-5K',
            'quantity': 5.0,
            'unit_cost': 60000.0,
          }
        ],
      );

      expect(
        () async => await db.addLocalPurchaseReturn(
          purchaseId: (po['id'] as num).toInt(),
          purchaseNumber: po['number'].toString(),
          supplierName: 'PT Beras Jaya',
          items: [
            {
              'product_id': 101,
              'quantity': 1.0,
              'unit_cost': 60000.0,
            }
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
