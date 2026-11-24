part of 'pos_cubit.dart';

extension PosCubitSyncExt on PosCubit {
  Future<void> _startConnectivityListener() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityService.onOnlineChanged.listen((online) async {
      if (isClosed) return;
      if (!online) {
        _wasOffline = true;
        _emitState(state.copyWith(isOnline: false, isSyncingOfflineQueue: false));
        return;
      }

      final transitionedFromOffline = _wasOffline;
      _wasOffline = false;
      _backoffAttempt = 0;
      _emitState(state.copyWith(isOnline: true));

      if (transitionedFromOffline || _computePendingRetryCount() > 0) {
        await _triggerReactiveAutoSync();
      }
    });
  }

  /// Lightweight exponential-backoff retry timer (15s -> 30s -> 60s -> 120s) that runs ONLY
  /// when unsynced non-conflict offline items exist (cancels immediately when queue == 0).
  /// Guarantees automatic recovery when branch Wi-Fi stays up while ISP WAN drops and recovers.
  void _scheduleBackoffSyncIfNeeded() {
    _backoffRetryTimer?.cancel();
    _backoffRetryTimer = null;
    if (_isLocalStandalone || isClosed) return;
    if (_computePendingRetryCount() <= 0) {
      _backoffAttempt = 0;
      return;
    }

    const backoffSeconds = [15, 30, 60, 120];
    final idx = _backoffAttempt.clamp(0, backoffSeconds.length - 1);
    final delay = Duration(seconds: backoffSeconds[idx]);
    _backoffRetryTimer = Timer(delay, () async {
      if (isClosed || _isLocalStandalone) return;
      final online = await _connectivityService.checkOnline();
      if (!online) {
        _backoffAttempt = (_backoffAttempt + 1).clamp(0, backoffSeconds.length - 1);
        _scheduleBackoffSyncIfNeeded();
        return;
      }
      await _triggerReactiveAutoSync();
    });
  }

  /// Non-blocking reactive background sync when internet returns:
  /// 1) Probe best tier (LAN Edge -> Cloud Master) if Edge URL configured
  /// 2) Push local offline products first (remap temp IDs)
  /// 3) Drain idempotent offline queues (sales -> receivables -> expenses -> shift closures)
  /// 4) Refresh catalog & balances silently without blocking active cashier cart/UI
  Future<void> _triggerReactiveAutoSync() async {
    if (_isAutoSyncRunning || isClosed || _isLocalStandalone) return;
    final token = await _apiClient.getToken();
    if (token == null || token.isEmpty) return;

    _isAutoSyncRunning = true;
    _emitState(state.copyWith(isOnline: true, isSyncingOfflineQueue: true));
    try {
      if (_apiClient.edgeDiscovery.getEdgeBaseUrl() != null) {
        await _apiClient.switchToBestEndpoint();
      }
      final uploadedProducts = await _syncPendingLocalProductsToCloud();
      final synced = uploadedProducts + await _offlineDb.syncOfflineQueue(_apiClient);
      if (synced > 0) {
        _backoffAttempt = 0;
      } else if (_computePendingRetryCount() > 0) {
        _backoffAttempt = (_backoffAttempt + 1).clamp(0, 3);
      }
      await syncWithCloud(force: false, preserveActiveCart: true, silent: true);
    } catch (_) {
      _backoffAttempt = (_backoffAttempt + 1).clamp(0, 3);
    } finally {
      _isAutoSyncRunning = false;
      if (!isClosed) {
        _emitState(state.copyWith(
          isSyncingOfflineQueue: false,
          salesHistory: _offlineDb.getLocalSalesHistory(),
          localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
          deadLetterItems: _offlineDb.getDeadLetterItems(),
          offlinePendingCount: _computePendingBadgeCount(),
        ));
        _scheduleBackoffSyncIfNeeded();
      }
    }
  }

  /// Fetch all pages of a paginated Cloud API collection cleanly into SQLite
  /// so first-time master data restore never truncates stores with > 200 items.
  Future<List<Map<String, dynamic>>?> _fetchAllPaginated(
    String endpoint, {
    int perPage = 200,
    int maxPages = 25,
  }) async {
    final collected = <Map<String, dynamic>>[];
    int page = 1;
    int lastPage = 1;

    while (page <= lastPage && page <= maxPages) {
      final res = await _apiClient.dio.get(
        endpoint,
        queryParameters: {'per_page': perPage, if (page > 1) 'page': page},
      );
      final body = res.data;
      if (body is! Map) break;
      final rawList = body['data'] as List<dynamic>?;
      if (rawList == null) {
        return page == 1 ? null : collected;
      }
      collected.addAll(rawList.map((e) => Map<String, dynamic>.from(e as Map)));

      final meta = body['meta'];
      if (meta is Map && meta['last_page'] is num) {
        lastPage = (meta['last_page'] as num).toInt();
      } else if (body['last_page'] is num) {
        lastPage = (body['last_page'] as num).toInt();
      } else {
        break;
      }
      if (rawList.isEmpty) break;
      page++;
    }

    return collected;
  }

  /// Fast < 5ms indexed SQLite search helper
  Future<List<ProductModel>> searchProductsFast(String query) async {
    final rows = await _offlineDb.searchProductSql(query);
    return rows.map(ProductModel.fromJson).toList();
  }

  /// Authoritative Cloud Sync: deduplicates concurrent sync requests, drains offline queue,
  /// then fetches full master data snapshot (with progress indicators on first-time restore).
  Future<void> syncWithCloud({
    bool force = false,
    bool preserveActiveCart = false,
    bool silent = false,
  }) async {
    if (_activeCloudSyncFuture != null) {
      await _activeCloudSyncFuture;
      if (!force) return;
    }

    final syncFuture = _performSyncWithCloud(
      force: force,
      preserveActiveCart: preserveActiveCart,
      silent: silent,
    );
    _activeCloudSyncFuture = syncFuture;
    try {
      await syncFuture;
    } finally {
      if (identical(_activeCloudSyncFuture, syncFuture)) {
        _activeCloudSyncFuture = null;
      }
    }
  }

  Future<void> _performSyncWithCloud({
    bool force = false,
    bool preserveActiveCart = false,
    bool silent = false,
  }) async {
    if (_isLocalStandalone) {
      final resolvedVertical = PosCubit._resolveInitialVertical(_offlineDb);
      final resolvedCaps = VerticalConfig.getCapabilities(resolvedVertical);
      final localProds = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
      _emitState(state.copyWith(
        isLoading: false,
        isInitialRestoring: false,
        initialRestoreProgress: 0.0,
        clearInitialRestoreStep: true,
        isSyncingOfflineQueue: false,
        currentVertical: resolvedVertical,
        posMode: resolvedVertical == BusinessVertical.restaurant ? 'restaurant' : 'retail',
        orderType: resolvedCaps.hasDineInTakeawayOrderType
            ? (state.orderType == 'retail' ? 'dine_in' : state.orderType)
            : 'retail',
        allProducts: localProds,
        categories: _offlineDb.getCachedCategories(),
        customers: _offlineDb.getCachedCustomers(),
        suppliers: _offlineDb.getCachedSuppliers(),
        paymentMethods: _offlineDb.getCachedPaymentMethods(),
        brands: _offlineDb.getCachedBrands(),
        units: _offlineDb.getCachedUnits(),
        returnReasons: _offlineDb.getCachedReturnReasons(),
        expenseCategories: _offlineDb.getCachedExpenseCategories(),
        customerGroups: _offlineDb.getCachedCustomerGroups(),
        heldCarts: PosCubit._hydrateHeldCarts(_offlineDb.getHeldSales(), catalogProducts: localProds),
        salesHistory: _offlineDb.getLocalSalesHistory(),
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      return;
    }

    // Fast-path offline guard: never stall firing 12 sequential GETs when device has no network.
    final hasConnectivity = await _connectivityService.checkOnline();
    if (!hasConnectivity) {
      _wasOffline = true;
      _emitState(state.copyWith(
        isLoading: false,
        isOnline: false,
        isInitialRestoring: false,
        initialRestoreProgress: 0.0,
        clearInitialRestoreStep: true,
        isSyncingOfflineQueue: false,
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      _scheduleBackoffSyncIfNeeded();
      return;
    }

    final isInitialRestore = !_offlineDb.hasMasterDataSnapshot;
    _emitState(state.copyWith(
      isLoading: silent ? state.isLoading : true,
      isInitialRestoring: isInitialRestore,
      initialRestoreProgress: isInitialRestore ? 0.10 : 0.0,
      initialRestoreStep:
          isInitialRestore ? 'Menarik katalog produk & harga ke SQLite lokal...' : null,
      isSyncingOfflineQueue: state.offlinePendingCount > 0 || state.isSyncingOfflineQueue,
    ));

    try {
      // 0a. Push any offline-queued local products to Cloud before syncing sales & fetching catalog
      await _syncPendingLocalProductsToCloud();

      // 0b. Drain pending offline transactions (mutex-guarded & idempotent)
      await _offlineDb.syncOfflineQueue(_apiClient);

      // 1. Fetch ALL pages of real products from server into SQLite
      final mapped = await _fetchAllPaginated(ApiEndpoints.products, perPage: 200);
      List<ProductModel> products = [];
      bool productsFetchedFromServer = false;
      if (mapped != null) {
        productsFetchedFromServer = true;
        final stillPendingLocal = _offlineDb.getCachedProducts().where((p) {
          final id = (p['id'] as num?)?.toInt() ?? 0;
          final isLocalCandidate = id < 0 || p['is_local_only'] == true || id > 1000000000;
          if (!isLocalCandidate) return false;
          final localSku = (p['sku'] ?? '').toString().trim().toLowerCase();
          if (localSku.isNotEmpty &&
              mapped.any((srv) => (srv['sku'] ?? '').toString().trim().toLowerCase() == localSku)) {
            return false;
          }
          return true;
        }).toList();
        if (stillPendingLocal.isNotEmpty) {
          mapped.insertAll(0, stillPendingLocal);
        }
        await _offlineDb.cacheProducts(mapped);
        products = mapped.map(ProductModel.fromJson).toList();
      }

      if (isInitialRestore && !isClosed) {
        _emitState(state.copyWith(
          allProducts: productsFetchedFromServer ? products : state.allProducts,
          initialRestoreProgress: 0.38,
          initialRestoreStep: 'Menarik kategori & metode pembayaran...',
        ));
      }

      // 2. Fetch real categories from server or derive directly from loaded products
      List<Map<String, dynamic>> categories = [];
      try {
        final catRes = await _apiClient.dio.get(ApiEndpoints.categories);
        final rawCats = catRes.data['data'] as List<dynamic>?;
        if (rawCats != null && rawCats.isNotEmpty) {
          categories = rawCats.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      // If categories is empty, extract dynamically from products
      if (categories.isEmpty && products.isNotEmpty) {
        final seen = <int>{};
        for (final p in products) {
          if (p.categoryId > 0 && seen.add(p.categoryId)) {
            categories.add({
              'id': p.categoryId,
              'name': p.categoryName,
              'color': '#2563EB',
              'products_count': products.where((item) => item.categoryId == p.categoryId).length,
            });
          }
        }
      }

      // Always ensure 'Semua' option at index 0
      categories.removeWhere((c) => c['id'] == 0 || c['name'] == 'Semua');
      categories.insert(0, {
        'id': 0,
        'name': 'Semua',
        'color': '#2563EB',
        'products_count': products.length,
      });
      await _offlineDb.cacheCategories(categories);

      if (isInitialRestore && !isClosed) {
        _emitState(state.copyWith(
          categories: categories,
          initialRestoreProgress: 0.56,
          initialRestoreStep: 'Menarik data pelanggan & pemasok...',
        ));
      }

      // 3. Fetch real customers from server (paginated)
      List<Map<String, dynamic>> customers = _offlineDb.getCachedCustomers();
      try {
        final allCust = await _fetchAllPaginated(ApiEndpoints.customers, perPage: 200);
        if (allCust != null) {
          customers = allCust;
          await _offlineDb.cacheCustomers(customers);
        }
      } catch (_) {}

      // 4. Fetch real suppliers from server (paginated)
      List<Map<String, dynamic>> suppliers = _offlineDb.getCachedSuppliers();
      try {
        final allSup = await _fetchAllPaginated(ApiEndpoints.suppliers, perPage: 200);
        if (allSup != null) {
          suppliers = allSup;
          await _offlineDb.cacheSuppliers(suppliers);
        }
      } catch (_) {}

      if (isInitialRestore && !isClosed) {
        _emitState(state.copyWith(
          customers: customers,
          suppliers: suppliers,
          initialRestoreProgress: 0.76,
          initialRestoreStep: 'Menarik riwayat nota, metode bayar & profil toko...',
        ));
      }

      // 5. Fetch real sales history from server
      List<Map<String, dynamic>> sales = [];
      try {
        final salesRes = await _apiClient.dio.get(ApiEndpoints.salesHistory, queryParameters: {'per_page': 50});
        final rawSales = salesRes.data['data'] as List<dynamic>?;
        if (rawSales != null) {
          sales = rawSales.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
      await _offlineDb.cacheSalesHistory(sales);

      // 6. Fetch cloud-held carts, payment methods, and return reasons
      final catalogProducts = productsFetchedFromServer
          ? products
          : _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
      final persistedLocalHeld = PosCubit._hydrateHeldCarts(
        _offlineDb.getHeldSales(),
        catalogProducts: catalogProducts,
      );
      List<Map<String, dynamic>> mergedHeldCarts = persistedLocalHeld.isNotEmpty
          ? persistedLocalHeld
          : (force ? [] : state.heldCarts);
      try {
        final heldRes = await _apiClient.dio.get(ApiEndpoints.heldSales);
        final rawHeld = heldRes.data['data'] as List<dynamic>?;
        if (rawHeld != null) {
          final serverHeld = <Map<String, dynamic>>[];
          for (final raw in rawHeld) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw);
            final rawItems = (map['items'] as List<dynamic>? ?? []);
            final cartItems = <CartItemModel>[];
            for (final itemRaw in rawItems) {
              if (itemRaw is! Map) continue;
              final pid = (itemRaw['product_id'] as num?)?.toInt() ?? 0;
              final matched = catalogProducts.where((p) => p.id == pid).toList();
              final prod = matched.isNotEmpty
                  ? matched.first
                  : ProductModel(
                      id: pid,
                      name: (itemRaw['product_name'] ?? 'Produk').toString(),
                      sku: (itemRaw['sku'] ?? 'SKU').toString(),
                      barcode: '',
                      sellingPrice: (itemRaw['unit_price'] as num?)?.toDouble() ?? 0,
                      stock: 99,
                    );
              cartItems.add(CartItemModel(
                saleItemId: (itemRaw['sale_item_id'] ?? itemRaw['id']) is num
                    ? ((itemRaw['sale_item_id'] ?? itemRaw['id']) as num).toInt()
                    : null,
                product: prod,
                quantity: (itemRaw['quantity'] as num?)?.toDouble() ?? 1,
                unitPrice: (itemRaw['unit_price'] as num?)?.toDouble() ?? prod.sellingPrice,
                discountAmount: (itemRaw['discount_amount'] as num?)?.toDouble() ?? 0,
                notes: itemRaw['notes']?.toString(),
              ));
            }
            serverHeld.add({
              'id': map['id'],
              'number': map['number'] ?? 'HOLD-${map['id']}',
              'held_label': map['held_label'] ?? map['table_name'] ?? 'Pesanan Ditahan',
              'table_name': map['table_name'],
              'table_id': map['table_id'],
              'notes': map['notes'],
              'service_charge_amount': (map['service_charge_amount'] as num?)?.toDouble() ?? 0.0,
              'subtotal': (map['grand_total'] as num?)?.toDouble() ??
                  (map['subtotal'] as num?)?.toDouble() ??
                  0.0,
              'held_at': (map['sale_datetime'] ?? '').toString(),
              'is_synced': 1,
              'cart_items': cartItems,
            });
          }
          final serverIds = serverHeld.map((e) => e['id']).toSet();
          final localSource = persistedLocalHeld.isNotEmpty ? persistedLocalHeld : state.heldCarts;
          // Always preserve unsynced local-only held carts so offline parked orders are never lost!
          final localOnly = localSource
              .where((l) => !serverIds.contains(l['id']) && l['is_synced'] != 1)
              .toList();
          mergedHeldCarts = [...serverHeld, ...localOnly];
          await _offlineDb.replaceHeldSales(
            mergedHeldCarts.map(PosCubit._serializeHeldEntry).toList(),
          );
        }
      } catch (_) {}

      List<Map<String, dynamic>> paymentMethods = _offlineDb.getCachedPaymentMethods();
      if (paymentMethods.isEmpty) {
        paymentMethods = state.paymentMethods;
      }
      try {
        final pmRes = await _apiClient.dio.get(ApiEndpoints.paymentMethods);
        final rawPm = pmRes.data['data'] as List<dynamic>?;
        if (rawPm != null && rawPm.isNotEmpty) {
          paymentMethods = rawPm.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await _offlineDb.cachePaymentMethods(paymentMethods);
        }
      } catch (_) {}

      List<Map<String, dynamic>> returnReasons = _offlineDb.getCachedReturnReasons();
      try {
        final rrRes = await _apiClient.dio.get(ApiEndpoints.returnReasons);
        final rawRr = rrRes.data['data'] as List<dynamic>?;
        if (rawRr != null && rawRr.isNotEmpty) {
          returnReasons = rawRr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await _offlineDb.cacheReturnReasons(returnReasons);
        }
      } catch (_) {}

      if (isInitialRestore && !isClosed) {
        _emitState(state.copyWith(
          paymentMethods: paymentMethods,
          initialRestoreProgress: 0.92,
          initialRestoreStep: 'Menyelesaikan sinkronisasi referensi cabang...',
        ));
      }

      final taxonomies = await _syncExtendedTaxonomies();
      if (force) {
        try {
          final meRes = await _apiClient.dio.get(ApiEndpoints.me);
          final meData = meRes.data is Map ? meRes.data['data'] : null;
          if (meData is Map && meData['numbering_formats'] is Map) {
            await _offlineDb.cacheNumberingFormats(
              Map<String, dynamic>.from(meData['numbering_formats'] as Map),
            );
          }
        } catch (_) {}
      }
      if (isClosed) return;

      final resolvedVertical = PosCubit._resolveInitialVertical(_offlineDb);
      final resolvedCaps = VerticalConfig.getCapabilities(resolvedVertical);
      _emitState(state.copyWith(
        isLoading: false,
        isOnline: _apiClient.isOnline,
        isSyncingOfflineQueue: false,
        isInitialRestoring: false,
        initialRestoreProgress: 1.0,
        clearInitialRestoreStep: true,
        activeNodeCode: _apiClient.edgeDiscovery.getMobileNodeCode(),
        currentVertical: resolvedVertical,
        posMode: resolvedVertical == BusinessVertical.restaurant ? 'restaurant' : 'retail',
        orderType: resolvedCaps.hasDineInTakeawayOrderType
            ? (state.orderType == 'retail' ? 'dine_in' : state.orderType)
            : 'retail',
        allProducts: catalogProducts,
        categories: categories,
        customers: customers,
        suppliers: suppliers,
        brands: taxonomies['brands'],
        units: taxonomies['units'],
        expenseCategories: taxonomies['expense_categories'],
        customerGroups: taxonomies['customer_groups'],
        salesHistory: sales,
        heldCarts: mergedHeldCarts,
        paymentMethods: paymentMethods,
        returnReasons: returnReasons,
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
        cart: (force && !preserveActiveCart) ? [] : state.cart,
      ));
      _scheduleBackoffSyncIfNeeded();
    } catch (_) {
      final online = await _connectivityService.checkOnline();
      if (isClosed) return;
      _wasOffline = !online;
      _emitState(state.copyWith(
        isLoading: false,
        isOnline: online && _apiClient.isOnline,
        isSyncingOfflineQueue: false,
        isInitialRestoring: false,
        initialRestoreProgress: 0.0,
        clearInitialRestoreStep: true,
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      _scheduleBackoffSyncIfNeeded();
    }
  }
}
