part of 'pos_cubit.dart';

extension PosCubitCartExt on PosCubit {
  Future<void> setBusinessVertical(BusinessVertical vertical) async {
    final effective = vertical.isAvailable ? vertical : BusinessVertical.retail;
    await _offlineDb.setSavedBusinessVertical(effective.key);
    final caps = VerticalConfig.getCapabilities(effective);
    _emitState(state.copyWith(
      currentVertical: effective,
      posMode: effective == BusinessVertical.restaurant ? 'restaurant' : 'retail',
      orderType: caps.hasDineInTakeawayOrderType ? 'dine_in' : 'retail',
      clearTable: !caps.hasTableManagement,
      clearOrderNotes: true,
      clearVerticalMetadata: true,
    ));
  }

  void setOrderNotes(String? notes) {
    final trimmed = notes?.trim() ?? '';
    if (trimmed.isEmpty) {
      _emitState(state.copyWith(clearOrderNotes: true));
    } else {
      _emitState(state.copyWith(orderNotes: trimmed));
    }
  }

  /// Phase 4: Store structured multi-vertical metadata (Workshop, Pharmacy, Laundry, Salon)
  /// and automatically sync human-readable summary into `orderNotes`.
  void setVerticalMetadata(Map<String, dynamic> metadata, {String? formattedSummary}) {
    final cleaned = <String, dynamic>{};
    metadata.forEach((key, value) {
      if (value != null && value.toString().trim().isNotEmpty) {
        cleaned[key] = value is String ? value.trim() : value;
      }
    });

    if (cleaned.isEmpty) {
      _emitState(state.copyWith(clearVerticalMetadata: true, clearOrderNotes: true));
      return;
    }

    String summary = formattedSummary?.trim() ?? '';
    if (summary.isEmpty) {
      final parts = <String>[];
      if ((cleaned['nopol'] ?? '').toString().isNotEmpty) {
        parts.add('No. Polisi: ${cleaned['nopol']}');
      }
      if ((cleaned['kendaraan'] ?? cleaned['vehicle_model'] ?? '').toString().isNotEmpty) {
        parts.add('Kendaraan: ${cleaned['kendaraan'] ?? cleaned['vehicle_model']}');
      }
      if ((cleaned['kilometer'] ?? cleaned['km'] ?? '').toString().isNotEmpty) {
        parts.add('KM: ${cleaned['kilometer'] ?? cleaned['km']}');
      }
      if ((cleaned['mechanic_name'] ?? '').toString().isNotEmpty) {
        parts.add('Mekanik: ${cleaned['mechanic_name']}');
      }
      if ((cleaned['doctor_name'] ?? '').toString().isNotEmpty) {
        parts.add('Dokter: ${cleaned['doctor_name']}');
      }
      if ((cleaned['doctor_sip'] ?? '').toString().isNotEmpty) {
        parts.add('SIP: ${cleaned['doctor_sip']}');
      }
      if ((cleaned['patient_name'] ?? '').toString().isNotEmpty) {
        parts.add('Pasien: ${cleaned['patient_name']}');
      }
      if ((cleaned['rack_number'] ?? '').toString().isNotEmpty) {
        parts.add('Rak: ${cleaned['rack_number']}');
      }
      if ((cleaned['estimated_ready_at'] ?? '').toString().isNotEmpty) {
        parts.add('Selesai: ${cleaned['estimated_ready_at']}');
      }
      if ((cleaned['stylist_name'] ?? '').toString().isNotEmpty) {
        parts.add('Kapster: ${cleaned['stylist_name']}');
      }
      summary = parts.join(' • ');
    }

    _emitState(state.copyWith(
      verticalMetadata: cleaned,
      orderNotes: summary.isNotEmpty ? summary : state.orderNotes,
    ));
  }

  Future<void> setPosMode(String mode) async {
    await setBusinessVertical(VerticalConfig.parse(mode));
  }

  void setOrderType(String orderType) {
    _emitState(state.copyWith(
      orderType: orderType,
      currentVertical: orderType == 'dine_in' ? BusinessVertical.restaurant : state.currentVertical,
      posMode: orderType == 'dine_in' ? 'restaurant' : state.posMode,
    ));
  }

  void selectCategory(int categoryId) {
    _emitState(state.copyWith(selectedCategoryId: categoryId));
  }

  void selectBrand(int brandId) {
    _emitState(state.copyWith(selectedBrandId: brandId));
  }

  void deleteHeldCart(int index) {
    if (index < 0 || index >= state.heldCarts.length) return;
    final remaining = List<Map<String, dynamic>>.from(state.heldCarts)..removeAt(index);
    unawaited(_offlineDb.replaceHeldSales(remaining.map(PosCubit._serializeHeldEntry).toList()));
    _emitState(state.copyWith(heldCarts: remaining));
  }

