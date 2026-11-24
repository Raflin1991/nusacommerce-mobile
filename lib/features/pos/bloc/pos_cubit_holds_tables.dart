part of 'pos_cubit.dart';

extension PosCubitHoldsTablesExt on PosCubit {
  /// B.1: Filter held carts by customer name, table name, label, or hold number
  List<Map<String, dynamic>> searchHeldCarts(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return state.heldCarts;
    return state.heldCarts.where((h) {
      final label = (h['held_label'] ?? '').toString().toLowerCase();
      final cust = (h['customer_name'] ??
              (h['customer'] is Map ? (h['customer'] as Map)['name'] : null) ??
              '')
          .toString()
          .toLowerCase();
      final table = (h['table_name'] ?? '').toString().toLowerCase();
      final number = (h['number'] ?? '').toString().toLowerCase();
      return label.contains(q) || cust.contains(q) || table.contains(q) || number.contains(q);
    }).toList();
  }

  /// Bug 2 Fix: Hold / Park current cart persistently into SQLite (`held_sales`) & SharedPreferences
  /// so parked table/queue orders survive force-close, battery drain, or app restart.
  Future<void> holdCurrentCart(String label) async {
    if (state.cart.isEmpty) return;
    final itemsToHold = List<CartItemModel>.from(state.cart);
    final resolvedLabel = label.trim().isEmpty
        ? (state.selectedCustomer?['name']?.toString() ??
            state.selectedTable?['name']?.toString() ??
            'Pelanggan Antre')
        : label.trim();
    final storeProfile = _offlineDb.getStoreProfile();
    final holdStoreCode = (storeProfile['code'] ?? storeProfile['branch'] ?? 'MAIN').toString();
    final holdNodeCode = _apiClient.edgeDiscovery.getMobileNodeCode();
    final holdNumber = await _offlineDb.generatePartitionedFallbackNumber(
      storeCode: holdStoreCode,
      docPrefix: 'HLD',
      docType: 'hold',
      nodeCode: holdNodeCode,
    );
    final now = DateTime.now();
    final heldUuid = _uuid.v4();
    final heldId = now.microsecondsSinceEpoch;
    final heldEntry = <String, dynamic>{
      'id': heldId,
      'local_uuid': heldUuid,
      'number': holdNumber,
      'held_label': resolvedLabel,
      'table_name': state.selectedTable?['name'],
      'selected_table': state.selectedTable,
      'customer': state.selectedCustomer,
      'customer_name': state.selectedCustomer?['name'] ?? 'Pelanggan Umum',
      if (state.verticalMetadata.isNotEmpty)
        'vertical_metadata': Map<String, dynamic>.from(state.verticalMetadata),
      'cart_discount_amount': state.cartDiscountAmount,
      'manager_discount_approved': state.managerDiscountApproved,
      'redeemed_loyalty_points': state.redeemedLoyaltyPoints,
      'order_type': state.orderType,
      'items_count': itemsToHold.length,
      if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
        'notes': state.orderNotes!.trim(),
      'subtotal': state.grandTotal,
      'held_at': DateFormat('HH:mm').format(now),
      'created_at': now.toIso8601String(),
      'is_synced': 0,
      'cart_items': itemsToHold,
    };

    final heldCustomerId = state.selectedCustomer?['id'];
    final heldTableId = state.selectedTable?['id'];

    // Persist immediately to SQLite `held_sales` BEFORE clearing active cart
    await _offlineDb.saveHeldSale(PosCubit._serializeHeldEntry(heldEntry));

    final updatedHeld = [heldEntry, ...state.heldCarts];
    _emitState(state.copyWith(
      heldCarts: updatedHeld,
      cart: [],
      cartDiscountAmount: 0,
      managerDiscountApproved: false,
      redeemedLoyaltyPoints: 0,
      clearCustomer: true,
      clearTable: true,
      clearVerticalMetadata: true,
      clearActiveHeldSaleId: true,
      clearExchangeSourceSale: true,
      clearOrderNotes: true,
    ));

    if (!_isLocalStandalone && state.isOnline) {
      unawaited(() async {
        try {
          final res = await _apiClient.dio.post(
            ApiEndpoints.holdCart,
            options: Options(headers: {'X-Idempotency-Key': heldUuid}),
            data: {
              'held_label': heldEntry['held_label'],
              if (heldEntry['notes'] != null) 'notes': heldEntry['notes'],
              if (heldCustomerId != null) 'customer_id': heldCustomerId,
              if (heldTableId != null) 'table_id': heldTableId,
              'items': itemsToHold
                  .map((c) => {
                        'product_id': c.product.id,
                        'variant_id': c.variant?.id,
                        'quantity': c.quantity,
                        'unit_price': c.unitPrice,
                        if (c.notes != null && c.notes!.trim().isNotEmpty) 'notes': c.notes!.trim(),
                        if (c.cookingNotes != null && c.cookingNotes!.trim().isNotEmpty)
                          'cooking_notes': c.cookingNotes!.trim(),
                        if (c.modifiers.isNotEmpty) 'modifiers': c.modifiers,
                      })
                  .toList(),
            },
          );
          final srvId = ((res.data is Map ? res.data['data'] : null) is Map)
              ? (res.data['data']['id'] as num?)?.toInt()
              : null;
          if (!isClosed) {
            final nextHeld = state.heldCarts.map((h) {
              if (h['local_uuid']?.toString() != heldUuid) return h;
              return {
                ...h,
                if (srvId != null && srvId > 0) 'server_id': srvId,
                'is_synced': 1,
              };
            }).toList();
            await _offlineDb.replaceHeldSales(nextHeld.map(PosCubit._serializeHeldEntry).toList());
            if (!isClosed) {
              _emitState(state.copyWith(heldCarts: nextHeld));
            }
          }
        } catch (_) {}
      }());
    }
  }

