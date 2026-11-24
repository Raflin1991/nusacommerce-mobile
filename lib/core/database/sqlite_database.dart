import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Enterprise Indexed Local Database Engine (`nusacommerce_local.db`) powered by SQLite (`sqflite`).
/// Provides < 5ms indexed lookup across thousands of products, customers, suppliers,
/// ACID-safe atomic offline checkout transactions, persistent held sales,
/// UUIDv4 idempotent sync queues (sales, receivables, expenses, shifts),
/// and a quarantined Dead-Letter Queue (DLQ).
class SqliteDatabase {
  SqliteDatabase._();

  static final SqliteDatabase instance = SqliteDatabase._();

  static const String _dbName = 'nusacommerce_local.db';
  static const int _dbVersion = 6;

  Database? _db;
  bool _ftsAvailable = false;

  bool get isSupported => !kIsWeb;

  Future<Database?> get database async {
    if (!isSupported) return null;
    if (_db != null && _db!.isOpen) return _db;
    return await init();
  }

  /// Initialize SQLite database with indexed schema (v5 Enterprise Hardening).
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
          await db.execute('''
            CREATE TABLE products (
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
            CREATE TABLE offline_sales (
              id TEXT PRIMARY KEY,
              payload TEXT,
              created_at TEXT,
              is_synced INTEGER DEFAULT 0
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_offline_synced ON offline_sales(is_synced, created_at)');

          await db.execute('''
            CREATE TABLE customers (
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
            CREATE TABLE suppliers (
              id INTEGER PRIMARY KEY,
              name TEXT,
              phone TEXT,
              raw_json TEXT
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_sup_name ON suppliers(name)');
          await _ensureStandaloneTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 6) {
            await _ensureColumn(db, 'products', 'can_be_sold', 'INTEGER NOT NULL DEFAULT 1');
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

    // v5 Table 1: Persistent Held Bills (Bug 2)
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

    // v5 Table 2: Offline Receivable Payments Sync Queue (Bug 3)
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

    // v5 Table 3: Offline Shift Closures Sync Queue (Bug 6)
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

    // v5 Table 4: Unified Dead-Letter Queue / Conflict Quarantine (Hardening #4)
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

    // v5 Tables 5-7: ACID Checkout Durability Tables (Hardening #1)
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
  }

  Map<String, dynamic> _productToRow(Map<String, dynamic> product) {
    final categoryMap = product['category'] is Map
        ? Map<String, dynamic>.from(product['category'] as Map)
        : null;
    final unitMap =
        product['unit'] is Map ? Map<String, dynamic>.from(product['unit'] as Map) : null;
    final catId = categoryMap != null
        ? ((categoryMap['id'] as num?)?.toInt() ?? 0)
        : ((product['category_id'] as num?)?.toInt() ?? 0);
    final catName = categoryMap != null
        ? (categoryMap['name'] ?? 'Umum').toString()
        : (product['category_name'] ?? 'Umum').toString();
    final unitCode = unitMap != null
        ? (unitMap['code'] ?? 'pcs').toString()
        : (product['unit_code'] ?? 'pcs').toString();
    final stockVal = (product['stock'] as num?)?.toDouble() ?? 0.0;
    final minStock = (product['reorder_level'] as num?)?.toDouble() ?? 5.0;
    final isLow = product['is_low_stock'] == true || stockVal <= minStock;
    final prodId = (product['id'] as num?)?.toInt() ?? 0;
    final isLocalOnly = product['is_local_only'] == true ||
        product['is_local_only'] == 1 ||
        prodId < 0;

    return {
      'id': prodId,
      'sku': (product['sku'] ?? '').toString(),
      'barcode': (product['barcode'] ?? '').toString(),
      'name': (product['name'] ?? '').toString(),
      'category_id': catId,
      'category_name': catName,
      'selling_price': (product['selling_price'] as num?)?.toDouble() ?? 0.0,
      'cost_price': (product['cost_price'] as num?)?.toDouble() ?? 0.0,
      'stock': stockVal,
      'unit_code': unitCode,
      'can_be_sold': product['can_be_sold'] == false ? 0 : 1,
      'is_low_stock': isLow ? 1 : 0,
      'is_local_only': isLocalOnly ? 1 : 0,
      'local_uuid': product['local_uuid']?.toString(),
      'raw_json': jsonEncode(product),
    };
  }

  Map<String, dynamic> _decodeProductRow(Map<String, Object?> row) {
    final raw = row['raw_json']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        decoded['stock'] = (row['stock'] as num?)?.toDouble() ?? decoded['stock'];
        decoded['is_low_stock'] = (row['is_low_stock'] as num?)?.toInt() == 1;
        if ((row['is_local_only'] as num?)?.toInt() == 1) {
          decoded['is_local_only'] = true;
        }
        if (row['local_uuid'] != null && row['local_uuid'].toString().isNotEmpty) {
          decoded['local_uuid'] = row['local_uuid'].toString();
        }
        return decoded;
      } catch (_) {}
    }
    return {
      'id': row['id'],
      'sku': row['sku'],
      'barcode': row['barcode'],
      'name': row['name'],
      'category_id': row['category_id'],
      'category_name': row['category_name'],
      'selling_price': row['selling_price'],
      'cost_price': row['cost_price'],
      'stock': row['stock'],
      'unit_code': row['unit_code'],
      'is_low_stock': (row['is_low_stock'] as num?)?.toInt() == 1,
      'is_local_only': (row['is_local_only'] as num?)?.toInt() == 1,
      if (row['local_uuid'] != null) 'local_uuid': row['local_uuid'].toString(),
    };
  }

