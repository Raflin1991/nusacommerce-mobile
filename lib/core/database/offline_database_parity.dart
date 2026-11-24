part of 'offline_database.dart';

extension OfflineDatabaseParityExt on OfflineDatabase {
  // ===========================================================================
  // A. TAXONOMIES (CATEGORIES CRUD, BRANDS, UNITS, RETURN REASONS, EXPENSE CATS, GROUPS)
  // ===========================================================================

  Future<Map<String, dynamic>> addOrUpdateLocalCategory(Map<String, dynamic> category) async {
    final cats = getCachedCategories().where((c) => (c['id'] as num?)?.toInt() != 0).toList();
    final id = (category['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{
      ...category,
      'id': id,
      'color': (category['color'] ?? '#2563EB').toString(),
      'products_count': category['products_count'] ?? 0,
    };
    final idx = cats.indexWhere((c) => (c['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      cats[idx] = entry;
    } else {
      cats.add(entry);
    }
    cats.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    final merged = [
      {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': getCachedProducts().length},
      ...cats,
    ];
    await cacheCategories(merged);
    return entry;
  }

  Future<void> deleteLocalCategory(int categoryId) async {
    final cats = getCachedCategories().where((c) => (c['id'] as num?)?.toInt() != categoryId).toList();
    await cacheCategories(cats);
  }

  Future<void> cacheBrands(List<Map<String, dynamic>> brands) async {
    await _writeCollectionList(OfflineDatabase._keyCachedBrands, brands);
  }

  List<Map<String, dynamic>> getCachedBrands() {
    final list = _readCollectionList(OfflineDatabase._keyCachedBrands);
    if (list.isNotEmpty) return list;
    return [
      {'id': 1, 'name': 'Generic / Toko', 'products_count': 0, 'is_default': true},
    ];
  }

  Future<Map<String, dynamic>> addOrUpdateLocalBrand(Map<String, dynamic> brand) async {
    final list = getCachedBrands();
    final id = (brand['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...brand, 'id': id};
    final idx = list.indexWhere((b) => (b['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await cacheBrands(list);
    return entry;
  }

  Future<void> deleteLocalBrand(int id) async {
    final list = getCachedBrands().where((b) => (b['id'] as num?)?.toInt() != id).toList();
    await cacheBrands(list);
  }

  Future<void> cacheUnits(List<Map<String, dynamic>> units) async {
    await _writeCollectionList(OfflineDatabase._keyCachedUnits, units);
  }

  List<Map<String, dynamic>> getCachedUnits() {
    final list = _readCollectionList(OfflineDatabase._keyCachedUnits);
    if (list.isNotEmpty) return list;
    return [
      {'id': 1, 'code': 'pcs', 'name': 'Pcs / Satuan', 'category': 'count'},
      {'id': 2, 'code': 'pak', 'name': 'Pak / Pack', 'category': 'count'},
      {'id': 3, 'code': 'box', 'name': 'Box / Dus', 'category': 'count'},
      {'id': 4, 'code': 'lusin', 'name': 'Lusin', 'category': 'count'},
      {'id': 5, 'code': 'kg', 'name': 'Kilogram', 'category': 'weight'},
      {'id': 6, 'code': 'liter', 'name': 'Liter', 'category': 'volume'},
      {'id': 7, 'code': 'porsi', 'name': 'Porsi', 'category': 'count'},
      {'id': 8, 'code': 'jasa', 'name': 'Jasa / Layanan', 'category': 'count'},
    ];
  }

  Future<Map<String, dynamic>> addOrUpdateLocalUnit(Map<String, dynamic> unit) async {
    final list = getCachedUnits();
    final id = (unit['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...unit, 'id': id};
    final idx = list.indexWhere((u) => (u['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await cacheUnits(list);
    return entry;
  }

  Future<void> deleteLocalUnit(int id) async {
    final list = getCachedUnits().where((u) => (u['id'] as num?)?.toInt() != id).toList();
    await cacheUnits(list);
  }

  Future<void> cacheReturnReasons(List<Map<String, dynamic>> reasons) async {
    await _writeCollectionList(OfflineDatabase._keyCachedReturnReasons, reasons);
  }

  List<Map<String, dynamic>> getCachedReturnReasons() {
    final list = _readCollectionList(OfflineDatabase._keyCachedReturnReasons);
    if (list.isNotEmpty) return list;
    return [
      {'id': 1, 'code': 'DAMAGED', 'name': 'Barang Rusak / Cacat', 'default_restock': false},
      {'id': 2, 'code': 'EXPIRED', 'name': 'Kadaluarsa / Basi', 'default_restock': false},
      {'id': 3, 'code': 'WRONG_ITEM', 'name': 'Salah Pilih / Tukar Item', 'default_restock': true},
      {'id': 4, 'code': 'CUSTOMER_CANCEL', 'name': 'Pelanggan Batal Beli', 'default_restock': true},
    ];
  }

  Future<Map<String, dynamic>> addOrUpdateLocalReturnReason(Map<String, dynamic> reason) async {
    final list = getCachedReturnReasons();
    final id = (reason['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...reason, 'id': id};
    final idx = list.indexWhere((r) => (r['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await cacheReturnReasons(list);
    return entry;
  }

  Future<void> deleteLocalReturnReason(int id) async {
    final list = getCachedReturnReasons().where((r) => (r['id'] as num?)?.toInt() != id).toList();
    await cacheReturnReasons(list);
  }

  Future<void> cacheExpenseCategories(List<Map<String, dynamic>> categories) async {
    await _writeCollectionList(OfflineDatabase._keyCachedExpenseCategories, categories);
  }

  List<Map<String, dynamic>> getCachedExpenseCategories() {
    final list = _readCollectionList(OfflineDatabase._keyCachedExpenseCategories);
    if (list.isNotEmpty) return list;
    return [
      {'id': 1, 'name': 'Listrik, Air & Internet'},
      {'id': 2, 'name': 'Plastik, Kemasan & ATK'},
      {'id': 3, 'name': 'Transport & Ongkir'},
      {'id': 4, 'name': 'Uang Makan / Gaji Harian'},
      {'id': 5, 'name': 'Sewa & Perawatan Toko'},
      {'id': 6, 'name': 'Biaya Operasional Lain'},
    ];
  }

  Future<Map<String, dynamic>> addOrUpdateLocalExpenseCategory(Map<String, dynamic> cat) async {
    final list = getCachedExpenseCategories();
    final id = (cat['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...cat, 'id': id};
    final idx = list.indexWhere((c) => (c['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await cacheExpenseCategories(list);
    return entry;
  }

  Future<void> deleteLocalExpenseCategory(int id) async {
    final list = getCachedExpenseCategories().where((c) => (c['id'] as num?)?.toInt() != id).toList();
    await cacheExpenseCategories(list);
  }

  Future<void> deleteLocalExpense(int id) async {
    final list = _readCollectionList(OfflineDatabase._keyLocalExpenses);
    list.removeWhere((e) => (e['id'] as num?)?.toInt() == id);
    await _sqlite.deleteLocalExpense(id);
    await _writeCollectionList(OfflineDatabase._keyLocalExpenses, list);
  }

  Future<void> updateLocalExpense(int id, {required String category, required double amount, required String description}) async {
    final list = _readCollectionList(OfflineDatabase._keyLocalExpenses);
    final idx = list.indexWhere((e) => (e['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      final item = Map<String, dynamic>.from(list[idx]);
      item['category_name'] = category;
      item['category'] = {'id': item['category_id'] ?? 1, 'name': category};
      item['amount'] = amount;
      item['description'] = description;
      list[idx] = item;
      await _sqlite.upsertLocalExpense(item);
      await _writeCollectionList(OfflineDatabase._keyLocalExpenses, list);
    }
  }

  Future<void> cacheCustomerGroups(List<Map<String, dynamic>> groups) async {
    await _writeCollectionList(OfflineDatabase._keyCachedCustomerGroups, groups);
  }

  List<Map<String, dynamic>> getCachedCustomerGroups() {
    final list = _readCollectionList(OfflineDatabase._keyCachedCustomerGroups);
    if (list.isNotEmpty) return list;
    return [
      {'id': 1, 'name': 'Umum / Walk-in', 'default_discount_percent': 0.0, 'loyalty_multiplier': 1.0, 'customers_count': 0},
      {'id': 2, 'name': 'Member Silver', 'default_discount_percent': 3.0, 'loyalty_multiplier': 1.5, 'customers_count': 0},
      {'id': 3, 'name': 'Grosir / VIP', 'default_discount_percent': 5.0, 'loyalty_multiplier': 2.0, 'customers_count': 0},
    ];
  }

  Future<Map<String, dynamic>> addOrUpdateLocalCustomerGroup(Map<String, dynamic> group) async {
    final list = getCachedCustomerGroups();
    final id = (group['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...group, 'id': id};
    final idx = list.indexWhere((g) => (g['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    await cacheCustomerGroups(list);
    return entry;
  }

  Future<void> deleteLocalCustomerGroup(int id) async {
    final list = getCachedCustomerGroups().where((g) => (g['id'] as num?)?.toInt() != id).toList();
    await cacheCustomerGroups(list);
  }

  // ===========================================================================
  // B. STOCK MOVEMENTS CARD & PRODUCT DELETE
  // ===========================================================================

  Future<void> deleteLocalProduct(int productId) async {
    final products = getCachedProducts()..removeWhere((p) => (p['id'] as num?)?.toInt() == productId);
    _memProducts = products;
    await productsDao.deleteProduct(productId);
    await _writeDaoMirrorFallback(OfflineDatabase._keyCachedProducts, products);
  }

  List<Map<String, dynamic>> getLocalStockMovements({int? productId, String? type}) {
    var list = _readCollectionList(OfflineDatabase._keyLocalStockMovements);
    if (productId != null) {
      list = list.where((m) => (m['product_id'] as num?)?.toInt() == productId).toList();
    }
    if (type != null && type.isNotEmpty && type != 'all') {
      list = list.where((m) => (m['type'] ?? '').toString() == type).toList();
    }
    list.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    return list;
  }

  Future<void> recordLocalStockMovement({
    required int productId,
    required String productName,
    required String sku,
    required String unitCode,
    required String type,
    required double quantityDelta,
    required double quantityAfter,
    double unitCost = 0.0,
    String? notes,
    String? createdBy,
  }) async {
    final list = _readCollectionList(OfflineDatabase._keyLocalStockMovements);
    list.insert(0, {
      'id': DateTime.now().microsecondsSinceEpoch,
      'product_id': productId,
      'product_name': productName,
      'sku': sku,
      'unit_code': unitCode,
      'type': type,
      'quantity_delta': quantityDelta,
      'quantity_after': quantityAfter,
      'unit_cost': unitCost,
      'notes': notes,
      'created_by': createdBy ?? 'Pemilik',
      'created_at': DateTime.now().toIso8601String(),
    });
    if (list.length > 500) {
      list.removeRange(500, list.length);
    }
    await productsDao.insertStockMovement(list.first);
    await _writeCollectionList(OfflineDatabase._keyLocalStockMovements, list);
  }

  // ===========================================================================
  // C. MULTI-ITEM PURCHASES (PO) & PURCHASE RETURNS
  // ===========================================================================

  List<Map<String, dynamic>> getLocalPurchases() {
    final list = _readCollectionList(OfflineDatabase._keyLocalPurchases);
    list.sort((a, b) => (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0));
    return list;
  }

  Future<Map<String, dynamic>> addLocalPurchase({
    required int supplierId,
    required String supplierName,
    String? supplierPhone,
    String? invoiceNumber,
    required List<Map<String, dynamic>> items,
    required String paymentMode, // paid | partial | credit | draft
    double paidAmount = 0.0,
    String paymentMethod = 'Tunai',
    String? dueDate,
    String? notes,
    bool isDraft = false,
  }) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final poNumber = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}-${(id % 10000).toString().padLeft(4, '0')}';

    final effectiveDraft = isDraft || paymentMode == 'draft';

    double grandTotal = 0.0;
    final normalizedItems = <Map<String, dynamic>>[];
    for (final raw in items) {
      final pid = (raw['product_id'] as num).toInt();
      final qty = (raw['quantity'] as num).toDouble();
      final unitCost = (raw['unit_cost'] as num).toDouble();
      final lineTotal = qty * unitCost;
      grandTotal += lineTotal;
      normalizedItems.add({
        'product_id': pid,
        'product_name': raw['product_name'] ?? 'Produk',
        'sku': raw['sku'] ?? '-',
        'quantity': qty,
        'unit_cost': unitCost,
        'line_total': lineTotal,
        'received_quantity': effectiveDraft ? 0.0 : qty,
        'returned_quantity': 0.0,
        'returnable_quantity': effectiveDraft ? 0.0 : qty,
      });

      if (!effectiveDraft) {
        // Increment product stock + update WAC cost_price + log stock movement
        final products = getCachedProducts();
        final pIdx = products.indexWhere((p) => (p['id'] as num?)?.toInt() == pid);
        if (pIdx >= 0) {
          final p = Map<String, dynamic>.from(products[pIdx]);
          final oldStock = (p['stock'] as num?)?.toDouble() ?? 0.0;
          final nextStock = oldStock + qty;
          p['stock'] = nextStock;
          if (unitCost > 0) p['cost_price'] = unitCost;
          p['is_low_stock'] = nextStock <= ((p['reorder_level'] as num?)?.toDouble() ?? 5.0);
          await addOrUpdateLocalProduct(p);
          await recordLocalStockMovement(
            productId: pid,
            productName: (p['name'] ?? 'Produk').toString(),
            sku: (p['sku'] ?? '-').toString(),
            unitCode: (p['unit_code'] ?? 'pcs').toString(),
            type: 'purchase',
            quantityDelta: qty,
            quantityAfter: nextStock,
            unitCost: unitCost,
            notes: 'Pembelian $poNumber ($supplierName)',
          );
        }
      }
    }

    double appliedPaid = 0.0;
    if (!effectiveDraft) {
      if (paymentMode == 'paid') {
        appliedPaid = grandTotal;
      } else if (paymentMode == 'partial') {
        appliedPaid = paidAmount.clamp(0.0, grandTotal);
      }
    }
    final balanceDue = effectiveDraft ? 0.0 : (grandTotal - appliedPaid).clamp(0.0, grandTotal);
    final status = effectiveDraft ? 'draft' : (balanceDue <= 0.5 ? 'paid' : (appliedPaid > 0 ? 'partially_paid' : 'received'));

    final record = {
      'id': id,
      'number': poNumber,
      'purchase_number': poNumber,
      'supplier_invoice_number': invoiceNumber,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_date': now.toIso8601String().split('T').first,
      'due_date': dueDate ?? now.add(const Duration(days: 14)).toIso8601String().split('T').first,
      'status': status,
      'status_label': effectiveDraft ? 'DRAF PO (BELUM DITERIMA)' : (status == 'paid' ? 'LUNAS' : 'TEMPO / HUTANG'),
      'is_received': !effectiveDraft,
      'can_receive': effectiveDraft,
      'is_returnable': !effectiveDraft,
      'is_fully_returned': false,
      'total_returnable_qty': effectiveDraft ? 0.0 : grandTotal,
      'subtotal': grandTotal,
      'grand_total': grandTotal,
      'paid_total': appliedPaid,
      'balance_due': balanceDue,
      'notes': notes,
      'items': normalizedItems,
      'is_local': true,
    };

    final purchases = _readCollectionList(OfflineDatabase._keyLocalPurchases);
    purchases.insert(0, record);
    await _writeCollectionList(OfflineDatabase._keyLocalPurchases, purchases);

    if (!effectiveDraft && balanceDue > 0.5) {
      await addLocalPayable(
        purchaseId: id,
        supplierId: supplierId,
        supplierName: supplierName,
        supplierPhone: supplierPhone,
        totalAmount: grandTotal,
        paidAmount: appliedPaid,
        dueDate: record['due_date'].toString(),
        invoiceNumber: invoiceNumber?.isNotEmpty == true ? invoiceNumber : poNumber,
        notes: notes,
      );
    }

    if (!effectiveDraft && appliedPaid > 0) {
      await addLocalCashEntry(
        title: 'Pembelian Stok $poNumber ($supplierName)',
        category: 'Pembelian Stok',
        direction: 'out',
        channel: paymentMethod.toLowerCase().contains('tunai') || paymentMethod.toLowerCase().contains('cash')
            ? 'cash'
            : 'non_cash',
        methodName: paymentMethod,
        amount: appliedPaid,
      );
    }
    return record;
  }

  Future<Map<String, dynamic>?> receiveLocalPurchase({
    required int purchaseId,
    String? poNumber,
    String? deliveryNoteNumber,
    String? receivedDate,
    String? notes,
    List<Map<String, dynamic>>? items,
  }) async {
    final purchases = _readCollectionList(OfflineDatabase._keyLocalPurchases);
    final idx = purchases.indexWhere(
      (p) =>
          (p['id'] as num?)?.toInt() == purchaseId ||
          (poNumber != null && poNumber.isNotEmpty && p['number'] == poNumber),
    );
    if (idx < 0) return null;

    final po = Map<String, dynamic>.from(purchases[idx]);
    final curStatus = (po['status'] ?? '').toString().toLowerCase();
    if (po['can_receive'] == false && (curStatus == 'received' || curStatus == 'paid' || curStatus == 'cancelled')) {
      return po;
    }

    final rawItems = po['items'] as List<dynamic>? ?? [];
    double newlyReceivedValue = 0.0;
    final updatedItems = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final rawMap = Map<String, dynamic>.from(raw);
      final pid = (rawMap['product_id'] as num?)?.toInt();
      final itemId = (rawMap['id'] as num?)?.toInt();
      final orderedQty = (rawMap['quantity'] as num?)?.toDouble() ?? 0.0;
      final prevReceived = (rawMap['received_quantity'] as num?)?.toDouble() ?? 0.0;
      final remUnreceived = (orderedQty - prevReceived).clamp(0.0, double.infinity);
      final unitCost = (rawMap['unit_cost'] as num?)?.toDouble() ?? 0.0;

      double receiveNow = 0.0;
      if (items != null && items.isNotEmpty) {
        final match = items.firstWhere(
          (m) =>
              (m['purchase_item_id'] as num?)?.toInt() == itemId ||
              (m['id'] as num?)?.toInt() == itemId ||
              (m['product_id'] as num?)?.toInt() == pid,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          final requestedQty = (match['quantity'] as num?)?.toDouble() ?? (match['quantity_received'] as num?)?.toDouble() ?? 0.0;
          receiveNow = requestedQty.clamp(0.0, remUnreceived);
        }
      } else {
        receiveNow = remUnreceived;
      }

      final nextReceivedQty = prevReceived + receiveNow;
      final prevReturned = (rawMap['returned_quantity'] as num?)?.toDouble() ?? 0.0;
      final nextReturnable = (nextReceivedQty - prevReturned).clamp(0.0, double.infinity);
      final nextUnreceived = (orderedQty - nextReceivedQty).clamp(0.0, double.infinity);

      rawMap['received_quantity'] = nextReceivedQty;
      rawMap['returnable_quantity'] = nextReturnable;
      rawMap['unreceived_quantity'] = nextUnreceived;
      updatedItems.add(rawMap);

      if (receiveNow <= 0 || pid == null) continue;

      newlyReceivedValue += receiveNow * unitCost;

      final products = getCachedProducts();
      final pIdx = products.indexWhere((p) => (p['id'] as num?)?.toInt() == pid);
      if (pIdx >= 0) {
        final p = Map<String, dynamic>.from(products[pIdx]);
        final oldStock = (p['stock'] as num?)?.toDouble() ?? 0.0;
        final nextStock = oldStock + receiveNow;
        p['stock'] = nextStock;
        if (unitCost > 0) p['cost_price'] = unitCost;
        p['is_low_stock'] = nextStock <= ((p['reorder_level'] as num?)?.toDouble() ?? 5.0);
        await addOrUpdateLocalProduct(p);
        await recordLocalStockMovement(
          productId: pid,
          productName: (p['name'] ?? 'Produk').toString(),
          sku: (p['sku'] ?? '-').toString(),
          unitCode: (p['unit_code'] ?? 'pcs').toString(),
          type: 'purchase',
          quantityDelta: receiveNow,
          quantityAfter: nextStock,
          unitCost: unitCost,
          notes: 'Penerimaan GRN ${po['number']} • SJ: ${deliveryNoteNumber ?? "-"} (${po['supplier_name']})',
        );
      }
    }

    double totalUnreceivedLeft = 0.0;
    double totalReturnableLeft = 0.0;
    for (final it in updatedItems) {
      totalUnreceivedLeft += (it['unreceived_quantity'] as num?)?.toDouble() ?? 0.0;
      totalReturnableLeft += (it['returnable_quantity'] as num?)?.toDouble() ?? 0.0;
    }

    final isAllReceived = totalUnreceivedLeft <= 0.0001;
    final grandTotal = (po['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paidTotal = (po['paid_total'] as num?)?.toDouble() ?? 0.0;

    final curBalance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
    final nextBalance = isAllReceived
        ? (grandTotal - paidTotal).clamp(0.0, grandTotal)
        : (curBalance + newlyReceivedValue).clamp(0.0, grandTotal);

    po['items'] = updatedItems;
    po['status'] = isAllReceived
        ? (nextBalance <= 0.5 ? 'paid' : 'received')
        : 'partially_received';
    po['status_label'] = isAllReceived
        ? (nextBalance <= 0.5 ? 'LUNAS' : 'DITERIMA LENGKAP')
        : 'DITERIMA SEBAGIAN';
    po['is_received'] = true;
    po['can_receive'] = !isAllReceived;
    po['is_received_in_full'] = isAllReceived;
    po['is_returnable'] = totalReturnableLeft > 0.0001;
    po['is_fully_returned'] = false;
    po['total_unreceived_qty'] = totalUnreceivedLeft;
    po['total_returnable_qty'] = totalReturnableLeft;
    po['balance_due'] = nextBalance;
    po['delivery_note_number'] = deliveryNoteNumber;
    po['received_at'] = receivedDate ?? DateTime.now().toIso8601String().split('T').first;
    if (notes != null && notes.isNotEmpty) {
      po['receive_notes'] = notes;
    }

    final now = DateTime.now();
    final grnNumber = 'GRN-${now.year}${now.month.toString().padLeft(2, '0')}-${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
    final receiptRecord = {
      'id': now.millisecondsSinceEpoch,
      'purchase_id': (po['id'] as num?)?.toInt() ?? purchaseId,
      'purchase_number': po['number'] ?? po['purchase_number'],
      'grn_number': grnNumber,
      'delivery_note_number': deliveryNoteNumber,
      'received_at': po['received_at'],
      'notes': notes,
      'items': updatedItems,
    };
    final receipts = _readCollectionList(OfflineDatabase._keyLocalPurchaseReceipts);
    receipts.insert(0, receiptRecord);
    await _writeCollectionList(OfflineDatabase._keyLocalPurchaseReceipts, receipts);

    purchases[idx] = po;
    await _writeCollectionList(OfflineDatabase._keyLocalPurchases, purchases);

    if (nextBalance > 0.5) {
      await addLocalPayable(
        purchaseId: (po['id'] as num?)?.toInt() ?? purchaseId,
        supplierId: (po['supplier_id'] as num?)?.toInt() ?? 0,
        supplierName: (po['supplier_name'] ?? 'Pemasok').toString(),
        supplierPhone: po['supplier_phone']?.toString(),
        totalAmount: grandTotal,
        paidAmount: paidTotal,
        dueDate: (po['due_date'] ?? DateTime.now().add(const Duration(days: 14)).toIso8601String().split('T').first).toString(),
        invoiceNumber: (po['supplier_invoice_number'] ?? deliveryNoteNumber ?? po['number'] ?? '').toString(),
        notes: notes ?? po['notes']?.toString(),
      );
    }

    return po;
  }

  List<Map<String, dynamic>> getLocalPurchaseReturns() {
    final list = _readCollectionList(OfflineDatabase._keyLocalPurchaseReturns);
    list.sort((a, b) => (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0));
    return list;
  }

}
