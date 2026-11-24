part of 'pos_cubit.dart';

extension PosCubitCatalogCrmExt on PosCubit {
  bool get _isLocalStandalone =>
      _offlineDb.getCachedAuthSession()?['is_local_trial'] == true;

  /// Add or update product in Inventory & Stock Opname
  Map<String, dynamic> _buildProductCreatePayload({
    required String name,
    required String sku,
    required String barcode,
    required double sellingPrice,
    required double costPrice,
    required double initialStock,
    int? categoryId,
    int? brandId,
    int? unitId,
    double reorderLevel = 5.0,
    bool trackStock = true,
    bool canBeSold = true,
    String? shelfLocation,
    String? type,
    bool soldByWeight = false,
  }) {
    final rawType = (type ?? 'simple').trim().toLowerCase();
    final normalizedType = (rawType.isEmpty || rawType == 'physical') ? 'simple' : rawType;
    final hasCategory = categoryId != null &&
        categoryId > 0 &&
        (state.categories.isEmpty ||
            state.categories.any((c) => (c['id'] as num?)?.toInt() == categoryId));
    return {
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'selling_price': sellingPrice,
      'cost_price': costPrice,
      'initial_stock': initialStock,
      'category_id': hasCategory ? categoryId : null,
      if (brandId != null && brandId > 0) 'brand_id': brandId,
      if (unitId != null && unitId > 0) 'unit_id': unitId,
      'reorder_level': reorderLevel,
      'track_stock': trackStock,
      'can_be_sold': canBeSold,
      'shelf_location': shelfLocation,
      'type': normalizedType,
      'sold_by_weight': soldByWeight,
    };
  }

  Future<int> _syncPendingLocalProductsToCloud({Map<int, int>? externalIdMap}) async {
    if (_isLocalStandalone) return 0;
    final cached = _offlineDb.getCachedProducts();
    final pending = cached.where((p) {
      final id = (p['id'] as num?)?.toInt() ?? 0;
      final status = (p['sync_status'] ?? 'pending').toString();
      if (status == 'dead_letter') return false;
      return id < 0 || p['is_local_only'] == true || id > 1000000000;
    }).toList();
    if (pending.isEmpty) return 0;

    final productIdMap = <int, int>{};
    final deadLetterProductIds = <int>{};
    int uploaded = 0;

    for (final p in pending) {
      final localId = (p['id'] as num?)?.toInt() ?? 0;
      String idempotencyKey = (p['local_uuid'] ?? '').toString().trim();
      if (idempotencyKey.isEmpty) {
        idempotencyKey = const Uuid().v4();
        final stamped = Map<String, dynamic>.from(p)
          ..['local_uuid'] = idempotencyKey
          ..['is_local_only'] = true;
        await _offlineDb.addOrUpdateLocalProduct(stamped);
      }

      final payload = _buildProductCreatePayload(
        name: (p['name'] ?? 'Produk').toString(),
        sku: (p['sku'] ?? '').toString(),
        barcode: (p['barcode'] ?? '').toString(),
        sellingPrice: (p['selling_price'] as num?)?.toDouble() ?? 0.0,
        costPrice: (p['cost_price'] as num?)?.toDouble() ?? 0.0,
        initialStock: (p['stock'] as num?)?.toDouble() ?? 0.0,
        categoryId: (p['category_id'] as num?)?.toInt(),
        brandId: (p['brand_id'] as num?)?.toInt(),
        unitId: (p['unit_id'] as num?)?.toInt(),
        reorderLevel: (p['reorder_level'] as num?)?.toDouble() ?? 5.0,
        trackStock: p['track_stock'] != false,
        canBeSold: p['can_be_sold'] != false,
        shelfLocation: p['shelf_location']?.toString(),
        type: p['type']?.toString(),
        soldByWeight: p['sold_by_weight'] == true,
      );

      try {
        final res = await _apiClient.dio.post(
          ApiEndpoints.products,
          data: payload,
          options: Options(
            headers: {
              'X-Idempotency-Key': idempotencyKey,
            },
          ),
        );
        final serverId =
            ((res.data is Map ? (res.data['data'] as Map?) : null)?['id'] as num?)?.toInt();
        if (serverId != null && localId != 0) {
          productIdMap[localId] = serverId;
          externalIdMap?[localId] = serverId;
        }
        uploaded++;
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status == 400 || status == 403 || status == 404 || status == 409 || status == 422) {
          // Quarantine permanently rejected product to Dead-Letter Queue without blocking others
          deadLetterProductIds.add(localId);
          final data = e.response?.data;
          final errCode = (data is Map && data['error_code'] != null)
              ? data['error_code'].toString()
              : 'HTTP_$status';
          await _offlineDb.enqueueDeadLetterItem(
            id: idempotencyKey,
            entityType: 'product',
            endpoint: ApiEndpoints.products,
            idempotencyKey: idempotencyKey,
            referenceLabel: 'Produk Baru "${p['name'] ?? 'Tanpa Nama'}"',
            payload: {
              ...payload,
              '_local_product_id': localId,
            },
            httpStatus: status,
            errorCode: errCode,
            errorMessage: ApiClient.extractErrorMessage(e),
            retryCount: 1,
          );
        } else if (ApiClient.isNetworkOfflineError(e) || status == 401) {
          break;
        }
      } catch (_) {}
    }