  /// Alias for [resumeHeldCart] for ergonomic recall of persisted held bills.
  void recallHeldSale(int index, {bool autoParkActiveCart = true}) =>
      resumeHeldCart(index, autoParkActiveCart: autoParkActiveCart);

  /// B.1 & Bug 2 Fix: Resume a persisted held cart from SQLite without destroying
  /// an active non-empty cart (auto-parks it persistently instead).
  void resumeHeldCart(int index, {bool autoParkActiveCart = true}) {
    if (index < 0 || index >= state.heldCarts.length) return;
    final held = state.heldCarts[index];
    final rawItems = held['cart_items'];
    final items = rawItems is List<CartItemModel>
        ? List<CartItemModel>.from(rawItems)
        : (rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((m) => CartItemModel.fromJson(
                      Map<String, dynamic>.from(m),
                      catalogProducts: state.allProducts,
                    ))
                .toList()
            : <CartItemModel>[]);
    final notes = held['notes']?.toString();
    final heldId = (held['id'] as num?)?.toInt();
    final restoredCustomer =
        held['customer'] is Map ? Map<String, dynamic>.from(held['customer'] as Map) : null;
    final restoredTable = held['selected_table'] is Map
        ? Map<String, dynamic>.from(held['selected_table'] as Map)
        : null;
    final restoredMeta = held['vertical_metadata'] is Map
        ? Map<String, dynamic>.from(held['vertical_metadata'] as Map)
        : const <String, dynamic>{};
    final restoredDiscount = (held['cart_discount_amount'] as num?)?.toDouble() ?? 0.0;
    final restoredApproved = held['manager_discount_approved'] == true;
    final restoredPoints = (held['redeemed_loyalty_points'] as num?)?.toInt() ?? 0;

    final remainingHeld = List<Map<String, dynamic>>.from(state.heldCarts)..removeAt(index);

    if (autoParkActiveCart && state.cart.isNotEmpty) {
      final now = DateTime.now();
      final activeItems = List<CartItemModel>.from(state.cart);
      final autoLabel = state.selectedCustomer?['name']?.toString() ??
          state.selectedTable?['name']?.toString() ??
          'Antrean Aktif (${DateFormat('HH:mm').format(now)})';
      remainingHeld.insert(0, {
        'id': now.microsecondsSinceEpoch,
        'local_uuid': _uuid.v4(),
        'number': 'HOLD-${now.minute}${now.second.toString().padLeft(2, '0')}',
        'held_label': autoLabel,
        'table_name': state.selectedTable?['name'],
        'selected_table': state.selectedTable,
        'customer': state.selectedCustomer,
        'customer_name': state.selectedCustomer?['name'] ?? 'Pelanggan Umum',
        if (state.verticalMetadata.isNotEmpty)
          'vertical_metadata': Map<String, dynamic>.from(state.verticalMetadata),
        'cart_discount_amount': state.cartDiscountAmount,
        'manager_discount_approved': state.managerDiscountApproved,
        'redeemed_loyalty_points': state.redeemedLoyaltyPoints,
        'order_type': state.orderType,
        'items_count': activeItems.length,
        if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
          'notes': state.orderNotes!.trim(),
        'subtotal': state.grandTotal,
        'held_at': DateFormat('HH:mm').format(now),
        'created_at': now.toIso8601String(),
        'is_synced': 0,
        'cart_items': activeItems,
      });
    }

    // Persist updated held bills list to SQLite + SharedPreferences
    unawaited(_offlineDb.replaceHeldSales(remainingHeld.map(PosCubit._serializeHeldEntry).toList()));

    _emitState(state.copyWith(
      cart: items,
      heldCarts: remainingHeld,
      activeHeldSaleId: heldId,
      clearActiveHeldSaleId: heldId == null,
      clearExchangeSourceSale: true,
      selectedCustomer: restoredCustomer,
      clearCustomer: restoredCustomer == null,
      selectedTable: restoredTable,
      clearTable: restoredTable == null,
      verticalMetadata: restoredMeta,
      clearVerticalMetadata: restoredMeta.isEmpty,
      cartDiscountAmount: restoredDiscount,
      managerDiscountApproved: restoredApproved,
      redeemedLoyaltyPoints: restoredPoints,
      orderNotes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : null,
      clearOrderNotes: notes == null || notes.trim().isEmpty,
    ));
  }

