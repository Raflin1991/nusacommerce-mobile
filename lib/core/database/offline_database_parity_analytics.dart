part of 'offline_database.dart';

extension OfflineDatabaseParityAnalyticsExt on OfflineDatabase {
  Future<Map<String, dynamic>> addLocalPurchaseReturn({
    required int purchaseId,
    required String purchaseNumber,
    required String supplierName,
    required List<Map<String, dynamic>> items,
    String? notes,
  }) async {
    final purchases = _readCollectionList(OfflineDatabase._keyLocalPurchases);
    final pIdx = purchases.indexWhere(
      (p) =>
          (p['id'] as num?)?.toInt() == purchaseId ||
          (p['number'] != null && p['number'] == purchaseNumber),
    );

    if (pIdx >= 0) {
      final po = purchases[pIdx];
      final poStatus = (po['status'] ?? '').toString().toLowerCase();
      if (poStatus == 'draft' || poStatus == 'submitted' || poStatus == 'approved') {
        throw StateError('PO status masih draft ($poStatus). Barang belum diterima dan tidak dapat diretur!');
      }
      if (po['is_fully_returned'] == true || po['is_returnable'] == false) {
        throw StateError('Semua barang dalam PO ini telah habis diretur!');
      }

      final poItems = (po['items'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (final it in items) {
        final pid = (it['product_id'] as num).toInt();
        final qty = (it['quantity'] as num).toDouble();
        final match = poItems.firstWhere(
          (m) => (m['product_id'] as num?)?.toInt() == pid,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          final origQty = (match['quantity'] as num?)?.toDouble() ?? 0.0;
          final prevReturned = (match['returned_quantity'] as num?)?.toDouble() ?? 0.0;
          final maxReturnable = (origQty - prevReturned).clamp(0.0, double.infinity);
          if (qty > maxReturnable + 0.0001) {
            throw ArgumentError('Kuantitas retur ($qty) melebihi batas yang dapat diretur ($maxReturnable) untuk produk ID $pid');
          }
        }
      }
    }

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
    final returns = _readCollectionList(OfflineDatabase._keyLocalPurchaseReturns);
    returns.insert(0, record);
    await _writeCollectionList(OfflineDatabase._keyLocalPurchaseReturns, returns);

    // Update cumulative returned quantities in original purchase to prevent over-returns
    if (pIdx >= 0) {
      final po = Map<String, dynamic>.from(purchases[pIdx]);
      final poItems = (po['items'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      double totalReturnableLeft = 0.0;
      for (final poItem in poItems) {
        final pid = (poItem['product_id'] as num?)?.toInt();
        final match = items.firstWhere(
          (retIt) => (retIt['product_id'] as num?)?.toInt() == pid,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          final retQty = (match['quantity'] as num?)?.toDouble() ?? 0.0;
          final prevReturned = (poItem['returned_quantity'] as num?)?.toDouble() ?? 0.0;
          poItem['returned_quantity'] = prevReturned + retQty;
        }
        final origQty = (poItem['quantity'] as num?)?.toDouble() ?? 0.0;
        final curReturned = (poItem['returned_quantity'] as num?)?.toDouble() ?? 0.0;
        final rem = (origQty - curReturned).clamp(0.0, double.infinity);
        poItem['returnable_quantity'] = rem;
        totalReturnableLeft += rem;
      }
      po['items'] = poItems;
      po['total_returnable_qty'] = totalReturnableLeft;
      po['is_returnable'] = totalReturnableLeft > 0.0001;
      po['is_fully_returned'] = totalReturnableLeft <= 0.0001;
      if (po['is_fully_returned'] == true) {
        po['status_label'] = 'SEMUA BARANG DIRETUR';
      }

      final curBalance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
      if (curBalance > 0) {
        po['balance_due'] = (curBalance - grandTotal).clamp(0.0, double.infinity);
      }

      purchases[pIdx] = po;
      await _writeCollectionList(OfflineDatabase._keyLocalPurchases, purchases);
    }

    return record;
  }

  // ===========================================================================
  // D. QUOTATIONS (SURAT PENAWARAN)
  // ===========================================================================

  List<Map<String, dynamic>> getLocalQuotations() {
    final list = _readCollectionList(OfflineDatabase._keyLocalQuotations);
    list.sort((a, b) => (b['id'] as num? ?? 0).compareTo(a['id'] as num? ?? 0));
    return list;
  }

  Future<Map<String, dynamic>> addOrUpdateLocalQuotation(Map<String, dynamic> quotation) async {
    final list = _readCollectionList(OfflineDatabase._keyLocalQuotations);
    final id = (quotation['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final entry = <String, dynamic>{...quotation, 'id': id};
    final idx = list.indexWhere((q) => (q['id'] as num?)?.toInt() == id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.insert(0, entry);
    }
    await _writeCollectionList(OfflineDatabase._keyLocalQuotations, list);
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
    final list = _readCollectionList(OfflineDatabase._keyLocalCashLedger);
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
    await salesQueueDao.insertCashLedgerEntry(list.first);
    await _writeCollectionList(OfflineDatabase._keyLocalCashLedger, list);
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
    for (final le in _readCollectionList(OfflineDatabase._keyLocalCashLedger)) {
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
    final logs = _readCollectionList(OfflineDatabase._keyLocalCustomerDepositLogs);
    logs.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'customer_id': customerId,
      'type': 'credit_add',
      'amount': amount,
      'balance_after_amount': nextBal,
      'notes': notes ?? 'Top-up Deposit Pelanggan',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _writeCollectionList(OfflineDatabase._keyLocalCustomerDepositLogs, logs);
    return {'customer_id': customerId, 'store_credit_balance': nextBal};
  }

  List<Map<String, dynamic>> getLocalCustomerDepositLogs(int customerId) {
    return _readCollectionList(OfflineDatabase._keyLocalCustomerDepositLogs)
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
