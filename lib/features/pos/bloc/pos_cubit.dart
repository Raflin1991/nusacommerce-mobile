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


part 'pos_state.dart';
part 'pos_cubit_sync.dart';
part 'pos_cubit_cart.dart';
part 'pos_cubit_holds_tables.dart';
part 'pos_cubit_checkout.dart';
part 'pos_cubit_catalog_crm.dart';
part 'pos_cubit_conflicts_warehouse.dart';
part 'pos_cubit_parity.dart';

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
}
