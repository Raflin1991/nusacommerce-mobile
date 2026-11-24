part of 'offline_database.dart';

extension OfflineDatabaseSalesQueueExt on OfflineDatabase {
  // ===========================================================================
  // 4. OFFLINE SALE QUEUE (UUIDv4 IDEMPOTENT SYNC ENGINE)
  // ===========================================================================
  List<Map<String, dynamic>> getOfflineSalesQueue() {
    if (_memOfflineSales != null) {
      return List<Map<String, dynamic>>.from(_memOfflineSales!);
    }
    final list = _readPrefsList(OfflineDatabase._keyOfflineSalesQueue);
    _memOfflineSales = list;
    return list;
  }

  Future<void> enqueueOfflineSale(Map<String, dynamic> salePayload) async {
    final String id = (salePayload['local_uuid'] ?? _uuid.v4()).toString();
    final String createdAt = DateTime.now().toIso8601String();
    final entry = <String, dynamic>{
      ...salePayload,
      'local_uuid': id,
      'queued_at': createdAt,
      'sync_status': 'pending',
    };

    await _sqlite.insertOfflineSale(id, entry, createdAt);

    final queue = getOfflineSalesQueue();
    queue.removeWhere((e) => e['local_uuid'] == id);
    queue.add(entry);
    _memOfflineSales = queue;
    await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, queue);
  }

  /// Flush pending offline sales to OXORA Cloud POST /api/v1/pos/checkout.
  /// Guarded by an in-flight mutex (`_activeQueueSyncFuture`) and deterministic
  /// `X-Idempotency-Key` (= persisted `local_uuid`) so flaky retries never double-count.
  Future<int> syncOfflineQueue(ApiClient apiClient) {
    if (_activeQueueSyncFuture != null) {
      return _activeQueueSyncFuture!;
    }
    final future = _performSyncOfflineQueue(apiClient).whenComplete(() {
      _activeQueueSyncFuture = null;
    });
    _activeQueueSyncFuture = future;
    return future;
  }

  Future<int> _performSyncOfflineQueue(ApiClient apiClient) async {
    List<Map<String, dynamic>> queue = [];
    if (_sqlite.isSupported) {
      queue = await _sqlite.getUnsyncedOfflineSales();
    }
    if (queue.isEmpty) {
      queue = getOfflineSalesQueue();
    }

    final remaining = <Map<String, dynamic>>[];
    int syncedCount = 0;

    for (final rawPayload in queue) {
      final payload = Map<String, dynamic>.from(rawPayload);
      final id = (payload['local_uuid'] ?? '').toString().trim();

      // Do not automatically retry sales already flagged as compliance/validation conflict;
      // await owner/manager manual reconciliation.
      if (payload['sync_status'] == 'sync_conflict' ||
          payload['sync_status'] == 'dead_letter') {
        remaining.add(payload);
        continue;
      }

      final sendPayload = Map<String, dynamic>.from(payload)
        ..remove('sync_status')
        ..remove('conflict_code')
        ..remove('conflict_reason')
        ..remove('conflict_detected_at')
        ..remove('retry_count')
        ..['synced_from_offline'] = true;
      final nodeCode = (sendPayload['origin_node_code'] ??
              _prefs.getString('nusa_mobile_node_code') ??
              '')
          .toString()
          .trim()
          .toUpperCase();

      try {
        final response = await apiClient.dio.post(
          ApiEndpoints.checkout,
          data: sendPayload,
          options: Options(
            headers: {
              if (id.isNotEmpty) 'X-Idempotency-Key': id,
              if (nodeCode.isNotEmpty) 'X-Edge-Node-Code': nodeCode,
            },
          ),
        );
        syncedCount++;
        final respMap =
            response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null;
        if (id.isNotEmpty) {
          await _sqlite.markOfflineSaleSynced(id);
          await _markLocalSaleHistorySynced(id, respMap);

          // Remap any offline receivable payments targeting this newly synced credit sale!
          final serverData = respMap?['data'] is Map
              ? Map<String, dynamic>.from(respMap!['data'] as Map)
              : null;
          final newCloudSaleId = (serverData?['id'] as num?)?.toInt();
          if (newCloudSaleId != null && newCloudSaleId > 0) {
            final localSaleId = (payload['id'] as num?)?.toInt();
            await remapPendingReceivableSaleId(
              saleLocalUuid: id,
              oldSaleId: localSaleId,
              newCloudSaleId: newCloudSaleId,
            );
          }
        }
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;
        final errorCode = (data is Map ? data['error_code'] : null)?.toString() ?? '';
        final message = (data is Map ? data['message'] : null)?.toString() ??
            ApiClient.extractErrorMessage(e);
        final msgLower = message.toLowerCase();
        final nextRetries = ((payload['retry_count'] as num?)?.toInt() ?? 0) + 1;
        payload['retry_count'] = nextRetries;

        final isInsufficientStock = statusCode == 422 &&
            (errorCode == 'InsufficientStock' ||
                errorCode.toLowerCase().contains('stock') ||
                msgLower.contains('insufficientstock') ||
                msgLower.contains('stok') ||
                msgLower.contains('insufficient stock'));

        final isOfflineErr = ApiClient.isNetworkOfflineError(e);
        final isRejectedBusinessRule = !isOfflineErr &&
            statusCode != null &&
            (statusCode == 400 ||
                statusCode == 403 ||
                statusCode == 404 ||
                statusCode == 409 ||
                statusCode == 422);
        final exceededTransientLimit = !isOfflineErr && nextRetries >= 5;

        if (isInsufficientStock) {
          payload['sync_status'] = 'sync_conflict';
          payload['conflict_code'] = errorCode.isNotEmpty ? errorCode : 'InsufficientStock';
          payload['conflict_reason'] = message;
          payload['conflict_detected_at'] = DateTime.now().toIso8601String();
          if (id.isNotEmpty) {
            await _sqlite.updateOfflineSalePayload(id, payload, isSynced: 0);
          }
        } else if (isRejectedBusinessRule || exceededTransientLimit) {
          payload['sync_status'] = 'sync_conflict';
          payload['conflict_code'] =
              errorCode.isNotEmpty ? errorCode : (exceededTransientLimit ? 'ServerRetryExceeded' : 'ValidationError');
          payload['conflict_reason'] = message;
          payload['conflict_detected_at'] = DateTime.now().toIso8601String();
          if (id.isNotEmpty) {
            await _sqlite.updateOfflineSalePayload(id, payload, isSynced: 0);
            await enqueueDeadLetterItem(
              id: id,
              entityType: 'sale',
              endpoint: ApiEndpoints.checkout,
              idempotencyKey: id,
              referenceLabel: 'Nota Offline ${payload['number'] ?? id}',
              payload: sendPayload,
              httpStatus: statusCode,
              errorCode: payload['conflict_code'].toString(),
              errorMessage: message,
              retryCount: nextRetries,
            );
          }
        } else if (id.isNotEmpty) {
          await _sqlite.updateOfflineSalePayload(id, payload, isSynced: 0);
        }
        remaining.add(payload);
      } catch (_) {
        remaining.add(payload);
      }
    }

    if (queue.isNotEmpty || (_memOfflineSales?.isNotEmpty ?? false)) {
      _memOfflineSales = remaining;
      await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, remaining);
    }

    // Strict FIFO Dependency Order after offline sales:
    // 1) Offline Receivable Payments (Bug 3) -> POST /api/v1/debts/receivables/{saleId}/pay
    syncedCount += await syncPendingReceivablePayments(apiClient);
    // 2) Offline Petty-Cash Expenses (Bug 5) -> POST /api/v1/expenses
    syncedCount += await syncPendingLocalExpenses(apiClient);
    // 3) Offline Shift Closures (Bug 6) -> POST /api/v1/shifts/close (MUST run AFTER shift's sales)
    syncedCount += await syncPendingShiftClosures(apiClient);

    return syncedCount;
  }

  Future<void> _markLocalSaleHistorySynced(
    String localUuid,
    Map<String, dynamic>? responseBody,
  ) async {
    final history = getLocalSalesHistory();
    bool changed = false;
    final serverData = responseBody?['data'] is Map
        ? Map<String, dynamic>.from(responseBody!['data'] as Map)
        : null;
    final meta = responseBody?['meta'] is Map
        ? Map<String, dynamic>.from(responseBody!['meta'] as Map)
        : null;

    for (final s in history) {
      if (s['local_uuid']?.toString() == localUuid) {
        s['is_offline_pending'] = false;
        s['synced_from_offline'] = true;
        if (serverData != null) {
          if (serverData['id'] != null) s['id'] = serverData['id'];
          if ((serverData['number'] ?? '').toString().isNotEmpty) {
            s['number'] = serverData['number'];
          }
        }
        if (meta != null && meta['conflict_flagged'] == true) {
          s['conflict_flagged'] = true;
          s['conflict_id'] = meta['conflict_id'];
          s['conflict_type'] = meta['conflict_type'];
        }
        changed = true;
      }
    }
    if (changed) {
      await _writeCollectionList(OfflineDatabase._keyCompletedSalesHistory, history);
    }
  }

  /// Return all locally flagged `sync_conflict` offline sales awaiting owner reconciliation.
  List<Map<String, dynamic>> getOfflineSyncConflicts() {
    return getOfflineSalesQueue()
        .where((e) => e['sync_status'] == 'sync_conflict')
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Retry syncing a conflicted offline sale without forcing oversell (e.g. after opening a cashier shift).
  Future<bool> retryOfflineSaleConflict(
    String localUuid,
    ApiClient apiClient,
  ) async {
    final queue = getOfflineSalesQueue();
    final idx = queue.indexWhere((e) => e['local_uuid']?.toString() == localUuid);
    if (idx < 0) return false;

    final payload = Map<String, dynamic>.from(queue[idx]);
    payload.remove('sync_status');
    payload.remove('conflict_code');
    payload.remove('conflict_reason');
    payload.remove('conflict_detected_at');
    payload['synced_from_offline'] = true;
    final nodeCode = (payload['origin_node_code'] ?? _prefs.getString('nusa_mobile_node_code') ?? '')
        .toString()
        .trim()
        .toUpperCase();

    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.checkout,
        data: payload,
        options: Options(
          headers: {
            'X-Idempotency-Key': localUuid,
            if (nodeCode.isNotEmpty) 'X-Edge-Node-Code': nodeCode,
          },
        ),
      );
      queue.removeAt(idx);
      _memOfflineSales = queue;
      await _sqlite.markOfflineSaleSynced(localUuid);
      await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, queue);
      await _markLocalSaleHistorySynced(
        localUuid,
        response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolve an offline InsufficientStock conflict by approving oversell (`allow_oversell: true`).
  Future<bool> resolveConflictApproveOversell(
    String localUuid,
    ApiClient apiClient,
  ) async {
    final queue = getOfflineSalesQueue();
    final idx = queue.indexWhere((e) => e['local_uuid']?.toString() == localUuid);
    if (idx < 0) return false;

    final payload = Map<String, dynamic>.from(queue[idx]);
    payload.remove('sync_status');
    payload.remove('conflict_code');
    payload.remove('conflict_reason');
    payload.remove('conflict_detected_at');
    payload['allow_oversell'] = true;
    payload['synced_from_offline'] = true;
    final nodeCode = (payload['origin_node_code'] ?? _prefs.getString('nusa_mobile_node_code') ?? '')
        .toString()
        .trim()
        .toUpperCase();

    try {
      final response = await apiClient.dio.post(
        ApiEndpoints.checkout,
        data: payload,
        options: Options(
          headers: {
            'X-Idempotency-Key': localUuid,
            if (nodeCode.isNotEmpty) 'X-Edge-Node-Code': nodeCode,
          },
        ),
      );
      queue.removeAt(idx);
      _memOfflineSales = queue;
      await _sqlite.markOfflineSaleSynced(localUuid);
      await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, queue);
      await _markLocalSaleHistorySynced(
        localUuid,
        response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolve an offline InsufficientStock conflict by cancelling/voiding the local sale.
  Future<void> resolveConflictCancelSale(String localUuid) async {
    final queue = getOfflineSalesQueue();
    queue.removeWhere((e) => e['local_uuid']?.toString() == localUuid);
    _memOfflineSales = queue;
    await _sqlite.deleteOfflineSale(localUuid);
    await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, queue);

    final history = getLocalSalesHistory();
    bool changed = false;
    for (final s in history) {
      if (s['local_uuid']?.toString() == localUuid) {
        s['status'] = 'voided';
        s['void_reason'] = 'Dibatalkan saat rekonsiliasi konflik stok offline';
        changed = true;
      }
    }
    if (changed) {
      await _writeCollectionList(OfflineDatabase._keyCompletedSalesHistory, history);
    }
  }

  /// Remaps negative local product/customer IDs inside queued offline sales to their new Cloud IDs before sync.
  Future<void> remapOfflineSalesIds(
    Map<int, int> productIdMap,
    Map<int, int> customerIdMap,
  ) async {
    if (productIdMap.isEmpty && customerIdMap.isEmpty) return;
    final queue = getOfflineSalesQueue();
    if (queue.isEmpty) return;
    bool modified = false;

    for (int i = 0; i < queue.length; i++) {
      final sale = Map<String, dynamic>.from(queue[i]);
      bool saleChanged = false;

      final cid = (sale['customer_id'] as num?)?.toInt();
      if (cid != null && customerIdMap.containsKey(cid)) {
        sale['customer_id'] = customerIdMap[cid];
        saleChanged = true;
      }

      if (sale['items'] is List) {
        final items = (sale['items'] as List).map((raw) {
          if (raw is! Map) return raw;
          final item = Map<String, dynamic>.from(raw);
          final pid = (item['product_id'] as num?)?.toInt();
          if (pid != null && productIdMap.containsKey(pid)) {
            item['product_id'] = productIdMap[pid];
            saleChanged = true;
          }
          return item;
        }).toList();
        if (saleChanged) {
          sale['items'] = items;
        }
      }

      if (saleChanged) {
        queue[i] = sale;
        final uuid = sale['local_uuid']?.toString();
        if (uuid != null && uuid.isNotEmpty) {
          await _sqlite.updateOfflineSalePayload(uuid, sale);
        }
        modified = true;
      }
    }

    if (modified) {
      _memOfflineSales = queue;
      await _writeDaoMirrorFallback(OfflineDatabase._keyOfflineSalesQueue, queue);
    }
  }

  // ===========================================================================
  // 5. LOCAL COMPLETED SALES HISTORY
  // ===========================================================================
  Future<void> cacheSalesHistory(List<Map<String, dynamic>> sales) async {
    await _writeCollectionList(OfflineDatabase._keyCompletedSalesHistory, sales);
    await setHasCloudSynced(true);
  }

  List<Map<String, dynamic>> getLocalSalesHistory() {
    final list = _readCollectionList(OfflineDatabase._keyCompletedSalesHistory);
    list.removeWhere((s) => (s['number'] ?? '').toString().startsWith('#INV-102'));
    return list;
  }

  Future<void> saveSaleToLocalHistory(Map<String, dynamic> saleReceipt) async {
    final history = getLocalSalesHistory();
    history.removeWhere((s) => s['number'] == saleReceipt['number']);
    history.insert(0, saleReceipt);
    await _writeCollectionList(OfflineDatabase._keyCompletedSalesHistory, history);
  }

  Future<void> updateLocalSaleStatus(int saleId, String status, {String? voidReason}) async {
    final history = getLocalSalesHistory();
    for (final s in history) {
      if (s['id'] == saleId) {
        s['status'] = status;
        if (voidReason != null) s['void_reason'] = voidReason;
      }
    }
    await _writeCollectionList(OfflineDatabase._keyCompletedSalesHistory, history);
  }

}
