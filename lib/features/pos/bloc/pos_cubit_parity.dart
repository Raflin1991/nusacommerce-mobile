part of 'pos_cubit.dart';

extension PosCubitParityExt on PosCubit {
  Future<Map<String, List<Map<String, dynamic>>>> _syncExtendedTaxonomies() async {
    var brands = _offlineDb.getCachedBrands();
    var units = _offlineDb.getCachedUnits();
    var expenseCategories = _offlineDb.getCachedExpenseCategories();
    var customerGroups = _offlineDb.getCachedCustomerGroups();

    if (_isLocalStandalone) {
      return {
        'brands': brands,
        'units': units,
        'expense_categories': expenseCategories,
        'customer_groups': customerGroups,
      };
    }

    try {
      final res = await _apiClient.dio.get(ApiEndpoints.brands);
      final raw = res.data['data'] as List<dynamic>?;
      if (raw != null) {
        brands = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _offlineDb.cacheBrands(brands);
      }
    } catch (_) {}

    try {
      final res = await _apiClient.dio.get(ApiEndpoints.units);
      final raw = res.data['data'] as List<dynamic>?;
      if (raw != null) {
        units = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _offlineDb.cacheUnits(units);
      }
    } catch (_) {}

    try {
      final res = await _apiClient.dio.get(ApiEndpoints.expenseCategories);
      final raw = res.data['data'] as List<dynamic>?;
      if (raw != null) {
        expenseCategories = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _offlineDb.cacheExpenseCategories(expenseCategories);
      }
    } catch (_) {}

    try {
      final res = await _apiClient.dio.get(ApiEndpoints.customerGroups);
      final raw = res.data['data'] as List<dynamic>?;
      if (raw != null) {
        customerGroups = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _offlineDb.cacheCustomerGroups(customerGroups);
      }
    } catch (_) {}

    return {
      'brands': brands,
      'units': units,
      'expense_categories': expenseCategories,
      'customer_groups': customerGroups,
    };
  }

  Future<void> refreshTaxonomies() async {
    final data = await _syncExtendedTaxonomies();
    var categories = _offlineDb.getCachedCategories();
    var returnReasons = _offlineDb.getCachedReturnReasons();
    if (!_isLocalStandalone) {
      try {
        final catRes = await _apiClient.dio.get(ApiEndpoints.categories);
        final rawCats = catRes.data['data'] as List<dynamic>?;
        if (rawCats != null) {
          categories = rawCats.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          categories.removeWhere((c) => c['id'] == 0 || c['name'] == 'Semua');
          categories.insert(0, {
            'id': 0,
            'name': 'Semua',
            'color': '#2563EB',
            'products_count': state.allProducts.length,
          });
          await _offlineDb.cacheCategories(categories);
        }
      } catch (_) {}
      try {
        final rrRes = await _apiClient.dio.get(ApiEndpoints.returnReasons);
        final rawRr = rrRes.data['data'] as List<dynamic>?;
        if (rawRr != null) {
          returnReasons = rawRr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await _offlineDb.cacheReturnReasons(returnReasons);
        }
      } catch (_) {}
    }

    _emitState(state.copyWith(
      categories: categories,
      brands: data['brands'],
      units: data['units'],
      expenseCategories: data['expense_categories'],
      customerGroups: data['customer_groups'],
      returnReasons: returnReasons,
    ));
  }

