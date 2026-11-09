import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/barcode_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/currency_formatter.dart';
import '../models/pos_models.dart';

class PosState extends Equatable {
  final bool isLoading;
  final String posMode; // 'retail' or 'restaurant'
  final List<ProductModel> allProducts;
  final List<Map<String, dynamic>> categories;
  final int selectedCategoryId;
  final String searchQuery;
  final List<CartItemModel> cart;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedTable;
  final double cartDiscountAmount;
  final bool managerDiscountApproved;
  final int redeemedLoyaltyPoints;
  final List<Map<String, dynamic>> heldCarts;
  final List<Map<String, dynamic>> salesHistory;
  final int offlinePendingCount;
  final String? alertMessage;

  const PosState({
    this.isLoading = false,
    this.posMode = 'retail',
    this.allProducts = const [],
    this.categories = const [],
    this.selectedCategoryId = 0,
    this.searchQuery = '',
    this.cart = const [],
    this.selectedCustomer,
    this.selectedTable,
    this.cartDiscountAmount = 0,
    this.managerDiscountApproved = false,
    this.redeemedLoyaltyPoints = 0,
    this.heldCarts = const [],
    this.salesHistory = const [],
    this.offlinePendingCount = 0,
    this.alertMessage,
  });

  List<ProductModel> get filteredProducts {
    return allProducts.where((p) {
      final matchesCat = selectedCategoryId == 0 || p.categoryId == selectedCategoryId;
      if (!matchesCat) return false;
      if (searchQuery.trim().isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          (p.scalePlu != null && p.scalePlu!.contains(q));
    }).toList();
  }

  double get totalItemsCount => cart.fold(0.0, (sum, item) => sum + item.quantity);

  double get subtotal => cart.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get customerGroupDiscount {
    final pct = (selectedCustomer?['default_discount_percent'] as num?)?.toDouble() ?? 0.0;
    if (pct <= 0) return 0.0;
    return (subtotal * (pct / 100.0)).roundToDouble();
  }

  double get loyaltyDiscountValue => redeemedLoyaltyPoints * 100.0; // 1 point = Rp 100

  double get totalDiscount => cartDiscountAmount + customerGroupDiscount + loyaltyDiscountValue;

  double get grandTotal => (subtotal - totalDiscount).clamp(0.0, double.infinity);

  int get lowStockProductsCount => allProducts.where((p) => p.isLowStock).length;

  PosState copyWith({
    bool? isLoading,
    String? posMode,
    List<ProductModel>? allProducts,
    List<Map<String, dynamic>>? categories,
    int? selectedCategoryId,
    String? searchQuery,
    List<CartItemModel>? cart,
    Map<String, dynamic>? selectedCustomer,
    bool clearCustomer = false,
    Map<String, dynamic>? selectedTable,
    bool clearTable = false,
    double? cartDiscountAmount,
    bool? managerDiscountApproved,
    int? redeemedLoyaltyPoints,
    List<Map<String, dynamic>>? heldCarts,
    List<Map<String, dynamic>>? salesHistory,
    int? offlinePendingCount,
    String? alertMessage,
  }) {
    return PosState(
      isLoading: isLoading ?? this.isLoading,
      posMode: posMode ?? this.posMode,
      allProducts: allProducts ?? this.allProducts,
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      searchQuery: searchQuery ?? this.searchQuery,
      cart: cart ?? this.cart,
      selectedCustomer: clearCustomer ? null : (selectedCustomer ?? this.selectedCustomer),
      selectedTable: clearTable ? null : (selectedTable ?? this.selectedTable),
      cartDiscountAmount: cartDiscountAmount ?? this.cartDiscountAmount,
      managerDiscountApproved: managerDiscountApproved ?? this.managerDiscountApproved,
      redeemedLoyaltyPoints: redeemedLoyaltyPoints ?? this.redeemedLoyaltyPoints,
      heldCarts: heldCarts ?? this.heldCarts,
      salesHistory: salesHistory ?? this.salesHistory,
      offlinePendingCount: offlinePendingCount ?? this.offlinePendingCount,
      alertMessage: alertMessage,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        posMode,
        allProducts,
        categories,
        selectedCategoryId,
        searchQuery,
        cart,
        selectedCustomer,
        selectedTable,
        cartDiscountAmount,
        managerDiscountApproved,
        redeemedLoyaltyPoints,
        heldCarts,
        salesHistory,
        offlinePendingCount,
        alertMessage,
      ];
}

class PosCubit extends Cubit<PosState> {
  final ApiClient _apiClient;
  final OfflineDatabase _offlineDb;
  final _uuid = const Uuid();

  PosCubit({
    required ApiClient apiClient,
    required OfflineDatabase offlineDb,
  })  : _apiClient = apiClient,
        _offlineDb = offlineDb,
        super(const PosState());

  /// Initialize POS catalog, categories, sales history & default cart matching Mockup Screen 3
  Future<void> initializeCatalog({bool seedDefaultCart = true}) async {
    emit(state.copyWith(isLoading: true));

    // Load local cache first for 0ms instant rendering
    var localProducts = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    var localCategories = _offlineDb.getCachedCategories();
    var localHistory = _offlineDb.getLocalSalesHistory();

    // Pre-populate cart with Air Mineral x1 + Teh Botol x2 = Rp 17.000 (Matches Mockup Screen 3 & 4!)
    List<CartItemModel> initialCart = state.cart;
    if (seedDefaultCart && initialCart.isEmpty && localProducts.length >= 2) {
      final airMineral = localProducts.firstWhere((p) => p.id == 101, orElse: () => localProducts[0]);
      final tehBotol = localProducts.firstWhere((p) => p.id == 102, orElse: () => localProducts[1]);
      initialCart = [
        CartItemModel(
          product: airMineral,
          batch: airMineral.fefoBatch,
          quantity: 1,
          unitPrice: airMineral.sellingPrice,
        ),
        CartItemModel(
          product: tehBotol,
          batch: tehBotol.fefoBatch,
          quantity: 2,
          unitPrice: tehBotol.sellingPrice,
        ),
      ];
    }

    emit(state.copyWith(
      isLoading: false,
      allProducts: localProducts,
      categories: localCategories,
      cart: initialCart,
      salesHistory: localHistory,
      offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
    ));

    // Sync with Cloud API in background if reachable
    try {
      final prodRes = await _apiClient.dio.get(ApiEndpoints.products, queryParameters: {'per_page': 100});
      final rawList = prodRes.data['data'] as List<dynamic>?;
      if (rawList != null && rawList.isNotEmpty) {
        final mapped = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _offlineDb.cacheProducts(mapped);
        localProducts = mapped.map(ProductModel.fromJson).toList();
        emit(state.copyWith(allProducts: localProducts));
      }
    } catch (_) {
      // Offline mode continues using localProducts seamlessly
    }
  }

  void setPosMode(String mode) {
    emit(state.copyWith(posMode: mode));
  }

  void selectCategory(int categoryId) {
    emit(state.copyWith(selectedCategoryId: categoryId));
  }

  void updateSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  void selectCustomer(Map<String, dynamic>? customer) {
    if (customer == null) {
      emit(state.copyWith(clearCustomer: true, redeemedLoyaltyPoints: 0));
    } else {
      emit(state.copyWith(selectedCustomer: customer));
    }
  }

  void selectRestaurantTable(Map<String, dynamic>? table) {
    if (table == null) {
      emit(state.copyWith(clearTable: true));
    } else {
      emit(state.copyWith(selectedTable: table, posMode: 'restaurant'));
    }
  }

  /// Add product to cart with FEFO Batch Expired Guard
  void addToCart(
    ProductModel product, {
    ProductVariantModel? variant,
    double quantity = 1.0,
    double? customUnitPrice,
    String? notes,
    String? digitalTargetValue,
  }) {
    final batch = product.fefoBatch;
    if (batch != null && batch.isExpired) {
      PosFeedback.onGuardBlocked();
      emit(state.copyWith(
        alertMessage: 'BLOKIR FEFO: Batch ${batch.batchNumber} (${product.name}) sudah kedaluwarsa!',
      ));
      return;
    }

    PosFeedback.onScanSuccess();
    final price = customUnitPrice ?? variant?.sellingPrice ?? product.sellingPrice;
    final updated = List<CartItemModel>.from(state.cart);

    final existingIdx = updated.indexWhere(
      (item) => item.product.id == product.id && item.variant?.id == variant?.id,
    );

    if (existingIdx >= 0) {
      final current = updated[existingIdx];
      updated[existingIdx] = current.copyWith(
        quantity: current.quantity + quantity,
        notes: notes ?? current.notes,
        digitalTargetValue: digitalTargetValue ?? current.digitalTargetValue,
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
        ),
      );
    }

    emit(state.copyWith(cart: updated, alertMessage: null));
  }

  /// Handle camera or laser barcode scan (Supports Standard EAN & Scale Prefix 20/21)
  bool handleBarcodeScanned(String rawCode) {
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
    emit(state.copyWith(alertMessage: 'Barcode "${parsed.rawBarcode}" tidak ditemukan di katalog.'));
    return false;
  }

  void incrementCartItem(int index) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart);
    final item = updated[index];
    final step = item.product.soldByWeight ? 0.5 : 1.0;
    updated[index] = item.copyWith(quantity: item.quantity + step);
    emit(state.copyWith(cart: updated));
  }

  void decrementCartItem(int index) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart);
    final item = updated[index];
    final step = item.product.soldByWeight ? 0.5 : 1.0;
    if (item.quantity - step <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = item.copyWith(quantity: item.quantity - step);
    }
    emit(state.copyWith(cart: updated));
  }

  void updateCartItemNote(int index, String note) {
    if (index < 0 || index >= state.cart.length) return;
    final updated = List<CartItemModel>.from(state.cart);
    updated[index] = updated[index].copyWith(notes: note);
    emit(state.copyWith(cart: updated));
  }

  void clearCart() {
    PosFeedback.onTapStepper();
    emit(state.copyWith(
      cart: [],
      cartDiscountAmount: 0,
      managerDiscountApproved: false,
      redeemedLoyaltyPoints: 0,
      clearTable: true,
    ));
  }

  /// Apply manual cart discount (requires Manager PIN if > 15% of subtotal)
  bool applyCartDiscount(double discountAmount, {String? managerPin}) {
    final maxCashierDiscount = state.subtotal * 0.15;
    if (discountAmount > maxCashierDiscount && managerPin != '1234' && !state.managerDiscountApproved) {
      PosFeedback.onGuardBlocked();
      return false; // Trigger Manager PIN Override Dialog in UI
    }
    emit(state.copyWith(
      cartDiscountAmount: discountAmount,
      managerDiscountApproved: managerPin == '1234' || state.managerDiscountApproved,
    ));
    return true;
  }

  void setRedeemedLoyaltyPoints(int points) {
    emit(state.copyWith(redeemedLoyaltyPoints: points));
  }

  /// Hold / Park current cart (POST /api/v1/pos/hold)
  Future<void> holdCurrentCart(String label) async {
    if (state.cart.isEmpty) return;
    final heldEntry = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'number': 'HOLD-${DateTime.now().minute}${DateTime.now().second}',
      'held_label': label.trim().isEmpty ? 'Pelanggan Antre' : label.trim(),
      'table_name': state.selectedTable?['name'],
      'subtotal': state.grandTotal,
      'held_at': DateFormat('HH:mm').format(DateTime.now()),
      'cart_items': state.cart,
    };

    final updatedHeld = [heldEntry, ...state.heldCarts];
    emit(state.copyWith(
      heldCarts: updatedHeld,
      cart: [],
      cartDiscountAmount: 0,
      redeemedLoyaltyPoints: 0,
    ));

    try {
      await _apiClient.dio.post(ApiEndpoints.holdCart, data: {
        'held_label': heldEntry['held_label'],
        'items': state.cart
            .map((c) => {
                  'product_id': c.product.id,
                  'variant_id': c.variant?.id,
                  'quantity': c.quantity,
                  'unit_price': c.unitPrice,
                })
            .toList(),
      });
    } catch (_) {}
  }

  void resumeHeldCart(int index) {
    if (index < 0 || index >= state.heldCarts.length) return;
    final held = state.heldCarts[index];
    final items = (held['cart_items'] as List<CartItemModel>? ?? []);
    final remainingHeld = List<Map<String, dynamic>>.from(state.heldCarts)..removeAt(index);
    emit(state.copyWith(cart: items, heldCarts: remainingHeld));
  }

  /// Complete POS Checkout (POST /api/v1/pos/checkout with UUIDv4 Idempotency + Offline Queue)
  Future<Map<String, dynamic>> completeCheckout({
    required List<Map<String, dynamic>> payments,
    required List<String> paymentMethodNames,
    required double paidTotal,
    required double changeReturned,
    required double balanceDue,
  }) async {
    final localUuid = _uuid.v4();
    final invoiceNo = '#INV-${1025 + state.salesHistory.length}';
    final nowFormatted = DateFormat('dd MMM yyyy • HH:mm').format(DateTime.now());

    final itemMaps = state.cart
        .map((c) => {
              'product_id': c.product.id,
              'variant_id': c.variant?.id,
              'batch_id': c.batch?.id,
              'product_name': c.displayName,
              'quantity': c.quantity,
              'unit_price': c.unitPrice,
              'discount_amount': c.discountAmount,
              'line_total': c.lineTotal,
              'notes': c.notes,
              'digital_target_value': c.digitalTargetValue,
            })
        .toList();

    final receiptPayload = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch,
      'number': invoiceNo,
      'local_uuid': localUuid,
      'sale_datetime': nowFormatted,
      'subtotal': state.subtotal,
      'discount_total': state.totalDiscount,
      'tax_total': 0.0,
      'grand_total': state.grandTotal,
      'paid_total': paidTotal,
      'change_returned': changeReturned,
      'balance_due': balanceDue,
      'status': 'completed',
      'order_type': state.posMode == 'restaurant' ? 'dine_in' : 'retail',
      'table_name': state.selectedTable?['name'],
      'payment_methods': paymentMethodNames,
      'customer': state.selectedCustomer ?? {'id': 0, 'name': 'Pelanggan Umum', 'phone': '081234567890'},
      'items': itemMaps,
      'payments': payments,
    };

    // Deduct local stock immediately
    final updatedProducts = state.allProducts.map((p) {
      final soldQty = state.cart
          .where((c) => c.product.id == p.id)
          .fold<double>(0.0, (sum, c) => sum + c.quantity);
      if (soldQty > 0) {
        final newStock = (p.stock - soldQty).clamp(0.0, double.infinity);
        _offlineDb.updateLocalProductStock(p.id, newStock);
        return ProductModel.fromJson({
          ...p.toJson(),
          'stock': newStock,
          'is_low_stock': newStock <= 5,
        });
      }
      return p;
    }).toList();

    await _offlineDb.saveSaleToLocalHistory(receiptPayload);
    final updatedHistory = _offlineDb.getLocalSalesHistory();

    // Attempt live Cloud Checkout; if offline, enqueue in OfflineSaleQueue
    try {
      final res = await _apiClient.dio.post(
        ApiEndpoints.checkout,
        data: {
          'local_uuid': localUuid,
          'customer_id': state.selectedCustomer?['id'],
          'order_type': state.posMode == 'restaurant' ? 'dine_in' : null,
          'table_id': state.selectedTable?['id'],
          'items': itemMaps,
          'payments': payments,
        },
      );
      final serverData = res.data['data'] as Map<String, dynamic>?;
      if (serverData != null && serverData['number'] != null) {
        receiptPayload['number'] = serverData['number'];
      }
    } catch (_) {
      await _offlineDb.enqueueOfflineSale({
        'local_uuid': localUuid,
        'customer_id': state.selectedCustomer?['id'],
        'items': itemMaps,
        'payments': payments,
      });
    }

    await PosFeedback.onCheckoutSuccess();

    emit(state.copyWith(
      allProducts: updatedProducts,
      cart: [],
      cartDiscountAmount: 0,
      managerDiscountApproved: false,
      redeemedLoyaltyPoints: 0,
      clearTable: true,
      salesHistory: updatedHistory,
      offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
    ));

    return receiptPayload;
  }

  /// Void a completed sale (POST /api/v1/pos/sales/{id}/void)
  Future<void> voidSaleTransaction(int saleId, String reason) async {
    await _offlineDb.updateLocalSaleStatus(saleId, 'voided', voidReason: reason);
    try {
      await _apiClient.dio.post(
        ApiEndpoints.voidSale(saleId),
        data: {'reason': reason},
      );
    } catch (_) {}
    emit(state.copyWith(salesHistory: _offlineDb.getLocalSalesHistory()));
  }

  /// Add or update product in Inventory & Stock Opname
  Future<void> saveProductInventory(ProductModel product) async {
    await _offlineDb.addOrUpdateLocalProduct(product.toJson());
    final updated = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    emit(state.copyWith(allProducts: updated));
  }

  /// Sync pending offline transactions manually
  Future<int> syncOfflineTransactions() async {
    final synced = await _offlineDb.syncOfflineQueue(_apiClient);
    emit(state.copyWith(offlinePendingCount: _offlineDb.getOfflineSalesQueue().length));
    return synced;
  }
}
