import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/barcode_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../models/pos_models.dart';

class PosState extends Equatable {
  final bool isLoading;
  final bool isOnline;
  final bool isSyncingOfflineQueue;
  final BusinessVertical currentVertical;
  final String posMode; // 'retail' or 'restaurant'
  final String orderType; // 'retail', 'dine_in', 'takeaway', 'delivery'
  final List<ProductModel> allProducts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> suppliers;
  final int selectedCategoryId;
  final String searchQuery;
  final List<CartItemModel> cart;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedTable;
  final String? orderNotes;
  final double cartDiscountAmount;
  final bool managerDiscountApproved;
  final int redeemedLoyaltyPoints;
  final List<Map<String, dynamic>> heldCarts;
  final List<Map<String, dynamic>> salesHistory;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> returnReasons;
  final int offlinePendingCount;
  final String? alertMessage;

  const PosState({
    this.isLoading = false,
    this.isOnline = true,
    this.isSyncingOfflineQueue = false,
    this.currentVertical = BusinessVertical.retail,
    this.posMode = 'retail',
    this.orderType = 'retail',
    this.allProducts = const [],
    this.categories = const [],
    this.customers = const [],
    this.suppliers = const [],
    this.selectedCategoryId = 0,
    this.searchQuery = '',
    this.cart = const [],
    this.selectedCustomer,
    this.selectedTable,
    this.orderNotes,
    this.cartDiscountAmount = 0,
    this.managerDiscountApproved = false,
    this.redeemedLoyaltyPoints = 0,
    this.heldCarts = const [],
    this.salesHistory = const [],
    this.paymentMethods = const [],
    this.returnReasons = const [],
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

  int get expiringSoonCount => allProducts.where((p) => p.hasExpiringSoonBatch).length;

  VerticalCapabilities get capabilities => VerticalConfig.getCapabilities(currentVertical);

  PosState copyWith({
    bool? isLoading,
    bool? isOnline,
    bool? isSyncingOfflineQueue,
    BusinessVertical? currentVertical,
    String? posMode,
    String? orderType,
    List<ProductModel>? allProducts,
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? customers,
    List<Map<String, dynamic>>? suppliers,
    int? selectedCategoryId,
    String? searchQuery,
    List<CartItemModel>? cart,
    Map<String, dynamic>? selectedCustomer,
    bool clearCustomer = false,
    Map<String, dynamic>? selectedTable,
    bool clearTable = false,
    String? orderNotes,
    bool clearOrderNotes = false,
    double? cartDiscountAmount,
    bool? managerDiscountApproved,
    int? redeemedLoyaltyPoints,
    List<Map<String, dynamic>>? heldCarts,
    List<Map<String, dynamic>>? salesHistory,
    List<Map<String, dynamic>>? paymentMethods,
    List<Map<String, dynamic>>? returnReasons,
    int? offlinePendingCount,
    String? alertMessage,
  }) {
    return PosState(
      isLoading: isLoading ?? this.isLoading,
      isOnline: isOnline ?? this.isOnline,
      isSyncingOfflineQueue: isSyncingOfflineQueue ?? this.isSyncingOfflineQueue,
      currentVertical: currentVertical ?? this.currentVertical,
      posMode: posMode ?? this.posMode,
      orderType: orderType ?? this.orderType,
      allProducts: allProducts ?? this.allProducts,
      categories: categories ?? this.categories,
      customers: customers ?? this.customers,
      suppliers: suppliers ?? this.suppliers,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      searchQuery: searchQuery ?? this.searchQuery,
      cart: cart ?? this.cart,
      selectedCustomer: clearCustomer ? null : (selectedCustomer ?? this.selectedCustomer),
      selectedTable: clearTable ? null : (selectedTable ?? this.selectedTable),
      orderNotes: clearOrderNotes ? null : (orderNotes ?? this.orderNotes),
      cartDiscountAmount: cartDiscountAmount ?? this.cartDiscountAmount,
      managerDiscountApproved: managerDiscountApproved ?? this.managerDiscountApproved,
      redeemedLoyaltyPoints: redeemedLoyaltyPoints ?? this.redeemedLoyaltyPoints,
      heldCarts: heldCarts ?? this.heldCarts,
      salesHistory: salesHistory ?? this.salesHistory,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      returnReasons: returnReasons ?? this.returnReasons,
      offlinePendingCount: offlinePendingCount ?? this.offlinePendingCount,
      alertMessage: alertMessage,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isOnline,
        isSyncingOfflineQueue,
        currentVertical,
        posMode,
        orderType,
        allProducts,
        categories,
        customers,
        suppliers,
        selectedCategoryId,
        searchQuery,
        cart,
        selectedCustomer,
        selectedTable,
        orderNotes,
        cartDiscountAmount,
        managerDiscountApproved,
        redeemedLoyaltyPoints,
        heldCarts,
        salesHistory,
        paymentMethods,
        returnReasons,
        offlinePendingCount,
        alertMessage,
      ];
}

class PosCubit extends Cubit<PosState> {
  final ApiClient _apiClient;
  final OfflineDatabase _offlineDb;
  final NetworkConnectivityService _connectivityService;
  final _uuid = const Uuid();
  StreamSubscription<bool>? _connectivitySubscription;
  bool _wasOffline = false;
  bool _isAutoSyncRunning = false;

  PosCubit({
    required ApiClient apiClient,
    required OfflineDatabase offlineDb,
    NetworkConnectivityService? connectivityService,
  })  : _apiClient = apiClient,
        _offlineDb = offlineDb,
        _connectivityService = connectivityService ?? NetworkConnectivityService(),
        super(_buildInitialState(offlineDb));

  VerticalCapabilities get capabilities => VerticalConfig.getCapabilities(state.currentVertical);

  static BusinessVertical _resolveInitialVertical(OfflineDatabase offlineDb) {
    final saved = offlineDb.getSavedBusinessVertical();
    String? raw = (saved != null && saved.trim().isNotEmpty) ? saved : null;
    if (raw == null) {
      final cachedSession = offlineDb.getCachedAuthSession();
      final store = cachedSession?['active_store'];
      if (store is Map) {
        final pm = store['pos_mode']?.toString();
        final bt = store['business_type']?.toString();
        if (pm != null && pm.trim().isNotEmpty) {
          raw = pm;
        } else if (bt != null && bt.trim().isNotEmpty) {
          raw = bt;
        }
      }
    }
    final parsed = VerticalConfig.parse(raw);
    return parsed.isAvailable ? parsed : BusinessVertical.retail;
  }

  static PosState _buildInitialState(OfflineDatabase offlineDb) {
    final vertical = _resolveInitialVertical(offlineDb);
    final caps = VerticalConfig.getCapabilities(vertical);
    return PosState(
      currentVertical: vertical,
      posMode: vertical == BusinessVertical.restaurant ? 'restaurant' : 'retail',
      orderType: caps.hasDineInTakeawayOrderType ? 'dine_in' : 'retail',
    );
  }

  @override
  Future<void> close() async {
    await _connectivitySubscription?.cancel();
    return super.close();
  }

  /// Initialize POS catalog, categories, sales history & background reactive connectivity listener
  Future<void> initializeCatalog({bool seedDefaultCart = false}) async {
    emit(state.copyWith(isLoading: true));

    // Load local cache (SQLite-backed) first for instant rendering
    var localProducts = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    var localCategories = _offlineDb.getCachedCategories();
    var localCustomers = _offlineDb.getCachedCustomers();
    var localSuppliers = _offlineDb.getCachedSuppliers();
    var localHistory = _offlineDb.getLocalSalesHistory();

    List<CartItemModel> initialCart = state.cart;
    if (seedDefaultCart && initialCart.isEmpty && localProducts.length >= 2) {
      final p1 = localProducts[0];
      final p2 = localProducts[1];
      initialCart = [
        CartItemModel(
          product: p1,
          batch: p1.fefoBatch,
          quantity: 1,
          unitPrice: p1.sellingPrice,
          selectedUnitCode: p1.unitCode,
          multiplier: 1.0,
        ),
        CartItemModel(
          product: p2,
          batch: p2.fefoBatch,
          quantity: 2,
          unitPrice: p2.sellingPrice,
          selectedUnitCode: p2.unitCode,
          multiplier: 1.0,
        ),
      ];
    }

    final currentlyOnline = await _connectivityService.checkOnline();
    _wasOffline = !currentlyOnline;
    final resolvedVertical = _resolveInitialVertical(_offlineDb);
    final resolvedCaps = VerticalConfig.getCapabilities(resolvedVertical);

    emit(state.copyWith(
      isLoading: false,
      isOnline: currentlyOnline,
      currentVertical: resolvedVertical,
      posMode: resolvedVertical == BusinessVertical.restaurant ? 'restaurant' : 'retail',
      orderType: resolvedCaps.hasDineInTakeawayOrderType
          ? (state.orderType == 'retail' ? 'dine_in' : state.orderType)
          : 'retail',
      allProducts: localProducts,
      categories: localCategories,
      customers: localCustomers,
      suppliers: localSuppliers,
      cart: initialCart,
      salesHistory: localHistory,
      offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
    ));

    // Start reactive connectivity listener (Offline -> Online auto-drain & refresh)
    await _startConnectivityListener();

    // Sync with Cloud API if token is present and online
    final token = await _apiClient.getToken();
    if (currentlyOnline && token != null && token.isNotEmpty) {
      await syncWithCloud(force: false);
    }
  }

  Future<void> _startConnectivityListener() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityService.onOnlineChanged.listen((online) async {
      if (isClosed) return;
      if (!online) {
        _wasOffline = true;
        emit(state.copyWith(isOnline: false, isSyncingOfflineQueue: false));
        return;
      }

      final transitionedFromOffline = _wasOffline;
      _wasOffline = false;
      emit(state.copyWith(isOnline: true));

      if (transitionedFromOffline || state.offlinePendingCount > 0) {
        await _triggerReactiveAutoSync();
      }
    });
  }

  Future<void> _triggerReactiveAutoSync() async {
    if (_isAutoSyncRunning || isClosed) return;
    final token = await _apiClient.getToken();
    if (token == null || token.isEmpty) return;

    _isAutoSyncRunning = true;
    emit(state.copyWith(isOnline: true, isSyncingOfflineQueue: true));
    try {
      await _offlineDb.syncOfflineQueue(_apiClient);
      await syncWithCloud(force: true, preserveActiveCart: true);
    } catch (_) {
      // Errors handled gracefully inside syncWithCloud / syncOfflineQueue
    } finally {
      _isAutoSyncRunning = false;
      if (!isClosed) {
        emit(state.copyWith(
          isSyncingOfflineQueue: false,
          offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
        ));
      }
    }
  }

  /// Fast < 5ms indexed SQLite search helper
  Future<List<ProductModel>> searchProductsFast(String query) async {
    final rows = await _offlineDb.searchProductSql(query);
    return rows.map(ProductModel.fromJson).toList();
  }

  /// Authoritative Cloud Sync: auto-drain offline queue, then fetch products, categories, customers, suppliers & sales
  Future<void> syncWithCloud({
    bool force = false,
    bool preserveActiveCart = false,
  }) async {
    emit(state.copyWith(
      isLoading: true,
      isSyncingOfflineQueue: state.offlinePendingCount > 0 || state.isSyncingOfflineQueue,
    ));
    try {
      // 0. Drain pending offline transactions first
      await _offlineDb.syncOfflineQueue(_apiClient);

      // 1. Fetch real products from server
      final prodRes = await _apiClient.dio.get(ApiEndpoints.products, queryParameters: {'per_page': 200});
      final rawList = prodRes.data['data'] as List<dynamic>?;
      List<ProductModel> products = [];
      if (rawList != null) {
        final mapped = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        await _offlineDb.cacheProducts(mapped);
        products = mapped.map(ProductModel.fromJson).toList();
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

      // 3. Fetch real customers from server
      List<Map<String, dynamic>> customers = state.customers;
      try {
        final custRes = await _apiClient.dio.get(ApiEndpoints.customers, queryParameters: {'per_page': 200});
        final rawCust = custRes.data['data'] as List<dynamic>?;
        if (rawCust != null) {
          customers = rawCust.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await _offlineDb.cacheCustomers(customers);
        }
      } catch (_) {}

      // 4. Fetch real suppliers from server
      List<Map<String, dynamic>> suppliers = state.suppliers;
      try {
        final supRes = await _apiClient.dio.get(ApiEndpoints.suppliers, queryParameters: {'per_page': 200});
        final rawSup = supRes.data['data'] as List<dynamic>?;
        if (rawSup != null) {
          suppliers = rawSup.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          await _offlineDb.cacheSuppliers(suppliers);
        }
      } catch (_) {}

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
      final catalogProducts = products.isNotEmpty ? products : state.allProducts;
      List<Map<String, dynamic>> mergedHeldCarts = state.heldCarts;
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
              'notes': map['notes'],
              'subtotal': (map['grand_total'] as num?)?.toDouble() ??
                  (map['subtotal'] as num?)?.toDouble() ??
                  0.0,
              'held_at': (map['sale_datetime'] ?? '').toString(),
              'cart_items': cartItems,
            });
          }
          final serverIds = serverHeld.map((e) => e['id']).toSet();
          final localOnly = state.heldCarts
              .where((l) => !serverIds.contains(l['id']))
              .toList();
          mergedHeldCarts = [...serverHeld, ...localOnly];
        }
      } catch (_) {}

