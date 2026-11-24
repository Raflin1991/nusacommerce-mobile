part of 'offline_database.dart';

/// Enterprise Offline Sync Queues, Persistent Held Sales, ACID Commit & Dead-Letter Queue
/// extension for [OfflineDatabase].
extension OfflineDatabaseSyncQueuesExt on OfflineDatabase {
  static const int _maxTransientRetriesBeforeDlq = 5;

  // ===========================================================================
  // A. PERSISTENT HELD SALES (BUG 2: SURVIVES CRASH / BATTERY DRAIN / RESTART)
  // ===========================================================================
  List<Map<String, dynamic>> getHeldSales() {
    if (_memHeldSales != null) {
      return _memHeldSales!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    final list = _readPrefsList(OfflineDatabase._keyHeldSales);
    _memHeldSales = list;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> saveHeldSale(Map<String, dynamic> serializedHeld) async {
    final entry = Map<String, dynamic>.from(serializedHeld);
    final id = (entry['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    entry['id'] = id;
    entry['local_uuid'] = (entry['local_uuid'] ?? _uuid.v4()).toString();
    entry['created_at'] = (entry['created_at'] ?? DateTime.now().toIso8601String()).toString();

    final list = getHeldSales();
    list.removeWhere((h) => (h['id'] as num?)?.toInt() == id);
    list.insert(0, entry);
    _memHeldSales = list;

    await _sqlite.upsertHeldSale(entry);
    await _writeDaoMirrorFallback(OfflineDatabase._keyHeldSales, list);
  }

  Future<void> replaceHeldSales(List<Map<String, dynamic>> serializedList) async {
    final normalized = serializedList.map((raw) {
      final copy = Map<String, dynamic>.from(raw);
      copy['id'] = (copy['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      copy['local_uuid'] = (copy['local_uuid'] ?? _uuid.v4()).toString();
      copy['created_at'] = (copy['created_at'] ?? DateTime.now().toIso8601String()).toString();
      return copy;
    }).toList();
    _memHeldSales = normalized;
    await _sqlite.replaceAllHeldSales(normalized);
    await _writeDaoMirrorFallback(OfflineDatabase._keyHeldSales, normalized);
  }

  Future<void> deleteHeldSale(int id) async {
    final list = getHeldSales()..removeWhere((h) => (h['id'] as num?)?.toInt() == id);
    _memHeldSales = list;
    await _sqlite.deleteHeldSale(id);
    await _writeDaoMirrorFallback(OfflineDatabase._keyHeldSales, list);
  }

  Future<void> remapHeldSalesProductIds(Map<int, int> productIdMap) async {
    if (productIdMap.isEmpty) return;
    final heldList = getHeldSales();
    if (heldList.isEmpty) return;
    bool changed = false;

    for (int i = 0; i < heldList.length; i++) {
      final held = Map<String, dynamic>.from(heldList[i]);
      bool heldModified = false;

      for (final listKey in const ['cart_items', 'items']) {
        final rawItems = held[listKey];
        if (rawItems is! List) continue;
        bool listChanged = false;
        final nextItems = rawItems.map((raw) {
          if (raw is! Map) return raw;
          final item = Map<String, dynamic>.from(raw);
          final pid = (item['product_id'] as num?)?.toInt() ??
              (item['product'] is Map ? (item['product']['id'] as num?)?.toInt() : null);
          if (pid != null && productIdMap.containsKey(pid)) {
            final nextId = productIdMap[pid]!;
            item['product_id'] = nextId;
            if (item['product'] is Map) {
              final prodMap = Map<String, dynamic>.from(item['product'] as Map);
              prodMap['id'] = nextId;
              prodMap['is_local_only'] = false;
              item['product'] = prodMap;
            }
            listChanged = true;
          }
          return item;
        }).toList();
        if (listChanged) {
          held[listKey] = nextItems;
          heldModified = true;
        }
      }

      if (heldModified) {
        heldList[i] = held;
        changed = true;
      }
    }

    if (changed) {
      await replaceHeldSales(heldList);
    }
  }

  // ===========================================================================
  // B. CLOUD RECEIVABLES CACHE + PENDING RECEIVABLE PAYMENTS QUEUE (BUG 3)
  // ===========================================================================
  Future<void> cacheCloudReceivables(List<Map<String, dynamic>> invoices) async {
    await _writeCollectionList(OfflineDatabase._keyCachedCloudReceivables, invoices);
  }

  List<Map<String, dynamic>> getCachedCloudReceivables() {
    return _readCollectionList(OfflineDatabase._keyCachedCloudReceivables);
  }

  List<Map<String, dynamic>> getPendingReceivablePayments() {
    if (_memPendingReceivablePayments != null) {
      return _memPendingReceivablePayments!
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final list = _readPrefsList(OfflineDatabase._keyPendingReceivablePayments);
    _memPendingReceivablePayments = list;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> enqueuePendingReceivablePayment({
    required int saleId,
    required double amount,
    required int paymentMethodId,
    String paymentMethodName = 'Tunai',
    String? saleLocalUuid,
    String? invoiceNumber,
    String? customerName,
    String? reference,
    String? notes,
    String? idempotencyKey,
  }) async {
    final id = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : _uuid.v4();
    final nowIso = DateTime.now().toIso8601String();
    final record = <String, dynamic>{
      'id': id,
      'local_uuid': id,
      'sale_id': saleId,
      if (saleLocalUuid != null && saleLocalUuid.isNotEmpty) 'sale_local_uuid': saleLocalUuid,
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) 'invoice_number': invoiceNumber,
      if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
      'payment_method_id': paymentMethodId > 0 ? paymentMethodId : 1,
      'payment_method_name': paymentMethodName,
      'amount': amount,
      'reference': (reference != null && reference.trim().isNotEmpty) ? reference.trim() : id,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'created_at': nowIso,
      'sync_status': 'pending',
      'retry_count': 0,
      'is_synced': 0,
    };

    final queue = getPendingReceivablePayments();
    queue.removeWhere((e) => e['id']?.toString() == id);
    queue.add(record);
    _memPendingReceivablePayments = queue;

    await _sqlite.upsertPendingReceivablePayment(record);
    await _writeDaoMirrorFallback(OfflineDatabase._keyPendingReceivablePayments, queue);
    return record;
  }

  Future<void> remapPendingReceivableSaleId({
    String? saleLocalUuid,
    int? oldSaleId,
    required int newCloudSaleId,
  }) async {
    if (newCloudSaleId <= 0) return;
    await _sqlite.remapPendingReceivableSaleId(
      saleLocalUuid: saleLocalUuid,
      oldSaleId: oldSaleId,
      newCloudSaleId: newCloudSaleId,
    );

    final queue = getPendingReceivablePayments();
    bool changed = false;
    for (int i = 0; i < queue.length; i++) {
      final item = Map<String, dynamic>.from(queue[i]);
      final matchesUuid = saleLocalUuid != null &&
          saleLocalUuid.isNotEmpty &&
          item['sale_local_uuid']?.toString() == saleLocalUuid;
      final matchesOldId = oldSaleId != null &&
          oldSaleId != 0 &&
          (item['sale_id'] as num?)?.toInt() == oldSaleId;
      if (matchesUuid || matchesOldId) {
        item['sale_id'] = newCloudSaleId;
        queue[i] = item;
        changed = true;
      }
    }
    if (changed) {
      _memPendingReceivablePayments = queue;
      await _writeDaoMirrorFallback(OfflineDatabase._keyPendingReceivablePayments, queue);
    }
  }

  /// Sync all pending offline receivable payments to `POST /api/v1/debts/receivables/{saleId}/pay`
  /// with persisted UUIDv4 `X-Idempotency-Key` and Dead-Letter Queue quarantine on permanent 4xx errors.
  Future<int> syncPendingReceivablePayments(ApiClient apiClient) async {
    List<Map<String, dynamic>> queue = [];
    if (_sqlite.isSupported) {
      queue = await _sqlite.getUnsyncedReceivablePayments();
    }
    if (queue.isEmpty) {
      queue = getPendingReceivablePayments()
          .where((e) => (e['is_synced'] as num?)?.toInt() != 1)
          .toList();
    }
    if (queue.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    int syncedCount = 0;

    for (final raw in queue) {
      final item = Map<String, dynamic>.from(raw);
      final id = (item['id'] ?? item['local_uuid'] ?? '').toString().trim();
      final syncStatus = (item['sync_status'] ?? 'pending').toString();
      if (syncStatus == 'dead_letter' || syncStatus == 'sync_conflict') {
        remaining.add(item);
        continue;
      }

      final saleId = (item['sale_id'] as num?)?.toInt() ?? 0;
      final saleUuid = (item['sale_local_uuid'] ?? '').toString().trim();
      // Wait for parent offline sale to sync & remap before attempting receivable settlement
      if (saleId <= 0 || (saleUuid.isNotEmpty && saleId > 1000000000)) {
        remaining.add(item);
        continue;
      }

      final payload = <String, dynamic>{
        'payment_method_id': (item['payment_method_id'] as num?)?.toInt() ?? 1,
        'amount': (item['amount'] as num?)?.toDouble() ?? 0.0,
        'reference': (item['reference'] ?? id).toString(),
        if ((item['notes'] ?? '').toString().trim().isNotEmpty)
          'notes': item['notes'].toString().trim(),
      };

      try {
        await apiClient.dio.post(
          ApiEndpoints.payReceivable(saleId),
          data: payload,
          options: Options(
            headers: {
              if (id.isNotEmpty) 'X-Idempotency-Key': id,
            },
          ),
        );
        syncedCount++;
        if (id.isNotEmpty) {
          await _sqlite.markReceivablePaymentSynced(id);
        }
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final isOffline = ApiClient.isNetworkOfflineError(e);
        final errMsg = ApiClient.extractErrorMessage(e);
        final nextRetries = ((item['retry_count'] as num?)?.toInt() ?? 0) + 1;
        final isPermanentRejection = !isOffline &&
            statusCode != null &&
            (statusCode == 400 ||
                statusCode == 403 ||
                statusCode == 404 ||
                statusCode == 409 ||
                statusCode == 422);

        if (isPermanentRejection || (!isOffline && nextRetries >= _maxTransientRetriesBeforeDlq)) {
          item['sync_status'] = 'dead_letter';
          item['error_message'] = errMsg;
          item['retry_count'] = nextRetries;
          if (id.isNotEmpty) {
            await _sqlite.updateReceivablePaymentStatus(
              id,
              syncStatus: 'dead_letter',
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
            await enqueueDeadLetterItem(
              id: id,
              entityType: 'receivable_payment',
              endpoint: ApiEndpoints.payReceivable(saleId),
              idempotencyKey: id,
              referenceLabel:
                  'Pelunasan Bon ${item['invoice_number'] ?? '#$saleId'} (${item['customer_name'] ?? 'Pelanggan'})',
              payload: payload,
              httpStatus: statusCode,
              errorCode: _extractServerErrorCode(e) ?? 'ReceivablePaymentRejected',
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
          }
        } else {
          item['retry_count'] = nextRetries;
          if (id.isNotEmpty) {
            await _sqlite.updateReceivablePaymentStatus(
              id,
              syncStatus: 'pending',
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
          }
        }
        remaining.add(item);
      } catch (e) {
        remaining.add(item);
      }
    }

    _memPendingReceivablePayments = remaining;
    await _writeDaoMirrorFallback(OfflineDatabase._keyPendingReceivablePayments, remaining);
    return syncedCount;
  }

  // ===========================================================================
  // C. PENDING LOCAL EXPENSES (PETTY CASH) SYNC (BUG 5)
  // ===========================================================================
  List<Map<String, dynamic>> getUnsyncedLocalExpenses() {
    return getLocalExpenses().where((e) {
      final synced = e['is_synced'] == true || (e['is_synced'] as num?)?.toInt() == 1;
      final status = (e['sync_status'] ?? 'pending').toString();
      return !synced && status != 'dead_letter' && status != 'sync_conflict';
    }).toList();
  }

  /// Sync all local petty-cash expenses (`is_synced == 0`) to `POST /api/v1/expenses`
  /// with persisted UUIDv4 `X-Idempotency-Key`, updating `is_synced = 1` on success.
  Future<int> syncPendingLocalExpenses(ApiClient apiClient) async {
    List<Map<String, dynamic>> unsynced = [];
    if (_sqlite.isSupported) {
      unsynced = await _sqlite.getUnsyncedLocalExpenses();
    }
    if (unsynced.isEmpty) {
      unsynced = getLocalExpenses()
          .where((e) {
            return !(e['is_synced'] == true || (e['is_synced'] as num?)?.toInt() == 1);
          })
          .toList()
          .reversed
          .toList();
    }
    if (unsynced.isEmpty) return 0;

    final allPrefsExpenses = _readCollectionList(OfflineDatabase._keyLocalExpenses);
    int syncedCount = 0;
    bool prefsChanged = false;

    for (final raw in unsynced) {
      final exp = Map<String, dynamic>.from(raw);
      final expId = (exp['id'] as num?)?.toInt() ?? 0;
      final syncStatus = (exp['sync_status'] ?? 'pending').toString();
      if (syncStatus == 'dead_letter' || syncStatus == 'sync_conflict') {
        continue;
      }

      var localUuid = (exp['local_uuid'] ?? '').toString().trim();
      if (localUuid.isEmpty) {
        localUuid = _uuid.v4();
        exp['local_uuid'] = localUuid;
      }

      final amount = (exp['amount'] as num?)?.toDouble() ?? 0.0;
      final desc = (exp['description'] ?? '').toString().trim();
      if (amount <= 0 || desc.isEmpty) continue;

      final catId = (exp['category_id'] as num?)?.toInt() ??
          (exp['category'] is Map ? (exp['category']['id'] as num?)?.toInt() : null);
      final pmId = (exp['payment_method_id'] as num?)?.toInt();
      final expDate = (exp['expense_date'] ?? '').toString().trim();

      final payload = <String, dynamic>{
        if (catId != null && catId > 0) 'category_id': catId,
        if (pmId != null && pmId > 0) 'payment_method_id': pmId,
        if (expDate.isNotEmpty) 'expense_date': expDate,
        'amount': amount,
        'description': desc,
        'reference': localUuid,
      };

      try {
        final res = await apiClient.dio.post(
          ApiEndpoints.expenses,
          data: payload,
          options: Options(
            headers: {
              'X-Idempotency-Key': localUuid,
            },
          ),
        );
        final serverId = ((res.data is Map ? res.data['data'] : null) is Map)
            ? ((res.data['data']['id']) as num?)?.toInt()
            : null;
        syncedCount++;

        if (expId != 0) {
          await _sqlite.markLocalExpenseSynced(expId, serverId: serverId);
        }
        final idx = allPrefsExpenses.indexWhere(
          (e) =>
              (localUuid.isNotEmpty && e['local_uuid']?.toString() == localUuid) ||
              (expId != 0 && (e['id'] as num?)?.toInt() == expId && (e['local_uuid']?.toString() ?? '').isEmpty),
        );
        if (idx >= 0) {
          final updated = Map<String, dynamic>.from(allPrefsExpenses[idx]);
          updated['is_synced'] = 1;
          updated['sync_status'] = 'synced';
          updated['local_uuid'] = localUuid;
          if (serverId != null) updated['server_id'] = serverId;
          allPrefsExpenses[idx] = updated;
          prefsChanged = true;
        }
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final isOffline = ApiClient.isNetworkOfflineError(e);
        final errMsg = ApiClient.extractErrorMessage(e);
        final nextRetries = ((exp['retry_count'] as num?)?.toInt() ?? 0) + 1;
        final isPermanentRejection = !isOffline &&
            statusCode != null &&
            (statusCode == 400 ||
                statusCode == 403 ||
                statusCode == 404 ||
                statusCode == 409 ||
                statusCode == 422);

        if (isPermanentRejection || (!isOffline && nextRetries >= _maxTransientRetriesBeforeDlq)) {
          if (expId != 0) {
            await _sqlite.updateLocalExpenseSyncStatus(
              expId,
              syncStatus: 'dead_letter',
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
          }
          final idx = allPrefsExpenses.indexWhere(
            (e) =>
                (localUuid.isNotEmpty && e['local_uuid']?.toString() == localUuid) ||
                (expId != 0 && (e['id'] as num?)?.toInt() == expId),
          );
          if (idx >= 0) {
            final updated = Map<String, dynamic>.from(allPrefsExpenses[idx]);
            updated['sync_status'] = 'dead_letter';
            updated['error_message'] = errMsg;
            updated['retry_count'] = nextRetries;
            updated['local_uuid'] = localUuid;
            allPrefsExpenses[idx] = updated;
            prefsChanged = true;
          }
          await enqueueDeadLetterItem(
            id: localUuid,
            entityType: 'expense',
            endpoint: ApiEndpoints.expenses,
            idempotencyKey: localUuid,
            referenceLabel: 'Biaya Kas Kecil: $desc',
            payload: {...payload, '_local_expense_id': expId},
            httpStatus: statusCode,
            errorCode: _extractServerErrorCode(e) ?? 'ExpenseRejected',
            errorMessage: errMsg,
            retryCount: nextRetries,
          );
        } else if (expId != 0) {
          await _sqlite.updateLocalExpenseSyncStatus(
            expId,
            syncStatus: 'pending',
            errorMessage: errMsg,
            retryCount: nextRetries,
          );
          final idx = allPrefsExpenses.indexWhere(
            (e) =>
                (localUuid.isNotEmpty && e['local_uuid']?.toString() == localUuid) ||
                (expId != 0 && (e['id'] as num?)?.toInt() == expId),
          );
          if (idx >= 0) {
            final updated = Map<String, dynamic>.from(allPrefsExpenses[idx]);
            updated['retry_count'] = nextRetries;
            updated['local_uuid'] = localUuid;
            allPrefsExpenses[idx] = updated;
            prefsChanged = true;
          }
        }
      } catch (_) {}
    }

    if (prefsChanged) {
      await _writeCollectionList(OfflineDatabase._keyLocalExpenses, allPrefsExpenses);
    }
    return syncedCount;
  }

  // ===========================================================================
  // D. PENDING SHIFT CLOSURES QUEUE & SYNC (BUG 6)
  // ===========================================================================
  List<Map<String, dynamic>> getPendingShiftClosures() {
    if (_memPendingShiftClosures != null) {
      return _memPendingShiftClosures!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    final list = _readPrefsList(OfflineDatabase._keyPendingShiftClosures);
    _memPendingShiftClosures = list;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  bool hasPendingClosureForShift(int? shiftId) {
    final pending = getPendingShiftClosures().where(
      (e) => (e['is_synced'] as num?)?.toInt() != 1,
    );
    if (shiftId == null) return pending.isNotEmpty;
    return pending.any(
      (e) => (e['shift_id'] as num?)?.toInt() == shiftId || e['shift_id'] == null,
    );
  }

  Future<Map<String, dynamic>> enqueuePendingShiftClosure({
    int? shiftId,
    required double closingCashCounted,
    Map<String, dynamic>? closingDenominations,
    String? varianceReason,
    String? varianceNotes,
    String? notes,
    String? closedAt,
    String? idempotencyKey,
  }) async {
    final id = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? idempotencyKey.trim()
        : _uuid.v4();
    final nowIso = closedAt ?? DateTime.now().toIso8601String();

    final record = <String, dynamic>{
      'id': id,
      'local_uuid': id,
      if (shiftId != null && shiftId > 0) 'shift_id': shiftId,
      'closing_cash_counted': closingCashCounted,
      if (closingDenominations != null && closingDenominations.isNotEmpty)
        'closing_denominations': closingDenominations,
      if (varianceReason != null && varianceReason.trim().isNotEmpty)
        'variance_reason': varianceReason.trim(),
      if (varianceNotes != null && varianceNotes.trim().isNotEmpty)
        'variance_notes': varianceNotes.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      'closed_at': nowIso,
      'sync_status': 'pending',
      'retry_count': 0,
      'is_synced': 0,
    };

    // Also close any open local shift record atomically inside SQLite
    Map<String, dynamic>? closedLocalShift;
    final shifts = getLocalShiftsHistory();
    final openIdx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (openIdx >= 0) {
      final enriched = _enrichShiftTotals(shifts[openIdx]);
      final expected = (enriched['expected_cash'] as num?)?.toDouble() ?? 0.0;
      enriched['status'] = 'closed';
      enriched['closed_at'] = nowIso;
      enriched['closing_cash'] = closingCashCounted;
      enriched['variance'] = closingCashCounted - expected;
      enriched['is_synced'] = 0;
      if (notes != null && notes.trim().isNotEmpty) {
        enriched['notes'] = notes.trim();
      }
      shifts[openIdx] = enriched;
      closedLocalShift = enriched;
    }

    await _sqlite.commitShiftClosureAtomic(
      closedShift: closedLocalShift,
      pendingClosure: record,
    );

    if (closedLocalShift != null) {
      await _saveLocalShifts(shifts);
    }

    final queue = getPendingShiftClosures();
    queue.removeWhere(
      (e) =>
          e['id']?.toString() == id ||
          (shiftId != null && (e['shift_id'] as num?)?.toInt() == shiftId),
    );
    queue.add(record);
    _memPendingShiftClosures = queue;
    await _writeDaoMirrorFallback(OfflineDatabase._keyPendingShiftClosures, queue);
    return record;
  }

  /// Sync all pending offline shift closures to `POST /api/v1/shifts/close` with UUIDv4 `X-Idempotency-Key`.
  /// Must execute AFTER offline sales/receivables/expenses so the shift captures every offline cash sale,
  /// and BEFORE opening a new shift on Cloud.
  Future<int> syncPendingShiftClosures(ApiClient apiClient) async {
    List<Map<String, dynamic>> queue = [];
    if (_sqlite.isSupported) {
      queue = await _sqlite.getUnsyncedShiftClosures();
    }
    if (queue.isEmpty) {
      queue = getPendingShiftClosures()
          .where((e) => (e['is_synced'] as num?)?.toInt() != 1)
          .toList();
    }
    if (queue.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    int syncedCount = 0;

    for (final raw in queue) {
      final item = Map<String, dynamic>.from(raw);
      final id = (item['id'] ?? item['local_uuid'] ?? '').toString().trim();
      final syncStatus = (item['sync_status'] ?? 'pending').toString();
      if (syncStatus == 'dead_letter' || syncStatus == 'sync_conflict') {
        remaining.add(item);
        continue;
      }

      final shiftId = (item['shift_id'] as num?)?.toInt();
      final payload = <String, dynamic>{
        if (shiftId != null && shiftId > 0 && shiftId < 1000000000) 'shift_id': shiftId,
        'closing_cash_counted': (item['closing_cash_counted'] as num?)?.toDouble() ?? 0.0,
        if (item['closing_denominations'] is Map)
          'closing_denominations': item['closing_denominations'],
        if ((item['variance_reason'] ?? '').toString().trim().isNotEmpty)
          'variance_reason': item['variance_reason'].toString().trim(),
        if ((item['variance_notes'] ?? '').toString().trim().isNotEmpty)
          'variance_notes': item['variance_notes'].toString().trim(),
        if ((item['notes'] ?? '').toString().trim().isNotEmpty)
          'notes': item['notes'].toString().trim(),
      };

      try {
        await apiClient.dio.post(
          ApiEndpoints.closeShift,
          data: payload,
          options: Options(
            headers: {
              if (id.isNotEmpty) 'X-Idempotency-Key': id,
            },
          ),
        );
        syncedCount++;
        if (id.isNotEmpty) {
          await _sqlite.markShiftClosureSynced(id);
        }
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final isOffline = ApiClient.isNetworkOfflineError(e);
        final errMsg = ApiClient.extractErrorMessage(e);
        final errCode = _extractServerErrorCode(e) ?? 'ShiftCloseRejected';
        final nextRetries = ((item['retry_count'] as num?)?.toInt() ?? 0) + 1;

        // If shift was already closed on Cloud (e.g. by supervisor on web), treat idempotently as synced!
        final lowerMsg = errMsg.toLowerCase();
        final alreadyClosedOnServer = !isOffline &&
            statusCode == 422 &&
            (lowerMsg.contains('tidak ada shift aktif') ||
                lowerMsg.contains('sudah ditutup') ||
                lowerMsg.contains('already closed'));
        if (alreadyClosedOnServer) {
          syncedCount++;
          if (id.isNotEmpty) {
            await _sqlite.markShiftClosureSynced(id);
          }
          continue;
        }

        final isPermanentRejection = !isOffline &&
            statusCode != null &&
            (statusCode == 400 ||
                statusCode == 403 ||
                statusCode == 404 ||
                statusCode == 409 ||
                statusCode == 422);

        if (isPermanentRejection || (!isOffline && nextRetries >= _maxTransientRetriesBeforeDlq)) {
          item['sync_status'] = 'dead_letter';
          item['error_code'] = errCode;
          item['error_message'] = errMsg;
          item['retry_count'] = nextRetries;
          if (id.isNotEmpty) {
            await _sqlite.updateShiftClosureStatus(
              id,
              syncStatus: 'dead_letter',
              errorCode: errCode,
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
            await enqueueDeadLetterItem(
              id: id,
              entityType: 'shift_closure',
              endpoint: ApiEndpoints.closeShift,
              idempotencyKey: id,
              referenceLabel: shiftId != null ? 'Tutup Shift #$shiftId' : 'Tutup Shift Kasir Offline',
              payload: payload,
              httpStatus: statusCode,
              errorCode: errCode,
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
          }
        } else {
          item['retry_count'] = nextRetries;
          if (id.isNotEmpty) {
            await _sqlite.updateShiftClosureStatus(
              id,
              syncStatus: 'pending',
              errorCode: errCode,
              errorMessage: errMsg,
              retryCount: nextRetries,
            );
          }
        }
        remaining.add(item);
      } catch (_) {
        remaining.add(item);
      }
    }

    _memPendingShiftClosures = remaining;
    await _writeDaoMirrorFallback(OfflineDatabase._keyPendingShiftClosures, remaining);
    return syncedCount;
  }

}
