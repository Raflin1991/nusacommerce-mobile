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
    await _prefs.setString(OfflineDatabase._keyCachedBrands, jsonEncode(brands));
  }

  List<Map<String, dynamic>> getCachedBrands() {
    final list = _readPrefsList(OfflineDatabase._keyCachedBrands);
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
    await _prefs.setString(OfflineDatabase._keyCachedUnits, jsonEncode(units));
  }

  List<Map<String, dynamic>> getCachedUnits() {
    final list = _readPrefsList(OfflineDatabase._keyCachedUnits);
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
    await _prefs.setString(OfflineDatabase._keyCachedReturnReasons, jsonEncode(reasons));
  }

  List<Map<String, dynamic>> getCachedReturnReasons() {
    final list = _readPrefsList(OfflineDatabase._keyCachedReturnReasons);
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
    await _prefs.setString(OfflineDatabase._keyCachedExpenseCategories, jsonEncode(categories));
  }

  List<Map<String, dynamic>> getCachedExpenseCategories() {
    final list = _readPrefsList(OfflineDatabase._keyCachedExpenseCategories);
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
    final list = _readPrefsList(OfflineDatabase._keyLocalExpenses);
    list.removeWhere((e) => (e['id'] as num?)?.toInt() == id);
    await _prefs.setString(OfflineDatabase._keyLocalExpenses, jsonEncode(list));
  }

  Future<void> updateLocalExpense(int id, {required String category, required double amount, required String description}) async {
    final list = _readPrefsList(OfflineDatabase._keyLocalExpenses);
    final idx = list.indexWhere((e) => (e['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      final item = Map<String, dynamic>.from(list[idx]);
      item['category_name'] = category;
      item['category'] = {'id': 1, 'name': category};
      item['amount'] = amount;
      item['description'] = description;
      list[idx] = item;
      await _prefs.setString(OfflineDatabase._keyLocalExpenses, jsonEncode(list));
    }
  }

  Future<void> cacheCustomerGroups(List<Map<String, dynamic>> groups) async {
    await _prefs.setString(OfflineDatabase._keyCachedCustomerGroups, jsonEncode(groups));
  }

  List<Map<String, dynamic>> getCachedCustomerGroups() {
    final list = _readPrefsList(OfflineDatabase._keyCachedCustomerGroups);
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
    await _sqlite.replaceAllProducts(products);
    await _prefs.setString(OfflineDatabase._keyCachedProducts, jsonEncode(products));
  }

  List<Map<String, dynamic>> getLocalStockMovements({int? productId, String? type}) {
    var list = _readPrefsList(OfflineDatabase._keyLocalStockMovements);
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
    final list = _readPrefsList(OfflineDatabase._keyLocalStockMovements);
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
    await _prefs.setString(OfflineDatabase._keyLocalStockMovements, jsonEncode(list));
  }

  // ===========================================================================
  // C. MULTI-ITEM PURCHASES (PO) & PURCHASE RETURNS
  // ===========================================================================

  List<Map<String, dynamic>> getLocalPurchases() {
    final list = _readPrefsList(OfflineDatabase._keyLocalPurchases);
    list.sort((a, b) => (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0));
    return list;
  }

  Future<Map<String, dynamic>> addLocalPurchase({
    required int supplierId,
    required String supplierName,
    String? supplierPhone,
    String? invoiceNumber,
    required List<Map<String, dynamic>> items,
    required String paymentMode, // paid | partial | credit
    double paidAmount = 0.0,
    String paymentMethod = 'Tunai',
    String? dueDate,
    String? notes,
  }) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final poNumber = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}-${(id % 10000).toString().padLeft(4, '0')}';

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
      });

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

    double appliedPaid = 0.0;
    if (paymentMode == 'paid') {
      appliedPaid = grandTotal;
    } else if (paymentMode == 'partial') {
      appliedPaid = paidAmount.clamp(0.0, grandTotal);
    }
    final balanceDue = (grandTotal - appliedPaid).clamp(0.0, grandTotal);
    final status = balanceDue <= 0.5 ? 'paid' : (appliedPaid > 0 ? 'partially_paid' : 'received');

    final record = {
      'id': id,
      'number': poNumber,
      'supplier_invoice_number': invoiceNumber,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'purchase_date': now.toIso8601String().split('T').first,
      'due_date': dueDate ?? now.add(const Duration(days: 14)).toIso8601String().split('T').first,
      'status': status,
      'subtotal': grandTotal,
      'grand_total': grandTotal,
      'paid_total': appliedPaid,
      'balance_due': balanceDue,
      'notes': notes,
      'items': normalizedItems,
      'is_local': true,
    };

    final purchases = _readPrefsList(OfflineDatabase._keyLocalPurchases);
    purchases.insert(0, record);
    await _prefs.setString(OfflineDatabase._keyLocalPurchases, jsonEncode(purchases));

    if (balanceDue > 0.5) {
      await addLocalPayable(
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

    if (appliedPaid > 0) {
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

  List<Map<String, dynamic>> getLocalPurchaseReturns() {
    final list = _readPrefsList(OfflineDatabase._keyLocalPurchaseReturns);
    list.sort((a, b) => (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0));
    return list;
  }

  Future<Map<String, dynamic>> addLocalPurchaseReturn({
    required int purchaseId,
    required String purchaseNumber,
    required String supplierName,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final retNo = 'PR-${now.year}${now.month.toString().padLeft(2, '0')}-${(id % 10000).toString().padLeft(4, '0')}';

    double grandTotal = 0.0;
    for (final it in items) {
      final pid = (it['product_id'] as num).toInt();
      final qty = (it['quantity'] as num).toDouble();
      final cost = (it['unit_cost'] as num?)?.toDouble() ?? 0.0;
      grandTotal += qty * cost;

      final products = getCachedProducts();
      final pIdx = products.indexWhere((p) => (p['id'] as num?)?.toInt() == pid);
      if (pIdx >= 0) {
        final p = Map<String, dynamic>.from(products[pIdx]);
        final nextStock = ((p['stock'] as num?)?.toDouble() ?? 0.0) - qty;
        p['stock'] = nextStock;
        p['is_low_stock'] = nextStock <= ((p['reorder_level'] as num?)?.toDouble() ?? 5.0);
        await addOrUpdateLocalProduct(p);
        await recordLocalStockMovement(
          productId: pid,
          productName: (p['name'] ?? 'Produk').toString(),
          sku: (p['sku'] ?? '-').toString(),
          unitCode: (p['unit_code'] ?? 'pcs').toString(),
          type: 'purchase_return',
          quantityDelta: -qty,
          quantityAfter: nextStock,
          unitCost: cost,
          notes: 'Retur Beli $retNo ($purchaseNumber)',
        );
      }
    }

    final record = {
      'id': id,
      'number': retNo,
      'purchase_id': purchaseId,
      'purchase_number': purchaseNumber,
      'supplier_name': supplierName,
      'return_date': now.toIso8601String().split('T').first,
      'grand_total': grandTotal,
      'notes': notes,
      'items': items,
    };
    final returns = _readPrefsList(OfflineDatabase._keyLocalPurchaseReturns);
    returns.insert(0, record);
    await _prefs.setString(OfflineDatabase._keyLocalPurchaseReturns, jsonEncode(returns));
    return record;
  }

  // ===========================================================================
  // D. QUOTATIONS (SURAT PENAWARAN)
  // ===========================================================================

  List<Map<String, dynamic>> getLocalQuotations() {
    final list = _readPrefsList(OfflineDatabase._keyLocalQuotations);
    list.sort((a, b) => (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0));
    return list;
  }

  Future<Map<String, dynamic>> addOrUpdateLocalQuotation(Map<String, dynamic> quotation) async {
    final list = _readPrefsList(OfflineDatabase._keyLocalQuotations);
    final id = (quotation['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...quotation, 'id': id};
    final idx = list.indexWhere((q) => (q['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.insert(0, entry);
    }
    await _prefs.setString(OfflineDatabase._keyLocalQuotations, jsonEncode(list));
    return entry;
  }

  // ===========================================================================
  // E. BUKU KAS TERPADU & CUSTOMER STORE CREDIT LOG
  // ===========================================================================

  Future<void> addLocalCashEntry({
    required String title,
    required String category,
    required String direction, // 'in' | 'out'
    required String channel, // 'cash' | 'non_cash'
    required String methodName,
    required double amount,
    String? notes,
  }) async {
    if (amount <= 0) return;
    final list = _readPrefsList(OfflineDatabase._keyLocalCashLedger);
    list.insert(0, {
      'id': 'loc-${DateTime.now().microsecondsSinceEpoch}',
      'title': title,
      'category': category,
      'direction': direction,
      'channel': channel,
      'method_name': methodName,
      'amount': amount,
      'notes': notes,
      'occurred_at': DateTime.now().toIso8601String(),
    });
    if (list.length > 500) {
      list.removeRange(500, list.length);
    }
    await _prefs.setString(OfflineDatabase._keyLocalCashLedger, jsonEncode(list));
  }

  Map<String, dynamic> computeLocalCashLedger({String channelFilter = 'all'}) {
    final entries = <Map<String, dynamic>>[];
    double cashIn = 0.0, cashOut = 0.0, nonCashIn = 0.0, nonCashOut = 0.0;

    // 1. Sales from history
    for (final s in getLocalSalesHistory()) {
      final st = (s['status'] ?? 'completed').toString().toLowerCase();
      if (st == 'voided') continue;
      final paid = (s['paid_total'] as num?)?.toDouble() ?? 0.0;
      if (paid <= 0) continue;
      final methods = (s['payment_methods'] as List<dynamic>? ?? []);
      final mName = methods.isNotEmpty ? methods.first.toString() : 'Tunai';
      final isCash = mName.toLowerCase().contains('tunai') || mName.toLowerCase().contains('cash');
      if (isCash) {
        cashIn += paid;
      } else {
        nonCashIn += paid;
      }
      if (channelFilter == 'cash' && !isCash) continue;
      if (channelFilter == 'non_cash' && isCash) continue;
      entries.add({
        'id': 'sale-${s['id']}',
        'source_type': 'pos_sale',
        'title': 'Penjualan ${s['number'] ?? ''}',
        'category': 'Penjualan Kasir',
        'direction': 'in',
        'channel': isCash ? 'cash' : 'non_cash',
        'method_name': mName,
        'amount': paid,
        'occurred_at': (s['created_at'] ?? s['sale_datetime'] ?? '').toString(),
      });
    }

    // 2. Expenses
    for (final e in getLocalExpenses()) {
      final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
      if (amt <= 0) continue;
      final mName = (e['payment_method'] ?? 'Tunai').toString();
      final isCash = mName.toLowerCase().contains('tunai') || mName.toLowerCase().contains('cash');
      if (isCash) {
        cashOut += amt;
      } else {
        nonCashOut += amt;
      }
      if (channelFilter == 'cash' && !isCash) continue;
      if (channelFilter == 'non_cash' && isCash) continue;
      entries.add({
        'id': 'exp-${e['id']}',
        'source_type': 'expense',
        'title': (e['description'] ?? 'Biaya Toko').toString(),
        'category': (e['category_name'] ?? 'Biaya Toko').toString(),
        'direction': 'out',
        'channel': isCash ? 'cash' : 'non_cash',
        'method_name': mName,
        'amount': amt,
        'occurred_at': (e['created_at'] ?? e['expense_date'] ?? '').toString(),
      });
    }

    // 3. Explicit Cash Ledger entries (Purchases, Supplier Payments, Manual Cash In/Out)
    for (final le in _readPrefsList(OfflineDatabase._keyLocalCashLedger)) {
      final amt = (le['amount'] as num?)?.toDouble() ?? 0.0;
      final isIn = le['direction'] == 'in';
      final isCash = le['channel'] == 'cash';
      if (isIn) {
        if (isCash) {
          cashIn += amt;
        } else {
          nonCashIn += amt;
        }
      } else {
        if (isCash) {
          cashOut += amt;
        } else {
          nonCashOut += amt;
        }
      }
      if (channelFilter == 'cash' && !isCash) continue;
      if (channelFilter == 'non_cash' && isCash) continue;
      entries.add(le);
    }

    entries.sort((a, b) => (b['occurred_at'] ?? '').toString().compareTo((a['occurred_at'] ?? '').toString()));
    return {
      'summary': {
        'cash_in': cashIn,
        'cash_out': cashOut,
        'cash_balance': cashIn - cashOut,
        'non_cash_in': nonCashIn,
        'non_cash_out': nonCashOut,
        'non_cash_balance': nonCashIn - nonCashOut,
        'total_in': cashIn + nonCashIn,
        'total_out': cashOut + nonCashOut,
        'net_cash_flow': (cashIn + nonCashIn) - (cashOut + nonCashOut),
      },
      'entries': entries.take(150).toList(),
    };
  }

  Future<Map<String, dynamic>> topupLocalCustomerDeposit({
    required int customerId,
    required double amount,
    String? notes,
  }) async {
    final customers = getCachedCustomers();
    final idx = customers.indexWhere((c) => (c['id'] as num?)?.toInt() == customerId);
    double nextBal = amount;
    if (idx >= 0) {
      final next = Map<String, dynamic>.from(customers[idx]);
      nextBal = ((next['store_credit_balance'] as num?)?.toDouble() ?? 0.0) + amount;
      next['store_credit_balance'] = nextBal;
      await addOrUpdateLocalCustomer(next);
    }
    final logs = _readPrefsList(OfflineDatabase._keyLocalCustomerDepositLogs);
    logs.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'customer_id': customerId,
      'type': 'credit_add',
      'amount': amount,
      'balance_after_amount': nextBal,
      'notes': notes ?? 'Top-up Deposit Pelanggan',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _prefs.setString(OfflineDatabase._keyLocalCustomerDepositLogs, jsonEncode(logs));
    return {'customer_id': customerId, 'store_credit_balance': nextBal};
  }

  List<Map<String, dynamic>> getLocalCustomerDepositLogs(int customerId) {
    return _readPrefsList(OfflineDatabase._keyLocalCustomerDepositLogs)
        .where((l) => (l['customer_id'] as num?)?.toInt() == customerId)
        .toList();
  }

  // ===========================================================================
  // F. LOCAL EXTENDED REPORTS (CATEGORIES, BRANDS, HOURLY, VALUATION, DEAD STOCK, AUDIT)
  // ===========================================================================

  Map<String, dynamic> computeLocalExtendedAnalytics({DateTime? startDate, DateTime? endDate}) {
    final products = getCachedProducts();
    final prodById = {for (final p in products) (p['id'] as num?)?.toInt() ?? 0: p};

    final catTotals = <String, Map<String, dynamic>>{};
    final brandTotals = <String, Map<String, dynamic>>{};
    final hourlyTotals = <int, Map<String, dynamic>>{};
    final custTotals = <int, Map<String, dynamic>>{};
    final voidRefundList = <Map<String, dynamic>>[];
    final soldQty30d = <int, double>{};

    for (final s in getLocalSalesHistory()) {
      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      final dt = _parseFlexDateTime(s['created_at'] ?? s['sale_datetime']);

      if (dt != null && DateTime.now().difference(dt).inDays <= 30 && status == 'completed') {
        for (final it in (s['items'] as List<dynamic>? ?? [])) {
          final pid = (it['product_id'] as num?)?.toInt() ?? 0;
          soldQty30d[pid] = (soldQty30d[pid] ?? 0.0) + ((it['quantity'] as num?)?.toDouble() ?? 1.0);
        }
      }

      if (dt != null) {
        if (startDate != null && dt.isBefore(startDate)) continue;
        if (endDate != null && dt.isAfter(endDate)) continue;
      }

      if (status == 'voided' || status == 'refunded' || status == 'partially_refunded') {
        voidRefundList.add({
          'id': s['id'],
          'number': s['number'] ?? '-',
          'status': status,
          'grand_total': (s['grand_total'] as num?)?.toDouble() ?? 0.0,
          'reason': s['void_reason'] ?? s['refund_reason'] ?? '-',
          'cashier_name': s['cashier_name'] ?? 'Kasir',
          'sale_datetime': (s['created_at'] ?? s['sale_datetime'] ?? '').toString(),
        });
        continue;
      }

      final grand = (s['grand_total'] as num?)?.toDouble() ?? 0.0;
      if (dt != null) {
        hourlyTotals[dt.hour] ??= {'hour_num': dt.hour, 'tx_count': 0, 'revenue': 0.0};
        hourlyTotals[dt.hour]!['tx_count'] = (hourlyTotals[dt.hour]!['tx_count'] as int) + 1;
        hourlyTotals[dt.hour]!['revenue'] = (hourlyTotals[dt.hour]!['revenue'] as double) + grand;
      }

      final cust = s['customer'] is Map ? Map<String, dynamic>.from(s['customer'] as Map) : null;
      final cid = (cust?['id'] as num?)?.toInt() ?? 0;
      if (cid > 0) {
        custTotals[cid] ??= {
          'id': cid,
          'name': cust?['name'] ?? 'Pelanggan',
          'phone': cust?['phone'] ?? '-',
          'tx_count': 0,
          'total_spent': 0.0,
        };
        custTotals[cid]!['tx_count'] = (custTotals[cid]!['tx_count'] as int) + 1;
        custTotals[cid]!['total_spent'] = (custTotals[cid]!['total_spent'] as double) + grand;
      }

      for (final rawItem in (s['items'] as List<dynamic>? ?? [])) {
        final it = Map<String, dynamic>.from(rawItem as Map);
        final pid = (it['product_id'] as num?)?.toInt() ?? 0;
        final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
        final rev = (it['line_total'] as num?)?.toDouble() ??
            (((it['unit_price'] as num?)?.toDouble() ?? 0.0) * qty);
        final p = prodById[pid];
        final catName = (p?['category'] is Map ? p!['category']['name'] : p?['category_name'] ?? 'Umum').toString();
        final brandName = (p?['brand'] is Map ? p!['brand']['name'] : p?['brand_name'] ?? 'Generic / Toko').toString();

        catTotals[catName] ??= {'name': catName, 'qty': 0.0, 'revenue': 0.0};
        catTotals[catName]!['qty'] = (catTotals[catName]!['qty'] as double) + qty;
        catTotals[catName]!['revenue'] = (catTotals[catName]!['revenue'] as double) + rev;

        brandTotals[brandName] ??= {'name': brandName, 'qty': 0.0, 'revenue': 0.0};
        brandTotals[brandName]!['qty'] = (brandTotals[brandName]!['qty'] as double) + qty;
        brandTotals[brandName]!['revenue'] = (brandTotals[brandName]!['revenue'] as double) + rev;
      }
    }

    double totalCostVal = 0.0, totalRetailVal = 0.0;
    final valItems = <Map<String, dynamic>>[];
    final deadStock = <Map<String, dynamic>>[];
    final fastStock = <Map<String, dynamic>>[];

    for (final p in products) {
      final pid = (p['id'] as num?)?.toInt() ?? 0;
      final qty = (p['stock'] as num?)?.toDouble() ?? 0.0;
      final cost = (p['cost_price'] as num?)?.toDouble() ?? 0.0;
      final sell = (p['selling_price'] as num?)?.toDouble() ?? 0.0;
      if (qty > 0) {
        final cv = qty * cost;
        final rv = qty * sell;
        totalCostVal += cv;
        totalRetailVal += rv;
        valItems.add({
          'product_id': pid,
          'name': p['name'],
          'sku': p['sku'],
          'quantity': qty,
          'cost_value': cv,
          'retail_value': rv,
        });
        if (!soldQty30d.containsKey(pid)) {
          deadStock.add({'product_id': pid, 'name': p['name'], 'sku': p['sku'], 'quantity': qty, 'cost_value': cv});
        }
      }
      if ((soldQty30d[pid] ?? 0) > 0) {
        fastStock.add({'product_id': pid, 'name': p['name'], 'sku': p['sku'], 'sold_30d': soldQty30d[pid]});
      }
    }

    valItems.sort((a, b) => (b['cost_value'] as double).compareTo(a['cost_value'] as double));
    fastStock.sort((a, b) => (b['sold_30d'] as double).compareTo(a['sold_30d'] as double));

    final expByCat = <String, Map<String, dynamic>>{};
    for (final e in getLocalExpenses()) {
      final cat = (e['category_name'] ?? 'Operasional').toString();
      final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
      expByCat[cat] ??= {'name': cat, 'entries_count': 0, 'total_amount': 0.0};
      expByCat[cat]!['entries_count'] = (expByCat[cat]!['entries_count'] as int) + 1;
      expByCat[cat]!['total_amount'] = (expByCat[cat]!['total_amount'] as double) + amt;
    }

    return {
      'by_category': catTotals.values.toList()..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double)),
      'by_brand': brandTotals.values.toList()..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double)),
      'hourly': hourlyTotals.values.toList()..sort((a, b) => (a['hour_num'] as int).compareTo(b['hour_num'] as int)),
      'void_refund_list': voidRefundList,
      'valuation': {
        'total_cost_value': totalCostVal,
        'total_retail_value': totalRetailVal,
        'potential_profit': totalRetailVal - totalCostVal,
        'skus_in_stock': valItems.length,
        'top_items': valItems.take(15).toList(),
      },
      'fast_stock': fastStock.take(10).toList(),
      'dead_stock': deadStock.take(15).toList(),
      'top_customers': custTotals.values.toList()..sort((a, b) => (b['total_spent'] as double).compareTo(a['total_spent'] as double)),
      'expenses_by_category': expByCat.values.toList()..sort((a, b) => (b['total_amount'] as double).compareTo(a['total_amount'] as double)),
      'shifts_by_cashier': getLocalShiftsHistory(),
    };
  }
}
