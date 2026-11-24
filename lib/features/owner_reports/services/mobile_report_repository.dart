import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../models/mobile_report_catalog.dart';
import 'report_file_saver.dart';

part 'mobile_report_repository_part1.dart';
part 'mobile_report_repository_part2.dart';

class MobileReportApiException implements Exception {
  final String message;
  final int? statusCode;

  const MobileReportApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}


class MobileReportExportResult {
  final String filename;
  final String? filePath;
  final int byteLength;
  final String? textContent;

  const MobileReportExportResult({
    required this.filename,
    this.filePath,
    required this.byteLength,
    this.textContent,
  });
}


/// Unified Cloud <-> Offline-First Repository for the Mobile 50-Report BI Center.
class MobileReportRepository {
  final ApiClient api;

  final OfflineDatabase offlineDb;

  final NetworkConnectivityService connectivity;


  MobileReportRepository({
    required this.api,
    required this.offlineDb,
    required this.connectivity,
  });


  /// SEC #18 CSV formula neutralization + RFC-4180 double-quote escaping.
  static String sanitizeCsvCell(String raw) {
    var safe = raw.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (safe.isNotEmpty) {
      final first = safe[0];
      if (first == '=' ||
          first == '+' ||
          first == '-' ||
          first == '@' ||
          first == '\t') {
        safe = "'$safe";
      }
    }
    final escaped = safe.replaceAll('"', '""');
    return '"$escaped"';
  }


  static ({DateTime start, DateTime end, String label}) resolveDateRange(
    String periodKey, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (periodKey) {
      case 'today':
        return (start: todayStart, end: todayEnd, label: 'Hari Ini');
      case 'yesterday':
        final yStart = todayStart.subtract(const Duration(days: 1));
        final yEnd = todayStart.subtract(const Duration(seconds: 1));
        return (start: yStart, end: yEnd, label: 'Kemarin');
      case '30d':
        return (
          start: todayStart.subtract(const Duration(days: 29)),
          end: todayEnd,
          label: '30 Hari Terakhir',
        );
      case 'month':
        return (
          start: DateTime(now.year, now.month, 1),
          end: todayEnd,
          label: 'Bulan Ini',
        );
      case 'last_month':
        final firstPrev = DateTime(now.year, now.month - 1, 1);
        final lastPrev = DateTime(now.year, now.month, 0, 23, 59, 59);
        return (start: firstPrev, end: lastPrev, label: 'Bulan Lalu');
      case 'custom':
        final s = customStart ?? todayStart.subtract(const Duration(days: 6));
        final e = customEnd != null
            ? DateTime(customEnd.year, customEnd.month, customEnd.day, 23, 59, 59)
            : todayEnd;
        final df = DateFormat('dd/MM/yyyy');
        return (
          start: DateTime(s.year, s.month, s.day),
          end: e,
          label: '${df.format(s)} - ${df.format(e)}',
        );
      case '7d':
      default:
        return (
          start: todayStart.subtract(const Duration(days: 6)),
          end: todayEnd,
          label: '7 Hari Terakhir',
        );
    }
  }


  static String buildCsvFromPayload(MobileReportPayload payload) {
    final buf = StringBuffer();
    buf.writeln([
      sanitizeCsvCell('Laporan'),
      sanitizeCsvCell(payload.title),
      sanitizeCsvCell('Periode'),
      sanitizeCsvCell(payload.periodLabel),
      sanitizeCsvCell('Cabang'),
      sanitizeCsvCell(payload.storeLabel),
    ].join(','));
    buf.writeln();

    if (payload.kpis.isNotEmpty) {
      buf.writeln('${sanitizeCsvCell('Ringkasan KPI')},${sanitizeCsvCell('Nilai')}');
      for (final k in payload.kpis) {
        buf.writeln('${sanitizeCsvCell(k.label)},${sanitizeCsvCell(k.formatted)}');
      }
      buf.writeln();
    }

    final cols = payload.columns.isNotEmpty
        ? payload.columns
        : ['Item', 'Keterangan', 'Nilai Utama', 'Nilai Tambahan'];
    buf.writeln(cols.map(sanitizeCsvCell).join(','));

    for (final item in payload.items) {
      if (item.details.isNotEmpty && payload.columns.isNotEmpty) {
        final cells = payload.columns
            .map((c) => sanitizeCsvCell(item.details[c] ?? '-'))
            .join(',');
        buf.writeln(cells);
      } else {
        buf.writeln([
          sanitizeCsvCell(item.title),
          sanitizeCsvCell(item.subtitle),
          sanitizeCsvCell(item.primaryValue),
          sanitizeCsvCell(item.secondaryValue ?? ''),
        ].join(','));
      }
    }
    return buf.toString();
  }


  static String buildWhatsAppSummary({
    required MobileReportDefinition definition,
    required String storeLabel,
    required String periodLabel,
    required List<MobileReportKpi> kpis,
    required List<MobileReportRowItem> items,
    bool isOfflineData = false,
    String? lastSyncLabel,
  }) {
    final buf = StringBuffer();
    buf.writeln('📊 *${definition.title.toUpperCase()} — OXORA*');
    buf.writeln('🏪 Cabang: $storeLabel');
    buf.writeln('📅 Periode: $periodLabel');
    if (isOfflineData && lastSyncLabel != null) {
      buf.writeln('📡 _Data Offline (Sinkronisasi Terakhir: $lastSyncLabel)_');
    }
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');

    if (kpis.isNotEmpty) {
      buf.writeln('📌 *Ringkasan Utama:*');
      for (final k in kpis.take(6)) {
        final icon = k.tone == 'danger'
            ? '🔴'
            : (k.tone == 'warning'
                ? '🟡'
                : (k.tone == 'positive' ? '🟢' : '▫️'));
        buf.writeln('$icon ${k.label}: *${k.formatted}*');
      }
      buf.writeln();
    }

    final dataRows = items.where((i) => !i.isSection && !i.isTotal).take(8).toList();
    if (dataRows.isNotEmpty) {
      buf.writeln('📋 *Sorotan Teratas (${dataRows.length}/${items.length}):*');
      for (int idx = 0; idx < dataRows.length; idx++) {
        final row = dataRows[idx];
        final extra = row.secondaryValue != null && row.secondaryValue!.isNotEmpty
            ? ' (${row.secondaryValue})'
            : '';
        buf.writeln('${idx + 1}. ${row.title} — *${row.primaryValue}*$extra');
      }
    } else {
      buf.writeln('_Tidak ada baris rincian pada periode ini._');
    }

    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('_Dikirim dari OXORA Mobile BI Center_');
    return buf.toString();
  }
}