  void updateSearchQuery(String query) {
    _emitState(state.copyWith(searchQuery: query));
  }

  void selectCustomer(Map<String, dynamic>? customer) {
    if (customer == null) {
      _emitState(state.copyWith(clearCustomer: true, redeemedLoyaltyPoints: 0));
    } else {
      _emitState(state.copyWith(selectedCustomer: customer));
    }
  }

  void selectRestaurantTable(Map<String, dynamic>? table) {
    if (table == null) {
      _emitState(state.copyWith(clearTable: true, clearActiveHeldSaleId: true));
    } else {
      final activeSaleId = (table['active_sale_id'] as num?)?.toInt() ??
          (table['active_sale'] is Map
              ? ((table['active_sale']['id'] as num?)?.toInt())
              : null);
      _emitState(state.copyWith(
        selectedTable: table,
        activeHeldSaleId: activeSaleId,
        clearActiveHeldSaleId: activeSaleId == null,
        currentVertical: BusinessVertical.restaurant,
        posMode: 'restaurant',
        orderType: 'dine_in',
      ));
    }
  }

  List<CartItemModel> _recalculateVolumeTiers(
    List<CartItemModel> cart,
    int productId, {
    bool skipCustomOverride = false,
  }) {
    if (skipCustomOverride) return cart;
    final totalQty = cart
        .where((c) => !c.isExchangeReturn && c.product.id == productId && (c.multiplier - 1.0).abs() < 0.0001)
        .fold<double>(0.0, (sum, c) => sum + c.quantity);

    return cart.map((item) {
      if (!item.isExchangeReturn &&
          item.product.id == productId &&
          (item.multiplier - 1.0).abs() < 0.0001 &&
          item.product.volumeTiers.isNotEmpty) {
        final newUnitPrice = item.product.resolveUnitPriceForQuantity(
          totalQty,
          basePriceOverride: item.variant?.sellingPrice ?? item.product.sellingPrice,
        );
        return item.copyWith(unitPrice: newUnitPrice);
      }
      return item;
    }).toList();
  }

  /// Add product to cart with FEFO Batch Expired Guard, Multi-Satuan & Tiered Volume Pricing support
  void addToCart(
    ProductModel product, {
    ProductVariantModel? variant,
    double quantity = 1.0,
    double? customUnitPrice,
    String? notes,
    String? digitalTargetValue,
    String? stylistName,
    ProductUnitConversion? unitConversion,
  }) {
    final batch = product.fefoBatch;
    if (batch != null && batch.isExpired) {
      PosFeedback.onGuardBlocked();
      _emitState(state.copyWith(
        alertMessage: 'BLOKIR FEFO: Batch ${batch.batchNumber} (${product.name}) sudah kedaluwarsa!',
      ));
      return;
    }

    PosFeedback.onScanSuccess();
    final String unitCode = unitConversion?.unitCode ?? product.unitCode;
    final double multiplier = unitConversion?.multiplier ?? 1.0;
    final double price = customUnitPrice ??
        unitConversion?.price ??
        variant?.sellingPrice ??
        product.sellingPrice;
    final updated = List<CartItemModel>.from(state.cart);

    final normalizedStylist = (stylistName ?? '').trim();
    final existingIdx = updated.indexWhere(
      (item) =>
          !item.isExchangeReturn &&
          item.product.id == product.id &&
          item.variant?.id == variant?.id &&
          item.effectiveUnitCode == unitCode &&
          (item.stylistName ?? '').trim() == normalizedStylist,
    );

    if (existingIdx >= 0) {
      final current = updated[existingIdx];
      updated[existingIdx] = current.copyWith(
        quantity: current.quantity + quantity,
        notes: notes ?? current.notes,
        digitalTargetValue: digitalTargetValue ?? current.digitalTargetValue,
        stylistName: stylistName ?? current.stylistName,
      );
    } else {
      updated.add(
        CartItemModel(
          product: product,
          variant: variant,
          batch: batch,
          quantity: quantity,
          unitPrice: price,
          notes: notes,
          digitalTargetValue: digitalTargetValue,
          stylistName: stylistName,
          selectedUnitCode: unitCode,
          multiplier: multiplier,
        ),
      );
    }

    final tieredCart = _recalculateVolumeTiers(
      updated,
      product.id,
      skipCustomOverride: customUnitPrice != null,
    );
    _emitState(state.copyWith(cart: tieredCart, alertMessage: null));
  }

