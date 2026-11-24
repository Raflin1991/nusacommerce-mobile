part of 'pos_cubit.dart';

extension PosCubitCheckoutExt on PosCubit {
  /// Complete POS Checkout (POST /api/v1/pos/checkout with UUIDv4 Idempotency,
  /// Multi-Tender Split, Kasbon DP, Store Credit, Held Table Split Sync & 1-Click Exchange)
  /// D.2: Protected by synchronous + async double-submit mutex and idempotency key cache.
  Future<Map<String, dynamic>> completeCheckout({
    required List<Map<String, dynamic>> payments,
    required List<String> paymentMethodNames,
    required double paidTotal,
    required double changeReturned,
    required double balanceDue,
    double storeCreditAmount = 0.0,
    double? grandTotalOverride,
    int? overrideHeldSaleId,
    bool refundSurplusToStoreCredit = false,
    List<int>? splitItemIndices,
    String? orderTypeOverride,
    String? dueDate,
    String? idempotencyKey,
  }) async {
    final trimmedKey = idempotencyKey?.trim();
    if (trimmedKey != null &&
        trimmedKey.isNotEmpty &&
        trimmedKey == _lastCompletedIdempotencyKey &&
        _lastCompletedReceipt != null) {
      return Map<String, dynamic>.from(_lastCompletedReceipt!);
    }
    if (_isCheckoutInProgress) {
      throw StateError('Transaksi sedang diproses. Mohon tunggu hingga selesai.');
    }
    _isCheckoutInProgress = true;
    try {
      final receipt = await _executeCompleteCheckout(
        payments: payments,
        paymentMethodNames: paymentMethodNames,
        paidTotal: paidTotal,
        changeReturned: changeReturned,
        balanceDue: balanceDue,
        storeCreditAmount: storeCreditAmount,
        grandTotalOverride: grandTotalOverride,
        overrideHeldSaleId: overrideHeldSaleId,
        refundSurplusToStoreCredit: refundSurplusToStoreCredit,
        splitItemIndices: splitItemIndices,
        orderTypeOverride: orderTypeOverride,
        dueDate: dueDate,
        idempotencyKey: trimmedKey,
      );
      if (trimmedKey != null && trimmedKey.isNotEmpty) {
        _lastCompletedIdempotencyKey = trimmedKey;
      }
      _lastCompletedReceipt = Map<String, dynamic>.from(receipt);
      return receipt;
    } finally {
      _isCheckoutInProgress = false;
    }
  }

