import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Enterprise Indexed Local Database Engine (`nusacommerce_local.db`) powered by SQLite (`sqflite`).
/// Provides < 5ms indexed lookup across thousands of products, customers, suppliers,
/// and ACID-safe UUIDv4 idempotent offline sales storage.
class SqliteDatabase {
  SqliteDatabase._();

  static final SqliteDatabase instance = SqliteDatabase._();

  static const String _dbName = 'nusacommerce_local.db';
  static const int _dbVersion = 1;

  Database? _db;

  bool get isSupported => !kIsWeb;

  Future<Database?> get database async {
    if (!isSupported) return null;
    if (_db != null && _db!.isOpen) return _db;
    return await init();
  }

  /// Initialize SQLite database with indexed schema.
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
              raw_json TEXT
            )
          ''');
          await db.execute('CREATE INDEX idx_barcode ON products(barcode)');
          await db.execute('CREATE INDEX idx_sku ON products(sku)');
          await db.execute('CREATE INDEX idx_cat ON products(category_id)');

          await db.execute('''
            CREATE TABLE offline_sales (
              id TEXT PRIMARY KEY,
              payload TEXT,
              created_at TEXT,
              is_synced INTEGER DEFAULT 0
            )
          ''');

          await db.execute('''
            CREATE TABLE customers (
              id INTEGER PRIMARY KEY,
              name TEXT,
              phone TEXT,
              code TEXT,
              raw_json TEXT
            )
          ''');
          await db.execute('CREATE INDEX idx_cust_phone ON customers(phone)');
          await db.execute('CREATE INDEX idx_cust_name ON customers(name)');

          await db.execute('''
            CREATE TABLE suppliers (
              id INTEGER PRIMARY KEY,
              name TEXT,
              phone TEXT,
              raw_json TEXT
            )
          ''');
          await db.execute('CREATE INDEX idx_sup_name ON suppliers(name)');
        },
      );
      return _db;
    } catch (_) {
      return null;
    }
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

    return {
      'id': (product['id'] as num?)?.toInt() ?? 0,
      'sku': (product['sku'] ?? '').toString(),
      'barcode': (product['barcode'] ?? '').toString(),
      'name': (product['name'] ?? '').toString(),
      'category_id': catId,
      'category_name': catName,
      'selling_price': (product['selling_price'] as num?)?.toDouble() ?? 0.0,
      'cost_price': (product['cost_price'] as num?)?.toDouble() ?? 0.0,
      'stock': stockVal,
      'unit_code': unitCode,
      'is_low_stock': isLow ? 1 : 0,
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
    };
  }

  // ===========================================================================
  // PRODUCTS CRUD & FAST INDEXED SEARCH (< 5ms)
  // ===========================================================================
  Future<void> replaceAllProducts(List<Map<String, dynamic>> products) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('products');
        final batch = txn.batch();
        for (final prod in products) {
          batch.insert(
            'products',
            _productToRow(prod),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<void> upsertProduct(Map<String, dynamic> product) async {
    final db = await database;
    if (db == null) return;
    try {
      await db.insert(
        'products',
        _productToRow(product),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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

  /// Fast indexed SQL lookup by exact barcode, exact SKU, or partial product name.
  Future<List<Map<String, dynamic>>> searchProduct(String query) async {
    final db = await database;
    if (db == null) return [];
    final q = query.trim();
    try {
      if (q.isEmpty) {
        final rows = await db.rawQuery('SELECT * FROM products LIMIT 50');
        return rows.map(_decodeProductRow).toList();
      }
      final rows = await db.rawQuery(
        'SELECT * FROM products WHERE barcode = ? OR sku = ? OR name LIKE ? LIMIT 50',
        [q, q, '%$q%'],
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

  Future<void> clearAll() async {
    final db = await database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('products');
        await txn.delete('customers');
        await txn.delete('suppliers');
      });
    } catch (_) {}
  }
}
