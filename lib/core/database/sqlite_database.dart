import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'daos/error_log_dao.dart';
import 'daos/product_local_dao.dart';
import 'daos/sales_queue_dao.dart';
import 'daos/shift_local_dao.dart';

/// Enterprise Indexed Local Database Engine (`nusacommerce_local.db`) powered by SQLite (`sqflite`).
/// Delegates all domain persistence to cohesive DAOs:
/// - [ProductLocalDao]: indexed `products`, `products_fts`, `customers`, `suppliers`, `kv_collections`
/// - [SalesQueueDao]: ACID offline checkout, `offline_sales`, `held_sales`, `pending_receivable_payments`, `dead_letter_queue`
/// - [ShiftLocalDao]: `shifts`, `pending_shift_closures`
/// - [ErrorLogDao]: sanitized `local_error_logs` (500-row rolling cap)
class SqliteDatabase {
  SqliteDatabase._();

  static final SqliteDatabase instance = SqliteDatabase._();

  static const String _dbName = 'nusacommerce_local.db';
  static const int _dbVersion = 7;

  Database? _db;
  bool _ftsAvailable = false;

  late final ProductLocalDao productsDao = ProductLocalDao(
    () => database,
    isFtsAvailable: () => _ftsAvailable,
  );
  late final SalesQueueDao salesQueueDao = SalesQueueDao(() => database);
  late final ShiftLocalDao shiftsDao = ShiftLocalDao(() => database);
  late final ErrorLogDao errorLogDao = ErrorLogDao(() => database);

  bool get isSupported => !kIsWeb;

  /// True when a live native `sqflite` database handle is open and ready (`BUG-002` SSOT gate).
  bool get hasActiveDatabase => _db != null && _db!.isOpen;

  Future<Database?> get database async {
    if (!isSupported) return null;
    if (_db != null && _db!.isOpen) return _db;
    return await init();
  }

  /// Injects an opened [Database] (e.g., for testing) and ensures schema v7 tables exist.
  @visibleForTesting
  Future<void> attachDatabaseForTesting(Database? db) async {
    _db = db;
    if (db != null && db.isOpen) {
      await _ensureCoreTables(db);
      await _ensureStandaloneTables(db);
    }
  }