  Future<Map<String, dynamic>> saveCategory(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = (id != null && id > 0)
            ? await _apiClient.dio.put(ApiEndpoints.categoryDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.categories, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalCategory(saved);
        _emitState(state.copyWith(categories: _offlineDb.getCachedCategories()));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    final saved = await _offlineDb.addOrUpdateLocalCategory({
      if (id != null) 'id': id,
      ...payload,
    });
    _emitState(state.copyWith(categories: _offlineDb.getCachedCategories()));
    return {'success': true, 'data': saved};
  }

  Future<Map<String, dynamic>> deleteCategory(int id) async {
    if (!_isLocalStandalone && id > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.categoryDetail(id));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalCategory(id);
    _emitState(state.copyWith(categories: _offlineDb.getCachedCategories()));
    return {'success': true};
  }

  Future<Map<String, dynamic>> saveBrand(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = (id != null && id > 0)
            ? await _apiClient.dio.put(ApiEndpoints.brandDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.brands, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalBrand(saved);
        _emitState(state.copyWith(brands: _offlineDb.getCachedBrands()));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    final saved = await _offlineDb.addOrUpdateLocalBrand({
      if (id != null) 'id': id,
      ...payload,
    });
    _emitState(state.copyWith(brands: _offlineDb.getCachedBrands()));
    return {'success': true, 'data': saved};
  }

  Future<Map<String, dynamic>> deleteBrand(int id) async {
    if (!_isLocalStandalone && id > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.brandDetail(id));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalBrand(id);
    _emitState(state.copyWith(brands: _offlineDb.getCachedBrands()));
    return {'success': true};
  }

  Future<Map<String, dynamic>> saveUnit(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = (id != null && id > 0)
            ? await _apiClient.dio.put(ApiEndpoints.unitDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.units, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalUnit(saved);
        _emitState(state.copyWith(units: _offlineDb.getCachedUnits()));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    final saved = await _offlineDb.addOrUpdateLocalUnit({
      if (id != null) 'id': id,
      ...payload,
    });
    _emitState(state.copyWith(units: _offlineDb.getCachedUnits()));
    return {'success': true, 'data': saved};
  }

  Future<Map<String, dynamic>> deleteUnit(int id) async {
    if (!_isLocalStandalone && id > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.unitDetail(id));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalUnit(id);
    _emitState(state.copyWith(units: _offlineDb.getCachedUnits()));
    return {'success': true};
  }

  Future<Map<String, dynamic>> deleteProduct(int productId) async {
    if (!_isLocalStandalone && productId > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.productDetail(productId));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalProduct(productId);
    final updated = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    _emitState(state.copyWith(allProducts: updated));
    return {'success': true};
  }

  Future<Map<String, dynamic>> saveReturnReason(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = (id != null && id > 0)
            ? await _apiClient.dio.put(ApiEndpoints.returnReasonDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.returnReasons, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalReturnReason(saved);
        _emitState(state.copyWith(returnReasons: _offlineDb.getCachedReturnReasons()));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    final saved = await _offlineDb.addOrUpdateLocalReturnReason({
      if (id != null) 'id': id,
      ...payload,
    });
    _emitState(state.copyWith(returnReasons: _offlineDb.getCachedReturnReasons()));
    return {'success': true, 'data': saved};
  }

  Future<Map<String, dynamic>> deleteReturnReason(int id) async {
    if (!_isLocalStandalone && id > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.returnReasonDetail(id));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalReturnReason(id);
    _emitState(state.copyWith(returnReasons: _offlineDb.getCachedReturnReasons()));
    return {'success': true};
  }

  Future<Map<String, dynamic>> saveExpenseCategory(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = (id != null && id > 0)
            ? await _apiClient.dio.put(ApiEndpoints.expenseCategoryDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.expenseCategories, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalExpenseCategory(saved);
        _emitState(state.copyWith(expenseCategories: _offlineDb.getCachedExpenseCategories()));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    final saved = await _offlineDb.addOrUpdateLocalExpenseCategory({
      if (id != null) 'id': id,
      ...payload,
    });
    _emitState(state.copyWith(expenseCategories: _offlineDb.getCachedExpenseCategories()));
    return {'success': true, 'data': saved};
  }

  Future<Map<String, dynamic>> deleteExpenseCategory(int id) async {
    if (!_isLocalStandalone && id > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.expenseCategoryDetail(id));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalExpenseCategory(id);
    _emitState(state.copyWith(expenseCategories: _offlineDb.getCachedExpenseCategories()));
    return {'success': true};
  }

  Future<Map<String, dynamic>> saveCustomerGroup(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    if (!_isLocalStandalone) {
      try {
        final res = (id != null && id > 0)
            ? await _apiClient.dio.put(ApiEndpoints.customerGroupDetail(id), data: payload)
            : await _apiClient.dio.post(ApiEndpoints.customerGroups, data: payload);
        final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
        await _offlineDb.addOrUpdateLocalCustomerGroup(saved);
        _emitState(state.copyWith(customerGroups: _offlineDb.getCachedCustomerGroups()));
        return {'success': true, 'data': saved};
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    final saved = await _offlineDb.addOrUpdateLocalCustomerGroup({
      if (id != null) 'id': id,
      ...payload,
    });
    _emitState(state.copyWith(customerGroups: _offlineDb.getCachedCustomerGroups()));
    return {'success': true, 'data': saved};
  }

  Future<Map<String, dynamic>> deleteCustomerGroup(int id) async {
    if (!_isLocalStandalone && id > 0) {
      try {
        await _apiClient.dio.delete(ApiEndpoints.customerGroupDetail(id));
      } catch (e) {
        if (state.isOnline) {
          return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
        }
      }
    }
    await _offlineDb.deleteLocalCustomerGroup(id);
    _emitState(state.copyWith(customerGroups: _offlineDb.getCachedCustomerGroups()));
    return {'success': true};
  }

  /// Load items & customer from a Quotation into active POS cart for 1-click billing
  void loadCartFromQuotation(Map<String, dynamic> quotation) {
    final rawItems = (quotation['items'] as List<dynamic>? ?? []);
    final newCart = <CartItemModel>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final pid = (item['product_id'] as num?)?.toInt() ?? 0;
      final matched = state.allProducts.where((p) => p.id == pid).toList();
      final prod = matched.isNotEmpty
          ? matched.first
          : ProductModel(
              id: pid,
              name: (item['product_name'] ?? 'Produk').toString(),
              sku: (item['sku'] ?? 'SKU').toString(),
              barcode: '',
              sellingPrice: (item['unit_price'] as num?)?.toDouble() ?? 0.0,
              stock: 99,
            );
      final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? prod.sellingPrice;
      final discount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
      newCart.add(CartItemModel(
        product: prod,
        batch: prod.fefoBatch,
        quantity: qty,
        unitPrice: unitPrice,
        discountAmount: discount,
        selectedUnitCode: prod.unitCode,
        multiplier: 1.0,
      ));
    }

    Map<String, dynamic>? customer;
    final custId = (quotation['customer_id'] as num?)?.toInt();
    if (custId != null && custId > 0) {
      customer = state.customers.where((c) => (c['id'] as num?)?.toInt() == custId).firstOrNull;
    }

    final qNumber = (quotation['quotation_number'] ?? quotation['number'] ?? '').toString();
    final qNotes = (quotation['notes'] ?? '').toString();
    final combinedNote = qNumber.isNotEmpty
        ? 'Dari Penawaran $qNumber${qNotes.isNotEmpty ? ' • $qNotes' : ''}'
        : qNotes;

    _emitState(state.copyWith(
      cart: newCart,
      selectedCustomer: customer,
      clearCustomer: customer == null,
      orderNotes: combinedNote.isNotEmpty ? combinedNote : null,
      clearOrderNotes: combinedNote.isEmpty,
      cartDiscountAmount: (quotation['discount_amount'] as num?)?.toDouble() ?? 0.0,
      clearActiveHeldSaleId: true,
      clearExchangeSourceSale: true,
    ));
  }
}
