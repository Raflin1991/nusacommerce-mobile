import 'dart:async';
import 'package:dio/dio.dart';
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
import '../utils/pos_financial_calculator.dart';

part 'pos_cubit_parity.dart';

class CheckoutServerException implements Exception {
  final String message;
  final String? errorCode;
  final int? statusCode;

  const CheckoutServerException({
    required this.message,
    this.errorCode,
    this.statusCode,
  });

  bool get isShiftRequired =>
      errorCode == 'ShiftRequired' ||
      message.toLowerCase().contains('shift kasir');

  @override
  String toString() => message;
}

class PosState extends Equatable {
  final bool isLoading;
  final bool isOnline;
  final bool isSyncingOfflineQueue;
  final bool isInitialRestoring;
  final double initialRestoreProgress;
  final String? initialRestoreStep;
  final String activeNodeCode;
  final BusinessVertical currentVertical;
  final String posMode; // 'retail' or 'restaurant'
  final String orderType; // 'retail', 'dine_in', 'takeaway', 'delivery'
  final List<ProductModel> allProducts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> suppliers;
  final int selectedCategoryId;
  final int selectedBrandId;
  final String searchQuery;
  final List<CartItemModel> cart;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedTable;
  final String? orderNotes;
  final Map<String, dynamic> verticalMetadata;
  final double cartDiscountAmount;
  final bool managerDiscountApproved;
  final int redeemedLoyaltyPoints;
  final List<Map<String, dynamic>> heldCarts;
  final List<Map<String, dynamic>> salesHistory;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> returnReasons;
  final List<Map<String, dynamic>> brands;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> expenseCategories;
  final List<Map<String, dynamic>> customerGroups;
  final List<Map<String, dynamic>> localSyncConflicts;
  final List<Map<String, dynamic>> deadLetterItems;
  final int? activeHeldSaleId;
  final Map<String, dynamic>? exchangeSourceSale;
  final int offlinePendingCount;
  final String? alertMessage;

  const PosState({
    this.isLoading = false,
    this.isOnline = true,
    this.isSyncingOfflineQueue = false,
    this.isInitialRestoring = false,
    this.initialRestoreProgress = 0.0,
    this.initialRestoreStep,
    this.activeNodeCode = 'M01',
    this.currentVertical = BusinessVertical.retail,
    this.posMode = 'retail',
    this.orderType = 'retail',
    this.allProducts = const [],
    this.categories = const [],
    this.customers = const [],
    this.suppliers = const [],
    this.selectedCategoryId = 0,
    this.selectedBrandId = 0,
    this.searchQuery = '',
    this.cart = const [],
    this.selectedCustomer,
    this.selectedTable,
    this.orderNotes,
    this.verticalMetadata = const {},
    this.cartDiscountAmount = 0,
    this.managerDiscountApproved = false,
    this.redeemedLoyaltyPoints = 0,
    this.heldCarts = const [],
    this.salesHistory = const [],
    this.paymentMethods = const [],
    this.returnReasons = const [],
    this.brands = const [],
    this.units = const [],
    this.expenseCategories = const [],
    this.customerGroups = const [],
    this.localSyncConflicts = const [],
    this.deadLetterItems = const [],
    this.activeHeldSaleId,
    this.exchangeSourceSale,
    this.offlinePendingCount = 0,
    this.alertMessage,
  });