  Future<Database?> init() async {
    if (!isSupported) return null;
    try {
      if (_db != null && _db!.isOpen) return _db;
      final dbDir = await getDatabasesPath();
      final dbPath = p.join(dbDir, _dbName);
      _db = await openDatabase(
        dbPath,
        version: _dbVersion,
        onCreate: (db, version) async {
          await _ensureCoreTables(db);
          await _ensureStandaloneTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 6) {
            await _ensureColumn(db, 'products', 'can_be_sold', 'INTEGER NOT NULL DEFAULT 1');
          }
          if (oldVersion < 7) {
            await _ensureV7Tables(db);
          }
          await _ensureStandaloneTables(db);
        },
      );
      if (_db != null) {
        await _ensureStandaloneTables(_db!);
      }
      return _db;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureCoreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY,
        sku TEXT,
        barcode TEXT,
        name TEXT,
        category_id INTEGER,
        category_name TEXT,
        selling_price REAL,
        cost_price REAL,
        stock REAL,
        unit_code TEXT,
        is_low_stock INTEGER,
        can_be_sold INTEGER NOT NULL DEFAULT 1,
        is_local_only INTEGER DEFAULT 0,
        local_uuid TEXT,
        raw_json TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_barcode ON products(barcode)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sku ON products(sku)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cat ON products(category_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_prod_name ON products(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_prod_local_only ON products(is_local_only)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sales (
        id TEXT PRIMARY KEY,
        payload TEXT,
        created_at TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_synced ON offline_sales(is_synced, created_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY,
        name TEXT,
        phone TEXT,
        code TEXT,
        raw_json TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cust_phone ON customers(phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cust_name ON customers(name)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY,
        name TEXT,
        phone TEXT,
        raw_json TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sup_name ON suppliers(name)');
  }

  Future<void> _ensureV7Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kv_collections (
        collection_key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await errorLogDao.ensureSchema(db);
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final exists = info.any((r) => (r['name'] ?? '').toString() == column);
      if (!exists) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
      }
    } catch (_) {}
  }

  Future<void> _ensureStandaloneTables(Database db) async {
    await _ensureColumn(db, 'products', 'can_be_sold', 'INTEGER NOT NULL DEFAULT 1');
    await _ensureColumn(db, 'products', 'is_local_only', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'products', 'local_uuid', 'TEXT');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_prod_name ON products(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_prod_local_only ON products(is_local_only)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_synced ON offline_sales(is_synced, created_at)');

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS products_fts USING fts5(
          product_id UNINDEXED,
          name,
          sku,
          barcode,
          category_name,
          brand_name,
          tokenize='unicode61'
        )
      ''');
      _ftsAvailable = true;
    } catch (_) {
      _ftsAvailable = false;
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS shifts (
        id INTEGER PRIMARY KEY,
        shift_number TEXT,
        cashier_name TEXT,
        status TEXT,
        opened_at TEXT,
        closed_at TEXT,
        opening_cash REAL DEFAULT 0,
        cash_sales REAL DEFAULT 0,
        cash_in REAL DEFAULT 0,
        cash_out REAL DEFAULT 0,
        expected_cash REAL DEFAULT 0,
        closing_cash REAL DEFAULT 0,
        variance REAL DEFAULT 0,
        notes TEXT,
        entries_json TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_expenses (
        id INTEGER PRIMARY KEY,
        local_uuid TEXT,
        category_id INTEGER,
        category TEXT,
        amount REAL DEFAULT 0,
        description TEXT,
        payment_method_id INTEGER,
        payment_method TEXT,
        recorded_by TEXT,
        expense_date TEXT,
        created_at TEXT,
        sync_status TEXT DEFAULT 'pending',
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        server_id INTEGER,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    await _ensureColumn(db, 'local_expenses', 'local_uuid', 'TEXT');
    await _ensureColumn(db, 'local_expenses', 'category_id', 'INTEGER');
    await _ensureColumn(db, 'local_expenses', 'payment_method_id', 'INTEGER');
    await _ensureColumn(db, 'local_expenses', 'sync_status', "TEXT DEFAULT 'pending'");
    await _ensureColumn(db, 'local_expenses', 'error_message', 'TEXT');
    await _ensureColumn(db, 'local_expenses', 'retry_count', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'local_expenses', 'server_id', 'INTEGER');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_exp_sync ON local_expenses(is_synced, sync_status, created_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_payables (
        id INTEGER PRIMARY KEY,
        invoice_number TEXT,
        supplier_id INTEGER,
        supplier_name TEXT,
        supplier_phone TEXT,
        total_amount REAL DEFAULT 0,
        paid_amount REAL DEFAULT 0,
        balance_due REAL DEFAULT 0,
        status TEXT,
        due_date TEXT,
        created_at TEXT,
        notes TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS held_sales (
        id INTEGER PRIMARY KEY,
        local_uuid TEXT,
        number TEXT,
        held_label TEXT,
        customer_name TEXT,
        table_name TEXT,
        subtotal REAL DEFAULT 0,
        held_at TEXT,
        created_at TEXT,
        payload_json TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_held_sales_created ON held_sales(created_at DESC)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_receivable_payments (
        id TEXT PRIMARY KEY,
        sale_id INTEGER NOT NULL,
        sale_local_uuid TEXT,
        invoice_number TEXT,
        customer_name TEXT,
        payment_method_id INTEGER DEFAULT 1,
        payment_method_name TEXT,
        amount REAL NOT NULL,
        reference TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rec_pay_sync ON pending_receivable_payments(is_synced, sync_status, created_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_shift_closures (
        id TEXT PRIMARY KEY,
        shift_id INTEGER,
        closing_cash_counted REAL NOT NULL,
        closing_denominations_json TEXT,
        variance_reason TEXT,
        variance_notes TEXT,
        notes TEXT,
        closed_at TEXT NOT NULL,
        sync_status TEXT DEFAULT 'pending',
        error_code TEXT,
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shift_close_sync ON pending_shift_closures(is_synced, sync_status, closed_at)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dead_letter_queue (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'POST',
        idempotency_key TEXT NOT NULL,
        reference_label TEXT,
        payload_json TEXT NOT NULL,
        http_status INTEGER,
        error_code TEXT,
        error_message TEXT NOT NULL,
        retry_count INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        last_failed_at TEXT NOT NULL,
        status TEXT DEFAULT 'quarantined'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dlq_status ON dead_letter_queue(status, last_failed_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_sales_history (
        id INTEGER PRIMARY KEY,
        local_uuid TEXT,
        number TEXT,
        created_at TEXT,
        payload_json TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_hist_created ON local_sales_history(created_at DESC)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_stock_movements (
        id INTEGER PRIMARY KEY,
        product_id INTEGER,
        type TEXT,
        quantity_delta REAL,
        quantity_after REAL,
        created_at TEXT,
        payload_json TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_mov_prod ON local_stock_movements(product_id, created_at DESC)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_cash_ledger (
        id TEXT PRIMARY KEY,
        direction TEXT,
        channel TEXT,
        amount REAL,
        occurred_at TEXT,
        payload_json TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_ledger_dt ON local_cash_ledger(occurred_at DESC)');

    await _ensureV7Tables(db);
  }

  // Facade delegations preserving 100% existing SqliteDatabase method contracts
  Future<bool> commitOfflineCheckoutAtomic({
    Map<String, dynamic>? offlineSaleEntry,
    required Map<String, dynamic> receiptPayload,
    required Map<int, double> stockUpdates,
    required List<Map<String, dynamic>> stockMovements,
    Map<String, dynamic>? updatedCustomer,
    Map<String, dynamic>? cashLedgerEntry,
    Map<String, dynamic>? updatedOpenShift,
    int? completedHeldSaleId,
  }) =>
      salesQueueDao.commitOfflineCheckoutAtomic(
        offlineSaleEntry: offlineSaleEntry,
        receiptPayload: receiptPayload,
        stockUpdates: stockUpdates,
        stockMovements: stockMovements,
        updatedCustomer: updatedCustomer,
        cashLedgerEntry: cashLedgerEntry,
        updatedOpenShift: updatedOpenShift,
        completedHeldSaleId: completedHeldSaleId,
      );

  Future<bool> commitReceivablePaymentAtomic({
    Map<String, dynamic>? pendingPayment,
    Map<String, dynamic>? updatedSaleHistory,
    Map<String, dynamic>? updatedCustomer,
    Map<String, dynamic>? updatedShift,
    Map<String, dynamic>? cashLedgerEntry,
  }) =>
      salesQueueDao.commitReceivablePaymentAtomic(
        pendingPayment: pendingPayment,
        updatedSaleHistory: updatedSaleHistory,
        updatedCustomer: updatedCustomer,
        updatedShift: updatedShift,
        cashLedgerEntry: cashLedgerEntry,
      );

  Future<bool> commitExpenseAtomic({
    required Map<String, dynamic> expense,
    Map<String, dynamic>? updatedShift,
  }) =>
      salesQueueDao.commitExpenseAtomic(expense: expense, updatedShift: updatedShift);

  Future<bool> commitShiftClosureAtomic({
    Map<String, dynamic>? closedShift,
    Map<String, dynamic>? pendingClosure,
  }) =>
      shiftsDao.commitShiftClosureAtomic(
        closedShift: closedShift,
        pendingClosure: pendingClosure,
      );

  Future<void> replaceAllProducts(List<Map<String, dynamic>> products) =>
      productsDao.replaceAllProducts(products);
  Future<void> upsertProduct(Map<String, dynamic> product) => productsDao.upsertProduct(product);
  Future<void> deleteProduct(int productId) => productsDao.deleteProduct(productId);
  Future<void> updateProductStock(int productId, double newStock, {bool? isLowStock}) =>
      productsDao.updateProductStock(productId, newStock, isLowStock: isLowStock);
  Future<void> batchUpdateProductStocks(Map<int, double> updates) =>
      productsDao.batchUpdateProductStocks(updates);
  Future<List<Map<String, dynamic>>> getAllProducts() => productsDao.getAllProducts();
  Future<List<Map<String, dynamic>>> searchProduct(String query) => productsDao.searchProduct(query);

  Future<void> replaceAllCustomers(List<Map<String, dynamic>> customers) =>
      productsDao.replaceAllCustomers(customers);
  Future<void> upsertCustomer(Map<String, dynamic> customer) =>
      productsDao.upsertCustomer(customer);
  Future<List<Map<String, dynamic>>> getAllCustomers() => productsDao.getAllCustomers();

  Future<void> replaceAllSuppliers(List<Map<String, dynamic>> suppliers) =>
      productsDao.replaceAllSuppliers(suppliers);
  Future<void> upsertSupplier(Map<String, dynamic> supplier) =>
      productsDao.upsertSupplier(supplier);
  Future<List<Map<String, dynamic>>> getAllSuppliers() => productsDao.getAllSuppliers();

  Future<void> upsertHeldSale(Map<String, dynamic> held) => salesQueueDao.upsertHeldSale(held);
  Future<void> replaceAllHeldSales(List<Map<String, dynamic>> heldSales) =>
      salesQueueDao.replaceAllHeldSales(heldSales);
  Future<List<Map<String, dynamic>>> getAllHeldSales() => salesQueueDao.getAllHeldSales();
  Future<void> deleteHeldSale(int id) => salesQueueDao.deleteHeldSale(id);

  Future<void> insertOfflineSale(String id, Map<String, dynamic> payload, String createdAt) =>
      salesQueueDao.insertOfflineSale(id, payload, createdAt);
  Future<List<Map<String, dynamic>>> getUnsyncedOfflineSales() =>
      salesQueueDao.getUnsyncedOfflineSales();
  Future<void> markOfflineSaleSynced(String id) => salesQueueDao.markOfflineSaleSynced(id);
  Future<void> updateOfflineSalePayload(
    String id,
    Map<String, dynamic> updatedPayload, {
    int isSynced = 0,
  }) =>
      salesQueueDao.updateOfflineSalePayload(id, updatedPayload, isSynced: isSynced);
  Future<void> deleteOfflineSale(String id) => salesQueueDao.deleteOfflineSale(id);

  Future<void> upsertPendingReceivablePayment(Map<String, dynamic> payment) =>
      salesQueueDao.upsertPendingReceivablePayment(payment);
  Future<List<Map<String, dynamic>>> getUnsyncedReceivablePayments() =>
      salesQueueDao.getUnsyncedReceivablePayments();
  Future<void> markReceivablePaymentSynced(String id) =>
      salesQueueDao.markReceivablePaymentSynced(id);
  Future<void> updateReceivablePaymentStatus(
    String id, {
    required String syncStatus,
    String? errorMessage,
    int? retryCount,
  }) =>
      salesQueueDao.updateReceivablePaymentStatus(
        id,
        syncStatus: syncStatus,
        errorMessage: errorMessage,
        retryCount: retryCount,
      );
  Future<void> remapPendingReceivableSaleId({
    String? saleLocalUuid,
    int? oldSaleId,
    required int newCloudSaleId,
  }) =>
      salesQueueDao.remapPendingReceivableSaleId(
        saleLocalUuid: saleLocalUuid,
        oldSaleId: oldSaleId,
        newCloudSaleId: newCloudSaleId,
      );
  Future<void> deletePendingReceivablePayment(String id) =>
      salesQueueDao.deletePendingReceivablePayment(id);

  Future<void> upsertLocalExpense(Map<String, dynamic> expense) =>
      salesQueueDao.upsertLocalExpense(expense);
  Future<List<Map<String, dynamic>>> getAllLocalExpenses() => salesQueueDao.getAllLocalExpenses();
  Future<List<Map<String, dynamic>>> getUnsyncedLocalExpenses() =>
      salesQueueDao.getUnsyncedLocalExpenses();
  Future<void> markLocalExpenseSynced(int id, {int? serverId}) =>
      salesQueueDao.markLocalExpenseSynced(id, serverId: serverId);
  Future<void> updateLocalExpenseSyncStatus(
    int id, {
    required String syncStatus,
    String? errorMessage,
    int? retryCount,
  }) =>
      salesQueueDao.updateLocalExpenseSyncStatus(
        id,
        syncStatus: syncStatus,
        errorMessage: errorMessage,
        retryCount: retryCount,
      );
  Future<void> deleteLocalExpense(int id) => salesQueueDao.deleteLocalExpense(id);

  Future<void> upsertPendingShiftClosure(Map<String, dynamic> closure) =>
      shiftsDao.upsertPendingShiftClosure(closure);
  Future<List<Map<String, dynamic>>> getUnsyncedShiftClosures() =>
      shiftsDao.getUnsyncedShiftClosures();
  Future<void> markShiftClosureSynced(String id) => shiftsDao.markShiftClosureSynced(id);
  Future<void> updateShiftClosureStatus(
    String id, {
    required String syncStatus,
    String? errorCode,
    String? errorMessage,
    int? retryCount,
  }) =>
      shiftsDao.updateShiftClosureStatus(
        id,
        syncStatus: syncStatus,
        errorCode: errorCode,
        errorMessage: errorMessage,
        retryCount: retryCount,
      );
  Future<void> deletePendingShiftClosure(String id) => shiftsDao.deletePendingShiftClosure(id);

  Future<void> upsertDeadLetterItem(Map<String, dynamic> item) =>
      salesQueueDao.upsertDeadLetterItem(item);
  Future<List<Map<String, dynamic>>> getQuarantinedDeadLetters() =>
      salesQueueDao.getQuarantinedDeadLetters();
  Future<void> deleteDeadLetterItem(String id) => salesQueueDao.deleteDeadLetterItem(id);

  Future<void> upsertShift(Map<String, dynamic> shift) => shiftsDao.upsertShift(shift);
  Future<List<Map<String, dynamic>>> getAllShifts() => shiftsDao.getAllShifts();
  Future<void> replaceAllShifts(List<Map<String, dynamic>> shifts) =>
      shiftsDao.replaceAllShifts(shifts);
  Future<void> upsertLocalPayable(Map<String, dynamic> payable) =>
      salesQueueDao.upsertLocalPayable(payable);

  Future<void> clearAll() async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        for (final table in const [
          'products',
          'customers',
          'suppliers',
          'offline_sales',
          'held_sales',
          'pending_receivable_payments',
          'pending_shift_closures',
          'dead_letter_queue',
          'local_sales_history',
          'local_stock_movements',
          'local_cash_ledger',
          'shifts',
          'local_expenses',
          'local_payables',
          'kv_collections',
          'local_error_logs',
        ]) {
          await txn.delete(table);
        }
        if (_ftsAvailable) {
          try {
            await txn.execute('DELETE FROM products_fts');
          } catch (_) {}
        }
      });
    } catch (_) {}
  }
}