  /// B.2: Gracefully synchronize in-memory cart prices & available stock against latest catalog/server data
  int reconcileCartWithLatestCatalog({
    List<ProductModel>? refreshedProducts,
    Map<String, dynamic>? serverPriceData,
  }) {
    if (state.cart.isEmpty) return 0;
    final sourceProducts = refreshedProducts ?? state.allProducts;
    final productById = {for (final p in sourceProducts) p.id: p};

    final serverItemsByKey = <String, Map<String, dynamic>>{};
    final serverItems = serverPriceData?['items'] as List<dynamic>? ?? const [];
    for (final raw in serverItems) {
      if (raw is Map) {
        final pid = (raw['product_id'] as num?)?.toInt();
        final vid = (raw['variant_id'] as num?)?.toInt();
        if (pid != null) {
          serverItemsByKey['$pid:${vid ?? 0}'] = Map<String, dynamic>.from(raw);
        }
      }
    }

    int adjustedCount = 0;
    final warnings = <String>[];
    final reconciled = <CartItemModel>[];

    for (final item in state.cart) {
      if (item.isExchangeReturn) {
        reconciled.add(item);
        continue;
      }
      final latestProduct = productById[item.product.id] ?? item.product;
      ProductVariantModel? latestVariant = item.variant;
      if (item.variant != null && latestProduct.variants.isNotEmpty) {
        for (final v in latestProduct.variants) {
          if (v.id == item.variant!.id) {
            latestVariant = v;
            break;
          }
        }
      }

      double updatedPrice = item.unitPrice;
      ProductModel effectiveProduct = latestProduct;
      final serverEntry = serverItemsByKey['${item.product.id}:${item.variant?.id ?? 0}'];
      final serverUnitPrice = (serverEntry?['unit_price'] as num?)?.toDouble();
      final serverTaxRate = (serverEntry?['tax_rate'] as num?)?.toDouble();
      final serverTaxInclusive = serverEntry?['tax_is_inclusive'];
      if (serverTaxRate != null &&
          ((serverTaxRate - latestProduct.taxRate).abs() > 0.001 ||
              (serverTaxInclusive is bool && serverTaxInclusive != latestProduct.taxInclusive))) {
        effectiveProduct = ProductModel.fromJson({
          ...latestProduct.toJson(),
          'tax_rate': serverTaxRate,
          'tax_inclusive': serverTaxInclusive is bool ? serverTaxInclusive : latestProduct.taxInclusive,
        });
        adjustedCount++;
      }
      if (serverUnitPrice != null && (serverUnitPrice - item.unitPrice).abs() > 0.5) {
        updatedPrice = serverUnitPrice;
        adjustedCount++;
        warnings.add('Harga ${item.displayName} diperbarui sesuai tarif server terbaru.');
      } else if (refreshedProducts != null && (item.multiplier - 1.0).abs() < 0.0001) {
        final catalogPrice = latestVariant?.sellingPrice ?? latestProduct.sellingPrice;
        if ((catalogPrice - item.unitPrice).abs() > 0.5 && (item.notes ?? '').isEmpty) {
          updatedPrice = catalogPrice;
          adjustedCount++;
        }
      }

      double updatedQty = item.quantity;
      if (!effectiveProduct.isServiceOrNonStockItem && effectiveProduct.stock > 0) {
        final availableInUnit = effectiveProduct.stock / item.multiplier;
        if (updatedQty > availableInUnit && availableInUnit > 0) {
          updatedQty = effectiveProduct.soldByWeight
              ? double.parse(availableInUnit.toStringAsFixed(2))
              : availableInUnit.floorToDouble();
          if (updatedQty > 0) {
            adjustedCount++;
            warnings.add('Qty ${item.displayName} disesuaikan ke sisa stok ($updatedQty).');
          }
        }
      }

      if (updatedQty > 0) {
        final clampedDisc = PosFinancialCalculator.clampDiscount(
          item.discountAmount,
          (updatedQty * updatedPrice).roundToDouble(),
        );
        reconciled.add(CartItemModel(
          saleItemId: item.saleItemId,
          isExchangeReturn: item.isExchangeReturn,
          product: effectiveProduct,
          variant: latestVariant,
          quantity: updatedQty,
          unitPrice: updatedPrice,
          discountAmount: clampedDisc,
          notes: item.notes,
          digitalTargetValue: item.digitalTargetValue,
          stylistName: item.stylistName,
          batch: effectiveProduct.fefoBatch ?? item.batch,
          selectedUnitCode: item.selectedUnitCode,
          multiplier: item.multiplier,
        ));
      }
    }

    if (adjustedCount > 0 || refreshedProducts != null) {
      _emitState(state.copyWith(
        cart: reconciled,
        allProducts: refreshedProducts ?? state.allProducts,
        alertMessage: warnings.isNotEmpty ? warnings.first : state.alertMessage,
      ));
    }
    return adjustedCount;
  }

