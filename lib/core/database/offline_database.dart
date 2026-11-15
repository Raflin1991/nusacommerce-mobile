import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';
import 'sqlite_database.dart';

/// Offline-First Local Database Engine backed by indexed SQLite (`nusacommerce_local.db`)
/// with seamless SharedPreferences fallback & automatic one-time migration.
/// Persists Products, Customers, Suppliers, Offline Sale Queue (UUIDv4 idempotent),
/// Printer MAC Address, and Store Profile locally on smartphone / handheld POS storage.
class OfflineDatabase {
  final SharedPreferences _prefs;
  final SqliteDatabase _sqlite = SqliteDatabase.instance;
  final Uuid _uuid = const Uuid();

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
  static const String _keyAuthSession = 'nusa_auth_session_v4';
  static const String _keySqliteMigrated = 'nusa_sqlite_migrated_v1';
  static const String _keyBusinessVerticalMode = 'nusa_business_vertical_mode';
  static const String _keyLocalShifts = 'nusa_local_shifts_v4';
  static const String _keyLocalExpenses = 'nusa_local_expenses_v4';
  static const String _keyLocalPayables = 'nusa_local_payables_v4';
  static const String _keyActiveTenantIdentity = 'nusa_active_tenant_identity_v4';

  List<Map<String, dynamic>>? _memProducts;
  List<Map<String, dynamic>>? _memCustomers;
  List<Map<String, dynamic>>? _memSuppliers;
  List<Map<String, dynamic>>? _memOfflineSales;

  OfflineDatabase(this._prefs);

  /// Initialize SQLite engine and migrate legacy SharedPreferences data once.
  Future<void> initialize() async {
    try {
      await _sqlite.init();
      final bool migrated = _prefs.getBool(_keySqliteMigrated) ?? false;

      if (_sqlite.isSupported && !migrated) {
        final legacyProducts = _readPrefsList(_keyCachedProducts);
        final legacyCustomers = _readPrefsList(_keyCachedCustomers);
        final legacySuppliers = _readPrefsList(_keyCachedSuppliers);
        final legacySales = _readPrefsList(_keyOfflineSalesQueue);

        if (legacyProducts.isNotEmpty) {
          await _sqlite.replaceAllProducts(legacyProducts);
        }
        if (legacyCustomers.isNotEmpty) {
          await _sqlite.replaceAllCustomers(legacyCustomers);
        }
        if (legacySuppliers.isNotEmpty) {
          await _sqlite.replaceAllSuppliers(legacySuppliers);
        }
        if (legacySales.isNotEmpty) {
          for (final sale in legacySales) {
            final id = (sale['local_uuid'] ?? _uuid.v4()).toString();
            final createdAt = (sale['queued_at'] ?? DateTime.now().toIso8601String()).toString();
            final normalized = {'local_uuid': id, ...sale};
            await _sqlite.insertOfflineSale(id, normalized, createdAt);
          }
        }
        await _prefs.setBool(_keySqliteMigrated, true);
      }

      if (_sqlite.isSupported) {
        final sqlProducts = await _sqlite.getAllProducts();
        if (sqlProducts.isNotEmpty) _memProducts = sqlProducts;

        final sqlCustomers = await _sqlite.getAllCustomers();
        if (sqlCustomers.isNotEmpty) _memCustomers = sqlCustomers;

        final sqlSuppliers = await _sqlite.getAllSuppliers();
        if (sqlSuppliers.isNotEmpty) _memSuppliers = sqlSuppliers;

        final sqlOfflineSales = await _sqlite.getUnsyncedOfflineSales();
        if (sqlOfflineSales.isNotEmpty) _memOfflineSales = sqlOfflineSales;
      }
    } catch (_) {
      // Safe fallback to SharedPreferences cache
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
  }

  bool get hasCloudSynced => _prefs.getBool(_keyHasCloudSynced) ?? false;

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
      hasForeignProducts = cachedProducts.any(
        (p) => p['is_local_only'] != true && ((p['id'] as num?)?.toInt() ?? 0) > 0,
      );
    } else if (normalized.startsWith('cloud:')) {
      hasForeignProducts = cachedProducts.any(
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
  }

  // ===========================================================================
  // 1. LOCAL PRODUCT CATALOG CACHE (SQLite Indexed + Memory Hydrated)
  // ===========================================================================
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    _memProducts = List<Map<String, dynamic>>.from(products);
    await _sqlite.replaceAllProducts(products);
    await _prefs.setString(_keyCachedProducts, jsonEncode(products));
    await setHasCloudSynced(true);
  }

