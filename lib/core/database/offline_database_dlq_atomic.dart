part of 'offline_database.dart';

extension OfflineDatabaseDlqAtomicExt on OfflineDatabase {
  // ===========================================================================
  // E. UNIFIED DEAD-LETTER QUEUE / CONFLICT RESOLVER (HARDENING #4)
  // ===========================================================================
  List<Map<String, dynamic>> getDeadLetterItems() {
    if (_memDeadLetterQueue != null) {
      return _memDeadLetterQueue!
          .where((e) => (e['status'] ?? 'quarantined') == 'quarantined')
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final list = _readPrefsList(OfflineDatabase._keyDeadLetterQueue);
    _memDeadLetterQueue = list;
    return list
        .where((e) => (e['status'] ?? 'quarantined') == 'quarantined')
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> enqueueDeadLetterItem({
    required String id,
    required String entityType,
    required String endpoint,
    String method = 'POST',
    required String idempotencyKey,
    String? referenceLabel,
    required Map<String, dynamic> payload,
    int? httpStatus,
    String? errorCode,
    required String errorMessage,
    int retryCount = 1,
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final record = <String, dynamic>{
      'id': id,
      'entity_type': entityType,
      'endpoint': endpoint,
      'method': method.toUpperCase(),
      'idempotency_key': idempotencyKey,
      if (referenceLabel != null && referenceLabel.isNotEmpty)
        'reference_label': referenceLabel,
      'payload': payload,
      if (httpStatus != null) 'http_status': httpStatus,
      if (errorCode != null && errorCode.isNotEmpty) 'error_code': errorCode,
      'error_message': errorMessage,
      'retry_count': retryCount,
      'created_at': nowIso,
      'last_failed_at': nowIso,
      'status': 'quarantined',
    };

    final list = getDeadLetterItems();
    list.removeWhere((e) => e['id']?.toString() == id);
    list.insert(0, record);
    _memDeadLetterQueue = list;

    await _sqlite.upsertDeadLetterItem(record);
    await _writeDaoMirrorFallback(OfflineDatabase._keyDeadLetterQueue, list);
  }

  /// Replay a quarantined Dead-Letter Queue payload using its exact original `X-Idempotency-Key`
  /// (with optional field overrides such as `variance_reason` or corrected SKU/price).
  Future<({bool success, String? errorMessage})> retryDeadLetterItem(
    String id,
    ApiClient apiClient, {
    Map<String, dynamic>? payloadOverrides,
  }) async {
    final list = getDeadLetterItems();
    final idx = list.indexWhere((e) => e['id']?.toString() == id);
    if (idx < 0) {
      return (success: false, errorMessage: 'Item antrean tidak ditemukan.');
    }

    final item = Map<String, dynamic>.from(list[idx]);
    final entityType = (item['entity_type'] ?? '').toString();
    final endpoint = (item['endpoint'] ?? '').toString();
    final idempotencyKey = (item['idempotency_key'] ?? id).toString();
    final rawPayload = item['payload'] is Map
        ? Map<String, dynamic>.from(item['payload'] as Map)
        : <String, dynamic>{};
    if (payloadOverrides != null && payloadOverrides.isNotEmpty) {
      rawPayload.addAll(payloadOverrides);
    }

    final localExpenseId = (rawPayload.remove('_local_expense_id') as num?)?.toInt();
    final localProductId = (rawPayload.remove('_local_product_id') as num?)?.toInt();

    try {
      final res = await apiClient.dio.post(
        endpoint,
        data: rawPayload,
        options: Options(
          headers: {
            if (idempotencyKey.isNotEmpty) 'X-Idempotency-Key': idempotencyKey,
          },
        ),
      );

      // Clean up source queue record on success
      if (entityType == 'receivable_payment') {
        await _sqlite.markReceivablePaymentSynced(id);
        final recQ = getPendingReceivablePayments()..removeWhere((e) => e['id']?.toString() == id);
        _memPendingReceivablePayments = recQ;
        await _writeDaoMirrorFallback(OfflineDatabase._keyPendingReceivablePayments, recQ);
      } else if (entityType == 'expense' && localExpenseId != null) {
        final serverId = ((res.data is Map ? res.data['data'] : null) is Map)
            ? ((res.data['data']['id']) as num?)?.toInt()
            : null;
        await _sqlite.markLocalExpenseSynced(localExpenseId, serverId: serverId);
        final exps = _readCollectionList(OfflineDatabase._keyLocalExpenses);
        final eIdx = exps.indexWhere((e) => (e['id'] as num?)?.toInt() == localExpenseId);
        if (eIdx >= 0) {
          exps[eIdx] = {
            ...exps[eIdx],
            'is_synced': 1,
            'sync_status': 'synced',
            if (serverId != null) 'server_id': serverId,
          };
          await _writeCollectionList(OfflineDatabase._keyLocalExpenses, exps);
        }
      } else if (entityType == 'shift_closure') {
        await _sqlite.markShiftClosureSynced(id);
        final shQ = getPendingShiftClosures()..removeWhere((e) => e['id']?.toString() == id);
        _memPendingShiftClosures = shQ;
        await _writeDaoMirrorFallback(OfflineDatabase._keyPendingShiftClosures, shQ);
      } else if (entityType == 'product' && localProductId != null) {
        final serverId = ((res.data is Map ? res.data['data'] : null) is Map)
            ? ((res.data['data']['id']) as num?)?.toInt()
            : null;
        if (serverId != null) {
          await remapOfflineSalesIds({localProductId: serverId}, const <int, int>{});
          await remapHeldSalesProductIds({localProductId: serverId});
          final products = getCachedProducts();
          final pIdx = products.indexWhere((p) => (p['id'] as num?)?.toInt() == localProductId);
          if (pIdx >= 0) {
            final updated = Map<String, dynamic>.from(products[pIdx]);
            updated['id'] = serverId;
            updated['is_local_only'] = false;
            updated.remove('sync_status');
            products[pIdx] = updated;
            await cacheProducts(products);
          }
        }
      } else if (entityType == 'sale') {
        final saleQueue = getOfflineSalesQueue()..removeWhere((e) => e['local_uuid']?.toString() == id);
        _memOfflineSales = saleQueue;
        await _sqlite.markOfflineSaleSynced(id);
        await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, saleQueue);
      }

      list.removeAt(idx);
      _memDeadLetterQueue = list;
      await _sqlite.deleteDeadLetterItem(id);
      await _writeDaoMirrorFallback(OfflineDatabase._keyDeadLetterQueue, list);
      return (success: true, errorMessage: null);
    } catch (e) {
      final errMsg = ApiClient.extractErrorMessage(e);
      item['retry_count'] = ((item['retry_count'] as num?)?.toInt() ?? 1) + 1;
      item['error_message'] = errMsg;
      item['last_failed_at'] = DateTime.now().toIso8601String();
      list[idx] = item;
      _memDeadLetterQueue = list;
      await _sqlite.upsertDeadLetterItem(item);
      await _writeDaoMirrorFallback(OfflineDatabase._keyDeadLetterQueue, list);
      return (success: false, errorMessage: errMsg);
    }
  }

  /// Discard a quarantined DLQ entry and remove it from its source pending queue.
  Future<void> discardDeadLetterItem(String id) async {
    final list = getDeadLetterItems();
    final match = list.where((e) => e['id']?.toString() == id).firstOrNull;
    final entityType = (match?['entity_type'] ?? '').toString();

    if (entityType == 'receivable_payment') {
      await _sqlite.deletePendingReceivablePayment(id);
      final recQ = getPendingReceivablePayments()..removeWhere((e) => e['id']?.toString() == id);
      _memPendingReceivablePayments = recQ;
      await _writeDaoMirrorFallback(OfflineDatabase._keyPendingReceivablePayments, recQ);
    } else if (entityType == 'shift_closure') {
      await _sqlite.deletePendingShiftClosure(id);
      final shQ = getPendingShiftClosures()..removeWhere((e) => e['id']?.toString() == id);
      _memPendingShiftClosures = shQ;
      await _writeDaoMirrorFallback(OfflineDatabase._keyPendingShiftClosures, shQ);
    } else if (entityType == 'expense') {
      final rawPayload = match?['payload'];
      final localExpId = rawPayload is Map ? (rawPayload['_local_expense_id'] as num?)?.toInt() : null;
      if (localExpId != null) {
        await _sqlite.markLocalExpenseSynced(localExpId);
        final exps = _readCollectionList(OfflineDatabase._keyLocalExpenses);
        final eIdx = exps.indexWhere((e) => (e['id'] as num?)?.toInt() == localExpId);
        if (eIdx >= 0) {
          exps[eIdx] = {...exps[eIdx], 'is_synced': 1, 'sync_status': 'discarded'};
          await _writeCollectionList(OfflineDatabase._keyLocalExpenses, exps);
        }
      }
    } else if (entityType == 'product') {
      final rawPayload = match?['payload'];
      final localPid = rawPayload is Map ? (rawPayload['_local_product_id'] as num?)?.toInt() : null;
      if (localPid != null) {
        await deleteLocalProduct(localPid);
      }
    } else if (entityType == 'sale') {
      await resolveConflictCancelSale(id);
    }

    list.removeWhere((e) => e['id']?.toString() == id);
    _memDeadLetterQueue = list;
    await _sqlite.deleteDeadLetterItem(id);
    await _writeDaoMirrorFallback(OfflineDatabase._keyDeadLetterQueue, list);
  }

  // ===========================================================================
  // F. ACID ATOMIC CHECKOUT COMMITTER (HARDENING #1)
  // ===========================================================================
  /// Persists an offline (or online) checkout atomically inside ONE SQLite `db.transaction(...)`:
  /// - Offline sale queue entry (when offline)
  /// - Local sales history receipt
  /// - Product stock updates
  /// - Stock movement audit entries
  /// - Customer balance updates (store credit / kasbon)
  /// - Cash-in ledger & open local shift totals
  /// - Cleans up completed held sale
  ///
  /// Prevents partial writes (e.g., stock deducted without receipt saved on force-close).
  Future<void> commitOfflineCheckoutAtomic({
    Map<String, dynamic>? offlineSaleApiBody,
    required Map<String, dynamic> receiptPayload,
    required Map<int, double> stockUpdates,
    required List<Map<String, dynamic>> stockMovements,
    List<Map<String, dynamic>>? updatedCustomers,
    Map<String, dynamic>? updatedCustomer,
    double netCashIn = 0.0,
    int? completedHeldSaleId,
  }) async {
    final nowIso = DateTime.now().toIso8601String();

    Map<String, dynamic>? normalizedOfflineSale;
    if (offlineSaleApiBody != null) {
      final id = (offlineSaleApiBody['local_uuid'] ?? _uuid.v4()).toString();
      normalizedOfflineSale = <String, dynamic>{
        ...offlineSaleApiBody,
        'local_uuid': id,
        'queued_at': (offlineSaleApiBody['queued_at'] ?? nowIso).toString(),
        'sync_status': 'pending',
      };
    }

    Map<String, dynamic>? cashEntry;
    if (netCashIn > 0.01) {
      cashEntry = <String, dynamic>{
        'id': 'sale-cash-${receiptPayload['local_uuid'] ?? DateTime.now().microsecondsSinceEpoch}',
        'title': 'Penjualan Tunai ${receiptPayload['number'] ?? ''}',
        'category': 'Penjualan Kasir',
        'direction': 'in',
        'channel': 'cash',
        'method_name': 'Tunai',
        'amount': netCashIn,
        'occurred_at': nowIso,
      };
    }

    Map<String, dynamic>? updatedOpenShift;
    final openShift = getCurrentLocalShift();
    if (openShift != null && netCashIn > 0.01) {
      updatedOpenShift = Map<String, dynamic>.from(openShift);
      updatedOpenShift['cash_sales'] =
          ((updatedOpenShift['cash_sales'] as num?)?.toDouble() ?? 0.0) + netCashIn;
      updatedOpenShift['expected_cash'] =
          ((updatedOpenShift['expected_cash'] as num?)?.toDouble() ?? 0.0) + netCashIn;
      updatedOpenShift['transactions_count'] =
          ((updatedOpenShift['transactions_count'] as num?)?.toInt() ?? 0) + 1;
    }

    // Step 1: Single ACID SQLite transaction — all or nothing!
    await _sqlite.commitOfflineCheckoutAtomic(
      offlineSaleEntry: normalizedOfflineSale,
      receiptPayload: receiptPayload,
      stockUpdates: stockUpdates,
      stockMovements: stockMovements,
      updatedCustomer: updatedCustomer,
      cashLedgerEntry: cashEntry,
      updatedOpenShift: updatedOpenShift,
      completedHeldSaleId: completedHeldSaleId,
    );

    // Step 2: Update in-memory & SharedPreferences mirrors ONLY AFTER SQLite transaction succeeds
    if (normalizedOfflineSale != null) {
      final queue = getOfflineSalesQueue();
      queue.removeWhere((e) => e['local_uuid'] == normalizedOfflineSale!['local_uuid']);
      queue.add(normalizedOfflineSale);
      _memOfflineSales = queue;
      await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, queue);
    }

    if (stockUpdates.isNotEmpty) {
      final products = getCachedProducts();
      for (final p in products) {
        final pid = (p['id'] as num?)?.toInt();
        if (pid != null && stockUpdates.containsKey(pid)) {
          final newStock = stockUpdates[pid]!;
          p['stock'] = newStock;
          final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 5.0;
          p['is_low_stock'] = newStock <= reorder;
        }
      }
      _memProducts = products;
      await _writeDaoMirrorFallback(OfflineDatabase._keyCachedProducts, products);
    }

    if (stockMovements.isNotEmpty) {
      final existingMovs = _readCollectionList(OfflineDatabase._keyLocalStockMovements);
      for (final mov in stockMovements) {
        existingMovs.insert(0, mov);
      }
      if (existingMovs.length > 500) {
        existingMovs.removeRange(500, existingMovs.length);
      }
      await _writeCollectionList(OfflineDatabase._keyLocalStockMovements, existingMovs);
    }

    await saveSaleToLocalHistory(receiptPayload);

    if (updatedCustomers != null) {
      _memCustomers = List<Map<String, dynamic>>.from(updatedCustomers);
      await _writeDaoMirrorFallback(OfflineDatabase._keyCachedCustomers, updatedCustomers);
    } else if (updatedCustomer != null) {
      final list = getCachedCustomers();
      final idx = list.indexWhere((c) => c['id'] == updatedCustomer['id']);
      if (idx >= 0) {
        list[idx] = updatedCustomer;
      } else {
        list.insert(0, updatedCustomer);
      }
      _memCustomers = list;
      await _writeDaoMirrorFallback(OfflineDatabase._keyCachedCustomers, list);
    }

    if (updatedOpenShift != null) {
      final shifts = getLocalShiftsHistory();
      final sIdx = shifts.indexWhere((s) => (s['id'] as num?)?.toInt() == (updatedOpenShift!['id'] as num?)?.toInt());
      if (sIdx >= 0) {
        shifts[sIdx] = updatedOpenShift;
        await _saveLocalShifts(shifts);
      }
    }

    if (completedHeldSaleId != null && completedHeldSaleId != 0) {
      final held = getHeldSales()..removeWhere((h) => (h['id'] as num?)?.toInt() == completedHeldSaleId);
      _memHeldSales = held;
      await _writeDaoMirrorFallback(OfflineDatabase._keyHeldSales, held);
    }
  }

  // ===========================================================================
  // G. UNIFIED PENDING COUNTS & HELPERS
  // ===========================================================================
  int get pendingOfflineProductsCount => getCachedProducts().where((p) {
        final id = (p['id'] as num?)?.toInt() ?? 0;
        final status = (p['sync_status'] ?? 'pending').toString();
        if (status == 'dead_letter') return false;
        return id < 0 || p['is_local_only'] == true || id > 1000000000;
      }).length;

  int get pendingReceivablePaymentsCount => getPendingReceivablePayments().where((e) {
        final synced = (e['is_synced'] as num?)?.toInt() == 1;
        final status = (e['sync_status'] ?? 'pending').toString();
        return !synced && status != 'dead_letter' && status != 'sync_conflict';
      }).length;

  int get pendingLocalExpensesCount => getUnsyncedLocalExpenses().length;

  int get pendingShiftClosuresCount => getPendingShiftClosures().where((e) {
        final synced = (e['is_synced'] as num?)?.toInt() == 1;
        final status = (e['sync_status'] ?? 'pending').toString();
        return !synced && status != 'dead_letter' && status != 'sync_conflict';
      }).length;

  int get deadLetterCount => getDeadLetterItems().length;

  /// Total non-conflict offline mutations waiting for Cloud sync across ALL 5 entity queues.
  int get totalPendingNonConflictSyncCount =>
      pendingNonConflictOfflineSalesCount +
      pendingReceivablePaymentsCount +
      pendingLocalExpensesCount +
      pendingShiftClosuresCount +
      pendingOfflineProductsCount;

  /// Total items queued locally (including quarantined sales conflicts) for UI badge display.
  int get totalOfflineQueueBadgeCount =>
      getOfflineSalesQueue().length +
      pendingReceivablePaymentsCount +
      pendingLocalExpensesCount +
      pendingShiftClosuresCount +
      pendingOfflineProductsCount;

  /// True if ANY unsynced offline transaction/mutation exists locally (guards against accidental wipe).
  bool get hasAnyPendingSyncItems =>
      getOfflineSalesQueue().isNotEmpty ||
      pendingOfflineProductsCount > 0 ||
      pendingReceivablePaymentsCount > 0 ||
      pendingLocalExpensesCount > 0 ||
      pendingShiftClosuresCount > 0 ||
      deadLetterCount > 0;

  String? _extractServerErrorCode(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error_code'] != null) {
      final code = data['error_code'].toString().trim();
      if (code.isNotEmpty) return code;
    }
    return null;
  }
}