  /// Sync Split Bill by Item with Backend `SplitBillAction` (`POST /api/v1/pos/tables/{table}/split`)
  /// Falls back cleanly to prorated calculation if offline or unheld.
  Future<Map<String, dynamic>> splitRestaurantTableBill(List<int> selectedIndices) async {
    final tableId = (state.selectedTable?['id'] as num?)?.toInt();
    final heldSaleId = state.activeHeldSaleId ??
        (state.selectedTable?['active_sale_id'] as num?)?.toInt();

    final selectedItems = [
      for (final idx in selectedIndices)
        if (idx >= 0 && idx < state.cart.length) state.cart[idx],
    ];

    final localCalc = PosFinancialCalculator.calculateProratedSplitBill(
      parentItems: state.cart
          .map((c) => {
                if (c.saleItemId != null) 'sale_item_id': c.saleItemId,
                'quantity': c.quantity,
                'unit_price': c.unitPrice,
                'discount_amount': c.discountAmount,
              })
          .toList(),
      itemsToSplit: selectedIndices
          .where((idx) => idx >= 0 && idx < state.cart.length)
          .map((idx) => {
                'index': idx,
                'quantity': state.cart[idx].quantity,
              })
          .toList(),
    );

    if (tableId != null && heldSaleId != null && selectedItems.isNotEmpty) {
      try {
        final res = await _apiClient.dio.post(
          ApiEndpoints.splitTable(tableId),
          data: {
            'held_sale_id': heldSaleId,
            'items': selectedItems
                .map((c) => {
                      if (c.saleItemId != null) 'sale_item_id': c.saleItemId,
                      'product_id': c.product.id,
                      if (c.variant?.id != null) 'variant_id': c.variant!.id,
                      'quantity': c.quantity,
                    })
                .toList(),
          },
        );
        final data = res.data?['data'] as Map<String, dynamic>?;
        final child = data?['child'] as Map<String, dynamic>?;
        if (child != null) {
          final childSaleId = (child['id'] as num?)?.toInt();
          final childGrand = (child['grand_total'] as num?)?.toDouble() ?? localCalc.childGrandTotal;
          final childServiceCharge = (child['service_charge_amount'] as num?)?.toDouble() ?? localCalc.childServiceCharge;
          final childTax = (child['tax_total'] as num?)?.toDouble() ?? localCalc.childTax;
          return {
            'synced': true,
            'child_held_sale_id': childSaleId,
            'grand_total': childGrand,
            'service_charge_amount': childServiceCharge,
            'tax_total': childTax,
          };
        }
      } catch (_) {
        // Fallback to local prorated calculation when offline
      }
    }

    return {
      'synced': false,
      'child_held_sale_id': null,
      'grand_total': localCalc.childGrandTotal,
      'service_charge_amount': localCalc.childServiceCharge,
      'tax_total': localCalc.childTax,
    };
  }
}