  String _extractBrandName(Map<String, dynamic> product) {
    final brandMap = product['brand'] is Map
        ? Map<String, dynamic>.from(product['brand'] as Map)
        : null;
    if (brandMap != null) {
      return (brandMap['name'] ?? '').toString();
    }
    return (product['brand_name'] ?? '').toString();
  }

  Map<String, dynamic> _shiftToRow(Map<String, dynamic> shift) {
    return {
      'id': (shift['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      'shift_number': (shift['shift_number'] ?? '').toString(),
      'cashier_name': (shift['cashier_name'] ?? 'Kasir').toString(),
      'status': (shift['status'] ?? 'open').toString(),
      'opened_at': (shift['opened_at'] ?? '').toString(),
      'closed_at': shift['closed_at']?.toString(),
      'opening_cash': (shift['opening_cash'] as num?)?.toDouble() ?? 0.0,
      'cash_sales': (shift['cash_sales'] as num?)?.toDouble() ?? 0.0,
      'cash_in': (shift['cash_in'] as num?)?.toDouble() ?? 0.0,
      'cash_out': (shift['cash_out'] as num?)?.toDouble() ?? 0.0,
      'expected_cash': (shift['expected_cash'] as num?)?.toDouble() ?? 0.0,
      'closing_cash': (shift['closing_cash'] as num?)?.toDouble() ?? 0.0,
      'variance': (shift['variance'] as num?)?.toDouble() ?? 0.0,
      'notes': shift['notes']?.toString(),
      'entries_json': jsonEncode(shift['entries'] ?? []),
      'is_synced': (shift['is_synced'] == true || shift['is_synced'] == 1) ? 1 : 0,
    };
  }

  Map<String, dynamic> _expenseToRow(Map<String, dynamic> expense) {
    final catRaw = expense['category'];
    final catName = (expense['category_name'] ??
            (catRaw is Map ? catRaw['name'] : catRaw) ??
            'Lain-lain')
        .toString();
    final catId = (expense['category_id'] as num?)?.toInt() ??
        (catRaw is Map ? (catRaw['id'] as num?)?.toInt() : null);
    final isSynced = (expense['is_synced'] == true || expense['is_synced'] == 1) ? 1 : 0;
    return {
      'id': (expense['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      'local_uuid': expense['local_uuid']?.toString(),
      'category_id': catId,
      'category': catName,
      'amount': (expense['amount'] as num?)?.toDouble() ?? 0.0,
      'description': (expense['description'] ?? '').toString(),
      'payment_method_id': (expense['payment_method_id'] as num?)?.toInt(),
      'payment_method': (expense['payment_method'] ?? 'Tunai').toString(),
      'recorded_by': (expense['recorded_by'] ?? 'Kasir').toString(),
      'expense_date': (expense['expense_date'] ?? '').toString(),
      'created_at': (expense['created_at'] ?? '').toString(),
      'sync_status': (expense['sync_status'] ?? (isSynced == 1 ? 'synced' : 'pending')).toString(),
      'error_message': expense['error_message']?.toString(),
      'retry_count': (expense['retry_count'] as num?)?.toInt() ?? 0,
      'server_id': (expense['server_id'] as num?)?.toInt(),
      'is_synced': isSynced,
    };
  }

  Map<String, dynamic> _decodeExpenseRow(Map<String, Object?> row) {
    final catName = (row['category'] ?? 'Operasional Toko').toString();
    final catId = (row['category_id'] as num?)?.toInt();
    final isSynced = (row['is_synced'] as num?)?.toInt() == 1;
    return {
      'id': (row['id'] as num?)?.toInt() ?? 0,
      if (row['local_uuid'] != null) 'local_uuid': row['local_uuid'].toString(),
      if (catId != null) 'category_id': catId,
      'category_name': catName,
      'category': {'id': catId ?? 1, 'name': catName},
      'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
      'description': (row['description'] ?? '').toString(),
      if (row['payment_method_id'] != null)
        'payment_method_id': (row['payment_method_id'] as num?)?.toInt(),
      'payment_method': (row['payment_method'] ?? 'Tunai').toString(),
      'recorded_by': (row['recorded_by'] ?? 'Kasir').toString(),
      'expense_date': (row['expense_date'] ?? '').toString(),
      'created_at': (row['created_at'] ?? '').toString(),
      'sync_status': (row['sync_status'] ?? (isSynced ? 'synced' : 'pending')).toString(),
      if (row['error_message'] != null) 'error_message': row['error_message'].toString(),
      'retry_count': (row['retry_count'] as num?)?.toInt() ?? 0,
      if (row['server_id'] != null) 'server_id': (row['server_id'] as num?)?.toInt(),
      'is_synced': isSynced ? 1 : 0,
      'is_local': true,
    };
  }

  // ===========================================================================
  // ACID ATOMIC TRANSACTION COMMITTERS (HARDENING #1)
  // ===========================================================================

  /// Atomically commits an offline/online checkout in ONE SQLite `db.transaction(...)`:
  /// 1) Insert pending offline sale (when offline)
  /// 2) Insert receipt into `local_sales_history`
  /// 3) Decrement/update every affected product's stock inside `products`
  /// 4) Record every `local_stock_movements` row
  /// 5) Update customer debt/store credit balance (if applicable)
  /// 6) Record cash-in into `local_cash_ledger` and update open shift (if applicable)
  /// 7) Remove completed held sale from `held_sales` (if recalled from hold)
  ///
  /// If ANY step fails (or app crashes mid-write), SQLite rolls back the entire transaction
  /// so stock is NEVER decremented without the sale receipt being saved.
  Future<bool> commitOfflineCheckoutAtomic({
    Map<String, dynamic>? offlineSaleEntry,
    required Map<String, dynamic> receiptPayload,
    required Map<int, double> stockUpdates,
    required List<Map<String, dynamic>> stockMovements,
    Map<String, dynamic>? updatedCustomer,
    Map<String, dynamic>? cashLedgerEntry,
    Map<String, dynamic>? updatedOpenShift,
    int? completedHeldSaleId,
  }) async {
    final db = await database;
    if (db == null) return true; // Web / headless fallback handled by OfflineDatabase prefs
    await db.transaction((txn) async {
      // 1. Offline sale queue entry (idempotent UUIDv4 primary key)
      if (offlineSaleEntry != null) {
        final saleUuid = (offlineSaleEntry['local_uuid'] ?? '').toString();
        final createdAt = (offlineSaleEntry['queued_at'] ??
                offlineSaleEntry['client_completed_at'] ??
                DateTime.now().toIso8601String())
            .toString();
        await txn.insert(
          'offline_sales',
          {
            'id': saleUuid,
            'payload': jsonEncode(offlineSaleEntry),
            'created_at': createdAt,
            'is_synced': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 2. Local sales history durability row
      final receiptId = (receiptPayload['id'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      await txn.insert(
        'local_sales_history',
        {
          'id': receiptId,
          'local_uuid': receiptPayload['local_uuid']?.toString(),
          'number': (receiptPayload['number'] ?? '').toString(),
          'created_at': (receiptPayload['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'payload_json': jsonEncode(receiptPayload),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Atomic product stock updates
      for (final entry in stockUpdates.entries) {
        final rows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final current = _decodeProductRow(rows.first);
        final reorder = (current['reorder_level'] as num?)?.toDouble() ?? 5.0;
        final low = entry.value <= reorder;
        current['stock'] = entry.value;
        current['is_low_stock'] = low;

        await txn.update(
          'products',
          {
            'stock': entry.value,
            'is_low_stock': low ? 1 : 0,
            'raw_json': jsonEncode(current),
          },
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }

      // 4. Stock movement audit trail
      for (final mov in stockMovements) {
        await txn.insert(
          'local_stock_movements',
          {
            'id': (mov['id'] as num?)?.toInt() ?? DateTime.now().microsecondsSinceEpoch,
            'product_id': (mov['product_id'] as num?)?.toInt() ?? 0,
            'type': (mov['type'] ?? 'sale').toString(),
            'quantity_delta': (mov['quantity_delta'] as num?)?.toDouble() ?? 0.0,
            'quantity_after': (mov['quantity_after'] as num?)?.toDouble() ?? 0.0,
            'created_at': (mov['created_at'] ?? DateTime.now().toIso8601String()).toString(),
            'payload_json': jsonEncode(mov),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 5. Customer store-credit / kasbon balance
      if (updatedCustomer != null) {
        await txn.insert(
          'customers',
          {
            'id': (updatedCustomer['id'] as num?)?.toInt() ?? 0,
            'name': (updatedCustomer['name'] ?? '').toString(),
            'phone': (updatedCustomer['phone'] ?? '').toString(),
            'code': (updatedCustomer['code'] ?? '').toString(),
            'raw_json': jsonEncode(updatedCustomer),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 6. Cash-in ledger & open shift cash summary
      if (cashLedgerEntry != null) {
        await txn.insert(
          'local_cash_ledger',
          {
            'id': (cashLedgerEntry['id'] ?? 'cash-${DateTime.now().microsecondsSinceEpoch}').toString(),
            'direction': (cashLedgerEntry['direction'] ?? 'in').toString(),
            'channel': (cashLedgerEntry['channel'] ?? 'cash').toString(),
            'amount': (cashLedgerEntry['amount'] as num?)?.toDouble() ?? 0.0,
            'occurred_at': (cashLedgerEntry['occurred_at'] ?? DateTime.now().toIso8601String()).toString(),
            'payload_json': jsonEncode(cashLedgerEntry),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (updatedOpenShift != null) {
        await txn.insert(
          'shifts',
          _shiftToRow(updatedOpenShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 7. Clean up completed held sale if recalled from hold
      if (completedHeldSaleId != null && completedHeldSaleId != 0) {
        await txn.delete(
          'held_sales',
          where: 'id = ?',
          whereArgs: [completedHeldSaleId],
        );
      }
    });
    return true;
  }

  /// Atomically commits an offline receivable payment (Kasbon settlement) in ONE SQLite transaction.
  Future<bool> commitReceivablePaymentAtomic({
    Map<String, dynamic>? pendingPayment,
    Map<String, dynamic>? updatedSaleHistory,
    Map<String, dynamic>? updatedCustomer,
    Map<String, dynamic>? updatedShift,
    Map<String, dynamic>? cashLedgerEntry,
  }) async {
    final db = await database;
    if (db == null) return true;
    await db.transaction((txn) async {
      if (pendingPayment != null) {
        await txn.insert(
          'pending_receivable_payments',
          _receivablePaymentToRow(pendingPayment),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (updatedSaleHistory != null) {
        await txn.insert(
          'local_sales_history',
          {
            'id': (updatedSaleHistory['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
            'local_uuid': updatedSaleHistory['local_uuid']?.toString(),
            'number': (updatedSaleHistory['number'] ?? '').toString(),
            'created_at': (updatedSaleHistory['created_at'] ?? DateTime.now().toIso8601String()).toString(),
            'payload_json': jsonEncode(updatedSaleHistory),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (updatedCustomer != null) {
        await txn.insert(
          'customers',
          {
            'id': (updatedCustomer['id'] as num?)?.toInt() ?? 0,
            'name': (updatedCustomer['name'] ?? '').toString(),
            'phone': (updatedCustomer['phone'] ?? '').toString(),
            'code': (updatedCustomer['code'] ?? '').toString(),
            'raw_json': jsonEncode(updatedCustomer),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (updatedShift != null) {
        await txn.insert(
          'shifts',
          _shiftToRow(updatedShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (cashLedgerEntry != null) {
        await txn.insert(
          'local_cash_ledger',
          {
            'id': (cashLedgerEntry['id'] ?? 'rec-${DateTime.now().microsecondsSinceEpoch}').toString(),
            'direction': (cashLedgerEntry['direction'] ?? 'in').toString(),
            'channel': (cashLedgerEntry['channel'] ?? 'cash').toString(),
            'amount': (cashLedgerEntry['amount'] as num?)?.toDouble() ?? 0.0,
            'occurred_at': (cashLedgerEntry['occurred_at'] ?? DateTime.now().toIso8601String()).toString(),
            'payload_json': jsonEncode(cashLedgerEntry),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  /// Atomically commits a local petty-cash expense + shift cash-out in ONE SQLite transaction.
  Future<bool> commitExpenseAtomic({
    required Map<String, dynamic> expense,
    Map<String, dynamic>? updatedShift,
  }) async {
    final db = await database;
    if (db == null) return true;
    await db.transaction((txn) async {
      await txn.insert(
        'local_expenses',
        _expenseToRow(expense),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (updatedShift != null) {
        await txn.insert(
          'shifts',
          _shiftToRow(updatedShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  /// Atomically commits a local shift closure + pending Cloud closure queue row in ONE SQLite transaction.
  Future<bool> commitShiftClosureAtomic({
    Map<String, dynamic>? closedShift,
    Map<String, dynamic>? pendingClosure,
  }) async {
    final db = await database;
    if (db == null) return true;
    await db.transaction((txn) async {
      if (closedShift != null) {
        await txn.insert(
          'shifts',
          _shiftToRow(closedShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (pendingClosure != null) {
        await txn.insert(
          'pending_shift_closures',
          _shiftClosureToRow(pendingClosure),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  // ===========================================================================
  // PRODUCTS CRUD & FAST INDEXED / FTS5 SEARCH (< 5ms)
  // ===========================================================================
  Future<void> replaceAllProducts(List<Map<String, dynamic>> products) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('products');
        if (_ftsAvailable) {
          try {
            await txn.execute('DELETE FROM products_fts');
          } catch (_) {}
        }
        final batch = txn.batch();
        for (final prod in products) {
          final row = _productToRow(prod);
          batch.insert(
            'products',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (_ftsAvailable) {
            batch.insert('products_fts', {
              'product_id': row['id'],
              'name': row['name'],
              'sku': row['sku'],
              'barcode': row['barcode'],
              'category_name': row['category_name'],
              'brand_name': _extractBrandName(prod),
            });
          }
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<void> upsertProduct(Map<String, dynamic> product) async {
    final db = await database;
    if (db == null) return;
    try {
      final row = _productToRow(product);
      await db.insert(
        'products',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (_ftsAvailable) {
        try {
          await db.delete(
            'products_fts',
            where: 'product_id = ?',
            whereArgs: [row['id']],
          );
          await db.insert('products_fts', {
            'product_id': row['id'],
            'name': row['name'],
            'sku': row['sku'],
            'barcode': row['barcode'],
            'category_name': row['category_name'],
            'brand_name': _extractBrandName(product),
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> updateProductStock(
    int productId,
    double newStock, {
    bool? isLowStock,
  }) async {
    final db = await database;
    if (db == null) return;
    try {
      final rows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final current = _decodeProductRow(rows.first);
      final reorder = (current['reorder_level'] as num?)?.toDouble() ?? 5.0;
      final low = isLowStock ?? (newStock <= reorder);
      current['stock'] = newStock;
      current['is_low_stock'] = low;

      await db.update(
        'products',
        {
          'stock': newStock,
          'is_low_stock': low ? 1 : 0,
          'raw_json': jsonEncode(current),
        },
        where: 'id = ?',
        whereArgs: [productId],
      );
    } catch (_) {}
  }

  Future<void> batchUpdateProductStocks(Map<int, double> updates) async {
    if (updates.isEmpty) return;
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        for (final entry in updates.entries) {
          final rows = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [entry.key],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          final current = _decodeProductRow(rows.first);
          final reorder = (current['reorder_level'] as num?)?.toDouble() ?? 5.0;
          final low = entry.value <= reorder;
          current['stock'] = entry.value;
          current['is_low_stock'] = low;

          await txn.update(
            'products',
            {
              'stock': entry.value,
              'is_low_stock': low ? 1 : 0,
              'raw_json': jsonEncode(current),
            },
            where: 'id = ?',
            whereArgs: [entry.key],
          );
        }
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllProducts() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query('products');
      return rows.map(_decodeProductRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchProduct(String query) async {
    final db = await database;
    if (db == null) return [];
    final q = query.trim();
    try {
      if (q.isEmpty) {
        final rows = await db.rawQuery('SELECT * FROM products ORDER BY name ASC LIMIT 50');
        return rows.map(_decodeProductRow).toList();
      }
      final qLower = q.toLowerCase();

      final exactRows = await db.rawQuery(
        'SELECT * FROM products WHERE LOWER(barcode) = ? OR LOWER(sku) = ? LIMIT 10',
        [qLower, qLower],
      );
      if (exactRows.isNotEmpty) {
        return exactRows.map(_decodeProductRow).toList();
      }

      if (_ftsAvailable) {
        final tokens = qLower
            .split(RegExp(r'\s+'))
            .map((t) => t.replaceAll(RegExp(r'[^a-z0-9]'), ''))
            .where((t) => t.isNotEmpty)
            .toList();
        if (tokens.isNotEmpty) {
          final ftsQuery = tokens.map((t) => '$t*').join(' AND ');
          try {
            final ftsRows = await db.rawQuery(
              'SELECT p.* FROM products p '
              'INNER JOIN products_fts f ON f.product_id = p.id '
              'WHERE products_fts MATCH ? '
              'ORDER BY bm25(products_fts), p.name ASC '
              'LIMIT 50',
              [ftsQuery],
            );
            if (ftsRows.isNotEmpty) {
              return ftsRows.map(_decodeProductRow).toList();
            }
          } catch (_) {}
        }
      }

      final rows = await db.rawQuery(
        'SELECT * FROM products '
        'WHERE LOWER(barcode) = ? OR LOWER(sku) = ? OR LOWER(name) LIKE ? OR LOWER(category_name) LIKE ? '
        'ORDER BY CASE WHEN LOWER(barcode) = ? OR LOWER(sku) = ? THEN 0 ELSE 1 END, name ASC '
        'LIMIT 50',
        [qLower, qLower, '%$qLower%', '%$qLower%', qLower, qLower],
      );
      return rows.map(_decodeProductRow).toList();
    } catch (_) {
      return [];
    }
  }

  // ===========================================================================
  // CUSTOMERS & SUPPLIERS CRUD
  // ===========================================================================
  Future<void> replaceAllCustomers(List<Map<String, dynamic>> customers) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('customers');
        final batch = txn.batch();
        for (final c in customers) {
          batch.insert(
            'customers',
            {
              'id': (c['id'] as num?)?.toInt() ?? 0,
              'name': (c['name'] ?? '').toString(),
              'phone': (c['phone'] ?? '').toString(),
              'code': (c['code'] ?? '').toString(),
              'raw_json': jsonEncode(c),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<void> upsertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'customers',
        {
          'id': (customer['id'] as num?)?.toInt() ?? 0,
          'name': (customer['name'] ?? '').toString(),
          'phone': (customer['phone'] ?? '').toString(),
          'code': (customer['code'] ?? '').toString(),
          'raw_json': jsonEncode(customer),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query('customers');
      return rows.map((r) {
        final raw = r['raw_json']?.toString();
        if (raw != null && raw.isNotEmpty) {
          return Map<String, dynamic>.from(jsonDecode(raw) as Map);
        }
        return {
          'id': r['id'],
          'name': r['name'],
          'phone': r['phone'],
          'code': r['code'],
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> replaceAllSuppliers(List<Map<String, dynamic>> suppliers) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('suppliers');
        final batch = txn.batch();
        for (final s in suppliers) {
          batch.insert(
            'suppliers',
            {
              'id': (s['id'] as num?)?.toInt() ?? 0,
              'name': (s['name'] ?? '').toString(),
              'phone': (s['phone'] ?? '').toString(),
              'raw_json': jsonEncode(s),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<void> upsertSupplier(Map<String, dynamic> supplier) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'suppliers',
        {
          'id': (supplier['id'] as num?)?.toInt() ?? 0,
          'name': (supplier['name'] ?? '').toString(),
          'phone': (supplier['phone'] ?? '').toString(),
          'raw_json': jsonEncode(supplier),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllSuppliers() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query('suppliers');
      return rows.map((r) {
        final raw = r['raw_json']?.toString();
        if (raw != null && raw.isNotEmpty) {
          return Map<String, dynamic>.from(jsonDecode(raw) as Map);
        }
        return {
          'id': r['id'],
          'name': r['name'],
          'phone': r['phone'],
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ===========================================================================
  // HELD SALES PERSISTENCE (BUG 2)
  // ===========================================================================
  Future<void> upsertHeldSale(Map<String, dynamic> held) async {
    final db = await database;
    if (db == null) return;
    try {
      final id = (held['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      await db.insert(
        'held_sales',
        {
          'id': id,
          'local_uuid': held['local_uuid']?.toString(),
          'number': (held['number'] ?? 'HLD-$id').toString(),
          'held_label': (held['held_label'] ?? 'Pesanan Ditahan').toString(),
          'customer_name': (held['customer_name'] ?? 'Pelanggan Umum').toString(),
          'table_name': held['table_name']?.toString(),
          'subtotal': (held['subtotal'] as num?)?.toDouble() ?? 0.0,
          'held_at': (held['held_at'] ?? '').toString(),
          'created_at': (held['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'payload_json': jsonEncode(held),
          'is_synced': (held['is_synced'] == true || held['is_synced'] == 1) ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> replaceAllHeldSales(List<Map<String, dynamic>> heldSales) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('held_sales');
        final batch = txn.batch();
        for (final held in heldSales) {
          final id = (held['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          batch.insert(
            'held_sales',
            {
              'id': id,
              'local_uuid': held['local_uuid']?.toString(),
              'number': (held['number'] ?? 'HLD-$id').toString(),
              'held_label': (held['held_label'] ?? 'Pesanan Ditahan').toString(),
              'customer_name': (held['customer_name'] ?? 'Pelanggan Umum').toString(),
              'table_name': held['table_name']?.toString(),
              'subtotal': (held['subtotal'] as num?)?.toDouble() ?? 0.0,
              'held_at': (held['held_at'] ?? '').toString(),
              'created_at': (held['created_at'] ?? DateTime.now().toIso8601String()).toString(),
              'payload_json': jsonEncode(held),
              'is_synced': (held['is_synced'] == true || held['is_synced'] == 1) ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllHeldSales() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query('held_sales', orderBy: 'created_at DESC');
      final list = <Map<String, dynamic>>[];
      for (final r in rows) {
        final raw = r['payload_json']?.toString();
        if (raw != null && raw.isNotEmpty) {
          try {
            list.add(Map<String, dynamic>.from(jsonDecode(raw) as Map));
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteHeldSale(int id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('held_sales', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  // ===========================================================================
  // OFFLINE SALES QUEUE (UUIDv4 IDEMPOTENT)
  // ===========================================================================
  Future<void> insertOfflineSale(
    String id,
    Map<String, dynamic> payload,
    String createdAt,
  ) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'offline_sales',
        {
          'id': id,
          'payload': jsonEncode(payload),
          'created_at': createdAt,
          'is_synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUnsyncedOfflineSales() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'offline_sales',
        where: 'is_synced = 0',
        orderBy: 'created_at ASC',
      );
      final list = <Map<String, dynamic>>[];
      for (final row in rows) {
        final raw = row['payload']?.toString();
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            decoded['local_uuid'] = decoded['local_uuid'] ?? row['id'];
            list.add(decoded);
          } catch (_) {}
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> markOfflineSaleSynced(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'offline_sales',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> updateOfflineSalePayload(
    String id,
    Map<String, dynamic> updatedPayload, {
    int isSynced = 0,
  }) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'offline_sales',
        {
          'payload': jsonEncode(updatedPayload),
          'is_synced': isSynced,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> deleteOfflineSale(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete(
        'offline_sales',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  // ===========================================================================
  // PENDING RECEIVABLE PAYMENTS QUEUE (BUG 3)
  // ===========================================================================
  Map<String, dynamic> _receivablePaymentToRow(Map<String, dynamic> p) {
    final isSynced = (p['is_synced'] == true || p['is_synced'] == 1) ? 1 : 0;
    return {
      'id': (p['id'] ?? p['local_uuid'] ?? '').toString(),
      'sale_id': (p['sale_id'] as num?)?.toInt() ?? 0,
      'sale_local_uuid': p['sale_local_uuid']?.toString(),
      'invoice_number': p['invoice_number']?.toString(),
      'customer_name': p['customer_name']?.toString(),
      'payment_method_id': (p['payment_method_id'] as num?)?.toInt() ?? 1,
      'payment_method_name': (p['payment_method_name'] ?? 'Tunai').toString(),
      'amount': (p['amount'] as num?)?.toDouble() ?? 0.0,
      'reference': p['reference']?.toString(),
      'notes': p['notes']?.toString(),
      'created_at': (p['created_at'] ?? DateTime.now().toIso8601String()).toString(),
      'sync_status': (p['sync_status'] ?? (isSynced == 1 ? 'synced' : 'pending')).toString(),
      'error_message': p['error_message']?.toString(),
      'retry_count': (p['retry_count'] as num?)?.toInt() ?? 0,
      'is_synced': isSynced,
    };
  }

  Map<String, dynamic> _decodeReceivablePaymentRow(Map<String, Object?> r) {
    return {
      'id': r['id']?.toString() ?? '',
      'local_uuid': r['id']?.toString() ?? '',
      'sale_id': (r['sale_id'] as num?)?.toInt() ?? 0,
      if (r['sale_local_uuid'] != null) 'sale_local_uuid': r['sale_local_uuid'].toString(),
      if (r['invoice_number'] != null) 'invoice_number': r['invoice_number'].toString(),
      if (r['customer_name'] != null) 'customer_name': r['customer_name'].toString(),
      'payment_method_id': (r['payment_method_id'] as num?)?.toInt() ?? 1,
      'payment_method_name': (r['payment_method_name'] ?? 'Tunai').toString(),
      'amount': (r['amount'] as num?)?.toDouble() ?? 0.0,
      if (r['reference'] != null) 'reference': r['reference'].toString(),
      if (r['notes'] != null) 'notes': r['notes'].toString(),
      'created_at': (r['created_at'] ?? '').toString(),
      'sync_status': (r['sync_status'] ?? 'pending').toString(),
      if (r['error_message'] != null) 'error_message': r['error_message'].toString(),
      'retry_count': (r['retry_count'] as num?)?.toInt() ?? 0,
      'is_synced': (r['is_synced'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> upsertPendingReceivablePayment(Map<String, dynamic> payment) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'pending_receivable_payments',
        _receivablePaymentToRow(payment),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUnsyncedReceivablePayments() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'pending_receivable_payments',
        where: 'is_synced = 0',
        orderBy: 'created_at ASC',
      );
      return rows.map(_decodeReceivablePaymentRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markReceivablePaymentSynced(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'pending_receivable_payments',
        {'is_synced': 1, 'sync_status': 'synced', 'error_message': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> updateReceivablePaymentStatus(
    String id, {
    required String syncStatus,
    String? errorMessage,
    int? retryCount,
  }) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'pending_receivable_payments',
        {
          'sync_status': syncStatus,
          'error_message': errorMessage,
          if (retryCount != null) 'retry_count': retryCount,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> remapPendingReceivableSaleId({
    String? saleLocalUuid,
    int? oldSaleId,
    required int newCloudSaleId,
  }) async {
    final db = await database;
    if (db == null) return;
    try {
      if (saleLocalUuid != null && saleLocalUuid.isNotEmpty) {
        await db.update(
          'pending_receivable_payments',
          {'sale_id': newCloudSaleId},
          where: 'sale_local_uuid = ? AND is_synced = 0',
          whereArgs: [saleLocalUuid],
        );
      }
      if (oldSaleId != null && oldSaleId != 0) {
        await db.update(
          'pending_receivable_payments',
          {'sale_id': newCloudSaleId},
          where: 'sale_id = ? AND is_synced = 0',
          whereArgs: [oldSaleId],
        );
      }
    } catch (_) {}
  }

  Future<void> deletePendingReceivablePayment(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('pending_receivable_payments', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  // ===========================================================================
  // LOCAL EXPENSES QUEUE & SYNC (BUG 5)
  // ===========================================================================
  Future<void> upsertLocalExpense(Map<String, dynamic> expense) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'local_expenses',
        _expenseToRow(expense),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllLocalExpenses() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query('local_expenses', orderBy: 'created_at DESC');
      return rows.map(_decodeExpenseRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLocalExpenses() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'local_expenses',
        where: 'is_synced = 0',
        orderBy: 'created_at ASC',
      );
      return rows.map(_decodeExpenseRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markLocalExpenseSynced(int id, {int? serverId}) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'local_expenses',
        {
          'is_synced': 1,
          'sync_status': 'synced',
          'error_message': null,
          if (serverId != null) 'server_id': serverId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> updateLocalExpenseSyncStatus(
    int id, {
    required String syncStatus,
    String? errorMessage,
    int? retryCount,
  }) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'local_expenses',
        {
          'sync_status': syncStatus,
          'error_message': errorMessage,
          if (retryCount != null) 'retry_count': retryCount,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> deleteLocalExpense(int id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('local_expenses', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  // ===========================================================================
  // PENDING SHIFT CLOSURES QUEUE (BUG 6)
  // ===========================================================================
  Map<String, dynamic> _shiftClosureToRow(Map<String, dynamic> c) {
    final isSynced = (c['is_synced'] == true || c['is_synced'] == 1) ? 1 : 0;
    return {
      'id': (c['id'] ?? c['local_uuid'] ?? '').toString(),
      'shift_id': (c['shift_id'] as num?)?.toInt(),
      'closing_cash_counted': (c['closing_cash_counted'] as num?)?.toDouble() ?? 0.0,
      'closing_denominations_json': c['closing_denominations'] != null
          ? jsonEncode(c['closing_denominations'])
          : null,
      'variance_reason': c['variance_reason']?.toString(),
      'variance_notes': c['variance_notes']?.toString(),
      'notes': c['notes']?.toString(),
      'closed_at': (c['closed_at'] ?? DateTime.now().toIso8601String()).toString(),
      'sync_status': (c['sync_status'] ?? (isSynced == 1 ? 'synced' : 'pending')).toString(),
      'error_code': c['error_code']?.toString(),
      'error_message': c['error_message']?.toString(),
      'retry_count': (c['retry_count'] as num?)?.toInt() ?? 0,
      'is_synced': isSynced,
    };
  }

  Map<String, dynamic> _decodeShiftClosureRow(Map<String, Object?> r) {
    Map<String, dynamic>? denoms;
    final rawDenom = r['closing_denominations_json']?.toString();
    if (rawDenom != null && rawDenom.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDenom);
        if (decoded is Map) denoms = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {
      'id': r['id']?.toString() ?? '',
      'local_uuid': r['id']?.toString() ?? '',
      if (r['shift_id'] != null) 'shift_id': (r['shift_id'] as num?)?.toInt(),
      'closing_cash_counted': (r['closing_cash_counted'] as num?)?.toDouble() ?? 0.0,
      if (denoms != null) 'closing_denominations': denoms,
      if (r['variance_reason'] != null) 'variance_reason': r['variance_reason'].toString(),
      if (r['variance_notes'] != null) 'variance_notes': r['variance_notes'].toString(),
      if (r['notes'] != null) 'notes': r['notes'].toString(),
      'closed_at': (r['closed_at'] ?? '').toString(),
      'sync_status': (r['sync_status'] ?? 'pending').toString(),
      if (r['error_code'] != null) 'error_code': r['error_code'].toString(),
      if (r['error_message'] != null) 'error_message': r['error_message'].toString(),
      'retry_count': (r['retry_count'] as num?)?.toInt() ?? 0,
      'is_synced': (r['is_synced'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> upsertPendingShiftClosure(Map<String, dynamic> closure) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'pending_shift_closures',
        _shiftClosureToRow(closure),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUnsyncedShiftClosures() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'pending_shift_closures',
        where: 'is_synced = 0',
        orderBy: 'closed_at ASC',
      );
      return rows.map(_decodeShiftClosureRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markShiftClosureSynced(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'pending_shift_closures',
        {'is_synced': 1, 'sync_status': 'synced', 'error_code': null, 'error_message': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> updateShiftClosureStatus(
    String id, {
    required String syncStatus,
    String? errorCode,
    String? errorMessage,
    int? retryCount,
  }) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.update(
        'pending_shift_closures',
        {
          'sync_status': syncStatus,
          'error_code': errorCode,
          'error_message': errorMessage,
          if (retryCount != null) 'retry_count': retryCount,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> deletePendingShiftClosure(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('pending_shift_closures', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  // ===========================================================================
  // UNIFIED DEAD-LETTER QUEUE / CONFLICT QUARANTINE (HARDENING #4)
  // ===========================================================================
  Future<void> upsertDeadLetterItem(Map<String, dynamic> item) async {
    final db = await database;
    if (db == null) return;
    try {
      final nowIso = DateTime.now().toIso8601String();
      await db.insert(
        'dead_letter_queue',
        {
          'id': (item['id'] ?? '').toString(),
          'entity_type': (item['entity_type'] ?? 'unknown').toString(),
          'endpoint': (item['endpoint'] ?? '').toString(),
          'method': (item['method'] ?? 'POST').toString(),
          'idempotency_key': (item['idempotency_key'] ?? item['id'] ?? '').toString(),
          'reference_label': item['reference_label']?.toString(),
          'payload_json': jsonEncode(item['payload'] ?? const <String, dynamic>{}),
          'http_status': (item['http_status'] as num?)?.toInt(),
          'error_code': item['error_code']?.toString(),
          'error_message': (item['error_message'] ?? 'Ditolak server').toString(),
          'retry_count': (item['retry_count'] as num?)?.toInt() ?? 1,
          'created_at': (item['created_at'] ?? nowIso).toString(),
          'last_failed_at': (item['last_failed_at'] ?? nowIso).toString(),
          'status': (item['status'] ?? 'quarantined').toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getQuarantinedDeadLetters() async {
    final db = await database;
    if (db == null) return [];
    try {
      final rows = await db.query(
        'dead_letter_queue',
        where: "status = 'quarantined'",
        orderBy: 'last_failed_at DESC',
      );
      return rows.map((r) {
        Map<String, dynamic> payload = <String, dynamic>{};
        final rawPayload = r['payload_json']?.toString();
        if (rawPayload != null && rawPayload.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawPayload);
            if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
          } catch (_) {}
        }
        return {
          'id': r['id']?.toString() ?? '',
          'entity_type': r['entity_type']?.toString() ?? 'unknown',
          'endpoint': r['endpoint']?.toString() ?? '',
          'method': r['method']?.toString() ?? 'POST',
          'idempotency_key': r['idempotency_key']?.toString() ?? '',
          if (r['reference_label'] != null) 'reference_label': r['reference_label'].toString(),
          'payload': payload,
          if (r['http_status'] != null) 'http_status': (r['http_status'] as num?)?.toInt(),
          if (r['error_code'] != null) 'error_code': r['error_code'].toString(),
          'error_message': r['error_message']?.toString() ?? '',
          'retry_count': (r['retry_count'] as num?)?.toInt() ?? 1,
          'created_at': r['created_at']?.toString() ?? '',
          'last_failed_at': r['last_failed_at']?.toString() ?? '',
          'status': r['status']?.toString() ?? 'quarantined',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteDeadLetterItem(String id) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.delete('dead_letter_queue', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  // ===========================================================================
  // SHIFTS & PAYABLES
  // ===========================================================================
  Future<void> upsertShift(Map<String, dynamic> shift) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'shifts',
        _shiftToRow(shift),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> upsertLocalPayable(Map<String, dynamic> payable) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'local_payables',
        {
          'id': (payable['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          'invoice_number': (payable['invoice_number'] ?? '').toString(),
          'supplier_id': (payable['supplier_id'] as num?)?.toInt(),
          'supplier_name': (payable['supplier_name'] ?? 'Supplier').toString(),
          'supplier_phone': payable['supplier_phone']?.toString(),
          'total_amount': (payable['total_amount'] as num?)?.toDouble() ?? 0.0,
          'paid_amount': (payable['paid_amount'] as num?)?.toDouble() ?? 0.0,
          'balance_due': (payable['balance_due'] as num?)?.toDouble() ?? 0.0,
          'status': (payable['status'] ?? 'unpaid').toString(),
          'due_date': payable['due_date']?.toString(),
          'created_at': (payable['created_at'] ?? '').toString(),
          'notes': payable['notes']?.toString(),
          'is_synced': (payable['is_synced'] == true || payable['is_synced'] == 1) ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// Factory-reset wipe of ALL local SQLite tables.
  /// MUST ONLY be triggered by explicit user Factory Reset or authorized foreign-tenant switch.
  Future<void> clearAll() async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('products');
        if (_ftsAvailable) {
          try {
            await txn.execute('DELETE FROM products_fts');
          } catch (_) {}
        }
        await txn.delete('customers');
        await txn.delete('suppliers');
        await txn.delete('offline_sales');
        await txn.delete('held_sales');
        await txn.delete('pending_receivable_payments');
        await txn.delete('pending_shift_closures');
        await txn.delete('dead_letter_queue');
        await txn.delete('local_sales_history');
        await txn.delete('local_stock_movements');
        await txn.delete('local_cash_ledger');
        await txn.delete('shifts');
        await txn.delete('local_expenses');
        await txn.delete('local_payables');
      });
    } catch (_) {}
  }
}
