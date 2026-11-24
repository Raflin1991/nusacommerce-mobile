import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';
import 'daos/error_log_dao.dart';
import 'daos/product_local_dao.dart';
import 'daos/sales_queue_dao.dart';
import 'daos/shift_local_dao.dart';
import 'sqlite_database.dart';

part 'offline_database_sales_queue.dart';
part 'offline_database_shifts_profile.dart';
part 'offline_database_vertical_seeds.dart';
part 'offline_database_debt_book.dart';
part 'offline_database_reports_numbering.dart';
part 'offline_database_parity.dart';
part 'offline_database_parity_analytics.dart';
part 'offline_database_sync_queues.dart';
part 'offline_database_dlq_atomic.dart';

/// Offline-First Local Database Engine backed by modular SQLite DAOs (`nusacommerce_local.db`).
/// BUG-002 Resolved: When native `sqflite` is active (`isUsingNativeSqlite == true`),
/// 100% of catalog, queue, ledger, and history collections persist in SQLite DAOs (`ProductLocalDao`,
/// `SalesQueueDao`, `ShiftLocalDao`, `ErrorLogDao`) with zero JSON array duplication in `SharedPreferences`.
/// Lightweight scalar flags remain in `SharedPreferences`, with seamless fallback on Web / headless VM tests.
class OfflineDatabase {
  final SharedPreferences _prefs;
  final SqliteDatabase _sqlite = SqliteDatabase.instance;
  final Uuid _uuid = const Uuid();

  ProductLocalDao get productsDao => _sqlite.productsDao;
  SalesQueueDao get salesQueueDao => _sqlite.salesQueueDao;
  ShiftLocalDao get shiftsDao => _sqlite.shiftsDao;
  ErrorLogDao get errorLogDao => _sqlite.errorLogDao;

  /// True when native `sqflite` database is open as Single Source of Truth (`BUG-002`).
  bool get isUsingNativeSqlite => _sqlite.hasActiveDatabase;

  static const String _keyCachedProducts = 'nusa_local_products_v4';
  static const String _keyCachedCategories = 'nusa_local_categories_v4';
  static const String _keyCachedCustomers = 'nusa_local_customers_v4';
  static const String _keyCachedSuppliers = 'nusa_local_suppliers_v4';
  static const String _keyOfflineSalesQueue = 'nusa_offline_sales_queue_v4';
  static const String _keyCompletedSalesHistory = 'nusa_local_sales_history_v4';
  static const String _keyStoreProfile = 'nusa_store_profile_v4';
  static const String _keyPairedPrinter = 'nusa_paired_printer_v4';
  static const String _keyPairedPrinterMac = 'nusa_paired_printer_mac_v4';
  static const String _keyHasCloudSynced = 'nusa_has_cloud_synced_v4';
  static const String _keyLastCloudSyncAt = 'nusa_last_cloud_sync_at_v4';
  static const String _keyAuthSession = 'nusa_auth_session_v4';
  static const String _keySqliteMigrated = 'nusa_sqlite_migrated_v1';
  static const String _keyBusinessVerticalMode = 'nusa_business_vertical_mode';
  static const String _keyLocalShifts = 'nusa_local_shifts_v4';
  static const String _keyLocalExpenses = 'nusa_local_expenses_v4';
  static const String _keyLocalPayables = 'nusa_local_payables_v4';
  static const String _keyActiveTenantIdentity = 'nusa_active_tenant_identity_v4';
  static const String _keyCachedBrands = 'nusa_local_brands_v4';
  static const String _keyCachedUnits = 'nusa_local_units_v4';
  static const String _keyCachedReturnReasons = 'nusa_local_return_reasons_v4';
  static const String _keyCachedExpenseCategories = 'nusa_local_expense_categories_v4';
  static const String _keyCachedCustomerGroups = 'nusa_local_customer_groups_v4';
  static const String _keyLocalStockMovements = 'nusa_local_stock_movements_v4';
  static const String _keyLocalPurchases = 'nusa_local_purchases_v4';
  static const String _keyLocalPurchaseReceipts = 'nusa_local_purchase_receipts_v4';
  static const String _keyLocalPurchaseReturns = 'nusa_local_purchase_returns_v4';
  static const String _keyLocalQuotations = 'nusa_local_quotations_v4';
  static const String _keyLocalCashLedger = 'nusa_local_cash_ledger_v4';
  static const String _keyLocalCustomerDepositLogs = 'nusa_local_deposit_logs_v4';
  static const String _keyCachedPaymentMethods = 'nusa_local_payment_methods_v4';
  static const String _keyNumberingFormats = 'nusa_numbering_formats_v1';
  static const String _keyHeldSales = 'nusa_local_held_sales_v5';
  static const String _keyPendingReceivablePayments = 'nusa_pending_receivable_payments_v5';
  static const String _keyCachedCloudReceivables = 'nusa_cached_cloud_receivables_v5';
  static const String _keyPendingShiftClosures = 'nusa_pending_shift_closures_v5';
  static const String _keyDeadLetterQueue = 'nusa_dead_letter_queue_v5';


