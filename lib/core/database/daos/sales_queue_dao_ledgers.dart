part of 'sales_queue_dao.dart';

extension SalesQueueDaoLedgersExt on SalesQueueDao {
  Future<void> upsertPendingReceivablePayment(Map<String, dynamic> payment) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'pending_receivable_payments',
        SalesQueueDao.receivablePaymentToRow(payment),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getUnsyncedReceivablePayments() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'pending_receivable_payments',
        where: 'is_synced = 0',
        orderBy: 'created_at ASC',
      );
      return rows.map(SalesQueueDao.decodeReceivablePaymentRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markReceivablePaymentSynced(String id) async {
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('pending_receivable_payments', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> upsertLocalExpense(Map<String, dynamic> expense) async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.insert(
        'local_expenses',
        SalesQueueDao.expenseToRow(expense),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getAllLocalExpenses() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query('local_expenses', orderBy: 'created_at DESC');
      return rows.map(SalesQueueDao.decodeExpenseRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLocalExpenses() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'local_expenses',
        where: 'is_synced = 0',
        orderBy: 'created_at ASC',
      );
      return rows.map(SalesQueueDao.decodeExpenseRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markLocalExpenseSynced(int id, {int? serverId}) async {
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('local_expenses', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> upsertDeadLetterItem(Map<String, dynamic> item) async {
    final db = await _dbProvider();
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
    final db = await _dbProvider();
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
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('dead_letter_queue', where: 'id = ?', whereArgs: [id]);
    } catch (_) {}
  }

  Future<void> upsertLocalPayable(Map<String, dynamic> payable) async {
    final db = await _dbProvider();
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

  Future<List<Map<String, dynamic>>> getAllLocalPayables() async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query('local_payables', orderBy: 'created_at DESC');
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }
}
