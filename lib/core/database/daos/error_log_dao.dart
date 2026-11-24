import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// SQLite Data Access Object for Local Error & Uncaught Crash Telemetry (`local_error_logs`).
/// Automatically redacts sensitive credentials (Bearer tokens, PINs, passwords, API keys)
/// and enforces a rolling 500-row cap so local storage never grows unbounded.
class ErrorLogDao {
  final Future<Database?> Function() _dbProvider;
  static const int maxRows = 500;

  const ErrorLogDao(this._dbProvider);

  /// Redacts sensitive tokens, PINs, passwords, and session secrets from diagnostic strings.
  static String sanitizeSensitiveText(String raw) {
    if (raw.isEmpty) return raw;
    var sanitized = raw;
    sanitized = sanitized.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'("(?:password|pin|supervisor_pin|whatsapp_pin|token|access_token|refresh_token|secret|authorization)"\s*:\s*)"[^"]*"',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}"[REDACTED]"',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'\b(password|pin|supervisor_pin|token|secret)\s*=\s*[^\s,&;]+',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}=[REDACTED]',
    );
    return sanitized;
  }

  Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_error_logs (
        id TEXT PRIMARY KEY,
        error_type TEXT NOT NULL,
        message TEXT NOT NULL,
        stack_trace TEXT,
        context TEXT,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_error_logs_created ON local_error_logs(is_synced, created_at DESC)',
    );
  }

  Future<Map<String, dynamic>> recordError({
    required String id,
    required String errorType,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? context,
    String? createdAt,
  }) async {
    final nowIso = createdAt ?? DateTime.now().toIso8601String();
    final safeMessage = sanitizeSensitiveText(message);
    final safeStack = stackTrace != null ? sanitizeSensitiveText(stackTrace) : null;
    final safeContext = context != null ? sanitizeSensitiveText(jsonEncode(context)) : null;

    final row = <String, dynamic>{
      'id': id,
      'error_type': sanitizeSensitiveText(errorType),
      'message': safeMessage.length > 2000 ? safeMessage.substring(0, 2000) : safeMessage,
      'stack_trace': safeStack != null && safeStack.length > 6000
          ? safeStack.substring(0, 6000)
          : safeStack,
      'context': safeContext,
      'created_at': nowIso,
      'is_synced': 0,
    };

    final db = await _dbProvider();
    if (db != null) {
      try {
        await db.transaction((txn) async {
          await txn.insert(
            'local_error_logs',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.rawDelete('''
            DELETE FROM local_error_logs
            WHERE id NOT IN (
              SELECT id FROM local_error_logs
              ORDER BY created_at DESC
              LIMIT $maxRows
            )
          ''');
        });
      } catch (_) {}
    }

    return row;
  }

  Future<List<Map<String, dynamic>>> getRecentErrors({
    int limit = 50,
    bool unsyncedOnly = false,
  }) async {
    final db = await _dbProvider();
    if (db == null) return [];
    try {
      final rows = await db.query(
        'local_error_logs',
        where: unsyncedOnly ? 'is_synced = 0' : null,
        orderBy: 'created_at DESC',
        limit: limit,
      );
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbProvider();
    if (db == null) return;
    try {
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE local_error_logs SET is_synced = 1 WHERE id IN ($placeholders)',
        ids,
      );
    } catch (_) {}
  }

  Future<void> clearAll() async {
    final db = await _dbProvider();
    if (db == null) return;
    try {
      await db.delete('local_error_logs');
    } catch (_) {}
  }
}