  Future<Map<String, dynamic>> _executeCompleteCheckout({
    required List<Map<String, dynamic>> payments,
    required List<String> paymentMethodNames,
    required double paidTotal,
    required double changeReturned,
    required double balanceDue,
    double storeCreditAmount = 0.0,
    double? grandTotalOverride,
    int? overrideHeldSaleId,
    bool refundSurplusToStoreCredit = false,
    List<int>? splitItemIndices,
    String? orderTypeOverride,
    String? dueDate,
    String? idempotencyKey,
  }) async {
    final isPartialSplit = splitItemIndices != null && splitItemIndices.isNotEmpty;
    final selectedSet = splitItemIndices?.toSet() ?? <int>{};
    final checkoutCart = isPartialSplit
        ? [
            for (int i = 0; i < state.cart.length; i++)
              if (selectedSet.contains(i)) state.cart[i],
          ]
        : List<CartItemModel>.from(state.cart);

    final localUuid =
        (idempotencyKey != null && idempotencyKey.isNotEmpty) ? idempotencyKey : _uuid.v4();
    final nowTs = DateTime.now();
    final nowIso = nowTs.toIso8601String();
    final storeProfile = _offlineDb.getStoreProfile();
    final storeCode = (storeProfile['code'] ?? storeProfile['branch'] ?? 'MAIN').toString();
    final nodeCode = _apiClient.edgeDiscovery.getMobileNodeCode();
    final invoiceNo = await _offlineDb.generatePartitionedFallbackNumber(
      storeCode: storeCode,
      docPrefix: 'INV',
      docType: 'sale',
      nodeCode: nodeCode,
      now: nowTs,
    );
    final nowFormatted = DateFormat('dd MMM yyyy • HH:mm').format(nowTs);
    final resolvedOrderType = orderTypeOverride ??
        (state.posMode == 'restaurant' && state.orderType == 'retail' ? 'dine_in' : state.orderType);

    final returnedLines = checkoutCart.where((c) => c.isExchangeReturn).toList();
    final positiveLines = checkoutCart.where((c) => !c.isExchangeReturn).toList();
    final isExchange = state.isExchangeMode && returnedLines.isNotEmpty;

    final positiveSubtotal = positiveLines.fold<double>(0.0, (sum, c) => sum + c.lineTotal);
    final returnCreditSubtotal = returnedLines.fold<double>(0.0, (sum, c) => sum + c.lineTotal.abs());
    final checkoutSubtotal = isExchange
        ? (positiveSubtotal - returnCreditSubtotal)
        : checkoutCart.fold<double>(0.0, (sum, c) => sum + c.lineTotal);
    final appliedOrderDiscount = isPartialSplit ? 0.0 : state.totalDiscount;
    double checkoutTaxTotal = 0.0;
    if (grandTotalOverride == null && (!isExchange || (checkoutSubtotal - appliedOrderDiscount) > 0)) {
      double remTaxDisc = appliedOrderDiscount.clamp(0.0, positiveSubtotal);
      for (int i = 0; i < positiveLines.length; i++) {
        final c = positiveLines[i];
        double share = 0.0;
        if (remTaxDisc > 0 && positiveSubtotal > 0) {
          if (i == positiveLines.length - 1) {
            share = remTaxDisc;
          } else {
            share = ((c.lineTotal / positiveSubtotal) * appliedOrderDiscount).roundToDouble();
            remTaxDisc = (remTaxDisc - share).clamp(0.0, positiveSubtotal);
          }
        }
        final taxableBase = (c.lineTotal - share).clamp(0.0, double.infinity);
        if (!c.product.taxInclusive && c.product.taxRate > 0) {
          checkoutTaxTotal += PosState._round4dp(taxableBase * (c.product.taxRate / 100.0));
        }
      }
      checkoutTaxTotal = PosState._round4dp(checkoutTaxTotal);
    }
    final checkoutGrandTotal = grandTotalOverride ??
        PosState._round4dp((checkoutSubtotal - appliedOrderDiscount).clamp(0.0, double.infinity) + checkoutTaxTotal);

    // Fold order-level discount proportionally into positive sale line discounts
    double remainingOrderDisc = appliedOrderDiscount;
    final positiveItemMaps = <Map<String, dynamic>>[];
    for (int i = 0; i < positiveLines.length; i++) {
      final c = positiveLines[i];
      double extraDisc = 0.0;
      if (appliedOrderDiscount > 0 && positiveSubtotal > 0) {
        if (i == positiveLines.length - 1) {
          extraDisc = remainingOrderDisc;
        } else {
          extraDisc = ((c.lineTotal / positiveSubtotal) * appliedOrderDiscount).roundToDouble();
          remainingOrderDisc -= extraDisc;
        }
      }
      final combinedDiscount = PosFinancialCalculator.clampDiscount(
        c.effectiveDiscountAmount + extraDisc,
        c.lineSubtotal,
      );
      final resolvedBatch = c.batch ?? c.product.fefoBatch;
      positiveItemMaps.add({
        'product_id': c.product.id,
        'variant_id': c.variant?.id,
        'batch_id': resolvedBatch?.id,
        if (resolvedBatch != null) 'batch_number': resolvedBatch.batchNumber,
        if (resolvedBatch?.expiryDate != null) 'expiry_date': resolvedBatch!.expiryDate,
        'category_name': c.product.categoryName,
        'product_name': c.displayName,
        'product_type': c.product.type,
        'is_service': c.product.isServiceOrNonStockItem,
        'unit_code': c.effectiveUnitCode,
        'multiplier': c.multiplier,
        'quantity': c.quantity,
        'unit_price': c.unitPrice,
        'cost_price': c.product.costPrice,
        'discount_amount': combinedDiscount,
        'line_total': (c.lineSubtotal - combinedDiscount).clamp(0.0, double.infinity).roundToDouble(),
        'notes': c.notes,
        if (c.stylistName != null && c.stylistName!.trim().isNotEmpty)
          'stylist_name': c.stylistName!.trim(),
        'digital_target_value': c.digitalTargetValue,
      });
    }

    final displayItemMaps = <Map<String, dynamic>>[
      ...returnedLines.map((c) => {
            'product_id': c.product.id,
            'variant_id': c.variant?.id,
            'product_name': '[RETUR] ${c.displayName}',
            'unit_code': c.effectiveUnitCode,
            'multiplier': c.multiplier,
            'quantity': c.quantity,
            'unit_price': c.unitPrice,
            'discount_amount': 0.0,
            'line_total': c.lineSubtotal,
            'is_exchange_return': true,
          }),
      ...positiveItemMaps,
    ];

    final effectiveHeldSaleId = overrideHeldSaleId ?? (isPartialSplit ? null : state.activeHeldSaleId);

    final receiptPayload = <String, dynamic>{
      'id': nowTs.millisecondsSinceEpoch,
      'number': invoiceNo,
      'local_uuid': localUuid,
      'origin_node_code': nodeCode,
      'sale_datetime': nowFormatted,
      'created_at': nowIso,
      'client_completed_at': nowIso,
      'subtotal': checkoutSubtotal,
      'discount_total': appliedOrderDiscount,
      'tax_total': checkoutTaxTotal,
      'grand_total': checkoutGrandTotal,
      'paid_total': paidTotal,
      'store_credit_amount': storeCreditAmount,
      'change_returned': changeReturned,
      'balance_due': balanceDue,
      if (dueDate != null && dueDate.isNotEmpty) 'due_date': dueDate,
      if (isExchange) 'exchange_return_total': returnCreditSubtotal,
      if (isExchange) 'exchange_replacement_total': positiveSubtotal,
      if (isExchange && state.exchangeSourceSale != null)
        'exchange_source_number': state.exchangeSourceSale!['number'],
      'status': (isExchange && positiveLines.isEmpty) ? 'refunded' : 'completed',
      'order_type': resolvedOrderType,
      'table_name': state.selectedTable?['name'],
      if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
        'notes': state.orderNotes!.trim(),
      if (state.verticalMetadata.isNotEmpty)
        'vertical_metadata': state.verticalMetadata,
      'payment_methods': paymentMethodNames,
      'customer': state.selectedCustomer ?? {'id': 0, 'name': 'Pelanggan Umum', 'phone': '-'},
      'items': displayItemMaps,
      'payments': payments,
    };

    bool checkoutSyncedOnline = true;
    double effectiveStoreCreditForApi = storeCreditAmount;

    // Step 1 of Exchange Mode: Execute Return/Refund on original sale
    if (isExchange) {
      final origSaleId = (state.exchangeSourceSale?['id'] as num?)?.toInt() ?? 0;
      final customerId = (state.selectedCustomer?['id'] as num?)?.toInt() ?? 0;
      final shouldCreditDepositOnReturn =
          customerId > 0 && (positiveLines.isNotEmpty || refundSurplusToStoreCredit);

      final canCallExchangeOnline =
          origSaleId > 0 && !_isLocalStandalone && state.isOnline && await _connectivityService.checkOnline();
      if (canCallExchangeOnline) {
        try {
          await _apiClient.dio.post(
            ApiEndpoints.refundSale(origSaleId),
            options: Options(
              headers: {
                'X-Idempotency-Key': 'ex-$localUuid',
                'X-Edge-Node-Code': nodeCode,
              },
            ),
            data: {
              'restock': true,
              if (shouldCreditDepositOnReturn) 'refund_to_store_credit': true,
              'notes': 'Tukar Barang (Exchange) ke $invoiceNo',
              'client_uuid': 'ex-$localUuid',
              'items': returnedLines
                  .where((c) => c.saleItemId != null)
                  .map((c) => {
                        'sale_item_id': c.saleItemId,
                        'quantity': c.quantity.abs(),
                        'restock': true,
                      })
                  .toList(),
            },
          );
          if (shouldCreditDepositOnReturn && positiveLines.isNotEmpty) {
            final usedFromExchangeCredit =
                returnCreditSubtotal.clamp(0.0, positiveSubtotal);
            effectiveStoreCreditForApi += usedFromExchangeCredit;
          }
        } catch (e) {
          if (!ApiClient.isNetworkOfflineError(e)) {
            final data = e is DioException ? e.response?.data : null;
            throw CheckoutServerException(
              message: ApiClient.extractErrorMessage(e),
              errorCode: (data is Map ? data['error_code'] : null)?.toString(),
              statusCode: e is DioException ? e.response?.statusCode : null,
            );
          }
          checkoutSyncedOnline = false;
        }
      } else if (origSaleId > 0) {
        checkoutSyncedOnline = false;
      }
    }

    Map<String, dynamic>? pendingOfflineSaleApiBody;

    // Step 2: Submit Checkout when there are replacement / normal sale items
    if (positiveItemMaps.isNotEmpty) {
      final apiPayments = List<Map<String, dynamic>>.from(payments);
      // For Guest exchange (no customer store credit), server records the full
      // replacement value against Cash (which nets out against the Cash refund above).
      final customerId = (state.selectedCustomer?['id'] as num?)?.toInt();
      if (isExchange && (customerId == null || customerId <= 0)) {
        final cashMethodId = state.paymentMethods.isNotEmpty
            ? ((state.paymentMethods.first['id'] as num?)?.toInt() ?? 1)
            : 1;
        final netTenderTotal = apiPayments.fold<double>(
            0.0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0.0));
        final missingCreditShare =
            (positiveSubtotal - appliedOrderDiscount - netTenderTotal)
                .clamp(0.0, double.infinity);
        if (missingCreditShare > 0.5) {
          apiPayments.add({
            'payment_method_id': cashMethodId,
            'amount': missingCreditShare,
            'reference': 'EXCHANGE-CREDIT-${state.exchangeSourceSale?['number'] ?? ''}',
          });
        }
      }

      final apiBody = <String, dynamic>{
        'local_uuid': localUuid,
        'number': invoiceNo,
        'offline_number': invoiceNo,
        'origin_node_code': nodeCode,
        'client_completed_at': nowIso,
        'synced_from_offline': false,
        'customer_id': state.selectedCustomer?['id'],
        'order_type': resolvedOrderType,
        'table_id': state.selectedTable?['id'],
        if (effectiveHeldSaleId != null) 'held_sale_id': effectiveHeldSaleId,
        if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
          'notes': state.orderNotes!.trim(),
        if (state.verticalMetadata.isNotEmpty)
          'vertical_metadata': state.verticalMetadata,
        if (!isPartialSplit && state.redeemedLoyaltyPoints > 0)
          'redeem_points': state.redeemedLoyaltyPoints,
        if (effectiveStoreCreditForApi > 0)
          'store_credit_amount': effectiveStoreCreditForApi,
        if (dueDate != null && dueDate.isNotEmpty) 'due_date': dueDate,
        'items': positiveItemMaps,
        'payments': apiPayments,
      };

      final hasLiveNetwork = !_isLocalStandalone && state.isOnline && await _connectivityService.checkOnline();

      if (_isLocalStandalone || !hasLiveNetwork) {
        checkoutSyncedOnline = false;
        apiBody['synced_from_offline'] = true;
        pendingOfflineSaleApiBody = apiBody;
      } else {
        try {
          final res = await _apiClient.dio.post(
            ApiEndpoints.checkout,
            data: apiBody,
            options: Options(
              headers: {
                'X-Idempotency-Key': localUuid,
                'X-Edge-Node-Code': nodeCode,
              },
            ),
          );
          final serverData = res.data['data'] as Map<String, dynamic>?;
          if (serverData != null) {
            if (serverData['number'] != null) receiptPayload['number'] = serverData['number'];
            if (serverData['id'] != null) receiptPayload['id'] = serverData['id'];
            if (serverData['subtotal'] != null) {
              receiptPayload['subtotal'] = (serverData['subtotal'] as num).toDouble();
            }
            if (serverData['tax_total'] != null) {
              receiptPayload['tax_total'] = (serverData['tax_total'] as num).toDouble();
            }
            if (serverData['grand_total'] != null) {
              receiptPayload['grand_total'] = (serverData['grand_total'] as num).toDouble();
            }
          }
        } catch (e) {
          if (!ApiClient.isNetworkOfflineError(e)) {
            final data = e is DioException ? e.response?.data : null;
            throw CheckoutServerException(
              message: ApiClient.extractErrorMessage(e),
              errorCode: (data is Map ? data['error_code'] : null)?.toString(),
              statusCode: e is DioException ? e.response?.statusCode : null,
            );
          }
          checkoutSyncedOnline = false;
          apiBody['synced_from_offline'] = true;
          pendingOfflineSaleApiBody = apiBody;
        }
      }
    }

