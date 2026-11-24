part of 'pos_cubit.dart';

extension PosCubitConflictsWarehouseExt on PosCubit {
  /// Retry a quarantined Dead-Letter Queue item (optionally supplying override fields
  /// such as `variance_reason` for a shift closure or adjusted SKU for a product).
  Future<({bool success, String? errorMessage})> retryDeadLetterItem(
    String id, {
    Map<String, dynamic>? payloadOverrides,
  }) async {
    final result = await _offlineDb.retryDeadLetterItem(
      id,
      _apiClient,
      payloadOverrides: payloadOverrides,
    );
    if (result.success) {
      await syncWithCloud(force: false, preserveActiveCart: true, silent: true);
    }
    _emitState(state.copyWith(
      allProducts: _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList(),
      salesHistory: _offlineDb.getLocalSalesHistory(),
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));
    return result;
  }

  /// Discard a permanently rejected Dead-Letter Queue item cleanly.
  Future<void> discardDeadLetterItem(String id) async {
    await _offlineDb.discardDeadLetterItem(id);
    _emitState(state.copyWith(
      allProducts: _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList(),
      salesHistory: _offlineDb.getLocalSalesHistory(),
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));
  }

  /// Retry syncing a non-stock offline conflict (e.g., ShiftRequired after opening a cashier shift).
  Future<bool> retryOfflineSyncConflict(String localUuid) async {
    final ok = await _offlineDb.retryOfflineSaleConflict(localUuid, _apiClient);
    if (ok) {
      await syncWithCloud(force: false, preserveActiveCart: true);
    }
    _emitState(state.copyWith(
      salesHistory: _offlineDb.getLocalSalesHistory(),
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));
    return ok;
  }

  /// Resolve an offline `InsufficientStock` conflict either by approving oversell
  /// or by voiding/cancelling the local conflicted sale.
  Future<bool> resolveOfflineStockConflict({
    required String localUuid,
    required bool approveOversell,
  }) async {
    bool ok = true;
    if (approveOversell) {
      ok = await _offlineDb.resolveConflictApproveOversell(localUuid, _apiClient);
      if (ok) {
        await syncWithCloud(force: false, preserveActiveCart: true);
      }
    } else {
      await _offlineDb.resolveConflictCancelSale(localUuid);
    }

    _emitState(state.copyWith(
      salesHistory: _offlineDb.getLocalSalesHistory(),
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));
    return ok;
  }

  /// Resolve a Cloud-side OfflineSyncConflict record (POST /api/v1/pos/offline-conflicts/{id}/resolve).
  Future<({bool success, String message})> resolveCloudOfflineConflict(
    int conflictId, {
    required String resolution,
    String? notes,
  }) async {
    if (_isLocalStandalone) {
      return (success: false, message: 'Mode Toko Mandiri tidak terhubung ke Cloud.');
    }
    try {
      final res = await _apiClient.dio.post(
        ApiEndpoints.resolveOfflineConflict(conflictId),
        data: {
          'resolution': resolution,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      final body = res.data;
      final msg = (body is Map ? body['message'] : null)?.toString() ??
          'Konflik sinkronisasi offline telah diselesaikan.';
      return (success: true, message: msg);
    } catch (e) {
      return (success: false, message: ApiClient.extractErrorMessage(e));
    }
  }

  /// Sync pending offline transactions manually in strict FIFO dependency order:
  /// (1) Local new products -> (2) Offline sales -> (3) Receivable payments ->
  /// (4) Petty cash expenses -> (5) Shift closures -> (6) Catalog refresh
  Future<int> syncOfflineTransactions() async {
    if (_isLocalStandalone) {
      _emitState(state.copyWith(
        isSyncingOfflineQueue: false,
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      return 0;
    }
    _emitState(state.copyWith(isSyncingOfflineQueue: true));
    try {
      final uploadedProducts = await _syncPendingLocalProductsToCloud();
      final synced = await _offlineDb.syncOfflineQueue(_apiClient);
      final online = await _connectivityService.checkOnline();
      if (online) {
        await syncWithCloud(force: false, preserveActiveCart: true, silent: true);
      }
      _emitState(state.copyWith(
        isOnline: online,
        isSyncingOfflineQueue: false,
        allProducts: _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList(),
        salesHistory: _offlineDb.getLocalSalesHistory(),
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      _scheduleBackoffSyncIfNeeded();
      return uploadedProducts + synced;
    } catch (_) {
      _emitState(state.copyWith(
        isSyncingOfflineQueue: false,
        salesHistory: _offlineDb.getLocalSalesHistory(),
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      _scheduleBackoffSyncIfNeeded();
      return 0;
    }
  }

  /// Fetch Multi-Warehouse & Cross-Store stock breakdown (GET /api/v1/pos/warehouse-stock)
  /// with seamless fallback to cached per-product multi-warehouse stocks when offline.
  Future<({bool fromCloud, List<Map<String, dynamic>> results, String? error})> fetchWarehouseStock({
    int? productId,
    String query = '',
  }) async {
    if (!_isLocalStandalone) {
      try {
        final params = <String, dynamic>{};
        if (productId != null) {
          params['product_id'] = productId;
        } else if (query.trim().isNotEmpty) {
          params['q'] = query.trim();
        }
        final res = await _apiClient.dio.get(
          ApiEndpoints.posWarehouseStock,
          queryParameters: params,
        );
        final data = res.data is Map ? res.data['data'] : null;
        if (data is Map) {
          if (productId != null && data['product'] is Map) {
            final p = Map<String, dynamic>.from(data['product'] as Map);
            return (
              fromCloud: true,
              results: [
                {
                  ...p,
                  'warehouses': (data['warehouses'] as List<dynamic>? ?? [])
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList(),
                  'total_other_stock': (data['total_other_stock'] as num?)?.toDouble() ?? 0.0,
                  'total_network_stock': (data['total_network_stock'] as num?)?.toDouble() ?? 0.0,
                }
              ],
              error: null,
            );
          }
          final rawResults = data['results'] as List<dynamic>? ?? const [];
          return (
            fromCloud: true,
            results: rawResults
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
            error: null,
          );
        }
      } catch (e) {
        if (!state.isOnline) {
          // Graceful fallback below
        } else {
          return (
            fromCloud: false,
            results: _offlineWarehouseResults(productId: productId, query: query),
            error: 'Gagal mengambil stok gudang terbaru dari server.',
          );
        }
      }
    }

    return (
      fromCloud: false,
      results: _offlineWarehouseResults(productId: productId, query: query),
      error: null,
    );
  }

  List<Map<String, dynamic>> _offlineWarehouseResults({
    int? productId,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    return state.allProducts.where((p) {
      if (productId != null) return p.id == productId;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).take(30).map((p) {
      return {
        'id': p.id,
        'name': p.name,
        'sku': p.sku,
        'barcode': p.barcode,
        'unit': p.unitCode,
        'selling_price': p.sellingPrice,
        'track_stock': p.trackStock,
        'current_store_available': p.stock,
        'total_other_stock': p.otherWarehousesStock,
        'total_network_stock': p.warehouseStocks.isNotEmpty ? p.multiWarehouseStock : p.stock,
        'warehouses': p.warehouseStocks.map((w) => w.toJson()).toList(),
      };
    }).toList();
  }
}