      List<Map<String, dynamic>> paymentMethods = state.paymentMethods;
      try {
        final pmRes = await _apiClient.dio.get(ApiEndpoints.paymentMethods);
        final rawPm = pmRes.data['data'] as List<dynamic>?;
        if (rawPm != null && rawPm.isNotEmpty) {
          paymentMethods = rawPm.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      List<Map<String, dynamic>> returnReasons = state.returnReasons;
      try {
        final rrRes = await _apiClient.dio.get(ApiEndpoints.returnReasons);
        final rawRr = rrRes.data['data'] as List<dynamic>?;
        if (rawRr != null && rawRr.isNotEmpty) {
          returnReasons = rawRr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      emit(state.copyWith(
        isLoading: false,
        isOnline: _apiClient.isOnline,
        isSyncingOfflineQueue: false,
        allProducts: catalogProducts,
        categories: categories,
        customers: customers,
        suppliers: suppliers,
        salesHistory: sales,
        heldCarts: mergedHeldCarts,
        paymentMethods: paymentMethods,
        returnReasons: returnReasons,
        offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
        cart: (force && !preserveActiveCart) ? [] : state.cart,
      ));
    } catch (_) {
      final online = await _connectivityService.checkOnline();
      _wasOffline = !online;
      emit(state.copyWith(
        isLoading: false,
        isOnline: online && _apiClient.isOnline,
        isSyncingOfflineQueue: false,
        offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
      ));
    }
  }

  Future<void> setBusinessVertical(BusinessVertical vertical) async {
    final effective = vertical.isAvailable ? vertical : BusinessVertical.retail;
    await _offlineDb.setSavedBusinessVertical(effective.key);
    final caps = VerticalConfig.getCapabilities(effective);
    emit(state.copyWith(
      currentVertical: effective,
      posMode: effective == BusinessVertical.restaurant ? 'restaurant' : 'retail',
      orderType: caps.hasDineInTakeawayOrderType ? 'dine_in' : 'retail',
      clearTable: !caps.hasTableManagement,
      clearOrderNotes: true,
    ));
  }

  void setOrderNotes(String? notes) {
    final trimmed = notes?.trim() ?? '';
    if (trimmed.isEmpty) {
      emit(state.copyWith(clearOrderNotes: true));
    } else {
      emit(state.copyWith(orderNotes: trimmed));
    }
  }

  Future<void> setPosMode(String mode) async {
    await setBusinessVertical(VerticalConfig.parse(mode));
  }

  void setOrderType(String orderType) {
    emit(state.copyWith(
      orderType: orderType,
      currentVertical: orderType == 'dine_in' ? BusinessVertical.restaurant : state.currentVertical,
      posMode: orderType == 'dine_in' ? 'restaurant' : state.posMode,
    ));
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
      emit(state.copyWith(
        selectedTable: table,
        currentVertical: BusinessVertical.restaurant,
        posMode: 'restaurant',
        orderType: 'dine_in',
      ));
    }
  }

  /// Add product to cart with FEFO Batch Expired Guard & Multi-Satuan support
  void addToCart(
    ProductModel product, {
    ProductVariantModel? variant,
    double quantity = 1.0,
    double? customUnitPrice,
    String? notes,
    String? digitalTargetValue,
    ProductUnitConversion? unitConversion,
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
    final String unitCode = unitConversion?.unitCode ?? product.unitCode;
    final double multiplier = unitConversion?.multiplier ?? 1.0;
    final double price = customUnitPrice ??
        unitConversion?.price ??
        variant?.sellingPrice ??
        product.sellingPrice;
    final updated = List<CartItemModel>.from(state.cart);

    final existingIdx = updated.indexWhere(
      (item) =>
          item.product.id == product.id &&
          item.variant?.id == variant?.id &&
          item.effectiveUnitCode == unitCode,
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
          selectedUnitCode: unitCode,
          multiplier: multiplier,
        ),
      );
    }

    emit(state.copyWith(cart: updated, alertMessage: null));
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
    emit(state.copyWith(cart: updated));
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

  void updateCartItemQuantity(int index, double quantity) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart);
    if (quantity <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(quantity: quantity);
    }
    emit(state.copyWith(cart: updated));
  }

  void updateCartItemDetails(
    int index, {
    double? quantity,
    double? discountAmount,
    String? notes,
  }) {
    if (index < 0 || index >= state.cart.length) return;
    final updated = List<CartItemModel>.from(state.cart);
    if (quantity != null && quantity <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(
        quantity: quantity,
        discountAmount: discountAmount,
        notes: notes,
      );
    }
    emit(state.copyWith(cart: updated));
  }

  void removeCartItem(int index) {
    if (index < 0 || index >= state.cart.length) return;
    PosFeedback.onTapStepper();
    final updated = List<CartItemModel>.from(state.cart)..removeAt(index);
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
          emit(state.copyWith(managerDiscountApproved: true));
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Apply manual cart discount (requires server Manager PIN approval if > 15% of subtotal)
  bool applyCartDiscount(double discountAmount) {
    final maxCashierDiscount = state.subtotal * 0.15;
    if (discountAmount > maxCashierDiscount && !state.managerDiscountApproved) {
      PosFeedback.onGuardBlocked();
      return false; // Trigger Manager PIN Override Dialog in UI
    }
    emit(state.copyWith(cartDiscountAmount: discountAmount));
    return true;
  }

  void setRedeemedLoyaltyPoints(int points) {
    emit(state.copyWith(redeemedLoyaltyPoints: points));
  }

  /// Hold / Park current cart (POST /api/v1/pos/hold)
  Future<void> holdCurrentCart(String label) async {
    if (state.cart.isEmpty) return;
    final itemsToHold = List<CartItemModel>.from(state.cart);
    final heldEntry = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'number': 'HOLD-${DateTime.now().minute}${DateTime.now().second}',
      'held_label': label.trim().isEmpty ? 'Pelanggan Antre' : label.trim(),
      'table_name': state.selectedTable?['name'],
      if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
        'notes': state.orderNotes!.trim(),
      'subtotal': state.grandTotal,
      'held_at': DateFormat('HH:mm').format(DateTime.now()),
      'cart_items': itemsToHold,
    };

    final updatedHeld = [heldEntry, ...state.heldCarts];
    emit(state.copyWith(
      heldCarts: updatedHeld,
      cart: [],
      cartDiscountAmount: 0,
      redeemedLoyaltyPoints: 0,
      clearOrderNotes: true,
    ));

    try {
      await _apiClient.dio.post(ApiEndpoints.holdCart, data: {
        'held_label': heldEntry['held_label'],
        if (heldEntry['notes'] != null) 'notes': heldEntry['notes'],
        'items': itemsToHold
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
    final notes = held['notes']?.toString();
    final remainingHeld = List<Map<String, dynamic>>.from(state.heldCarts)..removeAt(index);
    emit(state.copyWith(
      cart: items,
      heldCarts: remainingHeld,
      orderNotes: (notes != null && notes.trim().isNotEmpty) ? notes.trim() : null,
      clearOrderNotes: notes == null || notes.trim().isEmpty,
    ));
  }

  /// Complete POS Checkout (POST /api/v1/pos/checkout with UUIDv4 Idempotency + Offline Queue + Split Bill support)
  Future<Map<String, dynamic>> completeCheckout({
    required List<Map<String, dynamic>> payments,
    required List<String> paymentMethodNames,
    required double paidTotal,
    required double changeReturned,
    required double balanceDue,
    List<int>? splitItemIndices,
    String? orderTypeOverride,
    String? dueDate,
  }) async {
    final isPartialSplit = splitItemIndices != null && splitItemIndices.isNotEmpty;
    final selectedSet = splitItemIndices?.toSet() ?? <int>{};
    final checkoutCart = isPartialSplit
        ? [
            for (int i = 0; i < state.cart.length; i++)
              if (selectedSet.contains(i)) state.cart[i],
          ]
        : List<CartItemModel>.from(state.cart);

    final localUuid = _uuid.v4();
    final invoiceNo = '#INV-${(state.salesHistory.length + 1).toString().padLeft(4, '0')}';
    final nowFormatted = DateFormat('dd MMM yyyy • HH:mm').format(DateTime.now());
    final resolvedOrderType = orderTypeOverride ??
        (state.posMode == 'restaurant' && state.orderType == 'retail' ? 'dine_in' : state.orderType);

    final checkoutSubtotal = checkoutCart.fold<double>(0.0, (sum, c) => sum + c.lineTotal);
    final appliedOrderDiscount = isPartialSplit ? 0.0 : state.totalDiscount;
    final checkoutGrandTotal = (checkoutSubtotal - appliedOrderDiscount).clamp(0.0, double.infinity);

    // Fold order-level discount (manual cart, customer group, loyalty) proportionally into line discounts
    double remainingOrderDisc = appliedOrderDiscount;
    final itemMaps = <Map<String, dynamic>>[];
    for (int i = 0; i < checkoutCart.length; i++) {
      final c = checkoutCart[i];
      double extraDisc = 0.0;
      if (appliedOrderDiscount > 0 && checkoutSubtotal > 0) {
        if (i == checkoutCart.length - 1) {
          extraDisc = remainingOrderDisc;
        } else {
          extraDisc = ((c.lineTotal / checkoutSubtotal) * appliedOrderDiscount).roundToDouble();
          remainingOrderDisc -= extraDisc;
        }
      }
      final combinedDiscount = c.discountAmount + extraDisc;
      itemMaps.add({
        'product_id': c.product.id,
        'variant_id': c.variant?.id,
        'batch_id': c.batch?.id,
        'product_name': c.displayName,
        'unit_code': c.effectiveUnitCode,
        'multiplier': c.multiplier,
        'quantity': c.quantity,
        'unit_price': c.unitPrice,
        'discount_amount': combinedDiscount,
        'line_total': (c.lineSubtotal - combinedDiscount).clamp(0.0, double.infinity),
        'notes': c.notes,
        'digital_target_value': c.digitalTargetValue,
      });
    }

    final receiptPayload = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch,
      'number': invoiceNo,
      'local_uuid': localUuid,
      'sale_datetime': nowFormatted,
      'subtotal': checkoutSubtotal,
      'discount_total': appliedOrderDiscount,
      'tax_total': 0.0,
      'grand_total': checkoutGrandTotal,
      'paid_total': paidTotal,
      'change_returned': changeReturned,
      'balance_due': balanceDue,
      if (dueDate != null && dueDate.isNotEmpty) 'due_date': dueDate,
      'status': 'completed',
      'order_type': resolvedOrderType,
      'table_name': state.selectedTable?['name'],
      if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
        'notes': state.orderNotes!.trim(),
      'payment_methods': paymentMethodNames,
      'customer': state.selectedCustomer ?? {'id': 0, 'name': 'Pelanggan Umum', 'phone': '-'},
      'items': itemMaps,
      'payments': payments,
    };

    // Deduct local stock immediately (multiplied by selected unit multiplier)
    final updatedProducts = state.allProducts.map((p) {
      final soldBaseQty = checkoutCart
          .where((c) => c.product.id == p.id)
          .fold<double>(0.0, (sum, c) => sum + (c.quantity * c.multiplier));
      if (soldBaseQty > 0) {
        final newStock = (p.stock - soldBaseQty).clamp(0.0, double.infinity);
        _offlineDb.updateLocalProductStock(p.id, newStock);
        return ProductModel.fromJson({
          ...p.toJson(),
          'stock': newStock,
          'is_low_stock': newStock <= 5,
        });
      }
      return p;
    }).toList();

    final apiBody = <String, dynamic>{
      'local_uuid': localUuid,
      'customer_id': state.selectedCustomer?['id'],
      'order_type': resolvedOrderType,
      'table_id': state.selectedTable?['id'],
      if (state.orderNotes != null && state.orderNotes!.trim().isNotEmpty)
        'notes': state.orderNotes!.trim(),
      if (!isPartialSplit && state.redeemedLoyaltyPoints > 0)
        'redeem_points': state.redeemedLoyaltyPoints,
      if (dueDate != null && dueDate.isNotEmpty) 'due_date': dueDate,
      'items': itemMaps,
      'payments': payments,
    };

    // Attempt live Cloud Checkout; if offline, enqueue in OfflineSaleQueue
    bool checkoutSyncedOnline = true;
    try {
      final res = await _apiClient.dio.post(ApiEndpoints.checkout, data: apiBody);
      final serverData = res.data['data'] as Map<String, dynamic>?;
      if (serverData != null) {
        if (serverData['number'] != null) receiptPayload['number'] = serverData['number'];
        if (serverData['id'] != null) receiptPayload['id'] = serverData['id'];
      }
    } catch (_) {
      checkoutSyncedOnline = false;
      await _offlineDb.enqueueOfflineSale(apiBody);
    }

    await _offlineDb.saveSaleToLocalHistory(receiptPayload);
    final updatedHistory = _offlineDb.getLocalSalesHistory();

    final remainingCart = isPartialSplit
        ? [
            for (int i = 0; i < state.cart.length; i++)
              if (!selectedSet.contains(i)) state.cart[i],
          ]
        : <CartItemModel>[];

    await PosFeedback.onCheckoutSuccess();

    emit(state.copyWith(
      isOnline: checkoutSyncedOnline ? true : state.isOnline,
      allProducts: updatedProducts,
      cart: remainingCart,
      cartDiscountAmount: remainingCart.isEmpty ? 0 : state.cartDiscountAmount,
      managerDiscountApproved: remainingCart.isEmpty ? false : state.managerDiscountApproved,
      redeemedLoyaltyPoints: remainingCart.isEmpty ? 0 : state.redeemedLoyaltyPoints,
      clearTable: remainingCart.isEmpty,
      clearOrderNotes: remainingCart.isEmpty,
      salesHistory: updatedHistory,
      offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
    ));

    return receiptPayload;
  }

  /// Server-side authoritative cart pricing verification (POST /api/v1/pos/price-cart)
  Future<Map<String, dynamic>?> verifyServerCartPrice({
    int? customerId,
    int redeemPoints = 0,
  }) async {
    if (state.cart.isEmpty) return null;
    try {
      final res = await _apiClient.dio.post(
        ApiEndpoints.priceCart,
        data: {
          if (customerId != null) 'customer_id': customerId,
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (state.cartDiscountAmount > 0)
            'discount': {'type': 'fixed', 'value': state.cartDiscountAmount},
          'items': state.cart
              .map((c) => {
                    'product_id': c.product.id,
                    'variant_id': c.variant?.id,
                    'quantity': c.quantity,
                    'unit_price': c.unitPrice,
                    if (c.discountAmount > 0) 'discount_amount': c.discountAmount,
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
        emit(state.copyWith(returnReasons: reasons));
        return reasons;
      }
    } catch (_) {}
    return state.returnReasons;
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
          'notes': notes ?? 'Retur Pelanggan via NusaPOS Mobile',
        },
      );
    } catch (_) {}
    emit(state.copyWith(salesHistory: _offlineDb.getLocalSalesHistory()));
  }

  /// Add or update product in Inventory & Stock Opname
  /// Supports POST /api/v1/products (new) and POST /api/v1/products/{id}/adjust-stock (existing)
  Future<void> saveProductInventory(
    ProductModel product, {
    bool isNew = false,
    String notes = 'Stock Opname via NusaPOS Mobile',
  }) async {
    final bool isBrandNew = isNew || product.id <= 0 || product.id > 1000000000;

    try {
      if (isBrandNew) {
        await _apiClient.dio.post(
          ApiEndpoints.products,
          data: {
            'name': product.name,
            'sku': product.sku,
            'barcode': product.barcode,
            'selling_price': product.sellingPrice,
            'cost_price': product.costPrice,
            'initial_stock': product.stock,
            'category_id': product.categoryId > 0 ? product.categoryId : null,
            'shelf_location': product.shelfLocation,
            'type': product.type,
            'sold_by_weight': product.soldByWeight,
          },
        );
      } else {
        await _apiClient.dio.post(
          ApiEndpoints.adjustProductStock(product.id),
          data: {
            'new_quantity': product.stock,
            'name': product.name,
            'barcode': product.barcode,
            'selling_price': product.sellingPrice,
            'unit_cost': product.costPrice,
            'category_id': product.categoryId > 0 ? product.categoryId : null,
            'shelf_location': product.shelfLocation,
            'notes': notes,
          },
        );
      }
      await syncWithCloud(force: false);
    } catch (_) {
      // Local fallback for offline mode
      await _offlineDb.addOrUpdateLocalProduct(product.toJson());
      final updated = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
      emit(state.copyWith(allProducts: updated));
    }
  }

  /// Create or update Customer & Member (POST/PUT /api/v1/customers)
  Future<Map<String, dynamic>> saveCustomer(
    Map<String, dynamic> payload, {
    int? id,
    bool selectAfterSave = false,
  }) async {
    try {
      final res = id != null && id > 0
          ? await _apiClient.dio.put(ApiEndpoints.customerDetail(id), data: payload)
          : await _apiClient.dio.post(ApiEndpoints.customers, data: payload);
      final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
      await _offlineDb.addOrUpdateLocalCustomer(saved);
      final updatedList = _offlineDb.getCachedCustomers();
      final shouldSelect = selectAfterSave || (state.selectedCustomer?['id'] == saved['id']);
      emit(state.copyWith(
        customers: updatedList,
        selectedCustomer: shouldSelect ? saved : state.selectedCustomer,
      ));
      return {'success': true, 'data': saved};
    } catch (e) {
      // Offline cache fallback if backend unreachable during demo/offline
      if (id == null) {
        final localEntry = {
          'id': DateTime.now().millisecondsSinceEpoch,
          ...payload,
          'loyalty_points': payload['loyalty_points'] ?? 0,
          'outstanding_balance': 0.0,
        };
        await _offlineDb.addOrUpdateLocalCustomer(localEntry);
        final updatedList = _offlineDb.getCachedCustomers();
        emit(state.copyWith(
          customers: updatedList,
          selectedCustomer: selectAfterSave ? localEntry : state.selectedCustomer,
        ));
        return {'success': true, 'offline': true, 'data': localEntry};
      }
      return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
    }
  }

  /// Create or update Supplier (POST/PUT /api/v1/suppliers)
  Future<Map<String, dynamic>> saveSupplier(
    Map<String, dynamic> payload, {
    int? id,
  }) async {
    try {
      final res = id != null && id > 0
          ? await _apiClient.dio.put(ApiEndpoints.supplierDetail(id), data: payload)
          : await _apiClient.dio.post(ApiEndpoints.suppliers, data: payload);
      final saved = Map<String, dynamic>.from((res.data['data'] as Map?) ?? payload);
      await _offlineDb.addOrUpdateLocalSupplier(saved);
      emit(state.copyWith(suppliers: _offlineDb.getCachedSuppliers()));
      return {'success': true, 'data': saved};
    } catch (e) {
      return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
    }
  }

  /// Record Quick Stock In Purchase (POST /api/v1/purchases/quick-stock-in)
  Future<Map<String, dynamic>> submitQuickStockIn(Map<String, dynamic> payload) async {
    try {
      final res = await _apiClient.dio.post(ApiEndpoints.quickStockIn, data: payload);
      await syncWithCloud(force: false);
      return {'success': true, 'data': res.data['data']};
    } catch (e) {
      return {'success': false, 'message': ApiClient.extractErrorMessage(e)};
    }
  }

  /// Sync pending offline transactions manually
  Future<int> syncOfflineTransactions() async {
    emit(state.copyWith(isSyncingOfflineQueue: true));
    try {
      final synced = await _offlineDb.syncOfflineQueue(_apiClient);
      final online = await _connectivityService.checkOnline();
      if (online) {
        await syncWithCloud(force: false, preserveActiveCart: true);
      }
      emit(state.copyWith(
        isOnline: online,
        isSyncingOfflineQueue: false,
        offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
      ));
      return synced;
    } catch (_) {
      emit(state.copyWith(
        isSyncingOfflineQueue: false,
        offlinePendingCount: _offlineDb.getOfflineSalesQueue().length,
      ));
      return 0;
    }
  }
}