  /// Switch Multi-Satuan & Tiered Wholesale Price for a cart line item
  void changeCartItemUnit(int index, ProductUnitConversion unit) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart);
    final current = updated[index];

    double resolvedPrice = unit.price;
    if (current.variant != null && current.product.sellingPrice > 0) {
      if ((unit.multiplier - 1.0).abs() < 0.0001) {
        resolvedPrice = current.variant!.sellingPrice;
      } else {
        final variantRatio = current.variant!.sellingPrice / current.product.sellingPrice;
        resolvedPrice = ((unit.price * variantRatio) / 100).round() * 100.0;
      }
    }

    updated[index] = current.copyWith(
      selectedUnitCode: unit.unitCode,
      multiplier: unit.multiplier,
      unitPrice: resolvedPrice,
    );
    _emitState(state.copyWith(cart: updated));
  }

  /// Handle camera or laser barcode scan (Supports Standard EAN, Scale Prefix 20/21 & 350ms Debounce)
  bool handleBarcodeScanned(String rawCode) {
    if (!BarcodeService.shouldAcceptScan(rawCode)) {
      return false;
    }
    final parsed = BarcodeService.parse(rawCode);

    if (parsed.isWeightScaleBarcode && parsed.scalePlu != null) {
      final match = state.allProducts.where((p) => p.scalePlu == parsed.scalePlu).toList();
      if (match.isNotEmpty) {
        final product = match.first;
        final qty = parsed.weightKg ??
            (parsed.embeddedPrice != null && product.sellingPrice > 0
                ? (parsed.embeddedPrice! / product.sellingPrice)
                : 1.0);
        addToCart(product, quantity: double.parse(qty.toStringAsFixed(3)));
        return true;
      }
    }

    final exactMatch = state.allProducts.where(
      (p) => p.barcode == parsed.rawBarcode || p.sku.toLowerCase() == parsed.rawBarcode.toLowerCase(),
    );

    if (exactMatch.isNotEmpty) {
      addToCart(exactMatch.first);
      return true;
    }

    PosFeedback.onGuardBlocked();
    _emitState(state.copyWith(alertMessage: 'Barcode "${parsed.rawBarcode}" tidak ditemukan di katalog.'));
    return false;
  }

  void incrementCartItem(int index) {
    if (index < 0 || index >= state.cart.length) return;
    final item = state.cart[index];
    if (item.isExchangeReturn) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart);
    final step = item.product.soldByWeight ? 0.5 : 1.0;
    updated[index] = item.copyWith(quantity: item.quantity + step);
    _emitState(state.copyWith(cart: _recalculateVolumeTiers(updated, item.product.id)));
  }

  void decrementCartItem(int index) {
    if (index < 0 || index >= state.cart.length) return;
    final item = state.cart[index];
    if (item.isExchangeReturn) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart);
    final step = item.product.soldByWeight ? 0.5 : 1.0;
    if (item.quantity - step <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = item.copyWith(quantity: item.quantity - step);
    }
    _emitState(state.copyWith(cart: _recalculateVolumeTiers(updated, item.product.id)));
  }

  void updateCartItemNote(int index, String note) {
    if (index < 0 || index >= state.cart.length) return;
    final updated = List<CartItemModel>.from(state.cart);
    updated[index] = updated[index].copyWith(notes: note);
    _emitState(state.copyWith(cart: updated));
  }

  void updateCartItemQuantity(int index, double quantity) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final productId = state.cart[index].product.id;
    final updated = List<CartItemModel>.from(state.cart);
    if (quantity <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(quantity: quantity);
    }
    _emitState(state.copyWith(cart: _recalculateVolumeTiers(updated, productId)));
  }

  void changeCartItemQuantity(int index, double quantity) =>
      updateCartItemQuantity(index, quantity);

  void updateCartItemDetails(
    int index, {
    double? quantity,
    double? unitPrice,
    double? discountAmount,
    String? notes,
    String? stylistName,
  }) {
    if (index < 0 || index >= state.cart.length) return;
    final productId = state.cart[index].product.id;
    final updated = List<CartItemModel>.from(state.cart);
    if (quantity != null && quantity <= 0) {
      updated.removeAt(index);
    } else {
      final current = updated[index];
      final effectiveQty = quantity ?? current.quantity;
      final effectivePrice = unitPrice ?? current.unitPrice;
      final maxLineSubtotal =
          (effectiveQty * effectivePrice).roundToDouble().clamp(0.0, double.infinity);
      final clampedDiscount = discountAmount != null
          ? PosFinancialCalculator.clampDiscount(discountAmount, maxLineSubtotal)
          : PosFinancialCalculator.clampDiscount(current.discountAmount, maxLineSubtotal);
      updated[index] = current.copyWith(
        quantity: quantity,
        unitPrice: unitPrice,
        discountAmount: clampedDiscount,
        notes: notes,
        stylistName: stylistName,
      );
    }
    _emitState(state.copyWith(
      cart: _recalculateVolumeTiers(
        updated,
        productId,
        skipCustomOverride: unitPrice != null,
      ),
    ));
  }

  void removeCartItem(int index) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final productId = state.cart[index].product.id;
    final updated = List<CartItemModel>.from(state.cart)..removeAt(index);
    _emitState(state.copyWith(cart: _recalculateVolumeTiers(updated, productId)));
  }

  void clearCart() {
    PosFeedback.onTapStepper();
    _emitState(state.copyWith(
      cart: [],
      cartDiscountAmount: 0,
      managerDiscountApproved: false,
      redeemedLoyaltyPoints: 0,
      clearTable: true,
      clearActiveHeldSaleId: true,
      clearExchangeSourceSale: true,
      clearOrderNotes: true,
      clearVerticalMetadata: true,
    ));
  }

  /// Start 1-Click Item Exchange workflow from Transactions History.
  void startItemExchange({
    required Map<String, dynamic> originalSale,
    required List<Map<String, dynamic>> returnedItems,
  }) {
    final exchangeLines = <CartItemModel>[];
    for (final raw in returnedItems) {
      final pid = (raw['product_id'] as num?)?.toInt() ?? 0;
      final qty = ((raw['return_quantity'] ?? raw['quantity']) as num?)?.toDouble() ?? 1.0;
      if (qty <= 0) continue;

      final matched = state.allProducts.where((p) => p.id == pid).toList();
      final product = matched.isNotEmpty
          ? matched.first
          : ProductModel(
              id: pid,
              name: (raw['product_name'] ?? 'Produk').toString(),
              sku: (raw['sku'] ?? 'SKU').toString(),
              barcode: '',
              sellingPrice: (raw['unit_price'] as num?)?.toDouble() ?? 0.0,
              stock: 99,
            );

      final unitPrice = (raw['unit_price'] as num?)?.toDouble() ?? product.sellingPrice;
      final saleItemId = (raw['sale_item_id'] ?? raw['id']) is num
          ? ((raw['sale_item_id'] ?? raw['id']) as num).toInt()
          : null;

      exchangeLines.add(
        CartItemModel(
          saleItemId: saleItemId,
          isExchangeReturn: true,
          product: product,
          quantity: -qty,
          unitPrice: unitPrice,
          notes: 'Retur Tukar Barang (${originalSale['number'] ?? ''})',
          selectedUnitCode: (raw['unit_code'] ?? product.unitCode).toString(),
        ),
      );
    }

    Map<String, dynamic>? linkedCustomer;
    if (originalSale['customer'] is Map) {
      final rawCust = Map<String, dynamic>.from(originalSale['customer'] as Map);
      final cid = (rawCust['id'] as num?)?.toInt() ?? 0;
      if (cid > 0) {
        final found = state.customers.where((c) => (c['id'] as num?)?.toInt() == cid).toList();
        linkedCustomer = found.isNotEmpty ? found.first : rawCust;
      }
    }

    _emitState(state.copyWith(
      cart: exchangeLines,
      exchangeSourceSale: originalSale,
      selectedCustomer: linkedCustomer,
      clearCustomer: linkedCustomer == null,
      cartDiscountAmount: 0,
      redeemedLoyaltyPoints: 0,
      clearTable: true,
      clearActiveHeldSaleId: true,
      orderNotes: 'Tukar Barang dari Nota ${originalSale['number'] ?? '-'}',
    ));
  }

  void cancelExchangeMode() {
    final nonExchange = state.cart.where((c) => !c.isExchangeReturn).toList();
    _emitState(state.copyWith(
      cart: nonExchange,
      clearExchangeSourceSale: true,
      clearOrderNotes: true,
    ));
  }

  /// Verify Manager PIN strictly via Cloud POST /api/v1/pos/verify-pin
  Future<bool> verifyManagerPin(
    String pin, {
    String action = 'discount',
    bool setApprovedState = true,
  }) async {
    try {
      final res = await _apiClient.dio.post(
        ApiEndpoints.verifyPin,
        data: {'pin': pin.trim(), 'action': action},
      );
      if (res.data['success'] == true) {
        if (setApprovedState) {
          _emitState(state.copyWith(managerDiscountApproved: true));
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Apply manual cart discount (A.1 clamped <= subtotal, requires Manager PIN if > 15%)
  bool applyCartDiscount(double discountAmount) {
    final clampedDiscount = PosFinancialCalculator.clampDiscount(discountAmount, state.subtotal);
    final maxCashierDiscount = (state.subtotal * 0.15).roundToDouble();
    if (clampedDiscount > maxCashierDiscount && !state.managerDiscountApproved) {
      PosFeedback.onGuardBlocked();
      return false; // Trigger Manager PIN Override Dialog in UI
    }
    _emitState(state.copyWith(cartDiscountAmount: clampedDiscount));
    return true;
  }

  void setRedeemedLoyaltyPoints(int points) {
    _emitState(state.copyWith(redeemedLoyaltyPoints: points));
  }
}
