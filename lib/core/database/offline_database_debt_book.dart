part of 'offline_database.dart';

extension OfflineDatabaseDebtBookExt on OfflineDatabase {
  // ===========================================================================
  // 9. LOCAL DEBT BOOK (PIUTANG, HUTANG SUPPLIER & PENGELUARAN)
  // ===========================================================================
  List<Map<String, dynamic>> getLocalReceivables() {
    final sales = getLocalSalesHistory();
    final List<Map<String, dynamic>> receivables = [];
    for (final s in sales) {
      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided') continue;
      final balance = (s['balance_due'] as num?)?.toDouble() ?? 0.0;
      if (balance <= 0.5) continue;

      final customer = s['customer'] is Map ? Map<String, dynamic>.from(s['customer'] as Map) : <String, dynamic>{};
      final custName = (customer['name'] ?? s['customer_name'] ?? 'Pelanggan Umum').toString();
      final custPhone = (customer['phone'] ?? s['customer_phone'] ?? '').toString();
      int ageDays = 0;
      final dueStr = s['due_date']?.toString();
      if (dueStr != null && dueStr.trim().isNotEmpty) {
        final parsedDue = DateTime.tryParse(dueStr.trim());
        if (parsedDue != null) {
          ageDays = DateTime.now().difference(parsedDue).inDays;
        }
      }
      receivables.add({
        'id': s['id'],
        'sale_id': s['id'],
        'invoice_number': s['number'] ?? '#INV',
        'number': s['number'] ?? '#INV',
        'customer_id': customer['id'],
        'customer_name': custName,
        'customer_phone': custPhone,
        'customer': {
          'id': customer['id'],
          'name': custName,
          'phone': custPhone,
        },
        'age_days': ageDays,
        'total_amount': (s['grand_total'] as num?)?.toDouble() ?? 0.0,
        'paid_amount': (s['paid_total'] as num?)?.toDouble() ?? 0.0,
        'balance_due': balance,
        'due_date': s['due_date'],
        'created_at': s['sale_datetime'] ?? s['created_at'] ?? '',
        'is_local': true,
      });
    }
    return receivables;
  }

