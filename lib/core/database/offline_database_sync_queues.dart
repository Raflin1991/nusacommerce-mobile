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
    await _prefs.setString(OfflineDatabase._keyHeldSales, jsonEncode(list));
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
    await _prefs.setString(OfflineDatabase._keyHeldSales, jsonEncode(normalized));
  }

  Future<void> deleteHeldSale(int id) async {
    final list = getHeldSales()..removeWhere((h) => (h['id'] as num?)?.toInt() == id);
    _memHeldSales = list;
    await _sqlite.deleteHeldSale(id);
    await _prefs.setString(OfflineDatabase._keyHeldSales, jsonEncode(list));
  }

  Future<void> remapHeldSalesProductIds(Map<int, int> productIdMap) async {
    if (productIdMap.isEmpty) return;
    final heldList = getHeldSales();
    if (heldList.isEmpty) return;
    bool changed = false;

    for (int i = 0; i < heldList.length; i++) {
      final held = Map<String, dynamic>.from(heldList[i]);
      final rawItems = held['cart_items'];
      if (rawItems is! List) continue;
      bool heldModified = false;
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
          heldModified = true;
        }
        return item;
      }).toList();

      if (heldModified) {
        held['cart_items'] = nextItems;
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
    await _prefs.setString(OfflineDatabase._keyCachedCloudReceivables, jsonEncode(invoices));
  }

  List<Map<String, dynamic>> getCachedCloudReceivables() {
    return _readPrefsList(OfflineDatabase._keyCachedCloudReceivables);
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
    await _prefs.setString(OfflineDatabase._keyPendingReceivablePayments, jsonEncode(queue));
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
      await _prefs.setString(OfflineDatabase._keyPendingReceivablePayments, jsonEncode(queue));
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
    await _prefs.setString(OfflineDatabase._keyPendingReceivablePayments, jsonEncode(remaining));
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
      unsynced = getLocalExpenses().where((e) {
        return !(e['is_synced'] == true || (e['is_synced'] as num?)?.toInt() == 1);
      }).toList();
    }
    if (unsynced.isEmpty) return 0;

    final allPrefsExpenses = _readPrefsList(OfflineDatabase._keyLocalExpenses);
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
              (e['id'] as num?)?.toInt() == expId ||
              (e['local_uuid']?.toString() == localUuid && localUuid.isNotEmpty),
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
          final idx = allPrefsExpenses.indexWhere((e) => (e['id'] as num?)?.toInt() == expId);
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
          final idx = allPrefsExpenses.indexWhere((e) => (e['id'] as num?)?.toInt() == expId);
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
      await _prefs.setString(OfflineDatabase._keyLocalExpenses, jsonEncode(allPrefsExpenses));
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
    await _prefs.setString(OfflineDatabase._keyPendingShiftClosures, jsonEncode(queue));
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
    await _prefs.setString(OfflineDatabase._keyPendingShiftClosures, jsonEncode(remaining));
    return syncedCount;
  }

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
    await _prefs.setString(OfflineDatabase._keyDeadLetterQueue, jsonEncode(list));
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
        await _prefs.setString(OfflineDatabase._keyPendingReceivablePayments, jsonEncode(recQ));
      } else if (entityType == 'expense' && localExpenseId != null) {
        final serverId = ((res.data is Map ? res.data['data'] : null) is Map)
            ? ((res.data['data']['id']) as num?)?.toInt()
            : null;
        await _sqlite.markLocalExpenseSynced(localExpenseId, serverId: serverId);
        final exps = _readPrefsList(OfflineDatabase._keyLocalExpenses);
        final eIdx = exps.indexWhere((e) => (e['id'] as num?)?.toInt() == localExpenseId);
        if (eIdx >= 0) {
          exps[eIdx] = {
            ...exps[eIdx],
            'is_synced': 1,
            'sync_status': 'synced',
            if (serverId != null) 'server_id': serverId,
          };
          await _prefs.setString(OfflineDatabase._keyLocalExpenses, jsonEncode(exps));
        }
      } else if (entityType == 'shift_closure') {
        await _sqlite.markShiftClosureSynced(id);
        final shQ = getPendingShiftClosures()..removeWhere((e) => e['id']?.toString() == id);
        _memPendingShiftClosures = shQ;
        await _prefs.setString(OfflineDatabase._keyPendingShiftClosures, jsonEncode(shQ));
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
        await _prefs.setString(OfflineDatabase._keyOfflineSalesQueue, jsonEncode(saleQueue));
      }

      list.removeAt(idx);
      _memDeadLetterQueue = list;
      await _sqlite.deleteDeadLetterItem(id);
      await _prefs.setString(OfflineDatabase._keyDeadLetterQueue, jsonEncode(list));
      return (success: true, errorMessage: null);
    } catch (e) {
      final errMsg = ApiClient.extractErrorMessage(e);
      item['retry_count'] = ((item['retry_count'] as num?)?.toInt() ?? 1) + 1;
      item['error_message'] = errMsg;
      item['last_failed_at'] = DateTime.now().toIso8601String();
      list[idx] = item;
      _memDeadLetterQueue = list;
      await _sqlite.upsertDeadLetterItem(item);
      await _prefs.setString(OfflineDatabase._keyDeadLetterQueue, jsonEncode(list));
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
      await _prefs.setString(OfflineDatabase._keyPendingReceivablePayments, jsonEncode(recQ));
    } else if (entityType == 'shift_closure') {
      await _sqlite.deletePendingShiftClosure(id);
      final shQ = getPendingShiftClosures()..removeWhere((e) => e['id']?.toString() == id);
      _memPendingShiftClosures = shQ;
      await _prefs.setString(OfflineDatabase._keyPendingShiftClosures, jsonEncode(shQ));
    } else if (entityType == 'expense') {
      final rawPayload = match?['payload'];
      final localExpId = rawPayload is Map ? (rawPayload['_local_expense_id'] as num?)?.toInt() : null;
      if (localExpId != null) {
        await _sqlite.markLocalExpenseSynced(localExpId);
        final exps = _readPrefsList(OfflineDatabase._keyLocalExpenses);
        final eIdx = exps.indexWhere((e) => (e['id'] as num?)?.toInt() == localExpId);
        if (eIdx >= 0) {
          exps[eIdx] = {...exps[eIdx], 'is_synced': 1, 'sync_status': 'discarded'};
          await _prefs.setString(OfflineDatabase._keyLocalExpenses, jsonEncode(exps));
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
    await _prefs.setString(OfflineDatabase._keyDeadLetterQueue, jsonEncode(list));
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
      await _prefs.setString(OfflineDatabase._keyOfflineSalesQueue, jsonEncode(queue));
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
      await _prefs.setString(OfflineDatabase._keyCachedProducts, jsonEncode(products));
    }

    if (stockMovements.isNotEmpty) {
      final existingMovs = _readPrefsList(OfflineDatabase._keyLocalStockMovements);
      for (final mov in stockMovements) {
        existingMovs.insert(0, mov);
      }
      if (existingMovs.length > 500) {
        existingMovs.removeRange(500, existingMovs.length);
      }
      await _prefs.setString(OfflineDatabase._keyLocalStockMovements, jsonEncode(existingMovs));
    }

    await saveSaleToLocalHistory(receiptPayload);

    if (updatedCustomers != null) {
      _memCustomers = List<Map<String, dynamic>>.from(updatedCustomers);
      await _prefs.setString(OfflineDatabase._keyCachedCustomers, jsonEncode(updatedCustomers));
    } else if (updatedCustomer != null) {
      final list = getCachedCustomers();
      final idx = list.indexWhere((c) => c['id'] == updatedCustomer['id']);
      if (idx >= 0) {
        list[idx] = updatedCustomer;
      } else {
        list.insert(0, updatedCustomer);
      }
      _memCustomers = list;
      await _prefs.setString(OfflineDatabase._keyCachedCustomers, jsonEncode(list));
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
      await _prefs.setString(OfflineDatabase._keyHeldSales, jsonEncode(held));
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