  List<ProductModel> get filteredProducts {
    return allProducts.where((p) {
      // Cloud POS & APK POS consistency: tracked physical products with 0 balance do NOT appear in POS catalog
      if (!p.isSellableInPos) return false;
      final matchesCat = selectedCategoryId == 0 || p.categoryId == selectedCategoryId;
      if (!matchesCat) return false;
      final matchesBrand = selectedBrandId == 0 || p.brandId == selectedBrandId;
      if (!matchesBrand) return false;
      if (searchQuery.trim().isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          p.categoryName.toLowerCase().contains(q) ||
          (p.brandName != null && p.brandName!.toLowerCase().contains(q)) ||
          (p.scalePlu != null && p.scalePlu!.contains(q));
    }).toList();
  }

  /// Categories with at least one sellable POS item (always keeping 'Semua' at id=0)
  List<Map<String, dynamic>> get posCategories {
    final sellableCatIds = allProducts
        .where((p) => p.isSellableInPos)
        .map((p) => p.categoryId)
        .toSet();
    return categories.where((c) {
      final id = (c['id'] as num?)?.toInt() ?? 0;
      return id == 0 || sellableCatIds.contains(id);
    }).toList();
  }

  /// Brands with at least one sellable POS item (always keeping 'Semua Merek' at id=0)
  List<Map<String, dynamic>> get posBrands {
    final sellableBrandNames = <int, String>{};
    for (final p in allProducts) {
      if (!p.isSellableInPos) continue;
      final bid = p.brandId;
      final bname = p.brandName?.trim();
      if (bid != null && bid > 0 && bname != null && bname.isNotEmpty) {
        sellableBrandNames[bid] = bname;
      }
    }
    if (sellableBrandNames.isEmpty) return const [];
    final entries = sellableBrandNames.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return [
      {'id': 0, 'name': 'Semua Merek'},
      for (final e in entries) {'id': e.key, 'name': e.value},
    ];
  }

  bool get isExchangeMode =>
      exchangeSourceSale != null || cart.any((c) => c.isExchangeReturn);

  double get exchangeReturnCreditTotal => cart
      .where((c) => c.isExchangeReturn)
      .fold(0.0, (sum, c) => sum + c.lineTotal.abs());

  double get replacementItemsSubtotal => cart
      .where((c) => !c.isExchangeReturn)
      .fold(0.0, (sum, c) => sum + c.lineTotal);

  double get totalItemsCount =>
      cart.fold(0.0, (sum, item) => sum + item.quantity.abs());

  double get subtotal => cart.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get customerGroupDiscount {
    final pct = (selectedCustomer?['default_discount_percent'] as num?)?.toDouble() ?? 0.0;
    if (pct <= 0 || subtotal <= 0) return 0.0;
    return (subtotal * (pct / 100.0)).roundToDouble();
  }

  double get loyaltyDiscountValue => redeemedLoyaltyPoints * 100.0; // 1 point = Rp 100

  double get totalDiscount {
    final rawTotal = cartDiscountAmount + customerGroupDiscount + loyaltyDiscountValue;
    final maxAllowed = subtotal > 0 ? subtotal : 0.0;
    return rawTotal.clamp(0.0, maxAllowed).roundToDouble();
  }

  double get exchangeSurplusCredit {
    if (!isExchangeMode) return 0.0;
    final net = subtotal - totalDiscount;
    return net < 0 ? net.abs() : 0.0;
  }

  static double _round4dp(double value) => (value * 10000.0).roundToDouble() / 10000.0;

  /// Exclusive tax total across positive cart lines (mirrors backend `PriceCart` / `TaxResolver`).
  /// Products with `taxInclusive == true` already include tax in `unitPrice`, so 0 is added on top.
  double get exclusiveTaxTotal {
    if (isExchangeMode && (subtotal - totalDiscount) <= 0) return 0.0;
    final positiveLines = cart.where((c) => !c.isExchangeReturn).toList();
    if (positiveLines.isEmpty) return 0.0;
    final posSub = positiveLines.fold<double>(0.0, (s, c) => s + c.lineTotal);
    double remOrderDisc = totalDiscount.clamp(0.0, posSub);
    double taxSum = 0.0;
    for (int i = 0; i < positiveLines.length; i++) {
      final c = positiveLines[i];
      double orderDiscShare = 0.0;
      if (remOrderDisc > 0 && posSub > 0) {
        if (i == positiveLines.length - 1) {
          orderDiscShare = remOrderDisc;
        } else {
          orderDiscShare = ((c.lineTotal / posSub) * totalDiscount).roundToDouble();
          remOrderDisc = (remOrderDisc - orderDiscShare).clamp(0.0, posSub);
        }
      }
      final taxableBase = (c.lineTotal - orderDiscShare).clamp(0.0, double.infinity);
      if (!c.product.taxInclusive && c.product.taxRate > 0) {
        taxSum += _round4dp(taxableBase * (c.product.taxRate / 100.0));
      }
    }
    return _round4dp(taxSum);
  }

  double get grandTotal =>
      _round4dp((subtotal - totalDiscount).clamp(0.0, double.infinity) + exclusiveTaxTotal);

  int get lowStockProductsCount => allProducts.where((p) => p.isLowStock).length;

  int get expiringSoonCount => allProducts.where((p) => p.hasExpiringSoonBatch).length;

  VerticalCapabilities get capabilities => VerticalConfig.getCapabilities(currentVertical);

  /// C.2: Pharmacy prescription items currently in cart
  List<CartItemModel> get prescriptionRequiredCartProducts =>
      cart.where((item) => !item.isExchangeReturn && item.product.requiresPrescription).toList();

  /// C.2: True when cart contains prescription drugs without doctor/patient metadata
  bool get hasUnfulfilledPrescriptionRequirement {
    if (prescriptionRequiredCartProducts.isEmpty) return false;
    final doc = (verticalMetadata['doctor_name'] ?? '').toString().trim();
    final patient = (verticalMetadata['patient_name'] ?? '').toString().trim();
    return doc.isEmpty || patient.isEmpty;
  }

  PosState copyWith({
    bool? isLoading,
    bool? isOnline,
    bool? isSyncingOfflineQueue,
    bool? isInitialRestoring,
    double? initialRestoreProgress,
    String? initialRestoreStep,
    bool clearInitialRestoreStep = false,
    String? activeNodeCode,
    BusinessVertical? currentVertical,
    String? posMode,
    String? orderType,
    List<ProductModel>? allProducts,
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? customers,
    List<Map<String, dynamic>>? suppliers,
    int? selectedCategoryId,
    int? selectedBrandId,
    String? searchQuery,
    List<CartItemModel>? cart,
    Map<String, dynamic>? selectedCustomer,
    bool clearCustomer = false,
    Map<String, dynamic>? selectedTable,
    bool clearTable = false,
    String? orderNotes,
    bool clearOrderNotes = false,
    Map<String, dynamic>? verticalMetadata,
    bool clearVerticalMetadata = false,
    double? cartDiscountAmount,
    bool? managerDiscountApproved,
    int? redeemedLoyaltyPoints,
    List<Map<String, dynamic>>? heldCarts,
    List<Map<String, dynamic>>? salesHistory,
    List<Map<String, dynamic>>? paymentMethods,
    List<Map<String, dynamic>>? returnReasons,
    List<Map<String, dynamic>>? brands,
    List<Map<String, dynamic>>? units,
    List<Map<String, dynamic>>? expenseCategories,
    List<Map<String, dynamic>>? customerGroups,
    List<Map<String, dynamic>>? localSyncConflicts,
    List<Map<String, dynamic>>? deadLetterItems,
    int? activeHeldSaleId,
    bool clearActiveHeldSaleId = false,
    Map<String, dynamic>? exchangeSourceSale,
    bool clearExchangeSourceSale = false,
    int? offlinePendingCount,
    String? alertMessage,
  }) {
    return PosState(
      isLoading: isLoading ?? this.isLoading,
      isOnline: isOnline ?? this.isOnline,
      isSyncingOfflineQueue: isSyncingOfflineQueue ?? this.isSyncingOfflineQueue,
      isInitialRestoring: isInitialRestoring ?? this.isInitialRestoring,
      initialRestoreProgress: initialRestoreProgress ?? this.initialRestoreProgress,
      initialRestoreStep: clearInitialRestoreStep ? null : (initialRestoreStep ?? this.initialRestoreStep),
      activeNodeCode: activeNodeCode ?? this.activeNodeCode,
      currentVertical: currentVertical ?? this.currentVertical,
      posMode: posMode ?? this.posMode,
      orderType: orderType ?? this.orderType,
      allProducts: allProducts ?? this.allProducts,
      categories: categories ?? this.categories,
      customers: customers ?? this.customers,
      suppliers: suppliers ?? this.suppliers,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      selectedBrandId: selectedBrandId ?? this.selectedBrandId,
      searchQuery: searchQuery ?? this.searchQuery,
      cart: cart ?? this.cart,
      selectedCustomer: clearCustomer ? null : (selectedCustomer ?? this.selectedCustomer),
      selectedTable: clearTable ? null : (selectedTable ?? this.selectedTable),
      orderNotes: clearOrderNotes ? null : (orderNotes ?? this.orderNotes),
      verticalMetadata: clearVerticalMetadata ? const {} : (verticalMetadata ?? this.verticalMetadata),
      cartDiscountAmount: cartDiscountAmount ?? this.cartDiscountAmount,
      managerDiscountApproved: managerDiscountApproved ?? this.managerDiscountApproved,
      redeemedLoyaltyPoints: redeemedLoyaltyPoints ?? this.redeemedLoyaltyPoints,
      heldCarts: heldCarts ?? this.heldCarts,
      salesHistory: salesHistory ?? this.salesHistory,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      returnReasons: returnReasons ?? this.returnReasons,
      brands: brands ?? this.brands,
      units: units ?? this.units,
      expenseCategories: expenseCategories ?? this.expenseCategories,
      customerGroups: customerGroups ?? this.customerGroups,
      localSyncConflicts: localSyncConflicts ?? this.localSyncConflicts,
      deadLetterItems: deadLetterItems ?? this.deadLetterItems,
      activeHeldSaleId: clearActiveHeldSaleId ? null : (activeHeldSaleId ?? this.activeHeldSaleId),
      exchangeSourceSale: clearExchangeSourceSale ? null : (exchangeSourceSale ?? this.exchangeSourceSale),
      offlinePendingCount: offlinePendingCount ?? this.offlinePendingCount,
      alertMessage: alertMessage,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isOnline,
        isSyncingOfflineQueue,
        isInitialRestoring,
        initialRestoreProgress,
        initialRestoreStep,
        activeNodeCode,
        currentVertical,
        posMode,
        orderType,
        allProducts,
        categories,
        customers,
        suppliers,
        selectedCategoryId,
        selectedBrandId,
        searchQuery,
        cart,
        selectedCustomer,
        selectedTable,
        orderNotes,
        verticalMetadata,
        cartDiscountAmount,
        managerDiscountApproved,
        redeemedLoyaltyPoints,
        heldCarts,
        salesHistory,
        paymentMethods,
        returnReasons,
        brands,
        units,
        expenseCategories,
        customerGroups,
        localSyncConflicts,
        deadLetterItems,
        activeHeldSaleId,
        exchangeSourceSale,
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
  Timer? _backoffRetryTimer;
  int _backoffAttempt = 0;
  bool _wasOffline = false;
  bool _isAutoSyncRunning = false;
  bool _isCheckoutInProgress = false;
  Future<void>? _activeCloudSyncFuture;
  String? _lastCompletedIdempotencyKey;
  Map<String, dynamic>? _lastCompletedReceipt;

  bool get isCheckoutInProgress => _isCheckoutInProgress;

  void _emitState(PosState next) => emit(next);

  /// C.2: Explicit prescription validation helper returning warning text or null when valid.
  String? validatePrescriptionRequirements() {
    if (!state.hasUnfulfilledPrescriptionRequirement) return null;
    final names = state.prescriptionRequiredCartProducts
        .map((e) => e.displayName)
        .take(2)
        .join(', ');
    return 'Item wajib resep dokter ($names). Lengkapi Nama Dokter & Nama Pasien terlebih dahulu.';
  }

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

  static Map<String, dynamic> _serializeHeldEntry(Map<String, dynamic> held) {
    final copy = Map<String, dynamic>.from(held);
    final rawItems = copy['cart_items'];
    if (rawItems is List<CartItemModel>) {
      copy['cart_items'] = rawItems.map((c) => c.toJson()).toList();
    } else if (rawItems is List) {
      copy['cart_items'] = rawItems.map((e) {
        if (e is CartItemModel) return e.toJson();
        if (e is Map) return Map<String, dynamic>.from(e);
        return e;
      }).toList();
    }
    return copy;
  }

  static List<Map<String, dynamic>> _hydrateHeldCarts(
    List<Map<String, dynamic>> rawList, {
    List<ProductModel>? catalogProducts,
  }) {
    return rawList.map((raw) {
      final copy = Map<String, dynamic>.from(raw);
      final rawItems = copy['cart_items'];
      if (rawItems is List<CartItemModel>) {
        copy['cart_items'] = rawItems;
      } else if (rawItems is List) {
        final hydrated = <CartItemModel>[];
        for (final item in rawItems) {
          if (item is CartItemModel) {
            hydrated.add(item);
          } else if (item is Map) {
            hydrated.add(
              CartItemModel.fromJson(
                Map<String, dynamic>.from(item),
                catalogProducts: catalogProducts,
              ),
            );
          }
        }
        copy['cart_items'] = hydrated;
      } else {
        copy['cart_items'] = <CartItemModel>[];
      }
      return copy;
    }).toList();
  }

  static PosState _buildInitialState(OfflineDatabase offlineDb) {
    final vertical = _resolveInitialVertical(offlineDb);
    final caps = VerticalConfig.getCapabilities(vertical);
    final cachedProds = offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    return PosState(
      currentVertical: vertical,
      posMode: vertical == BusinessVertical.restaurant ? 'restaurant' : 'retail',
      orderType: caps.hasDineInTakeawayOrderType ? 'dine_in' : 'retail',
      heldCarts: _hydrateHeldCarts(offlineDb.getHeldSales(), catalogProducts: cachedProds),
      deadLetterItems: offlineDb.getDeadLetterItems(),
      localSyncConflicts: offlineDb.getOfflineSyncConflicts(),
    );
  }

  int _computePendingBadgeCount() => _isLocalStandalone
      ? _offlineDb.getOfflineSalesQueue().length
      : _offlineDb.totalOfflineQueueBadgeCount;

  int _computePendingRetryCount() =>
      _isLocalStandalone ? 0 : _offlineDb.totalPendingNonConflictSyncCount;

  /// Refresh offline pending count, conflict & dead-letter badges after mutations
  /// performed by other screens (e.g. DebtBookScreen receivable/expense or ShiftManagementScreen).
  void refreshOfflinePendingState() {
    if (isClosed) return;
    emit(state.copyWith(
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));
    _scheduleBackoffSyncIfNeeded();
  }

  @override
  Future<void> close() async {
    _backoffRetryTimer?.cancel();
    _backoffRetryTimer = null;
    await _connectivitySubscription?.cancel();
    return super.close();
  }

  /// Clears all in-memory catalog, cart, customers, suppliers, and sales state on logout or tenant switch.
  Future<void> resetForLogout() async {
    _backoffRetryTimer?.cancel();
    _backoffRetryTimer = null;
    _backoffAttempt = 0;
    _lastCompletedIdempotencyKey = null;
    _lastCompletedReceipt = null;
    _isCheckoutInProgress = false;
    _isAutoSyncRunning = false;
    _activeCloudSyncFuture = null;
    await _connectivitySubscription?.cancel();
    emit(PosState(activeNodeCode: _apiClient.edgeDiscovery.getMobileNodeCode()));
  }

  /// Update this device's partitioned terminal/node code (e.g. `M01`, `M02`, `M7A3C`).
  Future<void> updateTerminalNodeCode(String code) async {
    await _apiClient.edgeDiscovery.setMobileNodeCode(code);
    emit(state.copyWith(activeNodeCode: _apiClient.edgeDiscovery.getMobileNodeCode()));
  }

  /// Initialize POS catalog, categories, payment methods, sales history & reactive auto-sync listener.
  /// When [awaitCloudSync] is `false`, renders SQLite cache immediately and runs Cloud sync
  /// non-blockingly so offline cold starts never freeze.
  Future<void> initializeCatalog({
    bool seedDefaultCart = false,
    bool awaitCloudSync = true,
  }) async {
    emit(state.copyWith(isLoading: true));

    // Load local cache (SQLite-backed) first for instant <5ms rendering
    var localProducts = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
    var localCategories = _offlineDb.getCachedCategories();
    var localCustomers = _offlineDb.getCachedCustomers();
    var localSuppliers = _offlineDb.getCachedSuppliers();
    var localPaymentMethods = _offlineDb.getCachedPaymentMethods();
    var localHistory = _offlineDb.getLocalSalesHistory();
    final nodeCode = _apiClient.edgeDiscovery.getMobileNodeCode();

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
    if (isClosed) return;
    _wasOffline = !currentlyOnline;
    final resolvedVertical = _resolveInitialVertical(_offlineDb);
    final resolvedCaps = VerticalConfig.getCapabilities(resolvedVertical);

    emit(state.copyWith(
      isLoading: false,
      isOnline: currentlyOnline,
      activeNodeCode: nodeCode,
      currentVertical: resolvedVertical,
      posMode: resolvedVertical == BusinessVertical.restaurant ? 'restaurant' : 'retail',
      orderType: resolvedCaps.hasDineInTakeawayOrderType
          ? (state.orderType == 'retail' ? 'dine_in' : state.orderType)
          : 'retail',
      allProducts: localProducts,
      categories: localCategories,
      customers: localCustomers,
      suppliers: localSuppliers,
      paymentMethods: localPaymentMethods.isNotEmpty ? localPaymentMethods : state.paymentMethods,
      brands: _offlineDb.getCachedBrands(),
      units: _offlineDb.getCachedUnits(),
      returnReasons: _offlineDb.getCachedReturnReasons(),
      expenseCategories: _offlineDb.getCachedExpenseCategories(),
      customerGroups: _offlineDb.getCachedCustomerGroups(),
      cart: initialCart,
      heldCarts: _hydrateHeldCarts(_offlineDb.getHeldSales(), catalogProducts: localProducts),
      salesHistory: localHistory,
      localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
      deadLetterItems: _offlineDb.getDeadLetterItems(),
      offlinePendingCount: _computePendingBadgeCount(),
    ));

    // Start reactive connectivity listener (Offline -> Online auto-drain & refresh)
    await _startConnectivityListener();
    _scheduleBackoffSyncIfNeeded();

    // Sync with Cloud API only when NOT in Local Standalone mode and token is present
    final token = await _apiClient.getToken();
    if (!_isLocalStandalone && currentlyOnline && token != null && token.isNotEmpty) {
      if (awaitCloudSync) {
        await syncWithCloud(force: false);
      } else {
        unawaited(syncWithCloud(force: false));
      }
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
      _backoffAttempt = 0;
      emit(state.copyWith(isOnline: true));

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
    emit(state.copyWith(isOnline: true, isSyncingOfflineQueue: true));
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
        emit(state.copyWith(
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
      final resolvedVertical = _resolveInitialVertical(_offlineDb);
      final resolvedCaps = VerticalConfig.getCapabilities(resolvedVertical);
      final localProds = _offlineDb.getCachedProducts().map(ProductModel.fromJson).toList();
      emit(state.copyWith(
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
        heldCarts: _hydrateHeldCarts(_offlineDb.getHeldSales(), catalogProducts: localProds),
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
      emit(state.copyWith(
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
    emit(state.copyWith(
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
        emit(state.copyWith(
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
        emit(state.copyWith(
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
        emit(state.copyWith(
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
      final persistedLocalHeld = _hydrateHeldCarts(
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
            mergedHeldCarts.map(_serializeHeldEntry).toList(),
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
        emit(state.copyWith(
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

      final resolvedVertical = _resolveInitialVertical(_offlineDb);
      final resolvedCaps = VerticalConfig.getCapabilities(resolvedVertical);
      emit(state.copyWith(
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
      emit(state.copyWith(
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
      clearVerticalMetadata: true,
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
      emit(state.copyWith(clearVerticalMetadata: true, clearOrderNotes: true));
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

    emit(state.copyWith(
      verticalMetadata: cleaned,
      orderNotes: summary.isNotEmpty ? summary : state.orderNotes,
    ));
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

  void selectBrand(int brandId) {
    emit(state.copyWith(selectedBrandId: brandId));
  }

  void deleteHeldCart(int index) {
    if (index < 0 || index >= state.heldCarts.length) return;
    final remaining = List<Map<String, dynamic>>.from(state.heldCarts)..removeAt(index);
    unawaited(_offlineDb.replaceHeldSales(remaining.map(_serializeHeldEntry).toList()));
    emit(state.copyWith(heldCarts: remaining));
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
      emit(state.copyWith(clearTable: true, clearActiveHeldSaleId: true));
    } else {
      final activeSaleId = (table['active_sale_id'] as num?)?.toInt() ??
          (table['active_sale'] is Map
              ? ((table['active_sale']['id'] as num?)?.toInt())
              : null);
      emit(state.copyWith(
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
    emit(state.copyWith(cart: tieredCart, alertMessage: null));
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
    emit(state.copyWith(alertMessage: 'Barcode "${parsed.rawBarcode}" tidak ditemukan di katalog.'));
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
    emit(state.copyWith(cart: _recalculateVolumeTiers(updated, item.product.id)));
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
    emit(state.copyWith(cart: _recalculateVolumeTiers(updated, item.product.id)));
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
    final productId = state.cart[index].product.id;
    final updated = List<CartItemModel>.from(state.cart);
    if (quantity <= 0) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(quantity: quantity);
    }
    emit(state.copyWith(cart: _recalculateVolumeTiers(updated, productId)));
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
    emit(state.copyWith(
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
    emit(state.copyWith(cart: _recalculateVolumeTiers(updated, productId)));
  }

  void clearCart() {
    PosFeedback.onTapStepper();
    emit(state.copyWith(
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

    emit(state.copyWith(
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
    emit(state.copyWith(
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
          emit(state.copyWith(managerDiscountApproved: true));
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
    emit(state.copyWith(cartDiscountAmount: clampedDiscount));
    return true;
  }

  void setRedeemedLoyaltyPoints(int points) {
    emit(state.copyWith(redeemedLoyaltyPoints: points));
  }

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
    await _offlineDb.saveHeldSale(_serializeHeldEntry(heldEntry));

    final updatedHeld = [heldEntry, ...state.heldCarts];
    emit(state.copyWith(
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
            await _offlineDb.replaceHeldSales(nextHeld.map(_serializeHeldEntry).toList());
            if (!isClosed) {
              emit(state.copyWith(heldCarts: nextHeld));
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
    unawaited(_offlineDb.replaceHeldSales(remainingHeld.map(_serializeHeldEntry).toList()));

    emit(state.copyWith(
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
      emit(state.copyWith(
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

    emit(state.copyWith(
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
        emit(state.copyWith(returnReasons: reasons));
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

    emit(state.copyWith(
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
          'notes': notes ?? 'Retur Pelanggan via OXO.ID Mobile POS',
        },
      );
    } catch (_) {}
    emit(state.copyWith(salesHistory: _offlineDb.getLocalSalesHistory()));
  }

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
    String notes = 'Stock Opname via OXO.ID Mobile POS',
  }) async {
    final bool isBrandNew =
        isNew || product.isLocalOnly || product.id <= 0 || product.id > 1000000000;
    final String localUuid =
        (product.localUuid != null && product.localUuid!.trim().isNotEmpty)
            ? product.localUuid!.trim()
            : const Uuid().v4();

    if (!_isLocalStandalone) {
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
    emit(state.copyWith(
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
        emit(state.copyWith(
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
    emit(state.copyWith(
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
        emit(state.copyWith(suppliers: _offlineDb.getCachedSuppliers()));
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
    emit(state.copyWith(suppliers: _offlineDb.getCachedSuppliers()));
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
        emit(state.copyWith(allProducts: updated));
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

  /// One-Click Local-to-Cloud Data Migration when upgrading Standalone Mode to OXO Cloud
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
    emit(state.copyWith(
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
    emit(state.copyWith(
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
    emit(state.copyWith(
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

    emit(state.copyWith(
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
      emit(state.copyWith(
        isSyncingOfflineQueue: false,
        localSyncConflicts: _offlineDb.getOfflineSyncConflicts(),
        deadLetterItems: _offlineDb.getDeadLetterItems(),
        offlinePendingCount: _computePendingBadgeCount(),
      ));
      return 0;
    }
    emit(state.copyWith(isSyncingOfflineQueue: true));
    try {
      final uploadedProducts = await _syncPendingLocalProductsToCloud();
      final synced = await _offlineDb.syncOfflineQueue(_apiClient);
      final online = await _connectivityService.checkOnline();
      if (online) {
        await syncWithCloud(force: false, preserveActiveCart: true, silent: true);
      }
      emit(state.copyWith(
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
      emit(state.copyWith(
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