    if (productIdMap.isNotEmpty || deadLetterProductIds.isNotEmpty) {
      if (productIdMap.isNotEmpty) {
        await _offlineDb.remapOfflineSalesIds(productIdMap, const <int, int>{});
        await _offlineDb.remapHeldSalesProductIds(productIdMap);
      }

      final current = _offlineDb.getCachedProducts();
      final existingIds = current
          .map((p) => (p['id'] as num?)?.toInt() ?? 0)
          .where((id) => !productIdMap.containsKey(id))
          .toSet();

      final updatedList = <Map<String, dynamic>>[];
      for (final raw in current) {
        final item = Map<String, dynamic>.from(raw);
        final id = (item['id'] as num?)?.toInt() ?? 0;
        if (productIdMap.containsKey(id)) {
          final serverId = productIdMap[id]!;
          if (!existingIds.contains(serverId)) {
            item['id'] = serverId;
            item['is_local_only'] = false;
            item.remove('sync_status');
            updatedList.add(item);
            existingIds.add(serverId);
          }
        } else if (deadLetterProductIds.contains(id)) {
          item['sync_status'] = 'dead_letter';
          updatedList.add(item);
        } else {
          updatedList.add(item);
        }
      }
      await _offlineDb.cacheProducts(updatedList);
    }
    return uploaded;
  }

  /// Supports POST /api/v1/products (new) and POST /api/v1/products/{id}/adjust-stock (existing)
  Future<({bool ok, bool syncedToCloud, String? errorMessage})> saveProductInventory(
    ProductModel product, {
    bool isNew = false,
    String notes = 'Stock Opname via OXORA Mobile POS',
  }) async {
    final bool isBrandNew =
        isNew || product.isLocalOnly || product.id <= 0 || product.id > 1000000000;
    final String localUuid =
        (product.localUuid != null && product.localUuid!.trim().isNotEmpty)
            ? product.localUuid!.trim()
            : const Uuid().v4();

    final bool hasLiveNetwork =
        !_isLocalStandalone && await _connectivityService.checkOnline();

    if (hasLiveNetwork) {
      try {
        if (isBrandNew) {
          final res = await _apiClient.dio.post(
            ApiEndpoints.products,
            data: _buildProductCreatePayload(
              name: product.name,
              sku: product.sku,
              barcode: product.barcode,
              sellingPrice: product.sellingPrice,
              costPrice: product.costPrice,
              initialStock: product.stock,
              categoryId: product.categoryId,
              brandId: product.brandId,
              unitId: product.unitId,
              reorderLevel: product.reorderLevel,
              trackStock: product.trackStock,
              canBeSold: product.canBeSold,
              shelfLocation: product.shelfLocation,
              type: product.type,
              soldByWeight: product.soldByWeight,
            ),
            options: Options(
              headers: {
                'X-Idempotency-Key': localUuid,
              },
            ),
          );
          final serverId =
              ((res.data is Map ? (res.data['data'] as Map?) : null)?['id'] as num?)?.toInt();
          if (product.id < 0 || product.isLocalOnly || product.id > 1000000000) {
            if (serverId != null && product.id != 0) {
              await _offlineDb.remapOfflineSalesIds({product.id: serverId}, const <int, int>{});
              await _offlineDb.remapHeldSalesProductIds({product.id: serverId});
            }
            final remaining = _offlineDb.getCachedProducts().where((p) {
              return ((p['id'] as num?)?.toInt() ?? 0) != product.id;
            }).toList();
            await _offlineDb.cacheProducts(remaining);
          }
        } else {
          final normalizedType = (product.type.trim().toLowerCase() == 'physical')
              ? 'simple'
              : product.type.trim().toLowerCase();
          await _apiClient.dio.post(
            ApiEndpoints.adjustProductStock(product.id),
            data: {
              'new_quantity': product.stock,
              'name': product.name,
              'barcode': product.barcode,
              'selling_price': product.sellingPrice,
              'unit_cost': product.costPrice,
              'category_id': product.categoryId > 0 ? product.categoryId : null,
              if (product.brandId != null && product.brandId! > 0) 'brand_id': product.brandId,
              if (product.unitId != null && product.unitId! > 0) 'unit_id': product.unitId,
              'reorder_level': product.reorderLevel,
              'track_stock': product.trackStock,
              'can_be_sold': product.canBeSold,
              if (normalizedType.isNotEmpty) 'type': normalizedType,
              'shelf_location': product.shelfLocation,
              'notes': notes,
            },
          );
        }
        await syncWithCloud(force: false);
        return (ok: true, syncedToCloud: true, errorMessage: null);
      } catch (e) {
        if (!ApiClient.isNetworkOfflineError(e)) {
          return (
            ok: false,
            syncedToCloud: false,
            errorMessage: ApiClient.extractErrorMessage(e),
          );
        }
      }
    }

    // Local fallback strictly for offline / standalone mode
    final prevStock = state.allProducts
            .where((p) => p.id == product.id)
            .firstOrNull
            ?.stock ??
        0.0;
    final int localId = (isBrandNew && product.id >= 0)
        ? -DateTime.now().millisecondsSinceEpoch
        : product.id;
    final map = <String, dynamic>{
      ...product.toJson(),
      'id': localId,
      'local_uuid': localUuid,
      if (isBrandNew || localId < 0) 'is_local_only': true,
    };
    await _offlineDb.addOrUpdateLocalProduct(map);
    if (product.trackStock) {
      final delta = isBrandNew ? product.stock : (product.stock - prevStock);
      if (delta.abs() > 0.0001 || isBrandNew) {
        await _offlineDb.recordLocalStockMovement(
          productId: localId,
          productName: product.name,
          sku: product.sku,
          unitCode: product.unitCode,
          type: isBrandNew ? 'initial_stock' : 'stock_opname',
          quantityDelta: delta,
          quantityAfter: product.stock,
          unitCost: product.costPrice,
          notes: notes,
        );
      }
    }
    final updated = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    _emitState(state.copyWith(
      allProducts: updated,
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));
    if (!_isLocalStandalone) {
      _scheduleBackoffSyncIfNeeded();
    }
    return (ok: true, syncedToCloud: false, errorMessage: null);
  }

  /// Create or update Customer & Member (POST/PUT /api/v1/customers)
  Future<Map<String, dynamic>> saveCustomer(
    Map<String, dynamic> payload, {
    int? id,
    bool selectAfterSave = false,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = id != null && id > 0
            ? await _apiClient.dio.put(ApiEndpoints.customerDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.customers, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalCustomer(saved);
        final updatedList = _offlineDb.getCachedCustomers();
        final shouldSelect = selectAfterSave || (state.selectedCustomer?['id'] == saved['id']);
        _emitState(state.copyWith(
          customers: updatedList,
          selectedCustomer: shouldSelect ? saved : state.selectedCustomer,
        ));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (id != null && id > 0 && state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }

    final resolvedId = id ?? -DateTime.now().millisecondsSinceEpoch;
    final existingIdx = _offlineDb.getCachedCustomers().indexWhere(
      (c) => (c['id'] as num?)?.toInt() == resolvedId,
    );
    final existing = existingIdx >= 0 ? _offlineDb.getCachedCustomers()[existingIdx] : <String, dynamic>{};
    final localEntry = <String, dynamic>{
      ...existing,
      'id': resolvedId,
      ...payload,
      'loyalty_points': payload['loyalty_points'] ?? existing['loyalty_points'] ?? 0,
      'outstanding_balance': existing['outstanding_balance'] ?? 0.0,
      if (resolvedId < 0) 'is_local_only': true,
    };
    await _offlineDb.addOrUpdateLocalCustomer(localEntry);
    final updatedList = _offlineDb.getCachedCustomers();
    final shouldSelect = selectAfterSave || (state.selectedCustomer?['id'] == localEntry['id']);
    _emitState(state.copyWith(
      customers: updatedList,
      selectedCustomer: shouldSelect ? localEntry : state.selectedCustomer,
    ));
    return {'success': true, 'offline': true, 'data': localEntry};
  }

  /// Create or update Supplier (POST/PUT /api/v1/suppliers)
  Future<Map<String, dynamic>> saveSupplier(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = id != null && id > 0
            ? await _apiClient.dio.put(ApiEndpoints.supplierDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.suppliers, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalSupplier(saved);
        _emitState(state.copyWith(suppliers: _offlineDb.getCachedSuppliers()));
        return {'success': true, 'data': saved};
      } catch (_) {}
    }

    final resolvedId = id ?? -DateTime.now().millisecondsSinceEpoch;
    final localEntry = <String, dynamic>{
      'id': resolvedId,
      ...payload,
      if (resolvedId < 0) 'is_local_only': true,
    };
    await _offlineDb.addOrUpdateLocalSupplier(localEntry);
    _emitState(state.copyWith(suppliers: _offlineDb.getCachedSuppliers()));
    return {'success': true, 'offline': true, 'data': localEntry};
  }

  /// Record Quick Stock In Purchase (POST /api/v1/purchases/quick-stock-in)
  Future<Map<String, dynamic>> submitQuickStockIn(Map<String, dynamic> payload) async {
    if (!_isLocalStandalone) {
      try {
        final res = await _apiClient.dio.post(ApiEndpoints.quickStockIn, data: payload);
        await syncWithCloud(force: false);
        return {'success': true, 'data': res.data['data']};
      } catch (_) {}
    }

    // Standalone / offline stock-in + optional credit payable recording
    final pid = (payload['product_id'] as num?)?.toInt();
    final sid = (payload['supplier_id'] as num?)?.toInt();
    final qty = (payload['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (payload['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final payStatus = (payload['payment_status'] ?? payload['payment_type'] ?? 'paid').toString().toLowerCase();

    if (pid != null && qty > 0) {
      final cached = _offlineDb.getCachedProducts();
      final idx = cached.indexWhere((p) => (p['id'] as num?)?.toInt() == pid);
      if (idx >= 0) {
        final item = Map<String, dynamic>.from(cached[idx]);
        final oldStock = (item['stock'] as num?)?.toDouble() ?? 0.0;
        item['stock'] = oldStock + qty;
        if (unitCost > 0) {
          item['cost_price'] = unitCost;
        }
        await _offlineDb.addOrUpdateLocalProduct(item);
        final updated = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
        _emitState(state.copyWith(allProducts: updated));
      }
    }

    final totalCost = qty * unitCost;
    if (totalCost > 0 && (payStatus == 'credit' || payStatus == 'unpaid' || payStatus == 'tempo' || payStatus == 'hutang')) {
      final sup = state.suppliers.firstWhere(
        (s) => (s['id'] as num?)?.toInt() == sid,
        orElse: () => {'id': sid, 'name': 'Supplier', 'phone': ''},
      );
      await _offlineDb.addLocalPayable(
        supplierId: sid,
        supplierName: (sup['name'] ?? 'Supplier').toString(),
        supplierPhone: sup['phone']?.toString(),
        totalAmount: totalCost,
        paidAmount: 0.0,
        dueDate: payload['due_date']?.toString(),
        invoiceNumber: payload['invoice_number']?.toString(),
        notes: payload['notes']?.toString(),
      );
    } else if (totalCost > 0 && (payStatus == 'paid' || payStatus == 'tunai' || payStatus == 'cash')) {
      if (_offlineDb.getCurrentLocalShift() != null) {
        await _offlineDb.addLocalShiftCashEntry(
          type: 'pay_out',
          amount: totalCost,
          reason: 'Belanja Stok Tunai (${payload['invoice_number'] ?? 'Stok Masuk'})',
        );
      }
    }

    return {'success': true, 'offline': true};
  }

  /// One-Click Local-to-Cloud Data Migration when upgrading Standalone Mode to OXORA Cloud
  Future<Map<String, int>> migrateLocalStandaloneDataToCloud() async {
    int uploadedProducts = 0;
    int uploadedCustomers = 0;
    int uploadedSuppliers = 0;
    int syncedSales = 0;

    final productIdMap = <int, int>{};
    final customerIdMap = <int, int>{};

    // 1. Migrate local-only suppliers
    final suppliers = _offlineDb.getCachedSuppliers();
    for (final s in suppliers) {
      final id = (s['id'] as num?)?.toInt() ?? 0;
      if (id < 0 || s['is_local_only'] == true) {
        try {
          await _apiClient.dio.post(
            ApiEndpoints.suppliers,
            data: {
              'name': s['name'] ?? 'Supplier',
              'phone': s['phone'] ?? '-',
              'address': s['address'] ?? '',
              'email': s['email'] ?? '',
            },
          );
          uploadedSuppliers++;
        } catch (_) {}
      }
    }

    // 2. Migrate local-only customers & map old negative IDs -> new server IDs
    final customers = _offlineDb.getCachedCustomers();
    for (final c in customers) {
      final id = (c['id'] as num?)?.toInt() ?? 0;
      if (id < 0 || c['is_local_only'] == true) {
        try {
          final res = await _apiClient.dio.post(
            ApiEndpoints.customers,
            data: {
              'name': c['name'] ?? 'Pelanggan',
              'phone': c['phone'] ?? '-',
              'email': c['email'] ?? '',
              'address': c['address'] ?? '',
            },
          );
          final serverId = ((res.data['data'] as Map?)?['id'] as num?)?.toInt();
          if (serverId != null && id != 0) {
            customerIdMap[id] = serverId;
          }
          uploadedCustomers++;
        } catch (_) {}
      }
    }

    // 3. Migrate local-only products & map old negative IDs -> new server IDs
    uploadedProducts = await _syncPendingLocalProductsToCloud(externalIdMap: productIdMap);

    // 4. Remap IDs inside offline sales & held sales, then push sales + receivables + expenses + shift closures
    await _offlineDb.remapOfflineSalesIds(productIdMap, customerIdMap);
    await _offlineDb.remapHeldSalesProductIds(productIdMap);
    final pendingReceivablesBefore = _offlineDb.pendingReceivablePaymentsCount;
    final pendingExpensesBefore = _offlineDb.pendingLocalExpensesCount;
    syncedSales = await _offlineDb.syncOfflineQueue(_apiClient);
    final syncedReceivables =
        (pendingReceivablesBefore - _offlineDb.pendingReceivablePaymentsCount).clamp(0, pendingReceivablesBefore);
    final syncedExpenses =
        (pendingExpensesBefore - _offlineDb.pendingLocalExpensesCount).clamp(0, pendingExpensesBefore);

    final cachedAuth = _offlineDb.getCachedAuthSession();
    final sub = (cachedAuth?['tenant_subdomain'] ?? '').toString().trim().toLowerCase();
    if (sub.isNotEmpty) {
      await _offlineDb.setActiveTenantIdentity('cloud:$sub');
    }

    // 5. Refresh clean authoritative Cloud catalog
    await syncWithCloud(force: true, preserveActiveCart: true);

    return {
      'products': uploadedProducts,
      'customers': uploadedCustomers,
      'suppliers': uploadedSuppliers,
      'sales': syncedSales,
      'receivables': syncedReceivables,
      'expenses': syncedExpenses,
    };
  }
}