    // Prepare atomic ACID batch: offline sale queue + sales history + stock deduction +
    // stock movements + customer balance + cash-in ledger/open shift + held sale cleanup.
    final stockUpdates = <int, double>{};
    final stockMovements = <Map<String, dynamic>>[];
    final updatedProducts = state.allProducts.map((p) {
      if (p.isServiceOrNonStockItem) return p;
      final soldBaseQty = positiveLines
          .where((c) => c.product.id == p.id)
          .fold<double>(0.0, (sum, c) => sum + (c.quantity * c.multiplier));
      final returnedBaseQty = returnedLines
          .where((c) => c.product.id == p.id)
          .fold<double>(0.0, (sum, c) => sum + (c.quantity.abs() * c.multiplier));
      final netDelta = returnedBaseQty - soldBaseQty;
      if (netDelta.abs() > 0.0001) {
        final newStock = (p.stock + netDelta).clamp(0.0, double.infinity);
        stockUpdates[p.id] = newStock;
        stockMovements.add({
          'id': '${nowTs.microsecondsSinceEpoch}-${p.id}',
          'product_id': p.id,
          'product_name': p.name,
          'sku': p.sku,
          'unit_code': p.unitCode,
          'type': netDelta < 0 ? 'sale' : 'return',
          'quantity_delta': netDelta,
          'quantity_after': newStock,
          'unit_cost': p.costPrice,
          'notes': 'Nota ${receiptPayload['number'] ?? invoiceNo}',
          'created_at': nowIso,
        });
        return ProductModel.fromJson({
          ...p.toJson(),
          'stock': newStock,
          'is_low_stock': newStock <= p.reorderLevel,
        });
      }
      return p;
    }).toList();

