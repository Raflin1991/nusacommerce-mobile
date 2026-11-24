import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// SQLite Data Access Object for Indexed Products (+ FTS5), Customers, Suppliers,
/// Local Stock Movements, and Keyed Master Collections (`kv_collections`).
class ProductLocalDao {
  final Future<Database?> Function() _dbProvider;
  final bool Function() _isFtsAvailable;

  const ProductLocalDao(this._dbProvider, {required bool Function() isFtsAvailable})
      : _isFtsAvailable = isFtsAvailable;

  static Map<String, dynamic> productToRow(Map<String, dynamic> product) {
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

  static Map<String, dynamic> decodeProductRow(Map<String, Object?> row) {
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

  static String extractBrandName(Map<String, dynamic> product) {
    final brandMap = product['brand'] is Map
        ? Map<String, dynamic>.from(product['brand'] as Map)
        : null;
    if (brandMap != null) {
      return (brandMap['name'] ?? '').toString();
    }
    return (product['brand_name'] ?? '').toString();
  }

  Future<void> replaceAllProducts(List<Map<String, dynamic>> products) async {
    final db = await _dbProvider();
    if (db == null) return;
    final fts = _isFtsAvailable();
    try {
      await db.transaction((txn) async {
        await txn.delete('products');
        if (fts) {
          try {
            await txn.execute('DELETE FROM products_fts');
          } catch (_) {}
        }
        final batch = txn.batch();
        for (final prod in products) {
          final row = productToRow(prod);
          batch.insert(
            'products',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (fts) {
            batch.insert('products_fts', {
              'product_id': row['id'],
              'name': row['name'],
              'sku': row['sku'],
              'barcode': row['barcode'],
              'category_name': row['category_name'],
              'brand_name': extractBrandName(prod),
            });
          }
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<void> upsertProduct(Map<String, dynamic> product) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      final row = productToRow(product);
      await db.insert(
        'products',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (_isFtsAvailable()) {
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
            'brand_name': extractBrandName(product),
          });
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> deleteProduct(int productId) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('products', where: 'id = ?', whereArgs: [productId]);
      if (_isFtsAvailable()) {
        try {
          await db.delete('products_fts', where: 'product_id = ?', whereArgs: [productId]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> updateProductStock(
    int productId,
    double newStock, {
    bool? isLowStock,
  }) async {
    await batchUpdateProductStocks({productId: newStock}, forceIsLow: isLowStock);
  }

  Future<void> batchUpdateProductStocks(
    Map<int, double> updates, {
    bool? forceIsLow,
  }) async {
    if (updates.isEmpty) return;
    final db = await _dbProvider();
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
          final current = decodeProductRow(rows.first);
          final reorder = (current['reorder_level'] as num?)?.toDouble() ?? 5.0;
          final low = forceIsLow ?? (entry.value <= reorder);
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
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query('products');
      return rows.map(decodeProductRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchProduct(String query) async {
    final db = await _dbProvider();
    if (db == null) return [];
    final q = query.trim();
    try {
      if (q.isEmpty) {
        final rows = await db.rawQuery('SELECT * FROM products ORDER BY name ASC LIMIT 50');
        return rows.map(decodeProductRow).toList();
      }
      final qLower = q.toLowerCase();

      final exactRows = await db.rawQuery(
        'SELECT * FROM products WHERE LOWER(barcode) = ? OR LOWER(sku) = ? LIMIT 10',
        [qLower, qLower],
      );
      if (exactRows.isNotEmpty) {
        return exactRows.map(decodeProductRow).toList();
      }

      if (_isFtsAvailable()) {
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
              return ftsRows.map(decodeProductRow).toList();
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
      return rows.map(decodeProductRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> replaceAllCustomers(List<Map<String, dynamic>> customers) async {
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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

  Future<void> insertStockMovement(Map<String, dynamic> mov) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
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
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getStockMovements({int limit = 500}) async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'local_stock_movements',
        orderBy: 'created_at DESC',
        limit: limit,
      );
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        final raw = r['payload_json']?.toString();
        if (raw != null && raw.isNotEmpty) {
          try {
            out.add(Map<String, dynamic>.from(jsonDecode(raw) as Map));
          } catch (_) {}
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCollectionJson(String key, Object payload) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'kv_collections',
        {
          'collection_key': key,
          'payload_json': jsonEncode(payload),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> getCollectionList(String key) async {
    final db = await _dbProvider();
    if (db == null) return null;
    try {
      final rows = await db.query(
        'kv_collections',
        where: 'collection_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['payload_json']?.toString();
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> loadAllCollectionsRaw() async {
    final db = await _dbProvider();
    if (db == null) return const {};
    try {
      final rows = await db.query('kv_collections');
      final map = <String, String>{};
      for (final r in rows) {
        final k = r['collection_key']?.toString();
        final v = r['payload_json']?.toString();
        if (k != null && v != null) {
          map[k] = v;
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }
}