  List<Map<String, dynamic>> getCachedProducts() {
    if (_memProducts != null && _memProducts!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_memProducts!);
    }
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
    bool isLow = newStock <= 5.0;
    final products = getCachedProducts();
    for (final p in products) {
      if (p['id'] == productId) {
        p['stock'] = newStock;
        isLow = newStock <= ((p['reorder_level'] as num?)?.toDouble() ?? 5.0);
        p['is_low_stock'] = isLow;
        break;
      }
    }
    _memProducts = products;
    await _sqlite.updateProductStock(productId, newStock, isLowStock: isLow);
    await _prefs.setString(_keyCachedProducts, jsonEncode(products));
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
    await _prefs.setString(_keyCachedProducts, jsonEncode(products));
  }

  // ===========================================================================
  // 2. CATEGORIES CACHE (100% Cloud Derived, Zero Dummy FMCG)
  // ===========================================================================
  Future<void> cacheCategories(List<Map<String, dynamic>> categories) async {
    await _prefs.setString(_keyCachedCategories, jsonEncode(categories));
  }

  List<Map<String, dynamic>> getCachedCategories() {
    final raw = _prefs.getString(_keyCachedCategories);
    if (raw == null || raw.isEmpty) {
      return [
        {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': 0},
      ];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      // Purge any stale dummy FMCG category relics
      list.removeWhere((c) => const {'Minuman', 'Snack', 'Sembako', 'Pulsa'}.contains(c['name']));
      return list;
    } catch (_) {
      return [
        {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': 0},
      ];
    }
  }

  // ===========================================================================
  // 3. CUSTOMERS & SUPPLIERS CACHE (SQLite Indexed)
  // ===========================================================================
  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) async {
    _memCustomers = List<Map<String, dynamic>>.from(customers);
    await _sqlite.replaceAllCustomers(customers);
    await _prefs.setString(_keyCachedCustomers, jsonEncode(customers));
  }

  List<Map<String, dynamic>> getCachedCustomers() {
    if (_memCustomers != null && _memCustomers!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_memCustomers!);
    }
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
    await _prefs.setString(_keyCachedCustomers, jsonEncode(list));
  }

  Future<void> cacheSuppliers(List<Map<String, dynamic>> suppliers) async {
    _memSuppliers = List<Map<String, dynamic>>.from(suppliers);
    await _sqlite.replaceAllSuppliers(suppliers);
    await _prefs.setString(_keyCachedSuppliers, jsonEncode(suppliers));
  }

  List<Map<String, dynamic>> getCachedSuppliers() {
    if (_memSuppliers != null && _memSuppliers!.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_memSuppliers!);
    }
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
    await _prefs.setString(_keyCachedSuppliers, jsonEncode(list));
  }

  // ===========================================================================
  // 4. OFFLINE SALE QUEUE (UUIDv4 IDEMPOTENT SYNC ENGINE)
  // ===========================================================================
  List<Map<String, dynamic>> getOfflineSalesQueue() {
    if (_memOfflineSales != null) {
      return List<Map<String, dynamic>>.from(_memOfflineSales!);
    }
    final list = _readPrefsList(_keyOfflineSalesQueue);
    _memOfflineSales = list;
    return list;
  }

  Future<void> enqueueOfflineSale(Map<String, dynamic> salePayload) async {
    final String id = (salePayload['local_uuid'] ?? _uuid.v4()).toString();
    final String createdAt = DateTime.now().toIso8601String();
    final entry = <String, dynamic>{
      ...salePayload,
      'local_uuid': id,
      'queued_at': createdAt,
      'sync_status': 'pending',
    };

    await _sqlite.insertOfflineSale(id, entry, createdAt);

    final queue = getOfflineSalesQueue();
    queue.removeWhere((e) => e['local_uuid'] == id);
    queue.add(entry);
    _memOfflineSales = queue;
    await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(queue));
  }

  /// Flush pending offline sales to NusaCommerce Cloud POST /api/v1/pos/checkout
  Future<int> syncOfflineQueue(ApiClient apiClient) async {
    List<Map<String, dynamic>> queue = [];
    if (_sqlite.isSupported) {
      queue = await _sqlite.getUnsyncedOfflineSales();
    }
    if (queue.isEmpty) {
      queue = getOfflineSalesQueue();
    }
    if (queue.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    int syncedCount = 0;

    for (final rawPayload in queue) {
      final payload = Map<String, dynamic>.from(rawPayload);
      final id = (payload['local_uuid'] ?? '').toString();

      // Do not automatically retry sales already flagged as stock/business conflict;
      // await owner/manager manual reconciliation (Approve Oversell or Cancel).
      if (payload['sync_status'] == 'sync_conflict') {
        remaining.add(payload);
        continue;
      }

      try {
        await apiClient.dio.post(ApiEndpoints.checkout, data: payload);
        syncedCount++;
        if (id.isNotEmpty) {
          await _sqlite.markOfflineSaleSynced(id);
        }
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;
        final errorCode = (data is Map ? data['error_code'] : null)?.toString() ?? '';
        final message = (data is Map ? data['message'] : null)?.toString() ??
            ApiClient.extractErrorMessage(e);
        final msgLower = message.toLowerCase();

        final isInsufficientStock = statusCode == 422 &&
            (errorCode == 'InsufficientStock' ||
                errorCode.toLowerCase().contains('stock') ||
                msgLower.contains('insufficientstock') ||
                msgLower.contains('stok') ||
                msgLower.contains('insufficient stock'));

        if (isInsufficientStock) {
          payload['sync_status'] = 'sync_conflict';
          payload['conflict_code'] = errorCode.isNotEmpty ? errorCode : 'InsufficientStock';
          payload['conflict_reason'] = message;
          payload['conflict_detected_at'] = DateTime.now().toIso8601String();
          if (id.isNotEmpty) {
            await _sqlite.updateOfflineSalePayload(id, payload, isSynced: 0);
          }
        }
        remaining.add(payload);
      } catch (_) {
        remaining.add(payload);
      }
    }

    _memOfflineSales = remaining;
    await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(remaining));
    return syncedCount;
  }

  /// Return all locally flagged `sync_conflict` offline sales awaiting owner reconciliation.
  List<Map<String, dynamic>> getOfflineSyncConflicts() {
    return getOfflineSalesQueue()
        .where((e) => e['sync_status'] == 'sync_conflict')
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Resolve an offline InsufficientStock conflict by approving oversell (`allow_oversell: true`).
  Future<bool> resolveConflictApproveOversell(
    String localUuid,
    ApiClient apiClient,
  ) async {
    final queue = getOfflineSalesQueue();
    final idx = queue.indexWhere((e) => e['local_uuid']?.toString() == localUuid);
    if (idx < 0) return false;

    final payload = Map<String, dynamic>.from(queue[idx]);
    payload.remove('sync_status');
    payload.remove('conflict_code');
    payload.remove('conflict_reason');
    payload.remove('conflict_detected_at');
    payload['allow_oversell'] = true;

    try {
      await apiClient.dio.post(ApiEndpoints.checkout, data: payload);
      queue.removeAt(idx);
      _memOfflineSales = queue;
      await _sqlite.markOfflineSaleSynced(localUuid);
      await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(queue));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolve an offline InsufficientStock conflict by cancelling/voiding the local sale.
  Future<void> resolveConflictCancelSale(String localUuid) async {
    final queue = getOfflineSalesQueue();
    queue.removeWhere((e) => e['local_uuid']?.toString() == localUuid);
    _memOfflineSales = queue;
    await _sqlite.deleteOfflineSale(localUuid);
    await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(queue));

    final history = getLocalSalesHistory();
    bool changed = false;
    for (final s in history) {
      if (s['local_uuid']?.toString() == localUuid) {
        s['status'] = 'voided';
        s['void_reason'] = 'Dibatalkan saat rekonsiliasi konflik stok offline';
        changed = true;
      }
    }
    if (changed) {
      await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(history));
    }
  }

  /// Remaps negative local product/customer IDs inside queued offline sales to their new Cloud IDs before sync.
  Future<void> remapOfflineSalesIds(
    Map<int, int> productIdMap,
    Map<int, int> customerIdMap,
  ) async {
    if (productIdMap.isEmpty && customerIdMap.isEmpty) return;
    final queue = getOfflineSalesQueue();
    if (queue.isEmpty) return;
    bool modified = false;

    for (int i = 0; i < queue.length; i++) {
      final sale = Map<String, dynamic>.from(queue[i]);
      bool saleChanged = false;

      final cid = (sale['customer_id'] as num?)?.toInt();
      if (cid != null && customerIdMap.containsKey(cid)) {
        sale['customer_id'] = customerIdMap[cid];
        saleChanged = true;
      }

      if (sale['items'] is List) {
        final items = (sale['items'] as List).map((raw) {
          if (raw is! Map) return raw;
          final item = Map<String, dynamic>.from(raw);
          final pid = (item['product_id'] as num?)?.toInt();
          if (pid != null && productIdMap.containsKey(pid)) {
            item['product_id'] = productIdMap[pid];
            saleChanged = true;
          }
          return item;
        }).toList();
        if (saleChanged) {
          sale['items'] = items;
        }
      }

      if (saleChanged) {
        queue[i] = sale;
        final uuid = sale['local_uuid']?.toString();
        if (uuid != null && uuid.isNotEmpty) {
          await _sqlite.updateOfflineSalePayload(uuid, sale);
        }
        modified = true;
      }
    }

    if (modified) {
      _memOfflineSales = queue;
      await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(queue));
    }
  }

  // ===========================================================================
  // 5. LOCAL COMPLETED SALES HISTORY
  // ===========================================================================
  Future<void> cacheSalesHistory(List<Map<String, dynamic>> sales) async {
    await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(sales));
    await setHasCloudSynced(true);
  }

  List<Map<String, dynamic>> getLocalSalesHistory() {
    final raw = _prefs.getString(_keyCompletedSalesHistory);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      // Purge any stale dummy seed invoices (#INV-1024..#INV-1020)
      list.removeWhere((s) => (s['number'] ?? '').toString().startsWith('#INV-102'));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSaleToLocalHistory(Map<String, dynamic> saleReceipt) async {
    final history = getLocalSalesHistory();
    history.removeWhere((s) => s['number'] == saleReceipt['number']);
    history.insert(0, saleReceipt);
    await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(history));
  }

  Future<void> updateLocalSaleStatus(int saleId, String status, {String? voidReason}) async {
    final history = getLocalSalesHistory();
    for (final s in history) {
      if (s['id'] == saleId) {
        s['status'] = status;
        if (voidReason != null) s['void_reason'] = voidReason;
      }
    }
    await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(history));
  }

  // ===========================================================================
  // 6. STORE PROFILE & PAIRED BLUETOOTH PRINTER (NAME + MAC ADDRESS)
  // ===========================================================================
  Map<String, dynamic> getStoreProfile() {
    final raw = _prefs.getString(_keyStoreProfile);
    if (raw == null || raw.isEmpty) {
      return {
        'name': 'NusaCommerce POS',
        'branch': 'Toko Utama',
        'address': '-',
        'phone': '-',
        'receipt_footer': 'Terima kasih atas kunjungan Anda!',
        'paper_size': '58mm',
      };
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {
        'name': 'NusaCommerce POS',
        'branch': 'Toko Utama',
        'address': '-',
        'phone': '-',
        'receipt_footer': 'Terima kasih atas kunjungan Anda!',
        'paper_size': '58mm',
      };
    }
  }

  Future<void> saveStoreProfile(Map<String, dynamic> profile) async {
    await _prefs.setString(_keyStoreProfile, jsonEncode(profile));
  }

  String? getPairedPrinterName() => _prefs.getString(_keyPairedPrinter);

  Future<void> setPairedPrinterName(String? name) async {
    if (name == null) {
      await _prefs.remove(_keyPairedPrinter);
    } else {
      await _prefs.setString(_keyPairedPrinter, name);
    }
  }

  String? getSavedPrinterMac() => _prefs.getString(_keyPairedPrinterMac);

  Future<void> setSavedPrinterMac(String? mac) async {
    if (mac == null || mac.trim().isEmpty) {
      await _prefs.remove(_keyPairedPrinterMac);
    } else {
      await _prefs.setString(_keyPairedPrinterMac, mac.trim());
    }
  }

  // ===========================================================================
  // 7. BUSINESS VERTICAL MODE (Single Source of Truth Fallback)
  // ===========================================================================
  String? getSavedBusinessVertical() => _prefs.getString(_keyBusinessVerticalMode);

  Future<void> setSavedBusinessVertical(String mode) async {
    await _prefs.setString(_keyBusinessVerticalMode, mode.trim().toLowerCase());
  }

  // ===========================================================================
  // 7. STANDALONE TRIAL SEEDING (6 VERTICAL TEMPLATES)
  // ===========================================================================
  Future<List<Map<String, dynamic>>> seedVerticalSampleProductsIfEmpty(
    String verticalCode, {
    bool forceReseed = false,
  }) async {
    final existing = getCachedProducts();
    final hasLeakedCloudProducts = existing.any(
      (p) => p['is_local_only'] != true && ((p['id'] as num?)?.toInt() ?? 0) > 0,
    );
    if (!forceReseed && existing.isNotEmpty && !hasLeakedCloudProducts) {
      return existing;
    }
    if (hasLeakedCloudProducts || forceReseed) {
      final prevIdentity = getActiveTenantIdentity();
      final prevVertical = getSavedBusinessVertical();
      final prevProfile = _prefs.getString(_keyStoreProfile);
      await clearTenantCache();
      if (prevIdentity != null && prevIdentity.startsWith('local-trial')) {
        await setActiveTenantIdentity(prevIdentity);
      }
      if (prevVertical != null && prevVertical.isNotEmpty) {
        await setSavedBusinessVertical(prevVertical);
      }
      if (prevProfile != null && prevProfile.isNotEmpty) {
        await _prefs.setString(_keyStoreProfile, prevProfile);
      }
    }

    final code = verticalCode.trim().toLowerCase();
    final List<Map<String, dynamic>> samples;

    switch (code) {
      case 'restaurant':
      case 'fnb':
      case 'cafe':
        samples = [
          {
            'id': -101,
            'name': 'Kopi Susu Gula Aren',
            'sku': 'FNB-001',
            'barcode': '899000100101',
            'type': 'standard',
            'selling_price': 18000.0,
            'cost_price': 8500.0,
            'stock': 50.0,
            'reorder_level': 10.0,
            'unit_code': 'cup',
            'category_id': 1,
            'category_name': 'Minuman',
            'icon_type': 'coffee',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Americano Iced',
            'sku': 'FNB-002',
            'barcode': '899000100102',
            'type': 'standard',
            'selling_price': 15000.0,
            'cost_price': 6000.0,
            'stock': 50.0,
            'reorder_level': 10.0,
            'unit_code': 'cup',
            'category_id': 1,
            'category_name': 'Minuman',
            'icon_type': 'coffee',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Nasi Goreng Spesial',
            'sku': 'FNB-003',
            'barcode': '899000100103',
            'type': 'standard',
            'selling_price': 25000.0,
            'cost_price': 13000.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'porsi',
            'category_id': 2,
            'category_name': 'Makanan Berat',
            'icon_type': 'food',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Ayam Geprek Sambal Matah',
            'sku': 'FNB-004',
            'barcode': '899000100104',
            'type': 'standard',
            'selling_price': 22000.0,
            'cost_price': 12000.0,
            'stock': 35.0,
            'reorder_level': 5.0,
            'unit_code': 'porsi',
            'category_id': 2,
            'category_name': 'Makanan Berat',
            'icon_type': 'food',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Kentang Goreng Crispy',
            'sku': 'FNB-005',
            'barcode': '899000100105',
            'type': 'standard',
            'selling_price': 14000.0,
            'cost_price': 6500.0,
            'stock': 40.0,
            'reorder_level': 8.0,
            'unit_code': 'porsi',
            'category_id': 3,
            'category_name': 'Snack',
            'icon_type': 'food',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Es Teh Manis Jumbo',
            'sku': 'FNB-006',
            'barcode': '899000100106',
            'type': 'standard',
            'selling_price': 7000.0,
            'cost_price': 2000.0,
            'stock': 80.0,
            'reorder_level': 10.0,
            'unit_code': 'gelas',
            'category_id': 1,
            'category_name': 'Minuman',
            'icon_type': 'drink',
            'is_local_only': true,
          },
        ];
        break;

      case 'pharmacy':
      case 'apotek':
        samples = [
          {
            'id': -101,
            'name': 'Paracetamol 500mg',
            'sku': 'APT-001',
            'barcode': '899000200101',
            'type': 'standard',
            'selling_price': 8000.0,
            'cost_price': 4500.0,
            'stock': 60.0,
            'reorder_level': 10.0,
            'unit_code': 'strip',
            'category_id': 1,
            'category_name': 'Obat Bebas',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Vitamin C 1000mg',
            'sku': 'APT-002',
            'barcode': '899000200102',
            'type': 'standard',
            'selling_price': 25000.0,
            'cost_price': 17000.0,
            'stock': 40.0,
            'reorder_level': 8.0,
            'unit_code': 'tube',
            'category_id': 2,
            'category_name': 'Vitamin',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Antasida Doen Sirup',
            'sku': 'APT-003',
            'barcode': '899000200103',
            'type': 'standard',
            'selling_price': 18500.0,
            'cost_price': 12500.0,
            'stock': 25.0,
            'reorder_level': 5.0,
            'unit_code': 'btl',
            'category_id': 1,
            'category_name': 'Obat Bebas',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Amoxicillin 500mg',
            'sku': 'APT-004',
            'barcode': '899000200104',
            'type': 'standard',
            'selling_price': 15000.0,
            'cost_price': 9000.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'strip',
            'category_id': 3,
            'category_name': 'Obat Resep',
            'requires_prescription': true,
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Masker Medis 3-Ply (Box 50)',
            'sku': 'APT-005',
            'barcode': '899000200105',
            'type': 'standard',
            'selling_price': 28000.0,
            'cost_price': 18000.0,
            'stock': 20.0,
            'reorder_level': 5.0,
            'unit_code': 'box',
            'category_id': 4,
            'category_name': 'Alkes',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Minyak Kayu Putih 60ml',
            'sku': 'APT-006',
            'barcode': '899000200106',
            'type': 'standard',
            'selling_price': 24000.0,
            'cost_price': 16500.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'btl',
            'category_id': 2,
            'category_name': 'Vitamin & Herbal',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
        ];
        break;

      case 'workshop':
      case 'bengkel':
        samples = [
          {
            'id': -101,
            'name': 'Oli Mesin MPX2 0.8L',
            'sku': 'BKL-001',
            'barcode': '899000300101',
            'type': 'standard',
            'selling_price': 58000.0,
            'cost_price': 44000.0,
            'stock': 30.0,
            'reorder_level': 6.0,
            'unit_code': 'btl',
            'category_id': 1,
            'category_name': 'Oli & Pelumas',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Jasa Servis Tune-Up Ringan',
            'sku': 'BKL-002',
            'barcode': '899000300102',
            'type': 'service',
            'selling_price': 45000.0,
            'cost_price': 10000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'jasa',
            'category_id': 2,
            'category_name': 'Jasa Bengkel',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Kampas Rem Depan Matic',
            'sku': 'BKL-003',
            'barcode': '899000300103',
            'type': 'standard',
            'selling_price': 42000.0,
            'cost_price': 26000.0,
            'stock': 20.0,
            'reorder_level': 4.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Sparepart',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Busi Standar Beat / Vario',
            'sku': 'BKL-004',
            'barcode': '899000300104',
            'type': 'standard',
            'selling_price': 22000.0,
            'cost_price': 13000.0,
            'stock': 35.0,
            'reorder_level': 5.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Sparepart',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Oli Gardan Matic 120ml',
            'sku': 'BKL-005',
            'barcode': '899000300105',
            'type': 'standard',
            'selling_price': 18000.0,
            'cost_price': 11000.0,
            'stock': 40.0,
            'reorder_level': 8.0,
            'unit_code': 'pcs',
            'category_id': 1,
            'category_name': 'Oli & Pelumas',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Jasa Tambal Ban Tubeless',
            'sku': 'BKL-006',
            'barcode': '899000300106',
            'type': 'service',
            'selling_price': 20000.0,
            'cost_price': 3000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'jasa',
            'category_id': 2,
            'category_name': 'Jasa Bengkel',
            'icon_type': 'service',
            'is_local_only': true,
          },
        ];
        break;

      case 'laundry':
        samples = [
          {
            'id': -101,
            'name': 'Cuci Komplit Reguler (2 Hari)',
            'sku': 'LND-001',
            'barcode': '899000400101',
            'type': 'service',
            'selling_price': 7000.0,
            'cost_price': 2500.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'kg',
            'sold_by_weight': true,
            'category_id': 1,
            'category_name': 'Kiloan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Cuci Express Kilat (6 Jam)',
            'sku': 'LND-002',
            'barcode': '899000400102',
            'type': 'service',
            'selling_price': 14000.0,
            'cost_price': 4000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'kg',
            'sold_by_weight': true,
            'category_id': 1,
            'category_name': 'Kiloan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Setrika Uap Saja',
            'sku': 'LND-003',
            'barcode': '899000400103',
            'type': 'service',
            'selling_price': 5000.0,
            'cost_price': 1500.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'kg',
            'sold_by_weight': true,
            'category_id': 1,
            'category_name': 'Kiloan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Cuci Bedcover Besar',
            'sku': 'LND-004',
            'barcode': '899000400104',
            'type': 'service',
            'selling_price': 35000.0,
            'cost_price': 10000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'pcs',
            'category_id': 2,
            'category_name': 'Satuan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Cuci Sepatu Deep Clean',
            'sku': 'LND-005',
            'barcode': '899000400105',
            'type': 'service',
            'selling_price': 30000.0,
            'cost_price': 7000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'psg',
            'category_id': 2,
            'category_name': 'Satuan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
        ];
        break;

      case 'salon':
      case 'barbershop':
        samples = [
          {
            'id': -101,
            'name': 'Potong Rambut + Cuci',
            'sku': 'SLN-001',
            'barcode': '899000500101',
            'type': 'service',
            'selling_price': 40000.0,
            'cost_price': 8000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 1,
            'category_name': 'Haircut',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Creambath Aromatherapy',
            'sku': 'SLN-002',
            'barcode': '899000500102',
            'type': 'service',
            'selling_price': 65000.0,
            'cost_price': 18000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 2,
            'category_name': 'Perawatan',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Shaving & Beard Trim',
            'sku': 'SLN-003',
            'barcode': '899000500103',
            'type': 'service',
            'selling_price': 25000.0,
            'cost_price': 5000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 1,
            'category_name': 'Haircut',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Pomade Waterbased Premium',
            'sku': 'SLN-004',
            'barcode': '899000500104',
            'type': 'standard',
            'selling_price': 75000.0,
            'cost_price': 48000.0,
            'stock': 20.0,
            'reorder_level': 4.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Produk Rambut',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Hair Coloring Natural',
            'sku': 'SLN-005',
            'barcode': '899000500105',
            'type': 'service',
            'selling_price': 120000.0,
            'cost_price': 42000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 2,
            'category_name': 'Perawatan',
            'icon_type': 'salon',
            'is_local_only': true,
          },
        ];
        break;

      case 'retail':
      default:
        samples = [
          {
            'id': -101,
            'name': 'Indomie Goreng Original',
            'sku': 'RTL-001',
            'barcode': '899000000101',
            'type': 'standard',
            'selling_price': 3500.0,
            'cost_price': 2700.0,
            'stock': 80.0,
            'reorder_level': 12.0,
            'unit_code': 'pcs',
            'category_id': 1,
            'category_name': 'Sembako',
            'icon_type': 'retail',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Aqua Botol 600ml',
            'sku': 'RTL-002',
            'barcode': '899000000102',
            'type': 'standard',
            'selling_price': 4000.0,
            'cost_price': 2500.0,
            'stock': 60.0,
            'reorder_level': 12.0,
            'unit_code': 'btl',
            'category_id': 2,
            'category_name': 'Minuman',
            'icon_type': 'drink',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Beras Pandan Wangi 5kg',
            'sku': 'RTL-003',
            'barcode': '899000000103',
            'type': 'standard',
            'selling_price': 74000.0,
            'cost_price': 64000.0,
            'stock': 20.0,
            'reorder_level': 4.0,
            'unit_code': 'sak',
            'category_id': 1,
            'category_name': 'Sembako',
            'icon_type': 'retail',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Minyak Goreng Pouch 1L',
            'sku': 'RTL-004',
            'barcode': '899000000104',
            'type': 'standard',
            'selling_price': 18500.0,
            'cost_price': 15500.0,
            'stock': 35.0,
            'reorder_level': 6.0,
            'unit_code': 'pcs',
            'category_id': 1,
            'category_name': 'Sembako',
            'icon_type': 'retail',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Kopi Kapal Api Mix 165g',
            'sku': 'RTL-005',
            'barcode': '899000000105',
            'type': 'standard',
            'selling_price': 16000.0,
            'cost_price': 12500.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'pak',
            'category_id': 2,
            'category_name': 'Minuman',
            'icon_type': 'coffee',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Sabun Cuci Piring 750ml',
            'sku': 'RTL-006',
            'barcode': '899000000106',
            'type': 'standard',
            'selling_price': 15000.0,
            'cost_price': 11200.0,
            'stock': 25.0,
            'reorder_level': 5.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Kebersihan',
            'icon_type': 'retail',
            'is_local_only': true,
          },
        ];
        break;
    }

    await cacheProducts(samples);

    final cats = <int, Map<String, dynamic>>{
      0: {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': samples.length},
    };
    for (final s in samples) {
      final cid = (s['category_id'] as num?)?.toInt() ?? 1;
      final cname = (s['category_name'] ?? 'Umum').toString();
      if (!cats.containsKey(cid)) {
        cats[cid] = {'id': cid, 'name': cname, 'color': '#2563EB', 'products_count': 1};
      } else {
        cats[cid]!['products_count'] = ((cats[cid]!['products_count'] as int?) ?? 0) + 1;
      }
    }
    await cacheCategories(cats.values.toList());

    if (getCachedCustomers().isEmpty) {
      await cacheCustomers([
        {
          'id': -201,
          'name': 'Pelanggan Langganan',
          'phone': '081234567890',
          'outstanding_balance': 0.0,
          'store_credit_balance': 0.0,
          'points_balance': 0,
          'is_local_only': true,
        },
      ]);
    }
    if (getCachedSuppliers().isEmpty) {
      await cacheSuppliers([
        {
          'id': -301,
          'name': 'Supplier Utama',
          'phone': '081200001111',
          'address': 'Pusat Grosir Setempat',
          'is_local_only': true,
        },
      ]);
    }
    return samples;
  }

  // ===========================================================================
  // 8. LOCAL SHIFTS & DRAWER CASH MUTATION ENGINE
  // ===========================================================================
  List<Map<String, dynamic>> getLocalShiftsHistory() {
    final list = _readPrefsList(_keyLocalShifts);
    list.sort((a, b) => (b['opened_at'] ?? '').toString().compareTo((a['opened_at'] ?? '').toString()));
    return list;
  }

  Future<void> _saveLocalShifts(List<Map<String, dynamic>> shifts) async {
    await _prefs.setString(_keyLocalShifts, jsonEncode(shifts));
  }

  DateTime? _parseFlexDateTime(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    final iso = DateTime.tryParse(str);
    if (iso != null) return iso;
    // Handle dd/MM/yyyy HH:mm or dd/MM/yyyy HH:mm:ss
    final reg = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
    final m = reg.firstMatch(str);
    if (m != null) {
      return DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
        int.tryParse(m.group(4) ?? '0') ?? 0,
        int.tryParse(m.group(5) ?? '0') ?? 0,
        int.tryParse(m.group(6) ?? '0') ?? 0,
      );
    }
    return null;
  }

  ({double cashSales, int txCount}) _computeShiftCashSales(DateTime openedAt) {
    double cashTotal = 0.0;
    int txCount = 0;
    final sales = getLocalSalesHistory();
    for (final s in sales) {
      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided') continue;
      final saleDt = _parseFlexDateTime(s['created_at'] ?? s['sale_datetime']);
      if (saleDt != null && saleDt.isBefore(openedAt.subtract(const Duration(seconds: 2)))) {
        continue;
      }
      txCount++;
      final payments = s['payments'];
      final changeReturned = (s['change_returned'] as num?)?.toDouble() ?? 0.0;
      double saleCash = 0.0;
      if (payments is List && payments.isNotEmpty) {
        for (final p in payments) {
          if (p is! Map) continue;
          final method = (p['method_name'] ?? p['payment_method_name'] ?? p['name'] ?? '').toString().toLowerCase();
          final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          if (method.contains('tunai') || method.contains('cash')) {
            saleCash += amt;
          }
        }
        if (saleCash > 0 && changeReturned > 0) {
          saleCash = (saleCash - changeReturned).clamp(0.0, double.infinity);
        }
      } else {
        final methods = (s['payment_methods'] as List?)?.join(' ').toLowerCase() ?? '';
        if (methods.contains('tunai') || methods.contains('cash')) {
          saleCash = ((s['paid_total'] as num?)?.toDouble() ?? 0.0) - changeReturned;
          if (saleCash < 0) saleCash = 0.0;
        }
      }
      cashTotal += saleCash;
    }
    return (cashSales: cashTotal, txCount: txCount);
  }

  Map<String, dynamic> _enrichShiftTotals(Map<String, dynamic> rawShift) {
    final shift = Map<String, dynamic>.from(rawShift);
    final openedAt = _parseFlexDateTime(shift['opened_at']) ?? DateTime.now();
    final isClosed = (shift['status'] ?? 'open').toString().toLowerCase() == 'closed';
    final computed = isClosed
        ? (
            cashSales: (shift['cash_sales'] as num?)?.toDouble() ?? 0.0,
            txCount: (shift['transactions_count'] as num?)?.toInt() ?? 0,
          )
        : _computeShiftCashSales(openedAt);

    final opening = (shift['opening_cash'] as num?)?.toDouble() ?? 0.0;
    final cashIn = (shift['cash_in'] as num?)?.toDouble() ?? 0.0;
    final cashOut = (shift['cash_out'] as num?)?.toDouble() ?? 0.0;
    final expected = opening + computed.cashSales + cashIn - cashOut;

    shift['cash_sales'] = computed.cashSales;
    shift['transactions_count'] = computed.txCount;
    shift['expected_cash'] = expected;
    if (shift['entries'] is! List) shift['entries'] = <dynamic>[];
    return shift;
  }

  Map<String, dynamic>? getCurrentLocalShift() {
    final shifts = getLocalShiftsHistory();
    for (final s in shifts) {
      if ((s['status'] ?? '').toString().toLowerCase() == 'open') {
        return _enrichShiftTotals(s);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> openLocalShift({
    required double openingCash,
    String? notes,
    String? cashierName,
  }) async {
    final shifts = getLocalShiftsHistory();
    final existingIdx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (existingIdx >= 0) {
      final enriched = _enrichShiftTotals(shifts[existingIdx]);
      enriched['status'] = 'closed';
      enriched['closed_at'] = DateTime.now().toIso8601String();
      enriched['closing_cash'] = enriched['expected_cash'];
      enriched['variance'] = 0.0;
      shifts[existingIdx] = enriched;
      await _sqlite.upsertShift(enriched);
    }

    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final newShift = <String, dynamic>{
      'id': id,
      'shift_number': 'SHF-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(id % 1000).toString().padLeft(3, '0')}',
      'cashier_name': (cashierName ?? 'Kasir Mandiri').trim().isEmpty ? 'Kasir Mandiri' : cashierName!.trim(),
      'status': 'open',
      'opened_at': now.toIso8601String(),
      'opening_cash': openingCash,
      'cash_sales': 0.0,
      'cash_in': 0.0,
      'cash_out': 0.0,
      'expected_cash': openingCash,
      'no_sale_opens_count': 0,
      'transactions_count': 0,
      'notes': notes,
      'entries': <Map<String, dynamic>>[],
      'is_local': true,
    };

    shifts.insert(0, newShift);
    await _saveLocalShifts(shifts);
    await _sqlite.upsertShift(newShift);
    return newShift;
  }

  Future<Map<String, dynamic>?> addLocalShiftCashEntry({
    required String type,
    required double amount,
    required String reason,
  }) async {
    final shifts = getLocalShiftsHistory();
    final idx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (idx < 0) return null;

    final shift = Map<String, dynamic>.from(shifts[idx]);
    final entries = (shift['entries'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final entry = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'amount': amount,
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
    };
    entries.insert(0, entry);
    shift['entries'] = entries;

    if (type == 'pay_in') {
      shift['cash_in'] = ((shift['cash_in'] as num?)?.toDouble() ?? 0.0) + amount;
    } else if (type == 'pay_out') {
      shift['cash_out'] = ((shift['cash_out'] as num?)?.toDouble() ?? 0.0) + amount;
    } else if (type == 'drawer_open_no_sale') {
      shift['no_sale_opens_count'] = ((shift['no_sale_opens_count'] as num?)?.toInt() ?? 0) + 1;
    }

    final enriched = _enrichShiftTotals(shift);
    shifts[idx] = enriched;
    await _saveLocalShifts(shifts);
    await _sqlite.upsertShift(enriched);
    return enriched;
  }

  Future<Map<String, dynamic>?> closeLocalShift({
    required double actualClosingCash,
    String? notes,
  }) async {
    final shifts = getLocalShiftsHistory();
    final idx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (idx < 0) return null;

    final enriched = _enrichShiftTotals(shifts[idx]);
    final expected = (enriched['expected_cash'] as num?)?.toDouble() ?? 0.0;
    final variance = actualClosingCash - expected;

    enriched['status'] = 'closed';
    enriched['closed_at'] = DateTime.now().toIso8601String();
    enriched['closing_cash'] = actualClosingCash;
    enriched['variance'] = variance;
    if (notes != null && notes.trim().isNotEmpty) {
      enriched['notes'] = notes.trim();
    }

    shifts[idx] = enriched;
    await _saveLocalShifts(shifts);
    await _sqlite.upsertShift(enriched);
    return enriched;
  }

  // ===========================================================================
  // 9. LOCAL DEBT BOOK (PIUTANG, HUTANG SUPPLIER & PENGELUARAN)
  // ===========================================================================
  List<Map<String, dynamic>> getLocalReceivables() {
    final sales = getLocalSalesHistory();
    final List<Map<String, dynamic>> receivables = [];
    for (final s in sales) {
      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided') continue;
      final balance = (s['balance_due'] as num?)?.toDouble() ?? 0.0;
      if (balance <= 0.5) continue;

      final customer = s['customer'] is Map ? Map<String, dynamic>.from(s['customer'] as Map) : <String, dynamic>{};
      final custName = (customer['name'] ?? s['customer_name'] ?? 'Pelanggan Umum').toString();
      final custPhone = (customer['phone'] ?? s['customer_phone'] ?? '').toString();
      int ageDays = 0;
      final dueStr = s['due_date']?.toString();
      if (dueStr != null && dueStr.trim().isNotEmpty) {
        final parsedDue = DateTime.tryParse(dueStr.trim());
        if (parsedDue != null) {
          ageDays = DateTime.now().difference(parsedDue).inDays;
        }
      }
      receivables.add({
        'id': s['id'],
        'sale_id': s['id'],
        'invoice_number': s['number'] ?? '#INV',
        'number': s['number'] ?? '#INV',
        'customer_id': customer['id'],
        'customer_name': custName,
        'customer_phone': custPhone,
        'customer': {
          'id': customer['id'],
          'name': custName,
          'phone': custPhone,
        },
        'age_days': ageDays,
        'total_amount': (s['grand_total'] as num?)?.toDouble() ?? 0.0,
        'paid_amount': (s['paid_total'] as num?)?.toDouble() ?? 0.0,
        'balance_due': balance,
        'due_date': s['due_date'],
        'created_at': s['sale_datetime'] ?? s['created_at'] ?? '',
        'is_local': true,
      });
    }
    return receivables;
  }

  Future<Map<String, dynamic>?> payLocalReceivable({
    required int saleId,
    required double amount,
    String paymentMethod = 'Tunai',
    String? notes,
  }) async {
    if (amount <= 0) return null;
    final history = getLocalSalesHistory();
    final idx = history.indexWhere((s) => (s['id'] as num?)?.toInt() == saleId);
    if (idx < 0) return null;

    final sale = Map<String, dynamic>.from(history[idx]);
    final currentBalance = (sale['balance_due'] as num?)?.toDouble() ?? 0.0;
    final currentPaid = (sale['paid_total'] as num?)?.toDouble() ?? 0.0;
    final applied = amount > currentBalance ? currentBalance : amount;
    final nextBalance = (currentBalance - applied).clamp(0.0, double.infinity);

    sale['paid_total'] = currentPaid + applied;
    sale['balance_due'] = nextBalance;
    sale['payment_status'] = nextBalance <= 0.5 ? 'paid' : 'partial';

    final payments = (sale['payments'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    payments.add({
      'payment_method_name': paymentMethod,
      'method_name': paymentMethod,
      'amount': applied,
      'notes': notes,
      'paid_at': DateTime.now().toIso8601String(),
    });
    sale['payments'] = payments;

    history[idx] = sale;
    await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(history));

    // Sync customer outstanding balance
    final customerMap = sale['customer'] is Map ? Map<String, dynamic>.from(sale['customer'] as Map) : null;
    final custId = (customerMap?['id'] as num?)?.toInt();
    if (custId != null && custId != 0) {
      final customers = getCachedCustomers();
      final cIdx = customers.indexWhere((c) => (c['id'] as num?)?.toInt() == custId);
      if (cIdx >= 0) {
        final nextCust = Map<String, dynamic>.from(customers[cIdx]);
        final prevDebt = (nextCust['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
        nextCust['outstanding_balance'] = (prevDebt - applied).clamp(0.0, double.infinity);
        await addOrUpdateLocalCustomer(nextCust);
      }
    }

    // Record cash-in on active local shift when paid in Cash/Tunai
    final methodLower = paymentMethod.toLowerCase();
    if ((methodLower.contains('tunai') || methodLower.contains('cash')) && getCurrentLocalShift() != null) {
      await addLocalShiftCashEntry(
        type: 'pay_in',
        amount: applied,
        reason: 'Pelunasan Kasbon ${sale['number'] ?? saleId}',
      );
    }

    return {
      'sale_id': saleId,
      'invoice_number': sale['number'],
      'amount_paid': applied,
      'remaining_balance': nextBalance,
      'payment_status': sale['payment_status'],
    };
  }

  List<Map<String, dynamic>> getLocalPayables() {
    final list = _readPrefsList(_keyLocalPayables);
    final now = DateTime.now();
    final enriched = list.map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final balance = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
      final invNo = (item['number'] ?? item['invoice_number'] ?? '#PO').toString();
      final supName = (item['supplier_name'] ?? (item['supplier'] is Map ? item['supplier']['name'] : null) ?? 'Supplier').toString();
      final supPhone = (item['supplier_phone'] ?? (item['supplier'] is Map ? item['supplier']['phone'] : null) ?? '').toString();
      bool isOverdue = false;
      final dueStr = item['due_date']?.toString();
      if (balance > 0.5 && dueStr != null && dueStr.trim().isNotEmpty) {
        final parsedDue = DateTime.tryParse(dueStr.trim());
        if (parsedDue != null && now.isAfter(parsedDue.add(const Duration(days: 1)))) {
          isOverdue = true;
        }
      }
      item['purchase_id'] = item['purchase_id'] ?? item['id'];
      item['invoice_number'] = item['invoice_number'] ?? invNo;
      item['number'] = invNo;
      item['supplier'] = item['supplier'] is Map
          ? Map<String, dynamic>.from(item['supplier'] as Map)
          : {
              'id': item['supplier_id'],
              'name': supName,
              'phone': supPhone,
            };
      item['is_overdue'] = isOverdue;
      return item;
    }).toList();
    enriched.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    return enriched;
  }

  Future<Map<String, dynamic>> addLocalPayable({
    required String supplierName,
    String? supplierPhone,
    int? supplierId,
    required double totalAmount,
    double paidAmount = 0.0,
    String? dueDate,
    String? invoiceNumber,
    String? notes,
  }) async {
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final balanceDue = (totalAmount - paidAmount).clamp(0.0, double.infinity);
    final status = balanceDue <= 0.5 ? 'paid' : (paidAmount > 0 ? 'partial' : 'unpaid');
    final cleanSupplierName = supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim();
    final invNo = (invoiceNumber ?? '').trim().isNotEmpty
        ? invoiceNumber!.trim()
        : 'PO-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(id % 1000).toString().padLeft(3, '0')}';
    bool isOverdue = false;
    if (balanceDue > 0.5 && dueDate != null && dueDate.trim().isNotEmpty) {
      final parsedDue = DateTime.tryParse(dueDate.trim());
      if (parsedDue != null && now.isAfter(parsedDue.add(const Duration(days: 1)))) {
        isOverdue = true;
      }
    }
    final record = <String, dynamic>{
      'id': id,
      'purchase_id': id,
      'invoice_number': invNo,
      'number': invNo,
      'supplier_id': supplierId,
      'supplier_name': cleanSupplierName,
      'supplier_phone': supplierPhone ?? '',
      'supplier': {
        'id': supplierId,
        'name': cleanSupplierName,
        'phone': supplierPhone ?? '',
      },
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'balance_due': balanceDue,
      'status': status,
      'due_date': dueDate,
      'is_overdue': isOverdue,
      'created_at': now.toIso8601String(),
      'notes': notes,
      'is_local': true,
    };

    final list = _readPrefsList(_keyLocalPayables);
    list.insert(0, record);
    await _prefs.setString(_keyLocalPayables, jsonEncode(list));
    await _sqlite.upsertLocalPayable(record);
    return record;
  }

  Future<Map<String, dynamic>?> payLocalPayable({
    required int payableId,
    required double amount,
    String paymentMethod = 'Tunai',
  }) async {
    if (amount <= 0) return null;
    final list = _readPrefsList(_keyLocalPayables);
    final idx = list.indexWhere(
      (p) => (p['purchase_id'] as num?)?.toInt() == payableId || (p['id'] as num?)?.toInt() == payableId,
    );
    if (idx < 0) return null;

    final item = Map<String, dynamic>.from(list[idx]);
    final currentBalance = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
    final currentPaid = (item['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final applied = amount > currentBalance ? currentBalance : amount;
    final nextBalance = (currentBalance - applied).clamp(0.0, double.infinity);

    item['paid_amount'] = currentPaid + applied;
    item['balance_due'] = nextBalance;
    item['status'] = nextBalance <= 0.5 ? 'paid' : 'partial';
    if (nextBalance <= 0.5) {
      item['is_overdue'] = false;
    }

    list[idx] = item;
    await _prefs.setString(_keyLocalPayables, jsonEncode(list));
    await _sqlite.upsertLocalPayable(item);

    final methodLower = paymentMethod.toLowerCase();
    if ((methodLower.contains('tunai') || methodLower.contains('cash')) && getCurrentLocalShift() != null) {
      await addLocalShiftCashEntry(
        type: 'pay_out',
        amount: applied,
        reason: 'Bayar Hutang Supplier ${item['number'] ?? item['invoice_number'] ?? ''}',
      );
    }
    return item;
  }

  List<Map<String, dynamic>> getLocalExpenses() {
    final list = _readPrefsList(_keyLocalExpenses).map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final rawCat = item['category'];
      final catName = (item['category_name'] ?? (rawCat is Map ? rawCat['name'] : rawCat) ?? 'Operasional Toko').toString();
      item['category_name'] = catName;
      item['category'] = rawCat is Map ? Map<String, dynamic>.from(rawCat) : {'id': 1, 'name': catName};
      return item;
    }).toList();
    list.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    return list;
  }

  Future<Map<String, dynamic>> addLocalExpense({
    required String category,
    required double amount,
    required String description,
    String paymentMethod = 'Tunai',
    String? recordedBy,
  }) async {
    final now = DateTime.now();
    final catName = category.trim().isEmpty ? 'Operasional Toko' : category.trim();
    final record = <String, dynamic>{
      'id': now.millisecondsSinceEpoch,
      'category_name': catName,
      'category': {'id': 1, 'name': catName},
      'amount': amount,
      'description': description.trim(),
      'payment_method': paymentMethod,
      'recorded_by': recordedBy ?? 'Pemilik',
      'expense_date': now.toIso8601String().split('T').first,
      'created_at': now.toIso8601String(),
      'is_local': true,
    };

    final list = _readPrefsList(_keyLocalExpenses);
    list.insert(0, record);
    await _prefs.setString(_keyLocalExpenses, jsonEncode(list));
    await _sqlite.upsertLocalExpense(record);

    final methodLower = paymentMethod.toLowerCase();
    if ((methodLower.contains('tunai') || methodLower.contains('cash')) && getCurrentLocalShift() != null) {
      await addLocalShiftCashEntry(
        type: 'pay_out',
        amount: amount,
        reason: 'Biaya $catName: ${record['description']}',
      );
    }
    return record;
  }

  // ===========================================================================
  // 10. LOCAL BUSINESS REPORT & REAL-TIME PROFIT CALCULATION ENGINE
  // ===========================================================================
  Map<String, dynamic> computeLocalBusinessReport({
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final products = getCachedProducts();
    final costById = <int, double>{};
    int lowStockCount = 0;
    for (final p in products) {
      final pid = (p['id'] as num?)?.toInt();
      if (pid != null) {
        costById[pid] = (p['cost_price'] as num?)?.toDouble() ?? 0.0;
      }
      final stock = (p['stock'] as num?)?.toDouble() ?? 0.0;
      final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 5.0;
      final isService = (p['type'] ?? '').toString().toLowerCase() == 'service';
      if (!isService && stock <= reorder) {
        lowStockCount++;
      }
    }

    final sales = getLocalSalesHistory();
    double grossSales = 0.0;
    double netSales = 0.0;
    double discountTotal = 0.0;
    double totalCogs = 0.0;
    int txCount = 0;
    int voidCount = 0;
    int refundCount = 0;

    final paymentTotals = <String, double>{};
    final paymentCounts = <String, int>{};
    final productStats = <String, Map<String, dynamic>>{};
    final dailyMap = <String, Map<String, dynamic>>{};

    for (final s in sales) {
      final saleDt = _parseFlexDateTime(s['created_at'] ?? s['sale_datetime']);
      if (saleDt != null) {
        if (startDate != null && saleDt.isBefore(startDate)) continue;
        if (endDate != null && saleDt.isAfter(endDate)) continue;
      }

      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided') {
        voidCount++;
        continue;
      }
      if (status == 'refunded') {
        refundCount++;
        continue;
      }

      txCount++;
      final saleGrandTotal = (s['grand_total'] as num?)?.toDouble() ?? 0.0;
      final saleDiscount = (s['discount_total'] as num?)?.toDouble() ?? 0.0;
      final saleSubtotal = (s['subtotal'] as num?)?.toDouble() ?? (saleGrandTotal + saleDiscount);

      grossSales += saleSubtotal;
      netSales += saleGrandTotal;
      discountTotal += saleDiscount;

      // Daily trend grouping
      final dayKey = saleDt != null
          ? '${saleDt.year}-${saleDt.month.toString().padLeft(2, '0')}-${saleDt.day.toString().padLeft(2, '0')}'
          : DateTime.now().toIso8601String().split('T').first;
      final parts = dayKey.split('-');
      final dayLabel = parts.length == 3 ? '${parts[2]}/${parts[1]}' : dayKey;
      dailyMap.putIfAbsent(
        dayKey,
        () => {'date': dayKey, 'day_label': dayLabel, 'revenue': 0.0, 'transactions': 0},
      );
      dailyMap[dayKey]!['revenue'] = ((dailyMap[dayKey]!['revenue'] as double?) ?? 0.0) + saleGrandTotal;
      dailyMap[dayKey]!['transactions'] = ((dailyMap[dayKey]!['transactions'] as int?) ?? 0) + 1;

      // Payment breakdown
      final payments = s['payments'];
      if (payments is List && payments.isNotEmpty) {
        final changeReturned = (s['change_returned'] as num?)?.toDouble() ?? 0.0;
        for (int i = 0; i < payments.length; i++) {
          final p = payments[i];
          if (p is! Map) continue;
          final method = (p['method_name'] ?? p['payment_method_name'] ?? p['name'] ?? 'Tunai').toString();
          var amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          if (i == 0 && changeReturned > 0 && method.toLowerCase().contains('tunai')) {
            amt = (amt - changeReturned).clamp(0.0, double.infinity);
          }
          paymentTotals[method] = (paymentTotals[method] ?? 0.0) + amt;
          paymentCounts[method] = (paymentCounts[method] ?? 0) + 1;
        }
        final balDue = (s['balance_due'] as num?)?.toDouble() ?? 0.0;
        if (balDue > 0.5) {
          paymentTotals['Kasbon'] = (paymentTotals['Kasbon'] ?? 0.0) + balDue;
          paymentCounts['Kasbon'] = (paymentCounts['Kasbon'] ?? 0) + 1;
        }
      } else {
        final methods = s['payment_methods'] as List?;
        final label = (methods != null && methods.isNotEmpty) ? methods.first.toString() : 'Tunai';
        paymentTotals[label] = (paymentTotals[label] ?? 0.0) + saleGrandTotal;
        paymentCounts[label] = (paymentCounts[label] ?? 0) + 1;
      }

      // Items COGS & Top Products
      final items = s['items'] as List? ?? [];
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        if (rawItem['is_exchange_return'] == true) continue;
        final pid = (rawItem['product_id'] as num?)?.toInt();
        final pName = (rawItem['product_name'] ?? 'Produk').toString();
        final qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0.0;
        final mult = (rawItem['multiplier'] as num?)?.toDouble() ?? 1.0;
        final lineTotal = (rawItem['line_total'] as num?)?.toDouble() ?? 0.0;
        final itemCost = (rawItem['cost_price'] as num?)?.toDouble() ?? (pid != null ? (costById[pid] ?? 0.0) : 0.0);
        final lineCogs = qty * mult * itemCost;
        totalCogs += lineCogs;

        productStats.putIfAbsent(
          pName,
          () => {'name': pName, 'qty': 0.0, 'revenue': 0.0, 'profit': 0.0},
        );
        productStats[pName]!['qty'] = ((productStats[pName]!['qty'] as double?) ?? 0.0) + qty;
        productStats[pName]!['revenue'] = ((productStats[pName]!['revenue'] as double?) ?? 0.0) + lineTotal;
        productStats[pName]!['profit'] =
            ((productStats[pName]!['profit'] as double?) ?? 0.0) + (lineTotal - lineCogs);
      }
    }

    // Store Expenses from local_expenses
    double storeExpenses = 0.0;
    for (final e in getLocalExpenses()) {
      final dt = _parseFlexDateTime(e['created_at'] ?? e['expense_date']);
      if (dt != null) {
        if (startDate != null && dt.isBefore(startDate)) continue;
        if (endDate != null && dt.isAfter(endDate)) continue;
      }
      storeExpenses += (e['amount'] as num?)?.toDouble() ?? 0.0;
    }

    // Shifts Anti-Fraud metrics & standalone shift payouts
    int varianceShiftsCount = 0;
    int noSaleOpensCount = 0;
    for (final sh in getLocalShiftsHistory()) {
      final variance = (sh['variance'] as num?)?.toDouble() ?? 0.0;
      if ((sh['status'] ?? '').toString().toLowerCase() == 'closed' && variance.abs() > 100.0) {
        varianceShiftsCount++;
      }
      noSaleOpensCount += (sh['no_sale_opens_count'] as num?)?.toInt() ?? 0;
    }

    final grossProfit = netSales - totalCogs;
    final netProfit = grossProfit - storeExpenses;
    final profitMargin = netSales > 0 ? (netProfit / netSales) * 100.0 : 0.0;

    final topProducts = productStats.values.toList()
      ..sort((a, b) => ((b['revenue'] as double?) ?? 0.0).compareTo((a['revenue'] as double?) ?? 0.0));

    final paymentBreakdown = paymentTotals.entries
        .map((e) => {
              'method': e.key,
              'amount': e.value,
              'count': paymentCounts[e.key] ?? 1,
            })
        .toList()
      ..sort((a, b) => ((b['amount'] as double?) ?? 0.0).compareTo((a['amount'] as double?) ?? 0.0));

    final dailyTrend = dailyMap.values.toList()
      ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));

    final totalReceivables = getLocalReceivables().fold<double>(
      0.0,
      (sum, r) => sum + ((r['balance_due'] as num?)?.toDouble() ?? 0.0),
    );
    final totalPayables = getLocalPayables()
        .where((p) => ((p['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .fold<double>(
          0.0,
          (sum, p) => sum + ((p['balance_due'] as num?)?.toDouble() ?? 0.0),
        );

    return {
      'gross_sales': grossSales,
      'net_sales': netSales,
      'discount_total': discountTotal,
      'transactions_count': txCount,
      'average_basket': txCount > 0 ? (netSales / txCount) : 0.0,
      'total_cogs': totalCogs,
      'gross_profit': grossProfit,
      'store_expenses': storeExpenses,
      'net_profit': netProfit,
      'profit_margin': profitMargin,
      'total_receivables': totalReceivables,
      'total_payables': totalPayables,
      'low_stock_count': lowStockCount,
      'payment_breakdown': paymentBreakdown,
      'top_products': topProducts.take(10).toList(),
      'daily_trend': dailyTrend.take(7).toList(),
      'fraud_indicators': {
        'void_count': voidCount,
        'refund_count': refundCount,
        'variance_shifts_count': varianceShiftsCount,
        'no_sale_opens_count': noSaleOpensCount,
      },
    };
  }
}