    receiptPayload['is_offline_pending'] = !checkoutSyncedOnline;

    final remainingCart = isPartialSplit
        ? [
            for (int i = 0; i < state.cart.length; i++)
              if (!selectedSet.contains(i)) state.cart[i],
          ]
        : <CartItemModel>[];

    // Sync local customer deposit / kasbon balances so offline checkout + void remain consistent
    List<Map<String, dynamic>> nextCustomers = state.customers;
    Map<String, dynamic>? nextSelectedCustomer = state.selectedCustomer;
    Map<String, dynamic>? updatedCustomerMap;
    final checkoutCustomerId = (state.selectedCustomer?['id'] as num?)?.toInt();
    if (checkoutCustomerId != null &&
        checkoutCustomerId > 0 &&
        (storeCreditAmount > 0 || balanceDue > 0)) {
      nextCustomers = state.customers.map((c) {
        if ((c['id'] as num?)?.toInt() != checkoutCustomerId) return c;
        final updatedCust = Map<String, dynamic>.from(c);
        final curDeposit = (updatedCust['store_credit_balance'] as num?)?.toDouble() ?? 0.0;
        final curDebt = (updatedCust['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        updatedCust['store_credit_balance'] =
            (curDeposit - storeCreditAmount).clamp(0.0, double.infinity).roundToDouble();
        updatedCust['outstanding_balance'] = (curDebt + balanceDue).roundToDouble();
        updatedCustomerMap = updatedCust;
        return updatedCust;
      }).toList();
      nextSelectedCustomer = nextCustomers.firstWhere(
        (c) => (c['id'] as num?)?.toInt() == checkoutCustomerId,
        orElse: () => nextSelectedCustomer!,
      );
    }

    // Compute net cash received for atomic cash-in ledger & open shift tracking
    double cashPaidGross = 0.0;
    for (final p in payments) {
      final methodId = (p['payment_method_id'] as num?)?.toInt();
      final matched = state.paymentMethods
          .where((m) => (m['id'] as num?)?.toInt() == methodId)
          .firstOrNull;
      final methodType = (matched?['type'] ?? '').toString().toLowerCase();
      final methodName = (p['method_name'] ??
              p['payment_method_name'] ??
              matched?['name'] ??
              '')
          .toString()
          .toLowerCase();
      if (methodType == 'cash' ||
          methodName.contains('tunai') ||
          methodName.contains('cash')) {
        cashPaidGross += (p['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final double netCashIn =
        cashPaidGross > 0 ? (cashPaidGross - changeReturned).clamp(0.0, double.infinity) : 0.0;

    // Single ACID SQLite transaction — prevents stock deduction without saved receipt on crash!
    await _offlineDb.commitOfflineCheckoutAtomic(
      offlineSaleApiBody: pendingOfflineSaleApiBody,
      receiptPayload: receiptPayload,
      stockUpdates: stockUpdates,
      stockMovements: stockMovements,
      updatedCustomers: updatedCustomerMap != null ? nextCustomers : null,
      updatedCustomer: updatedCustomerMap,
      netCashIn: netCashIn,
      completedHeldSaleId: effectiveHeldSaleId,
    );

    if (pendingOfflineSaleApiBody != null) {
      _scheduleBackoffSyncIfNeeded();
    }

    final updatedHistory = _offlineDb.getLocalSalesHistory();
    final updatedHeldCarts = (effectiveHeldSaleId != null && effectiveHeldSaleId != 0)
        ? state.heldCarts
            .where((h) => (h['id'] as num?)?.toInt() != effectiveHeldSaleId)
            .toList()
        : state.heldCarts;

    await PosFeedback.onCheckoutSuccess();

    _emitState(state.copyWith(
      isOnline: checkoutSyncedOnline ? true : state.isOnline,
      allProducts: updatedProducts,
      customers: nextCustomers,
      selectedCustomer: nextSelectedCustomer,
      cart: remainingCart,
      heldCarts: updatedHeldCarts,
      cartDiscountAmount: remainingCart.isEmpty ? 0 : state.cartDiscountAmount,
      managerDiscountApproved: remainingCart.isEmpty ? false : state.managerDiscountApproved,
      redeemedLoyaltyPoints: remainingCart.isEmpty ? 0 : state.redeemedLoyaltyPoints,
      clearTable: remainingCart.isEmpty,
      clearActiveHeldSaleId: remainingCart.isEmpty,
      clearExchangeSourceSale: remainingCart.isEmpty,
      clearOrderNotes: remainingCart.isEmpty,
      clearVerticalMetadata: remainingCart.isEmpty,
      salesHistory: updatedHistory,
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));

    return receiptPayload;
  }

  /// Server-side authoritative cart pricing verification (POST /api/v1/pos/price-cart)
  Future<Map<String, dynamic>?> verifyServerCartPrice({
    int? customerId,
    int redeemPoints = 0,
  }) async {
    final positiveLines = state.cart.where((c) => !c.isExchangeReturn).toList();
    if (positiveLines.isEmpty) return null;
    try {
      final res = await _apiClient.dio.post(
        ApiEndpoints.priceCart,
        data: {
          if (customerId != null) 'customer_id': customerId,
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (state.totalDiscount > 0)
            'discount': {'type': 'fixed', 'value': state.totalDiscount},
          'items': positiveLines
              .map((c) {
                final resolvedBatch = c.batch ?? c.product.fefoBatch;
                return {
                  'product_id': c.product.id,
                  'variant_id': c.variant?.id,
                  if (resolvedBatch != null) 'batch_id': resolvedBatch.id,
                  'quantity': c.quantity,
                  'unit_price': c.unitPrice,
                  if (c.discountAmount > 0) 'discount_amount': c.discountAmount,
                };
              })
              .toList(),
        },
      );
      if (res.data is Map && res.data['data'] is Map) {
        return Map<String, dynamic>.from(res.data['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Hydrate complete sale receipt details including line items & store profile (GET /api/v1/pos/sales/{id})
  Future<Map<String, dynamic>?> fetchSaleDetail(int saleId) async {
    if (saleId <= 0) return null;
    try {
      final res = await _apiClient.dio.get(ApiEndpoints.saleDetail(saleId));
      if (res.data is Map && res.data['data'] is Map) {
        return Map<String, dynamic>.from(res.data['data'] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Fetch return / refund reason options (GET /api/v1/pos/return-reasons)
  Future<List<Map<String, dynamic>>> fetchReturnReasons() async {
    if (state.returnReasons.isNotEmpty) return state.returnReasons;
    try {
      final res = await _apiClient.dio.get(ApiEndpoints.returnReasons);
      final raw = res.data['data'] as List<dynamic>?;
      if (raw != null && raw.isNotEmpty) {
        final reasons = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _emitState(state.copyWith(returnReasons: reasons));
        return reasons;
      }
    } catch (_) {}
    return state.returnReasons;
  }

  /// Void a completed sale (POST /api/v1/pos/sales/{id}/void)
  /// A.4: Also locally reverses physical stock (skipping service items) and restores Store Credit / Kasbon.
  Future<void> voidSaleTransaction(int saleId, String reason) async {
    final existingHistory = _offlineDb.getLocalSalesHistory();
    Map<String, dynamic>? targetSale;
    for (final s in existingHistory) {
      if ((s['id'] as num?)?.toInt() == saleId) {
        targetSale = Map<String, dynamic>.from(s);
        break;
      }
    }

    await _offlineDb.updateLocalSaleStatus(saleId, 'voided', voidReason: reason);
    try {
      await _apiClient.dio.post(
        ApiEndpoints.voidSale(saleId),
        data: {'reason': reason},
      );
    } catch (_) {}

    List<ProductModel> nextProducts = state.allProducts;
    List<Map<String, dynamic>> nextCustomers = state.customers;
    Map<String, dynamic>? nextSelectedCustomer = state.selectedCustomer;

    if (targetSale != null && targetSale['status']?.toString() != 'voided') {
      final reversal = PosFinancialCalculator.computeVoidReversal(targetSale);

      if (reversal.restoredPhysicalStockByProduct.isNotEmpty) {
        nextProducts = state.allProducts.map((p) {
          final restoreQty = reversal.restoredPhysicalStockByProduct[p.id] ?? 0.0;
          if (restoreQty <= 0 || p.isServiceOrNonStockItem) return p;
          final restoredStock = (p.stock + restoreQty).clamp(0.0, double.infinity);
          _offlineDb.updateLocalProductStock(p.id, restoredStock);
          _offlineDb.recordLocalStockMovement(
            productId: p.id,
            productName: p.name,
            sku: p.sku,
            unitCode: p.unitCode,
            type: 'void_restore',
            quantityDelta: restoreQty,
            quantityAfter: restoredStock,
            unitCost: p.costPrice,
            notes: 'Void Nota #${targetSale?['number'] ?? saleId}: $reason',
          );
          return ProductModel.fromJson({
            ...p.toJson(),
            'stock': restoredStock,
            'is_low_stock': restoredStock <= p.reorderLevel,
          });
        }).toList();
      }

      final custId = (targetSale['customer'] is Map)
          ? ((targetSale['customer'] as Map)['id'] as num?)?.toInt()
          : (targetSale['customer_id'] as num?)?.toInt();
      if (custId != null &&
          custId > 0 &&
          (reversal.restoredStoreCredit > 0 || reversal.reversedCreditBalanceDue > 0)) {
        nextCustomers = state.customers.map((c) {
          if ((c['id'] as num?)?.toInt() != custId) return c;
          final updated = Map<String, dynamic>.from(c);
          final curDeposit = (updated['store_credit_balance'] as num?)?.toDouble() ?? 0.0;
          final curDebt = (updated['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
          updated['store_credit_balance'] =
              (curDeposit + reversal.restoredStoreCredit).roundToDouble();
          updated['outstanding_balance'] = (curDebt - reversal.reversedCreditBalanceDue)
              .clamp(0.0, double.infinity)
              .roundToDouble();
          return updated;
        }).toList();
        await _offlineDb.cacheCustomers(nextCustomers);
        if ((nextSelectedCustomer?['id'] as num?)?.toInt() == custId) {
          nextSelectedCustomer = nextCustomers.firstWhere(
            (c) => (c['id'] as num?)?.toInt() == custId,
            orElse: () => nextSelectedCustomer!,
          );
        }
      }
    }

    _emitState(state.copyWith(
      allProducts: nextProducts,
      customers: nextCustomers,
      selectedCustomer: nextSelectedCustomer,
      salesHistory: _offlineDb.getLocalSalesHistory(),
    ));
  }

  /// Refund / Return a completed sale (POST /api/v1/pos/sales/{id}/refund)
  Future<void> refundSaleTransaction(
    int saleId, {
    String? notes,
    int? reasonCodeId,
  }) async {
    await _offlineDb.updateLocalSaleStatus(saleId, 'refunded', voidReason: notes ?? 'Retur Pelanggan');
    try {
      await _apiClient.dio.post(
        ApiEndpoints.refundSale(saleId),
        data: {
          if (reasonCodeId != null) 'reason_code_id': reasonCodeId,
          'restock': true,
          'notes': notes ?? 'Retur Pelanggan via OXORA Mobile POS',
        },
      );
    } catch (_) {}
    _emitState(state.copyWith(salesHistory: _offlineDb.getLocalSalesHistory()));
  }
}