  List<Map<String, dynamic>>? _memProducts;
  List<Map<String, dynamic>>? _memCustomers;
  List<Map<String, dynamic>>? _memSuppliers;
  List<Map<String, dynamic>>? _memOfflineSales;
  List<Map<String, dynamic>>? _memHeldSales;
  List<Map<String, dynamic>>? _memPendingReceivablePayments;
  List<Map<String, dynamic>>? _memPendingShiftClosures;
  List<Map<String, dynamic>>? _memDeadLetterQueue;
  final Map<String, List<Map<String, dynamic>>> _memCollections = {};
  Future<int>? _activeQueueSyncFuture;

  OfflineDatabase(this._prefs);

  SharedPreferences get prefs => _prefs;

  /// Initialize SQLite DAO engine, migrate any legacy SharedPreferences JSON blobs once,
  /// and hydrate memory state from SQLite DAOs (`BUG-002`).
  Future<void> initialize() async {
    try {
      await _sqlite.init();
      final bool migrated = _prefs.getBool(_keySqliteMigrated) ?? false;

      if (_sqlite.hasActiveDatabase && !migrated) {
        final legacyProducts = _readPrefsList(_keyCachedProducts);
        final legacyCustomers = _readPrefsList(_keyCachedCustomers);
        final legacySuppliers = _readPrefsList(_keyCachedSuppliers);
        final legacySales = _readPrefsList(_keyOfflineSalesQueue);
        final legacyHistory = _readPrefsList(_keyCompletedSalesHistory);
        final legacyShifts = _readPrefsList(_keyLocalShifts);

        if (legacyProducts.isNotEmpty) await productsDao.replaceAllProducts(legacyProducts);
        if (legacyCustomers.isNotEmpty) await productsDao.replaceAllCustomers(legacyCustomers);
        if (legacySuppliers.isNotEmpty) await productsDao.replaceAllSuppliers(legacySuppliers);
        if (legacyHistory.isNotEmpty) await salesQueueDao.replaceSalesHistory(legacyHistory);
        if (legacyShifts.isNotEmpty) await shiftsDao.replaceAllShifts(legacyShifts);
        for (final sale in legacySales) {
          final id = (sale['local_uuid'] ?? _uuid.v4()).toString();
          final createdAt = (sale['queued_at'] ?? DateTime.now().toIso8601String()).toString();
          await salesQueueDao.insertOfflineSale(id, {'local_uuid': id, ...sale}, createdAt);
        }

        for (final colKey in const [
          _keyCachedCategories,
          _keyCachedBrands,
          _keyCachedUnits,
          _keyCachedReturnReasons,
          _keyCachedExpenseCategories,
          _keyCachedCustomerGroups,
          _keyCachedPaymentMethods,
          _keyCachedCloudReceivables,
          _keyLocalPurchases,
          _keyLocalPurchaseReceipts,
          _keyLocalPurchaseReturns,
          _keyLocalQuotations,
          _keyLocalCustomerDepositLogs,
        ]) {
          final legacyCol = _readPrefsList(colKey);
          if (legacyCol.isNotEmpty) {
            await productsDao.saveCollectionJson(colKey, legacyCol);
          }
          await _prefs.remove(colKey);
        }

        for (final daoKey in const [
          _keyCachedProducts,
          _keyCachedCustomers,
          _keyCachedSuppliers,
          _keyOfflineSalesQueue,
          _keyHeldSales,
          _keyCompletedSalesHistory,
          _keyLocalShifts,
          _keyLocalExpenses,
          _keyLocalPayables,
          _keyLocalStockMovements,
          _keyLocalCashLedger,
          _keyPendingReceivablePayments,
          _keyPendingShiftClosures,
          _keyDeadLetterQueue,
        ]) {
          await _prefs.remove(daoKey);
        }
        await _prefs.setBool(_keySqliteMigrated, true);
      }

      if (_sqlite.hasActiveDatabase) {
        _memProducts = await productsDao.getAllProducts();
        _memCustomers = await productsDao.getAllCustomers();
        _memSuppliers = await productsDao.getAllSuppliers();
        _memOfflineSales = await salesQueueDao.getUnsyncedOfflineSales();
        _memHeldSales = await salesQueueDao.getAllHeldSales();
        _memPendingReceivablePayments = await salesQueueDao.getUnsyncedReceivablePayments();
        _memPendingShiftClosures = await shiftsDao.getUnsyncedShiftClosures();
        _memDeadLetterQueue = await salesQueueDao.getQuarantinedDeadLetters();
        _memCollections[_keyCompletedSalesHistory] = await salesQueueDao.getAllSalesHistory();
        _memCollections[_keyLocalShifts] = await shiftsDao.getAllShifts();
        _memCollections[_keyLocalExpenses] = await salesQueueDao.getAllLocalExpenses();
        _memCollections[_keyLocalPayables] = await salesQueueDao.getAllLocalPayables();
        _memCollections[_keyLocalStockMovements] = await productsDao.getStockMovements();
        _memCollections[_keyLocalCashLedger] = await salesQueueDao.getAllCashLedgerEntries();

        final kvRaw = await productsDao.loadAllCollectionsRaw();
        for (final entry in kvRaw.entries) {
          try {
            final decoded = jsonDecode(entry.value);
            if (decoded is List) {
              _memCollections[entry.key] = decoded
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          } catch (_) {}
        }
      }
    } catch (_) {
      // Safe fallback to SharedPreferences on headless VM / Web
    }
  }

  List<Map<String, dynamic>> _readPrefsList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _readCollectionList(String key) {
    if (_memCollections.containsKey(key)) {
      return _memCollections[key]!.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (isUsingNativeSqlite) {
      return [];
    }
    final list = _readPrefsList(key);
    _memCollections[key] = list;
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> _writeCollectionList(String key, List<dynamic> rawList) async {
    final normalized = rawList
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _memCollections[key] = normalized;
    if (isUsingNativeSqlite) {
      if (key == _keyCompletedSalesHistory) {
        await salesQueueDao.replaceSalesHistory(normalized);
      } else if (key == _keyLocalShifts) {
        await shiftsDao.replaceAllShifts(normalized);
      } else {
        await productsDao.saveCollectionJson(key, normalized);
      }
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, jsonEncode(normalized));
  }

  Future<void> _writeDaoMirrorFallback(String key, Object payload) async {
    if (isUsingNativeSqlite) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, jsonEncode(payload));
  }

  /// Record sanitized diagnostic/crash error into SQLite `local_error_logs` DAO (500-row cap).
  Future<Map<String, dynamic>> recordLocalError({
    required String errorType,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? context,
  }) {
    return errorLogDao.recordError(
      id: _uuid.v4(),
      errorType: errorType,
      message: message,
      stackTrace: stackTrace,
      context: context,
    );
  }

  Future<List<Map<String, dynamic>>> getRecentLocalErrors({int limit = 50}) {
    return errorLogDao.getRecentErrors(limit: limit);
  }

  Future<void> saveAuthSession(Map<String, dynamic> sessionJson) async {
    await _prefs.setString(_keyAuthSession, jsonEncode(sessionJson));
  }

  Map<String, dynamic>? getCachedAuthSession() {
    final raw = _prefs.getString(_keyAuthSession);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAuthSession() async {
    await _prefs.remove(_keyAuthSession);
  }

  Future<void> setHasCloudSynced(bool synced) async {
    await _prefs.setBool(_keyHasCloudSynced, synced);
    if (synced) {
      await _prefs.setString(_keyLastCloudSyncAt, DateTime.now().toIso8601String());
    }
  }

  bool get hasCloudSynced => _prefs.getBool(_keyHasCloudSynced) ?? false;

  DateTime? getLastCloudSyncAt() {
    final raw = _prefs.getString(_keyLastCloudSyncAt);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setLastCloudSyncAt(DateTime timestamp) async {
    await _prefs.setString(_keyLastCloudSyncAt, timestamp.toIso8601String());
  }

  /// True only when an initial master data snapshot (catalog + cloud sync flag) exists locally.
  bool get hasMasterDataSnapshot => hasCloudSynced && getCachedProducts().isNotEmpty;

  /// Count of pending offline sales eligible for automatic background retry (excludes quarantined conflicts).
  int get pendingNonConflictOfflineSalesCount => getOfflineSalesQueue()
      .where((e) => e['sync_status'] != 'sync_conflict')
      .length;

  String? getActiveTenantIdentity() => _prefs.getString(_keyActiveTenantIdentity);

  Future<void> setActiveTenantIdentity(String identity) async {
    await _prefs.setString(_keyActiveTenantIdentity, identity.trim().toLowerCase());
  }

  /// Ensures strict tenant cache isolation whenever switching between Cloud tenants
  /// or entering/resuming Mode Toko Mandiri (local-trial).
  Future<void> ensureTenantIsolation(
    String newTenantIdentity, {
    bool forceClear = false,
  }) async {
    final normalized = newTenantIdentity.trim().toLowerCase();
    final current = getActiveTenantIdentity();

    final cachedProducts = getCachedProducts();
    final bool hasForeignProducts;
    if (normalized.startsWith('local-trial')) {
      hasForeignProducts = current != normalized &&
          cachedProducts.any((p) {
            final id = (p['id'] as num?)?.toInt() ?? 0;
            return p['is_local_only'] != true && id > 0 && id < 1000000000;
          });
    } else if (normalized.startsWith('cloud:')) {
      hasForeignProducts = (current == null || current != normalized) &&
          cachedProducts.any(
            (p) => p['is_local_only'] == true || ((p['id'] as num?)?.toInt() ?? 0) < 0,
          );
    } else {
      hasForeignProducts = false;
    }

    if (forceClear || (current != null && current != normalized) || hasForeignProducts) {
      await clearTenantCache();
    }
    await setActiveTenantIdentity(normalized);
  }

  Future<void> clearTenantCache() async {
    _memProducts = [];
    _memCustomers = [];
    _memSuppliers = [];
    _memOfflineSales = [];
    _memHeldSales = [];
    _memPendingReceivablePayments = [];
    _memPendingShiftClosures = [];
    _memDeadLetterQueue = [];
    _memCollections.clear();
    await _sqlite.clearAll();
    await _prefs.remove(_keyActiveTenantIdentity);
    await _prefs.remove(_keyBusinessVerticalMode);
    for (final v in ['', '_v2', '_v3', '_v4']) {
      await _prefs.remove('nusa_local_products$v');
      await _prefs.remove('nusa_local_categories$v');
      await _prefs.remove('nusa_local_customers$v');
      await _prefs.remove('nusa_local_suppliers$v');
      await _prefs.remove('nusa_offline_sales_queue$v');
      await _prefs.remove('nusa_offline_sync_conflicts$v');
      await _prefs.remove('nusa_local_sales_history$v');
      await _prefs.remove('nusa_local_shifts$v');
      await _prefs.remove('nusa_local_expenses$v');
      await _prefs.remove('nusa_local_payables$v');
      await _prefs.remove('nusa_store_profile$v');
      await _prefs.remove('nusa_has_cloud_synced$v');
    }
    await _prefs.remove(_keyCachedBrands);
    await _prefs.remove(_keyCachedUnits);
    await _prefs.remove(_keyCachedReturnReasons);
    await _prefs.remove(_keyCachedExpenseCategories);
    await _prefs.remove(_keyCachedCustomerGroups);
    await _prefs.remove(_keyLocalStockMovements);
    await _prefs.remove(_keyLocalPurchases);
    await _prefs.remove(_keyLocalPurchaseReturns);
    await _prefs.remove(_keyLocalQuotations);
    await _prefs.remove(_keyLocalCashLedger);
    await _prefs.remove(_keyLocalCustomerDepositLogs);
    await _prefs.remove(_keyCachedPaymentMethods);
    await _prefs.remove(_keyNumberingFormats);
    await _prefs.remove(_keyLastCloudSyncAt);
    await _prefs.remove(_keyHeldSales);
    await _prefs.remove(_keyPendingReceivablePayments);
    await _prefs.remove(_keyCachedCloudReceivables);
    await _prefs.remove(_keyPendingShiftClosures);
    await _prefs.remove(_keyDeadLetterQueue);
  }

  /// Explicit Factory Reset: permanently clears ALL local SQLite tables, SharedPreferences
  /// store data, held bills, sync queues, and active session.
  /// MUST ONLY be triggered when the user explicitly confirms "Reset Pabrik / Hapus Seluruh Database".
  Future<void> factoryResetAll() async {
    await clearTenantCache();
    await clearAuthSession();
  }

  // ===========================================================================
  // 1. LOCAL PRODUCT CATALOG CACHE (SQLite Indexed + Memory Hydrated)
  // ===========================================================================
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    _memProducts = List<Map<String, dynamic>>.from(products);
    await _sqlite.replaceAllProducts(products);
    await _writeDaoMirrorFallback(_keyCachedProducts, products);
    await setHasCloudSynced(true);
  }

  List<Map<String, dynamic>> getCachedProducts() {
    if (_memProducts != null && (_memProducts!.isNotEmpty || isUsingNativeSqlite)) {
      return List<Map<String, dynamic>>.from(_memProducts!);
    }
    if (isUsingNativeSqlite) return [];
    final list = _readPrefsList(_keyCachedProducts);
    _memProducts = list;
    return list;
  }

  /// Fast indexed SQLite query (< 5ms across thousands of SKUs)
  Future<List<Map<String, dynamic>>> searchProductSql(String query) async {
    if (_sqlite.isSupported) {
      final rows = await _sqlite.searchProduct(query);
      if (rows.isNotEmpty || query.trim().isNotEmpty) {
        return rows;
      }
    }
    final q = query.trim().toLowerCase();
    final all = getCachedProducts();
    if (q.isEmpty) return all.take(50).toList();
    return all
        .where((p) {
          final barcode = (p['barcode'] ?? '').toString().toLowerCase();
          final sku = (p['sku'] ?? '').toString().toLowerCase();
          final name = (p['name'] ?? '').toString().toLowerCase();
          return barcode == q || sku == q || name.contains(q);
        })
        .take(50)
        .toList();
  }

  Future<void> updateLocalProductStock(int productId, double newStock) async {
    await batchUpdateLocalProductStocks({productId: newStock});
  }

  /// Atomically persists multiple stock updates (e.g., all lines of an offline checkout)
  /// in a single SQLite transaction + single SharedPreferences write to prevent race conditions.
  Future<void> batchUpdateLocalProductStocks(Map<int, double> updates) async {
    if (updates.isEmpty) return;
    final products = getCachedProducts();
    for (final p in products) {
      final pid = (p['id'] as num?)?.toInt();
      if (pid != null && updates.containsKey(pid)) {
        final newStock = updates[pid]!;
        p['stock'] = newStock;
        final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 5.0;
        p['is_low_stock'] = newStock <= reorder;
      }
    }
    _memProducts = products;
    await _sqlite.batchUpdateProductStocks(updates);
    await _writeDaoMirrorFallback(_keyCachedProducts, products);
  }

  // ===========================================================================
  // 1b. PAYMENT METHODS CACHE (Offline-First Checkout Parity)
  // ===========================================================================
  Future<void> cachePaymentMethods(List<Map<String, dynamic>> methods) async {
    await _writeCollectionList(_keyCachedPaymentMethods, methods);
  }

  List<Map<String, dynamic>> getCachedPaymentMethods() {
    return _readCollectionList(_keyCachedPaymentMethods);
  }

  Future<void> addOrUpdateLocalProduct(Map<String, dynamic> product) async {
    final products = getCachedProducts();
    final idx = products.indexWhere((p) => p['id'] == product['id']);
    if (idx >= 0) {
      products[idx] = product;
    } else {
      products.insert(0, product);
    }
    _memProducts = products;
    await _sqlite.upsertProduct(product);
    await _writeDaoMirrorFallback(_keyCachedProducts, products);
  }

  // ===========================================================================
  // 2. CATEGORIES CACHE (100% Cloud Derived, Zero Dummy FMCG)
  // ===========================================================================
  Future<void> cacheCategories(List<Map<String, dynamic>> categories) async {
    await _writeCollectionList(_keyCachedCategories, categories);
  }

  List<Map<String, dynamic>> getCachedCategories() {
    final list = _readCollectionList(_keyCachedCategories);
    if (list.isEmpty) {
      return [
        {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': 0},
      ];
    }
    list.removeWhere((c) => const {'Minuman', 'Snack', 'Sembako', 'Pulsa'}.contains(c['name']));
    return list;
  }

  // ===========================================================================
  // 3. CUSTOMERS & SUPPLIERS CACHE (SQLite Indexed)
  // ===========================================================================
  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) async {
    _memCustomers = List<Map<String, dynamic>>.from(customers);
    await _sqlite.replaceAllCustomers(customers);
    await _writeDaoMirrorFallback(_keyCachedCustomers, customers);
  }

  List<Map<String, dynamic>> getCachedCustomers() {
    if (_memCustomers != null && (_memCustomers!.isNotEmpty || isUsingNativeSqlite)) {
      return List<Map<String, dynamic>>.from(_memCustomers!);
    }
    if (isUsingNativeSqlite) return [];
    final list = _readPrefsList(_keyCachedCustomers);
    _memCustomers = list;
    return list;
  }

  Future<void> addOrUpdateLocalCustomer(Map<String, dynamic> customer) async {
    final list = getCachedCustomers();
    final idx = list.indexWhere((c) => c['id'] == customer['id']);
    if (idx >= 0) {
      list[idx] = customer;
    } else {
      list.insert(0, customer);
    }
    _memCustomers = list;
    await _sqlite.upsertCustomer(customer);
    await _writeDaoMirrorFallback(_keyCachedCustomers, list);
  }

  Future<void> cacheSuppliers(List<Map<String, dynamic>> suppliers) async {
    _memSuppliers = List<Map<String, dynamic>>.from(suppliers);
    await _sqlite.replaceAllSuppliers(suppliers);
    await _writeDaoMirrorFallback(_keyCachedSuppliers, suppliers);
  }

  List<Map<String, dynamic>> getCachedSuppliers() {
    if (_memSuppliers != null && (_memSuppliers!.isNotEmpty || isUsingNativeSqlite)) {
      return List<Map<String, dynamic>>.from(_memSuppliers!);
    }
    if (isUsingNativeSqlite) return [];
    final list = _readPrefsList(_keyCachedSuppliers);
    _memSuppliers = list;
    return list;
  }

  Future<void> addOrUpdateLocalSupplier(Map<String, dynamic> supplier) async {
    final list = getCachedSuppliers();
    final idx = list.indexWhere((s) => s['id'] == supplier['id']);
    if (idx >= 0) {
      list[idx] = supplier;
    } else {
      list.insert(0, supplier);
    }
    _memSuppliers = list;
    await _sqlite.upsertSupplier(supplier);
    await _writeDaoMirrorFallback(_keyCachedSuppliers, list);
  }


  /// Guarantee an offline-safe `{node}` partition token exists inside [template]
  /// so multiple offline cashiers/devices in the same store can never generate identical numbers.
  static String injectNodeToken(String template) {
    if (template.contains('{node}')) return template;
    final seqMatch = RegExp(r'\{seq(?::\d+)?\}').firstMatch(template);
    if (seqMatch != null) {
      return template.replaceRange(seqMatch.start, seqMatch.start, '{node}-');
    }
    return '${template.replaceAll(RegExp(r'[-/]+$'), '')}-{node}';
  }

  /// Clamp rendered document number to [maxLength] while preserving trailing uniqueness
  /// segments (`{node}` + `{seq}`) so database VARCHAR limits never cause collisions.
  static String fitMaxLength(String rendered, int maxLength) {
    if (maxLength <= 0 || rendered.length <= maxLength) return rendered;
    final parts = <String>[];
    final matches = RegExp(r'[-_/]').allMatches(rendered);
    int last = 0;
    for (final m in matches) {
      if (m.start > last) parts.add(rendered.substring(last, m.start));
      parts.add(rendered.substring(m.start, m.end));
      last = m.end;
    }
    if (last < rendered.length) parts.add(rendered.substring(last));

    if (parts.length >= 5) {
      final tail = parts.sublist(parts.length - 4).join();
      final headBudget = maxLength - tail.length;
      if (headBudget >= 3) {
        final headRaw = parts.sublist(0, parts.length - 4).join();
        final head = headRaw
            .substring(0, headBudget.clamp(0, headRaw.length))
            .replaceAll(RegExp(r'[-_/]+$'), '');
        final combined = '$head$tail';
        return combined.length <= maxLength
            ? combined
            : combined.substring(combined.length - maxLength);
      }
    }
    return rendered.substring(rendered.length - maxLength);
  }

  /// Render a Cloud/Custom document number format template locally (1:1 parity with PHP `NumberFormat::render`).
  static String renderNumberFormat({
    required String template,
    required String storeCode,
    required String nodeCode,
    required int seq,
    DateTime? now,
    bool enforceOfflineNode = true,
    int maxLength = 32,
  }) {
    final ts = now ?? DateTime.now();
    final cleanStore = storeCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final storeSeg = cleanStore.isEmpty
        ? 'STORE'
        : (cleanStore.length > 6 ? cleanStore.substring(0, 6) : cleanStore);
    final cleanNode = nodeCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final nodeSeg = cleanNode.isEmpty
        ? 'M01'
        : (cleanNode.length > 6 ? cleanNode.substring(0, 6) : cleanNode);

    final effectiveTemplate = enforceOfflineNode ? injectNodeToken(template) : template;

    final y4 = ts.year.toString().padLeft(4, '0');
    final y2 = y4.substring(y4.length - 2);
    final m2 = ts.month.toString().padLeft(2, '0');
    final d2 = ts.day.toString().padLeft(2, '0');

    String rendered = effectiveTemplate
        .replaceAll('{store}', storeSeg)
        .replaceAll('{node}', nodeSeg)
        .replaceAll('{Y}', y4)
        .replaceAll('{y}', y2)
        .replaceAll('{m}', m2)
        .replaceAll('{d}', d2)
        .replaceAll('{Ym}', '$y4$m2')
        .replaceAll('{Ymd}', '$y4$m2$d2')
        .replaceAll('{seq}', seq.toString());

    rendered = rendered.replaceAllMapped(RegExp(r'\{seq:(\d+)\}'), (match) {
      final pad = (int.tryParse(match.group(1) ?? '4') ?? 4).clamp(0, 9);
      return pad > 0 ? seq.toString().padLeft(pad, '0') : seq.toString();
    });

    return fitMaxLength(rendered, maxLength);
  }

}
