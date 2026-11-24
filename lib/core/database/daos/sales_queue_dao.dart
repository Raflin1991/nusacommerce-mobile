import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'product_local_dao.dart';
import 'shift_local_dao.dart';

part 'sales_queue_dao_ledgers.dart';

/// SQLite Data Access Object for Offline Sales Queue, Held Sales, Sales History,
/// Receivable Payments, Expenses, Payables, Dead-Letter Queue, and ACID Transactions.
class SalesQueueDao {
  final Future<Database?> Function() _dbProvider;

  const SalesQueueDao(this._dbProvider);

  static Map<String, dynamic> expenseToRow(Map<String, dynamic> expense) {
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
      'sync_status':
          (expense['sync_status'] ?? (isSynced == 1 ? 'synced' : 'pending')).toString(),
      'error_message': expense['error_message']?.toString(),
      'retry_count': (expense['retry_count'] as num?)?.toInt() ?? 0,
      'server_id': (expense['server_id'] as num?)?.toInt(),
      'is_synced': isSynced,
    };
  }

  static Map<String, dynamic> decodeExpenseRow(Map<String, Object?> row) {
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

  static Map<String, dynamic> receivablePaymentToRow(Map<String, dynamic> p) {
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

  static Map<String, dynamic> decodeReceivablePaymentRow(Map<String, Object?> r) {
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

  // ===========================================================================
  // ACID ATOMIC TRANSACTION COMMITTERS
  // ===========================================================================
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
    final db = await _dbProvider();
    if (db == null) return true;
    await db.transaction((txn) async {
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

      final receiptId =
          (receiptPayload['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      await txn.insert(
        'local_sales_history',
        {
          'id': receiptId,
          'local_uuid': receiptPayload['local_uuid']?.toString(),
          'number': (receiptPayload['number'] ?? '').toString(),
          'created_at':
              (receiptPayload['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          'payload_json': jsonEncode(receiptPayload),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final entry in stockUpdates.entries) {
        final rows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final current = ProductLocalDao.decodeProductRow(rows.first);
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

      if (cashLedgerEntry != null) {
        await txn.insert(
          'local_cash_ledger',
          {
            'id': (cashLedgerEntry['id'] ?? 'cash-${DateTime.now().microsecondsSinceEpoch}')
                .toString(),
            'direction': (cashLedgerEntry['direction'] ?? 'in').toString(),
            'channel': (cashLedgerEntry['channel'] ?? 'cash').toString(),
            'amount': (cashLedgerEntry['amount'] as num?)?.toDouble() ?? 0.0,
            'occurred_at':
                (cashLedgerEntry['occurred_at'] ?? DateTime.now().toIso8601String()).toString(),
            'payload_json': jsonEncode(cashLedgerEntry),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (updatedOpenShift != null) {
        await txn.insert(
          'shifts',
          ShiftLocalDao.shiftToRow(updatedOpenShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (completedHeldSaleId != null && completedHeldSaleId != 0) {
        await txn.delete('held_sales', where: 'id = ?', whereArgs: [completedHeldSaleId]);
      }
    });
    return true;
  }

  Future<bool> commitReceivablePaymentAtomic({
    Map<String, dynamic>? pendingPayment,
    Map<String, dynamic>? updatedSaleHistory,
    Map<String, dynamic>? updatedCustomer,
    Map<String, dynamic>? updatedShift,
    Map<String, dynamic>? cashLedgerEntry,
  }) async {
    final db = await _dbProvider();
    if (db == null) return true;
    await db.transaction((txn) async {
      if (pendingPayment != null) {
        await txn.insert(
          'pending_receivable_payments',
          receivablePaymentToRow(pendingPayment),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (updatedSaleHistory != null) {
        await txn.insert(
          'local_sales_history',
          {
            'id': (updatedSaleHistory['id'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
            'local_uuid': updatedSaleHistory['local_uuid']?.toString(),
            'number': (updatedSaleHistory['number'] ?? '').toString(),
            'created_at':
                (updatedSaleHistory['created_at'] ?? DateTime.now().toIso8601String()).toString(),
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
          ShiftLocalDao.shiftToRow(updatedShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (cashLedgerEntry != null) {
        await txn.insert(
          'local_cash_ledger',
          {
            'id':
                (cashLedgerEntry['id'] ?? 'rec-${DateTime.now().microsecondsSinceEpoch}').toString(),
            'direction': (cashLedgerEntry['direction'] ?? 'in').toString(),
            'channel': (cashLedgerEntry['channel'] ?? 'cash').toString(),
            'amount': (cashLedgerEntry['amount'] as num?)?.toDouble() ?? 0.0,
            'occurred_at':
                (cashLedgerEntry['occurred_at'] ?? DateTime.now().toIso8601String()).toString(),
            'payload_json': jsonEncode(cashLedgerEntry),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  Future<bool> commitExpenseAtomic({
    required Map<String, dynamic> expense,
    Map<String, dynamic>? updatedShift,
  }) async {
    final db = await _dbProvider();
    if (db == null) return true;
    await db.transaction((txn) async {
      await txn.insert(
        'local_expenses',
        expenseToRow(expense),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (updatedShift != null) {
        await txn.insert(
          'shifts',
          ShiftLocalDao.shiftToRow(updatedShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  // ===========================================================================
  // SALES HISTORY & CASH LEDGER
  // ===========================================================================
  Future<void> replaceSalesHistory(List<Map<String, dynamic>> sales) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('local_sales_history');
        final batch = txn.batch();
        for (final s in sales) {
          batch.insert(
            'local_sales_history',
            {
              'id': (s['id'] as num?)?.toInt() ?? DateTime.now().microsecondsSinceEpoch,
              'local_uuid': s['local_uuid']?.toString(),
              'number': (s['number'] ?? '').toString(),
              'created_at':
                  (s['created_at'] ?? s['sale_datetime'] ?? DateTime.now().toIso8601String())
                      .toString(),
              'payload_json': jsonEncode(s),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<void> upsertSaleHistory(Map<String, dynamic> sale) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'local_sales_history',
        {
          'id': (sale['id'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          'local_uuid': sale['local_uuid']?.toString(),
          'number': (sale['number'] ?? '').toString(),
          'created_at':
              (sale['created_at'] ?? sale['sale_datetime'] ?? DateTime.now().toIso8601String())
                  .toString(),
          'payload_json': jsonEncode(sale),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllSalesHistory() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query('local_sales_history', orderBy: 'created_at DESC');
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

  Future<void> insertCashLedgerEntry(Map<String, dynamic> entry) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'local_cash_ledger',
        {
          'id': (entry['id'] ?? 'loc-${DateTime.now().microsecondsSinceEpoch}').toString(),
          'direction': (entry['direction'] ?? 'in').toString(),
          'channel': (entry['channel'] ?? 'cash').toString(),
          'amount': (entry['amount'] as num?)?.toDouble() ?? 0.0,
          'occurred_at': (entry['occurred_at'] ?? DateTime.now().toIso8601String()).toString(),
          'payload_json': jsonEncode(entry),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllCashLedgerEntries({int limit = 500}) async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'local_cash_ledger',
        orderBy: 'occurred_at DESC',
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

  // ===========================================================================
  // HELD SALES & OFFLINE SALES QUEUE
  // ===========================================================================
  Future<void> upsertHeldSale(Map<String, dynamic> held) async {
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('held_sales', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> insertOfflineSale(
    String id,
    Map<String, dynamic> payload,
    String createdAt,
  ) async {
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.update('offline_sales', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> updateOfflineSalePayload(
    String id,
    Map<String, dynamic> updatedPayload, {
    int isSynced = 0,
  }) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.update(
        'offline_sales',
        {'payload': jsonEncode(updatedPayload), 'is_synced': isSynced},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }

  Future<void> deleteOfflineSale(String id) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('offline_sales', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }
}