  Future<Map<String, dynamic>?> payLocalReceivable({
    required int saleId,
    required double amount,
    String paymentMethod = 'Tunai',
    int paymentMethodId = 1,
    String? saleLocalUuid,
    String? invoiceNumber,
    String? customerName,
    int? customerId,
    String? reference,
    String? notes,
    bool enqueueForCloudSync = true,
    String? idempotencyKey,
  }) async {
    if (amount <= 0) return null;
    final history = getLocalSalesHistory();
    final idx = history.indexWhere((s) => (s['id'] as num?)?.toInt() == saleId);

    Map<String, dynamic>? updatedSale;
    String resolvedInvoiceNo = invoiceNumber ?? 'BON-$saleId';
    String? resolvedSaleUuid = saleLocalUuid;
    String resolvedCustomerName = customerName ?? 'Pelanggan Umum';
    int? resolvedCustId = customerId;
    double applied = amount;
    double nextBalance = 0.0;
    String paymentStatus = 'paid';

    if (idx >= 0) {
      final sale = Map<String, dynamic>.from(history[idx]);
      final currentBalance = (sale['balance_due'] as num?)?.toDouble() ?? 0.0;
      final currentPaid = (sale['paid_total'] as num?)?.toDouble() ?? 0.0;
      applied = currentBalance > 0 && amount > currentBalance ? currentBalance : amount;
      nextBalance = (currentBalance - applied).clamp(0.0, double.infinity);

      sale['paid_total'] = currentPaid + applied;
      sale['balance_due'] = nextBalance;
      paymentStatus = nextBalance <= 0.5 ? 'paid' : 'partial';
      sale['payment_status'] = paymentStatus;

      final payments = (sale['payments'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      payments.add({
        'payment_method_id': paymentMethodId,
        'payment_method_name': paymentMethod,
        'method_name': paymentMethod,
        'amount': applied,
        'notes': notes,
        'paid_at': DateTime.now().toIso8601String(),
      });
      sale['payments'] = payments;

      history[idx] = sale;
      updatedSale = sale;
      resolvedInvoiceNo = (sale['number'] ?? resolvedInvoiceNo).toString();
      resolvedSaleUuid ??= sale['local_uuid']?.toString();
      final customerMap =
          sale['customer'] is Map ? Map<String, dynamic>.from(sale['customer'] as Map) : null;
      resolvedCustId ??= (customerMap?['id'] as num?)?.toInt();
      if (customerMap?['name'] != null) {
        resolvedCustomerName = customerMap!['name'].toString();
      }
    } else {
      // Also update cached Cloud receivables when settling a Cloud invoice while offline!
      final cachedRecs = getCachedCloudReceivables();
      final rIdx = cachedRecs.indexWhere(
        (r) =>
            (r['sale_id'] as num?)?.toInt() == saleId ||
            (r['id'] as num?)?.toInt() == saleId,
      );
      if (rIdx >= 0) {
        final rec = Map<String, dynamic>.from(cachedRecs[rIdx]);
        final currentBalance = (rec['balance_due'] as num?)?.toDouble() ?? amount;
        final currentPaid = (rec['paid_total'] as num?)?.toDouble() ?? 0.0;
        applied = currentBalance > 0 && amount > currentBalance ? currentBalance : amount;
        nextBalance = (currentBalance - applied).clamp(0.0, double.infinity);
        rec['paid_total'] = currentPaid + applied;
        rec['balance_due'] = nextBalance;
        paymentStatus = nextBalance <= 0.5 ? 'paid' : 'partial';
        cachedRecs[rIdx] = rec;
        await cacheCloudReceivables(cachedRecs);
        resolvedInvoiceNo = (rec['number'] ?? rec['invoice_number'] ?? resolvedInvoiceNo).toString();
        final cMap = rec['customer'] is Map ? Map<String, dynamic>.from(rec['customer'] as Map) : null;
        resolvedCustId ??= (cMap?['id'] as num?)?.toInt() ?? (rec['customer_id'] as num?)?.toInt();
        resolvedCustomerName = (cMap?['name'] ?? rec['customer_name'] ?? resolvedCustomerName).toString();
      } else if (!enqueueForCloudSync) {
        return null;
      }
    }

    // Prepare customer balance update
    Map<String, dynamic>? updatedCust;
    if (resolvedCustId != null && resolvedCustId != 0) {
      final customers = getCachedCustomers();
      final cIdx = customers.indexWhere((c) => (c['id'] as num?)?.toInt() == resolvedCustId);
      if (cIdx >= 0) {
        final nextCust = Map<String, dynamic>.from(customers[cIdx]);
        final prevDebt = (nextCust['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        nextCust['outstanding_balance'] = (prevDebt - applied).clamp(0.0, double.infinity);
        updatedCust = nextCust;
      }
    }

    // Prepare cash-in entry on active local shift when paid in Cash/Tunai
    final methodLower = paymentMethod.toLowerCase();
    final isCashMethod = methodLower.contains('tunai') || methodLower.contains('cash');
    final nowIso = DateTime.now().toIso8601String();
    final paymentUuid = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : _uuid.v4();

    Map<String, dynamic>? pendingPaymentRecord;
    if (enqueueForCloudSync) {
      pendingPaymentRecord = <String, dynamic>{
        'id': paymentUuid,
        'local_uuid': paymentUuid,
        'sale_id': saleId,
        if (resolvedSaleUuid != null && resolvedSaleUuid.isNotEmpty)
          'sale_local_uuid': resolvedSaleUuid,
        'invoice_number': resolvedInvoiceNo,
        'customer_name': resolvedCustomerName,
        'payment_method_id': paymentMethodId > 0 ? paymentMethodId : 1,
        'payment_method_name': paymentMethod,
        'amount': applied,
        'reference': (reference != null && reference.trim().isNotEmpty)
            ? reference.trim()
            : paymentUuid,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'created_at': nowIso,
        'sync_status': 'pending',
        'retry_count': 0,
        'is_synced': 0,
      };
    }

    Map<String, dynamic>? cashLedgerEntry;
    if (applied > 0) {
      cashLedgerEntry = <String, dynamic>{
        'id': 'rec-$paymentUuid',
        'title': 'Pelunasan Kasbon $resolvedInvoiceNo ($resolvedCustomerName)',
        'category': 'Pelunasan Piutang',
        'direction': 'in',
        'channel': isCashMethod ? 'cash' : 'non_cash',
        'method_name': paymentMethod,
        'amount': applied,
        'notes': notes,
        'occurred_at': nowIso,
      };
    }

    Map<String, dynamic>? updatedShift;
    List<Map<String, dynamic>>? updatedShiftsList;
    if (isCashMethod) {
      final shifts = getLocalShiftsHistory();
      final sIdx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
      if (sIdx >= 0) {
        final shift = Map<String, dynamic>.from(shifts[sIdx]);
        final entries = (shift['entries'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        entries.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch,
          'type': 'pay_in',
          'amount': applied,
          'reason': 'Pelunasan Kasbon $resolvedInvoiceNo',
          'created_at': nowIso,
        });
        shift['entries'] = entries;
        shift['cash_in'] = ((shift['cash_in'] as num?)?.toDouble() ?? 0.0) + applied;
        updatedShift = _enrichShiftTotals(shift);
        shifts[sIdx] = updatedShift;
        updatedShiftsList = shifts;
      }
    }

    // ACID SQLite transaction wrapping pending payment + sale history + customer + shift + cash ledger
    await _sqlite.commitReceivablePaymentAtomic(
      pendingPayment: pendingPaymentRecord,
      updatedSaleHistory: updatedSale,
      updatedCustomer: updatedCust,
      updatedShift: updatedShift,
      cashLedgerEntry: cashLedgerEntry,
    );

    // Update SharedPreferences & in-memory mirrors after SQLite commit succeeds
    if (updatedSale != null) {
      await _writeCollectionList(OfflineDatabase._keyCompletedSalesHistory, history);
    }
    if (updatedCust != null) {
      final customers = getCachedCustomers();
      final cIdx = customers.indexWhere((c) => c['id'] == updatedCust!['id']);
      if (cIdx >= 0) {
        customers[cIdx] = updatedCust;
      } else {
        customers.insert(0, updatedCust);
      }
      _memCustomers = customers;
      await _writeDaoMirrorFallback(OfflineDatabase._keyCachedCustomers, customers);
    }
    if (updatedShiftsList != null) {
      await _saveLocalShifts(updatedShiftsList);
    }
    if (pendingPaymentRecord != null) {
      final queue = getPendingReceivablePayments();
      queue.removeWhere((e) => e['id']?.toString() == paymentUuid);
      queue.add(pendingPaymentRecord);
      _memPendingReceivablePayments = queue;
      await _writeDaoMirrorFallback(OfflineDatabase._keyPendingReceivablePayments, queue);
    }

    return {
      'id': paymentUuid,
      'local_uuid': paymentUuid,
      'sale_id': saleId,
      'invoice_number': resolvedInvoiceNo,
      'amount_paid': applied,
      'remaining_balance': nextBalance,
      'payment_status': paymentStatus,
      'queued_for_sync': pendingPaymentRecord != null,
    };
  }

  List<Map<String, dynamic>> getLocalPayables() {
    final list = _readCollectionList(OfflineDatabase._keyLocalPayables);
    final now = DateTime.now();
    final enriched = list.map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final balance = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      final invNo = (item['number'] ?? item['invoice_number'] ?? '#PO').toString();
      final supName = (item['supplier_name'] ?? (item['supplier'] is Map ? item['supplier']['name'] : null) ?? 'Supplier').toString();
      final supPhone = (item['supplier_phone'] ?? (item['supplier'] is Map ? item['supplier']['phone'] : null) ?? '').toString();
      bool isOverdue = false;
      final dueStr = item['due_date']?.toString();
      if (balance > 0.5 && dueStr != null && dueStr.trim().isNotEmpty) {
        final parsedDue = DateTime.tryParse(dueStr.trim());
        if (parsedDue != null && now.isAfter(parsedDue.add(const Duration(days: 1)))) {
          isOverdue = true;
        }
      }
      item['purchase_id'] = item['purchase_id'] ?? item['id'];
      item['invoice_number'] = item['invoice_number'] ?? invNo;
      item['number'] = invNo;
      item['supplier'] = item['supplier'] is Map
          ? Map<String, dynamic>.from(item['supplier'] as Map)
          : {
              'id': item['supplier_id'],
              'name': supName,
              'phone': supPhone,
            };
      item['is_overdue'] = isOverdue;
      return item;
    }).toList();
    enriched.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    return enriched;
  }

  Future<Map<String, dynamic>> addLocalPayable({
    required String supplierName,
    String? supplierPhone,
    int? supplierId,
    int? purchaseId,
    required double totalAmount,
    double paidAmount = 0.0,
    String? dueDate,
    String? invoiceNumber,
    String? notes,
  }) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final balanceDue = (totalAmount - paidAmount).clamp(0.0, double.infinity);
    final status = balanceDue <= 0.5 ? 'paid' : (paidAmount > 0 ? 'partial' : 'unpaid');
    final cleanSupplierName = supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim();
    final invNo = (invoiceNumber ?? '').trim().isNotEmpty
        ? invoiceNumber!.trim()
        : 'PO-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(id % 1000).toString().padLeft(3, '0')}';
    bool isOverdue = false;
    if (balanceDue > 0.5 && dueDate != null && dueDate.trim().isNotEmpty) {
      final parsedDue = DateTime.tryParse(dueDate.trim());
      if (parsedDue != null && now.isAfter(parsedDue.add(const Duration(days: 1)))) {
        isOverdue = true;
      }
    }
    final record = <String, dynamic>{
      'id': id,
      'purchase_id': purchaseId ?? id,
      'invoice_number': invNo,
      'number': invNo,
      'supplier_id': supplierId,
      'supplier_name': cleanSupplierName,
      'supplier_phone': supplierPhone ?? '',
      'supplier': {
        'id': supplierId,
        'name': cleanSupplierName,
        'phone': supplierPhone ?? '',
      },
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'balance_due': balanceDue,
      'status': status,
      'due_date': dueDate,
      'is_overdue': isOverdue,
      'created_at': now.toIso8601String(),
      'notes': notes,
      'is_local': true,
    };

    final list = _readCollectionList(OfflineDatabase._keyLocalPayables);
    list.insert(0, record);
    await _writeCollectionList(OfflineDatabase._keyLocalPayables, list);
    await _sqlite.upsertLocalPayable(record);
    return record;
  }

  Future<Map<String, dynamic>?> payLocalPayable({
    required int payableId,
    required double amount,
    String paymentMethod = 'Tunai',
    String? invoiceNumber,
  }) async {
    if (amount <= 0) return null;
    final list = _readCollectionList(OfflineDatabase._keyLocalPayables);
    final idx = list.indexWhere(
      (p) =>
          (p['purchase_id'] as num?)?.toInt() == payableId ||
          (p['id'] as num?)?.toInt() == payableId ||
          (invoiceNumber != null &&
              invoiceNumber.trim().isNotEmpty &&
              (p['number'] == invoiceNumber || p['invoice_number'] == invoiceNumber)),
    );

    if (idx >= 0) {
      final item = Map<String, dynamic>.from(list[idx]);
      final currentBalance = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      final currentPaid = (item['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final applied = amount > currentBalance ? currentBalance : amount;
      final nextBalance = (currentBalance - applied).clamp(0.0, double.infinity);

      item['paid_amount'] = currentPaid + applied;
      item['balance_due'] = nextBalance;
      item['status'] = nextBalance <= 0.5 ? 'paid' : 'partial';
      if (nextBalance <= 0.5) {
        item['is_overdue'] = false;
      }
      final payLogs = (item['payments'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      payLogs.insert(0, {
        'id': DateTime.now().millisecondsSinceEpoch,
        'amount': applied,
        'method_name': paymentMethod,
        'payment_date': DateTime.now().toIso8601String().split('T').first,
        'cashier': 'Pemilik',
      });
      item['payments'] = payLogs;

      list[idx] = item;
      await _writeCollectionList(OfflineDatabase._keyLocalPayables, list);
      await _sqlite.upsertLocalPayable(item);

      // Also sync matching record in OfflineDatabase._keyLocalPurchases
      final purchases = _readCollectionList(OfflineDatabase._keyLocalPurchases);
      final pIdx = purchases.indexWhere(
        (p) =>
            (p['id'] as num?)?.toInt() == payableId ||
            (p['number'] != null && (p['number'] == item['number'] || p['number'] == invoiceNumber)),
      );
      if (pIdx >= 0) {
        final po = Map<String, dynamic>.from(purchases[pIdx]);
        final curPaid = (po['paid_total'] as num?)?.toDouble() ?? 0.0;
        final curGrand = (po['grand_total'] as num?)?.toDouble() ?? 0.0;
        final newPaid = curPaid + applied;
        final newBalance = (curGrand - newPaid).clamp(0.0, double.infinity);
        po['paid_total'] = newPaid;
        po['balance_due'] = newBalance;
        po['status'] = newBalance <= 0.5 ? 'paid' : 'partially_paid';
        purchases[pIdx] = po;
        await _writeCollectionList(OfflineDatabase._keyLocalPurchases, purchases);
      }

      await addLocalCashEntry(
        title: 'Bayar Hutang Supplier ${item['supplier_name'] ?? ''} (${item['number'] ?? item['invoice_number'] ?? ''})',
        category: 'Pembelian & Hutang',
        direction: 'out',
        channel: paymentMethod.toLowerCase().contains('tunai') || paymentMethod.toLowerCase().contains('cash')
            ? 'cash'
            : 'non_cash',
        methodName: paymentMethod,
        amount: applied,
      );

      final methodLower = paymentMethod.toLowerCase();
      if ((methodLower.contains('tunai') || methodLower.contains('cash')) && getCurrentLocalShift() != null) {
        await addLocalShiftCashEntry(
          type: 'pay_out',
          amount: applied,
          reason: 'Bayar Hutang Supplier ${item['number'] ?? item['invoice_number'] ?? ''}',
        );
      }
      return item;
    } else {
      // Direct update on OfflineDatabase._keyLocalPurchases if not present in payables list
      final purchases = _readCollectionList(OfflineDatabase._keyLocalPurchases);
      final pIdx = purchases.indexWhere(
        (p) =>
            (p['id'] as num?)?.toInt() == payableId ||
            (invoiceNumber != null &&
                invoiceNumber.trim().isNotEmpty &&
                (p['number'] == invoiceNumber || p['supplier_invoice_number'] == invoiceNumber)),
      );
      if (pIdx >= 0) {
        final po = Map<String, dynamic>.from(purchases[pIdx]);
        final curBalance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
        final curPaid = (po['paid_total'] as num?)?.toDouble() ?? 0.0;
        final applied = amount > curBalance ? curBalance : amount;
        final nextBalance = (curBalance - applied).clamp(0.0, double.infinity);
        po['paid_total'] = curPaid + applied;
        po['balance_due'] = nextBalance;
        po['status'] = nextBalance <= 0.5 ? 'paid' : 'partially_paid';
        purchases[pIdx] = po;
        await _writeCollectionList(OfflineDatabase._keyLocalPurchases, purchases);

        await addLocalCashEntry(
          title: 'Bayar Hutang PO ${po['number'] ?? ''} (${po['supplier_name'] ?? ''})',
          category: 'Pembelian & Hutang',
          direction: 'out',
          channel: paymentMethod.toLowerCase().contains('tunai') || paymentMethod.toLowerCase().contains('cash')
              ? 'cash'
              : 'non_cash',
          methodName: paymentMethod,
          amount: applied,
        );

        final methodLower = paymentMethod.toLowerCase();
        if ((methodLower.contains('tunai') || methodLower.contains('cash')) && getCurrentLocalShift() != null) {
          await addLocalShiftCashEntry(
            type: 'pay_out',
            amount: applied,
            reason: 'Bayar Hutang PO ${po['number'] ?? ''}',
          );
        }
        return po;
      }
      return null;
    }
  }

  List<Map<String, dynamic>> getLocalExpenses() {
    final list = _readCollectionList(OfflineDatabase._keyLocalExpenses).map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final rawCat = item['category'];
      final catName = (item['category_name'] ?? (rawCat is Map ? rawCat['name'] : rawCat) ?? 'Operasional Toko').toString();
      item['category_name'] = catName;
      item['category'] = rawCat is Map ? Map<String, dynamic>.from(rawCat) : {'id': 1, 'name': catName};
      return item;
    }).toList();
    list.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    return list;
  }

  Future<Map<String, dynamic>> addLocalExpense({
    required String category,
    int? categoryId,
    required double amount,
    required String description,
    String paymentMethod = 'Tunai',
    int? paymentMethodId,
    String? recordedBy,
    String? localUuid,
    bool isSynced = false,
  }) async {
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final catName = category.trim().isEmpty ? 'Operasional Toko' : category.trim();
    final resolvedUuid =
        (localUuid != null && localUuid.trim().isNotEmpty) ? localUuid.trim() : _uuid.v4();
    final existingExpenses = _readCollectionList(OfflineDatabase._keyLocalExpenses);
    int nextId = now.microsecondsSinceEpoch;
    final usedIds = existingExpenses.map((e) => (e['id'] as num?)?.toInt() ?? 0).toSet();
    while (usedIds.contains(nextId)) {
      nextId++;
    }
    final record = <String, dynamic>{
      'id': nextId,
      'local_uuid': resolvedUuid,
      if (categoryId != null && categoryId > 0) 'category_id': categoryId,
      'category_name': catName,
      'category': {'id': categoryId ?? 1, 'name': catName},
      'amount': amount,
      'description': description.trim(),
      if (paymentMethodId != null && paymentMethodId > 0) 'payment_method_id': paymentMethodId,
      'payment_method': paymentMethod,
      'recorded_by': recordedBy ?? 'Pemilik',
      'expense_date': nowIso.split('T').first,
      'created_at': nowIso,
      'is_local': true,
      'is_synced': isSynced ? 1 : 0,
      'sync_status': isSynced ? 'synced' : 'pending',
      'retry_count': 0,
    };

    // Prepare shift cash-out update atomically if paid in Cash/Tunai
    final methodLower = paymentMethod.toLowerCase();
    Map<String, dynamic>? updatedShift;
    List<Map<String, dynamic>>? updatedShiftsList;
    if (methodLower.contains('tunai') || methodLower.contains('cash')) {
      final shifts = getLocalShiftsHistory();
      final sIdx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
      if (sIdx >= 0) {
        final shift = Map<String, dynamic>.from(shifts[sIdx]);
        final entries = (shift['entries'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        entries.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch,
          'type': 'pay_out',
          'amount': amount,
          'reason': 'Biaya $catName: ${record['description']}',
          'created_at': nowIso,
        });
        shift['entries'] = entries;
        shift['cash_out'] = ((shift['cash_out'] as num?)?.toDouble() ?? 0.0) + amount;
        updatedShift = _enrichShiftTotals(shift);
        shifts[sIdx] = updatedShift;
        updatedShiftsList = shifts;
      }
    }

    // ACID SQLite transaction for expense + shift cash-out
    await _sqlite.commitExpenseAtomic(
      expense: record,
      updatedShift: updatedShift,
    );

    final list = _readCollectionList(OfflineDatabase._keyLocalExpenses);
    list.insert(0, record);
    await _writeCollectionList(OfflineDatabase._keyLocalExpenses, list);
    if (updatedShiftsList != null) {
      await _saveLocalShifts(updatedShiftsList);
    }
    return record;
  }

}
