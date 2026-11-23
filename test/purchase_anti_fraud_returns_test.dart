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
        'name': 'Samsung Galaxy S25 256GB',
        'sku': 'S25-256',
        'selling_price': 15000000.0,
        'cost_price': 13500000.0,
        'stock': 10.0,
      });
    });

    test('Draft PO does not increment stock until GRN receipt is confirmed', () async {
      // 1. Create a draft PO with 5 units of product 101
      final po = await db.addLocalPurchase(
        supplierId: 1,
        supplierName: 'PT Samsung Electronics Indonesia',
        invoiceNumber: 'INV-SAM-001',
        paymentMode: 'draft',
        isDraft: true,
        items: [
          {
            'product_id': 101,
            'product_name': 'Samsung Galaxy S25 256GB',
            'sku': 'S25-256',
            'quantity': 5.0,
            'unit_cost': 13500000.0,
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

      // 2. Receive the PO goods (full GRN confirmation)
      final receivedPo = await db.receiveLocalPurchase(
        purchaseId: poId,
        deliveryNoteNumber: 'SJ-SAM-001',
        receivedDate: '2026-11-23',
      );
      expect(receivedPo, isNotNull);
      expect(receivedPo!['status'], 'received');
      expect(receivedPo['is_received'], true);
      expect(receivedPo['is_returnable'], true);
      expect(receivedPo['can_receive'], false);
      expect(receivedPo['balance_due'], 67500000.0); // 5 * 13.5M

      // Stock must now be 10 + 5 = 15.0
      final p2 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p2['stock'], 15.0);

      // Stock movements must record GRN purchase
      final movements = db.getLocalStockMovements(productId: 101);
      expect(movements.any((m) => m['type'] == 'purchase'), true);
    });

    test('Partial GRN receipt increments stock proportionally, tracks surat jalan, and allows multiple deliveries', () async {
      // 1. Create a draft PO with 7 units of product 101 (Rp 94.500.000)
      final po = await db.addLocalPurchase(
        supplierId: 1,
        supplierName: 'PT Samsung Electronics Indonesia',
        invoiceNumber: 'INV-SAM-009',
        paymentMode: 'draft',
        isDraft: true,
        items: [
          {
            'product_id': 101,
            'product_name': 'Samsung Galaxy S25 256GB',
            'sku': 'S25-256',
            'quantity': 7.0,
            'unit_cost': 13500000.0,
          }
        ],
      );

      final poId = (po['id'] as num).toInt();
      expect(po['status'], 'draft');

      // 2. First partial GRN: receive 4 units with Surat Jalan SJ-001
      final partial1 = await db.receiveLocalPurchase(
        purchaseId: poId,
        deliveryNoteNumber: 'SJ-SAM-001',
        receivedDate: '2026-11-23',
        notes: 'Diterima 4 box mulus',
        items: [
          {
            'product_id': 101,
            'quantity': 4.0,
          }
        ],
      );

      expect(partial1, isNotNull);
      expect(partial1!['status'], 'partially_received');
      expect(partial1['can_receive'], true);
      expect(partial1['is_received_in_full'], false);
      expect(partial1['delivery_note_number'], 'SJ-SAM-001');
      expect(partial1['received_at'], '2026-11-23');

      // Stock should increase from initial 10.0 to 14.0 (exactly +4)
      final p1 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p1['stock'], 14.0);

      final item1 = (partial1['items'] as List).first;
      expect(item1['received_quantity'], 4.0);
      expect(item1['unreceived_quantity'], 3.0);
      expect(item1['returnable_quantity'], 4.0);

      // Accrued debt for 4 units: 4 * 13.500.000 = 54.000.000
      expect(partial1['balance_due'], 54000000.0);

      // 3. Second partial GRN: receive remaining 3 units with Surat Jalan SJ-002
      final partial2 = await db.receiveLocalPurchase(
        purchaseId: poId,
        deliveryNoteNumber: 'SJ-SAM-002',
        receivedDate: '2026-11-24',
        notes: 'Sisa 3 box tiba lengkap',
        items: [
          {
            'product_id': 101,
            'quantity': 3.0,
          }
        ],
      );

      expect(partial2, isNotNull);
      expect(partial2!['status'], 'received');
      expect(partial2['can_receive'], false);
      expect(partial2['is_received_in_full'], true);
      expect(partial2['delivery_note_number'], 'SJ-SAM-002');

      // Stock should now be 14 + 3 = 17.0 (all 7 units received)
      final p2 = db.getCachedProducts().firstWhere((p) => p['id'] == 101);
      expect(p2['stock'], 17.0);

      final item2 = (partial2['items'] as List).first;
      expect(item2['received_quantity'], 7.0);
      expect(item2['unreceived_quantity'], 0.0);
      expect(item2['returnable_quantity'], 7.0);

      // Total debt is now full grand total: 7 * 13.500.000 = 94.500.000
      expect(partial2['balance_due'], 94500000.0);
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
            'product_name': 'Samsung Galaxy S25 256GB',
            'sku': 'S25-256',
            'quantity': 10.0,
            'unit_cost': 13500000.0,
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
            'unit_cost': 13500000.0,
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
            'unit_cost': 13500000.0,
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
              'unit_cost': 13500000.0,
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
        supplierName: 'PT Samsung Electronics Indonesia',
        paymentMode: 'draft',
        isDraft: true,
        items: [
          {
            'product_id': 101,
            'product_name': 'Samsung Galaxy S25 256GB',
            'sku': 'S25-256',
            'quantity': 5.0,
            'unit_cost': 13500000.0,
          }
        ],
      );

      expect(
        () async => await db.addLocalPurchaseReturn(
          purchaseId: (po['id'] as num).toInt(),
          purchaseNumber: po['number'].toString(),
          supplierName: 'PT Samsung Electronics Indonesia',
          items: [
            {
              'product_id': 101,
              'quantity': 1.0,
              'unit_cost': 13500000.0,
            }
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
