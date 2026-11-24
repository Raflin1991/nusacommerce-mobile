import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// SQLite Data Access Object for Cashier Shifts & Pending Offline Shift Closures.
class ShiftLocalDao {
  final Future<Database?> Function() _dbProvider;

  const ShiftLocalDao(this._dbProvider);

  static Map<String, dynamic> shiftToRow(Map<String, dynamic> shift) {
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

  static Map<String, dynamic> decodeShiftRow(Map<String, Object?> row) {
    List<Map<String, dynamic>> entries = [];
    final rawEntries = row['entries_json']?.toString();
    if (rawEntries != null && rawEntries.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEntries);
        if (decoded is List) {
          entries = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    int noSaleOpens = 0;
    for (final e in entries) {
      if (e['type'] == 'drawer_open_no_sale') noSaleOpens++;
    }
    return {
      'id': (row['id'] as num?)?.toInt() ?? 0,
      'shift_number': (row['shift_number'] ?? '').toString(),
      'cashier_name': (row['cashier_name'] ?? 'Kasir').toString(),
      'status': (row['status'] ?? 'open').toString(),
      'opened_at': (row['opened_at'] ?? '').toString(),
      if (row['closed_at'] != null) 'closed_at': row['closed_at'].toString(),
      'opening_cash': (row['opening_cash'] as num?)?.toDouble() ?? 0.0,
      'cash_sales': (row['cash_sales'] as num?)?.toDouble() ?? 0.0,
      'cash_in': (row['cash_in'] as num?)?.toDouble() ?? 0.0,
      'cash_out': (row['cash_out'] as num?)?.toDouble() ?? 0.0,
      'expected_cash': (row['expected_cash'] as num?)?.toDouble() ?? 0.0,
      'closing_cash': (row['closing_cash'] as num?)?.toDouble() ?? 0.0,
      'variance': (row['variance'] as num?)?.toDouble() ?? 0.0,
      'no_sale_opens_count': noSaleOpens,
      if (row['notes'] != null) 'notes': row['notes'].toString(),
      'entries': entries,
      'is_synced': (row['is_synced'] as num?)?.toInt() ?? 0,
      'is_local': true,
    };
  }

  static Map<String, dynamic> shiftClosureToRow(Map<String, dynamic> c) {
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

  static Map<String, dynamic> decodeShiftClosureRow(Map<String, Object?> r) {
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

  Future<List<Map<String, dynamic>>> getAllShifts() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query('shifts', orderBy: 'opened_at DESC');
      return rows.map(decodeShiftRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> upsertShift(Map<String, dynamic> shift) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'shifts',
        shiftToRow(shift),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<void> replaceAllShifts(List<Map<String, dynamic>> shifts) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        await txn.delete('shifts');
        final batch = txn.batch();
        for (final s in shifts) {
          batch.insert(
            'shifts',
            shiftToRow(s),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } catch (_) {}
  }

  Future<bool> commitShiftClosureAtomic({
    Map<String, dynamic>? closedShift,
    Map<String, dynamic>? pendingClosure,
  }) async {
    final db = await _dbProvider();
    if (db == null) return true;
    await db.transaction((txn) async {
      if (closedShift != null) {
        await txn.insert(
          'shifts',
          shiftToRow(closedShift),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (pendingClosure != null) {
        await txn.insert(
          'pending_shift_closures',
          shiftClosureToRow(pendingClosure),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return true;
  }

  Future<void> upsertPendingShiftClosure(Map<String, dynamic> closure) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'pending_shift_closures',
        shiftClosureToRow(closure),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUnsyncedShiftClosures() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'pending_shift_closures',
        where: 'is_synced = 0',
        orderBy: 'closed_at ASC',
      );
      return rows.map(decodeShiftClosureRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markShiftClosureSynced(String id) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.update(
        'pending_shift_closures',
        {
          'is_synced': 1,
          'sync_status': 'synced',
          'error_code': null,
          'error_message': null,
        },
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('pending_shift_closures', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }
}
