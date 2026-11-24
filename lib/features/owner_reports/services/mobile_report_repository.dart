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

  String formatLastSyncLabel({required bool isLocalTrial}) {
    if (isLocalTrial) {
      return 'Mode Toko Mandiri (Lokal)';
    }
    final syncedAt = offlineDb.getLastCloudSyncAt();
    if (syncedAt == null) {
      return 'Belum Pernah Sinkronisasi';
    }
    return DateFormat('dd MMM yyyy, HH:mm').format(syncedAt);
  }

  Future<MobileReportPayload> fetchReport({
    required MobileReportDefinition definition,
    required String periodKey,
    DateTime? customStart,
    DateTime? customEnd,
    required String storeScope,
    required String storeLabel,
    required bool isLocalTrial,
    String search = '',
  }) async {
    final range = resolveDateRange(
      periodKey,
      customStart: customStart,
      customEnd: customEnd,
    );

    if (isLocalTrial || !(await connectivity.checkOnline())) {
      return _buildLocalReport(
        definition: definition,
        range: range,
        storeLabel: storeLabel,
        isLocalTrial: isLocalTrial,
        search: search,
      );
    }

    final params = <String, dynamic>{
      'period': periodKey,
      'store_id': storeScope,
      if (search.trim().isNotEmpty) 'search': search.trim(),
    };
    if (periodKey == 'custom' && customStart != null && customEnd != null) {
      params['start_date'] = DateFormat('yyyy-MM-dd').format(customStart);
      params['end_date'] = DateFormat('yyyy-MM-dd').format(customEnd);
    }

    try {
      final res = await api.dio.get(
        ApiEndpoints.reportRun(definition.id),
        queryParameters: params,
      );
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      return MobileReportPayload.fromApiJson(data, periodLabel: range.label);
    } catch (e) {
      // NEVER mask online HTTP 401/403/422/500 rejections as offline fallback!
      if (!ApiClient.isNetworkOfflineError(e)) {
        final statusCode = e is DioException ? e.response?.statusCode : null;
        throw MobileReportApiException(
          ApiClient.extractErrorMessage(e),
          statusCode: statusCode,
        );
      }

      return _buildLocalReport(
        definition: definition,
        range: range,
        storeLabel: storeLabel,
        isLocalTrial: isLocalTrial,
        search: search,
      );
    }
  }

  /// Downloads official Cloud-rendered A4 PDF from `/api/v1/reports/export/{reportId}?format=pdf`.
  Future<MobileReportExportResult> downloadServerPdf({
    required MobileReportDefinition definition,
    required String periodKey,
    DateTime? customStart,
    DateTime? customEnd,
    required String storeScope,
  }) async {
    final params = <String, dynamic>{
      'format': 'pdf',
      'period': periodKey,
      'store_id': storeScope,
    };
    if (periodKey == 'custom' && customStart != null && customEnd != null) {
      params['start_date'] = DateFormat('yyyy-MM-dd').format(customStart);
      params['end_date'] = DateFormat('yyyy-MM-dd').format(customEnd);
    }

    final res = await api.dio.get<List<int>>(
      ApiEndpoints.reportExport(definition.id),
      queryParameters: params,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Accept': 'application/pdf, application/json'},
      ),
    );
    final bytes = res.data ?? const <int>[];
    if (bytes.isEmpty) {
      throw const MobileReportApiException('File PDF dari server kosong.');
    }
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'oxora_${definition.id}_$ts.pdf';
    final path = await saveReportExportBytes(filename: filename, bytes: bytes);
    return MobileReportExportResult(
      filename: filename,
      filePath: path,
      byteLength: bytes.length,
    );
  }

  /// Builds & persists a UTF-8 BOM SEC #18 formula-safe CSV file for any report payload.
  Future<MobileReportExportResult> exportCsvFile(
    MobileReportPayload payload,
  ) async {
    final csv = payload.csvContent.trim().isNotEmpty
        ? payload.csvContent
        : buildCsvFromPayload(payload);
    final bomBytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(csv)];
    final ts = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final filename = 'oxora_${payload.reportId}_$ts.csv';
    final path = await saveReportExportBytes(filename: filename, bytes: bomBytes);
    return MobileReportExportResult(
      filename: filename,
      filePath: path,
      byteLength: bomBytes.length,
      textContent: csv,
    );
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

  // ===========================================================================
  // OFFLINE-FIRST LOCAL REPORT COMPUTATION ENGINE
  // ===========================================================================

  MobileReportPayload _buildLocalReport({
    required MobileReportDefinition definition,
    required ({DateTime start, DateTime end, String label}) range,
    required String storeLabel,
    required bool isLocalTrial,
    required String search,
  }) {
    final lastSync = formatLastSyncLabel(isLocalTrial: isLocalTrial);
    final startStr = DateFormat('yyyy-MM-dd').format(range.start);
    final endStr = DateFormat('yyyy-MM-dd').format(range.end);

    final base = offlineDb.computeLocalBusinessReport(
      startDate: range.start,
      endDate: range.end,
    );
    final ext = offlineDb.computeLocalExtendedAnalytics(
      startDate: range.start,
      endDate: range.end,
    );

    List<MobileReportKpi> kpis = [];
    List<String> columns = [];
    List<MobileReportRowItem> items = [];
    String? offlineNotice;

    switch (definition.id) {
      case 'sales-report':
        final net = (base['net_sales'] as num?)?.toDouble() ?? 0;
        final gross = (base['gross_sales'] as num?)?.toDouble() ?? 0;
        final disc = (base['discount_total'] as num?)?.toDouble() ?? 0;
        final tx = (base['transactions_count'] as num?)?.toInt() ?? 0;
        final avg = (base['average_basket'] as num?)?.toDouble() ?? 0;
        kpis = [
          MobileReportKpi(label: 'Omzet Bersih', formatted: IdrCurrencyFormatter.format(net), numericValue: net, type: 'currency', tone: 'positive'),
          MobileReportKpi(label: 'Total Transaksi', formatted: '$tx nota', numericValue: tx, type: 'count'),
          MobileReportKpi(label: 'Rata-rata Nota', formatted: IdrCurrencyFormatter.format(avg), numericValue: avg, type: 'currency'),
          MobileReportKpi(label: 'Total Diskon', formatted: IdrCurrencyFormatter.format(disc), numericValue: disc, type: 'currency', tone: disc > 0 ? 'warning' : 'neutral'),
        ];
        columns = ['Tanggal', 'Transaksi', 'Omzet'];
        final daily = (base['daily_trend'] as List<dynamic>? ?? []);
        items = daily.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
          final cnt = (m['transactions'] as num?)?.toInt() ?? 0;
          return MobileReportRowItem(
            title: (m['date'] ?? m['day_label'] ?? '-').toString(),
            subtitle: '$cnt transaksi selesai',
            primaryValue: IdrCurrencyFormatter.format(rev),
            primaryNumeric: rev,
            secondaryValue: '$cnt nota',
            details: {
              'Tanggal': (m['date'] ?? '-').toString(),
              'Transaksi': '$cnt nota',
              'Omzet': IdrCurrencyFormatter.format(rev),
              'Omzet Kotor Periode': IdrCurrencyFormatter.format(gross),
            },
          );
        }).toList();
        break;

      case 'bill-wise-profit':
        final sales = _filterLocalSales(range.start, range.end);
        final products = offlineDb.getCachedProducts();
        final costById = {
          for (final p in products)
            (p['id'] as num?)?.toInt() ?? 0: (p['cost_price'] as num?)?.toDouble() ?? 0.0,
        };
        double sumRev = 0, sumProfit = 0;
        columns = ['No. Faktur', 'Pelanggan', 'Omzet', 'HPP', 'Laba Kotor', 'Margin %'];
        for (final s in sales) {
          final rev = (s['grand_total'] as num?)?.toDouble() ?? 0;
          double cogs = 0;
          for (final it in (s['items'] as List<dynamic>? ?? [])) {
            if (it is! Map) continue;
            final pid = (it['product_id'] as num?)?.toInt() ?? 0;
            final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
            final unitCost = (it['cost_price'] as num?)?.toDouble() ?? (costById[pid] ?? 0);
            cogs += qty * unitCost;
          }
          final profit = rev - cogs;
          final margin = rev > 0 ? (profit / rev) * 100 : 0.0;
          sumRev += rev;
          sumProfit += profit;
          final custName = s['customer'] is Map
              ? (s['customer']['name'] ?? 'Pelanggan Umum').toString()
              : (s['customer_name'] ?? 'Pelanggan Umum').toString();
          final invNo = (s['number'] ?? '#INV').toString();
          items.add(MobileReportRowItem(
            title: invNo,
            subtitle: '$custName • ${(s['created_at'] ?? s['sale_datetime'] ?? '').toString().split('T').first}',
            badge: '${margin.toStringAsFixed(1)}%',
            badgeTone: margin >= 20 ? 'positive' : (margin > 0 ? 'warning' : 'danger'),
            primaryValue: IdrCurrencyFormatter.format(profit),
            primaryNumeric: profit,
            secondaryValue: 'Omzet ${IdrCurrencyFormatter.format(rev)}',
            details: {
              'No. Faktur': invNo,
              'Pelanggan': custName,
              'Omzet': IdrCurrencyFormatter.format(rev),
              'HPP': IdrCurrencyFormatter.format(cogs),
              'Laba Kotor': IdrCurrencyFormatter.format(profit),
              'Margin %': '${margin.toStringAsFixed(1)}%',
            },
          ));
        }
        final avgMargin = sumRev > 0 ? (sumProfit / sumRev) * 100 : 0.0;
        kpis = [
          MobileReportKpi(label: 'Total Omzet', formatted: IdrCurrencyFormatter.format(sumRev), numericValue: sumRev, type: 'currency'),
          MobileReportKpi(label: 'Laba Kotor', formatted: IdrCurrencyFormatter.format(sumProfit), numericValue: sumProfit, type: 'currency', tone: sumProfit >= 0 ? 'positive' : 'danger'),
          MobileReportKpi(label: 'Rata-rata Margin', formatted: '${avgMargin.toStringAsFixed(1)}%', numericValue: avgMargin, type: 'percent', tone: 'positive'),
          MobileReportKpi(label: 'Jumlah Faktur', formatted: '${sales.length} nota', numericValue: sales.length, type: 'count'),
        ];
        break;

      case 'sales-by-product':
        final top = (base['top_products'] as List<dynamic>? ?? []);
        final totalRev = top.fold<double>(0, (s, e) => s + ((e['revenue'] as num?)?.toDouble() ?? 0));
        final totalQty = top.fold<double>(0, (s, e) => s + ((e['qty'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Produk Terjual', formatted: '${top.length} SKU', numericValue: top.length, type: 'count'),
          MobileReportKpi(label: 'Total Qty Terjual', formatted: IdrCurrencyFormatter.formatQty(totalQty), numericValue: totalQty, type: 'count'),
          MobileReportKpi(label: 'Total Omzet Produk', formatted: IdrCurrencyFormatter.format(totalRev), numericValue: totalRev, type: 'currency', tone: 'positive'),
        ];
        columns = ['Produk', 'Qty Terjual', 'Omzet', 'Estimasi Laba'];
        items = top.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
          final prof = (m['profit'] as num?)?.toDouble() ?? 0;
          final qty = (m['qty'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (m['name'] ?? 'Produk').toString(),
            subtitle: 'Terjual ${IdrCurrencyFormatter.formatQty(qty)} unit',
            primaryValue: IdrCurrencyFormatter.format(rev),
            primaryNumeric: rev,
            secondaryValue: 'Laba ${IdrCurrencyFormatter.format(prof)}',
            details: {
              'Produk': (m['name'] ?? 'Produk').toString(),
              'Qty Terjual': IdrCurrencyFormatter.formatQty(qty),
              'Omzet': IdrCurrencyFormatter.format(rev),
              'Estimasi Laba': IdrCurrencyFormatter.format(prof),
            },
          );
        }).toList();
        break;

      case 'sales-by-category':
        final list = (ext['by_category'] as List<dynamic>? ?? []);
        final totalRev = list.fold<double>(0, (s, e) => s + ((e['revenue'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Kategori Aktif', formatted: '${list.length}', numericValue: list.length, type: 'count'),
          MobileReportKpi(label: 'Total Omzet', formatted: IdrCurrencyFormatter.format(totalRev), numericValue: totalRev, type: 'currency', tone: 'positive'),
        ];
        columns = ['Kategori', 'Qty', 'Omzet', 'Kontribusi %'];
        items = list.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
          final qty = (m['qty'] as num?)?.toDouble() ?? 0;
          final pct = totalRev > 0 ? (rev / totalRev) * 100 : 0.0;
          return MobileReportRowItem(
            title: (m['name'] ?? 'Umum').toString(),
            subtitle: '${IdrCurrencyFormatter.formatQty(qty)} item terjual',
            badge: '${pct.toStringAsFixed(1)}%',
            badgeTone: 'positive',
            primaryValue: IdrCurrencyFormatter.format(rev),
            primaryNumeric: rev,
            details: {
              'Kategori': (m['name'] ?? 'Umum').toString(),
              'Qty': IdrCurrencyFormatter.formatQty(qty),
              'Omzet': IdrCurrencyFormatter.format(rev),
              'Kontribusi %': '${pct.toStringAsFixed(1)}%',
            },
          );
        }).toList();
        break;

      case 'sales-by-brand':
        final list = (ext['by_brand'] as List<dynamic>? ?? []);
        final totalRev = list.fold<double>(0, (s, e) => s + ((e['revenue'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Merek / Brand Aktif', formatted: '${list.length}', numericValue: list.length, type: 'count'),
          MobileReportKpi(label: 'Total Omzet', formatted: IdrCurrencyFormatter.format(totalRev), numericValue: totalRev, type: 'currency', tone: 'positive'),
        ];
        columns = ['Brand / Merek', 'Qty', 'Omzet'];
        items = list.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
          final qty = (m['qty'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (m['name'] ?? 'Generic').toString(),
            subtitle: '${IdrCurrencyFormatter.formatQty(qty)} item terjual',
            primaryValue: IdrCurrencyFormatter.format(rev),
            primaryNumeric: rev,
            details: {
              'Brand / Merek': (m['name'] ?? 'Generic').toString(),
              'Qty': IdrCurrencyFormatter.formatQty(qty),
              'Omzet': IdrCurrencyFormatter.format(rev),
            },
          );
        }).toList();
        break;

      case 'sales-by-channel':
        final sales = _filterLocalSales(range.start, range.end);
        final byCh = <String, ({int count, double rev})>{};
        for (final s in sales) {
          final ch = (s['origin'] ?? s['channel'] ?? 'POS Mobile').toString().toUpperCase();
          final prev = byCh[ch] ?? (count: 0, rev: 0.0);
          byCh[ch] = (count: prev.count + 1, rev: prev.rev + ((s['grand_total'] as num?)?.toDouble() ?? 0));
        }
        final totalRev = byCh.values.fold<double>(0, (sum, e) => sum + e.rev);
        kpis = [
          MobileReportKpi(label: 'Saluran Aktif', formatted: '${byCh.length}', numericValue: byCh.length, type: 'count'),
          MobileReportKpi(label: 'Total Omzet', formatted: IdrCurrencyFormatter.format(totalRev), numericValue: totalRev, type: 'currency', tone: 'positive'),
        ];
        columns = ['Saluran', 'Transaksi', 'Omzet'];
        items = byCh.entries.map((e) => MobileReportRowItem(
          title: e.key,
          subtitle: '${e.value.count} transaksi',
          primaryValue: IdrCurrencyFormatter.format(e.value.rev),
          primaryNumeric: e.value.rev,
          details: {
            'Saluran': e.key,
            'Transaksi': '${e.value.count}',
            'Omzet': IdrCurrencyFormatter.format(e.value.rev),
          },
        )).toList();
        break;

      case 'sales-by-cashier':
        final sales = _filterLocalSales(range.start, range.end);
        final byCashier = <String, ({int count, double rev})>{};
        for (final s in sales) {
          final name = (s['cashier_name'] ?? 'Kasir Lokal').toString();
          final prev = byCashier[name] ?? (count: 0, rev: 0.0);
          byCashier[name] = (count: prev.count + 1, rev: prev.rev + ((s['grand_total'] as num?)?.toDouble() ?? 0));
        }
        final totalRev = byCashier.values.fold<double>(0, (sum, e) => sum + e.rev);
        kpis = [
          MobileReportKpi(label: 'Kasir Aktif', formatted: '${byCashier.length} orang', numericValue: byCashier.length, type: 'count'),
          MobileReportKpi(label: 'Total Omzet', formatted: IdrCurrencyFormatter.format(totalRev), numericValue: totalRev, type: 'currency', tone: 'positive'),
        ];
        columns = ['Kasir', 'Jumlah Nota', 'Total Omzet', 'Rata-rata Nota'];
        items = byCashier.entries.map((e) {
          final avg = e.value.count > 0 ? e.value.rev / e.value.count : 0.0;
          return MobileReportRowItem(
            title: e.key,
            subtitle: '${e.value.count} transaksi • Avg ${IdrCurrencyFormatter.format(avg)}',
            primaryValue: IdrCurrencyFormatter.format(e.value.rev),
            primaryNumeric: e.value.rev,
            details: {
              'Kasir': e.key,
              'Jumlah Nota': '${e.value.count}',
              'Total Omzet': IdrCurrencyFormatter.format(e.value.rev),
              'Rata-rata Nota': IdrCurrencyFormatter.format(avg),
            },
          );
        }).toList();
        break;

      case 'sales-by-payment-method':
        final list = (base['payment_breakdown'] as List<dynamic>? ?? []);
        final totalAmt = list.fold<double>(0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Metode Digunakan', formatted: '${list.length}', numericValue: list.length, type: 'count'),
          MobileReportKpi(label: 'Total Pembayaran', formatted: IdrCurrencyFormatter.format(totalAmt), numericValue: totalAmt, type: 'currency', tone: 'positive'),
        ];
        columns = ['Metode Pembayaran', 'Frekuensi', 'Total Nominal', 'Porsi %'];
        items = list.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final amt = (m['amount'] as num?)?.toDouble() ?? 0;
          final cnt = (m['count'] as num?)?.toInt() ?? 0;
          final pct = totalAmt > 0 ? (amt / totalAmt) * 100 : 0.0;
          return MobileReportRowItem(
            title: (m['method'] ?? 'Tunai').toString(),
            subtitle: '$cnt transaksi',
            badge: '${pct.toStringAsFixed(1)}%',
            badgeTone: 'positive',
            primaryValue: IdrCurrencyFormatter.format(amt),
            primaryNumeric: amt,
            details: {
              'Metode Pembayaran': (m['method'] ?? 'Tunai').toString(),
              'Frekuensi': '$cnt transaksi',
              'Total Nominal': IdrCurrencyFormatter.format(amt),
              'Porsi %': '${pct.toStringAsFixed(1)}%',
            },
          );
        }).toList();
        break;

      case 'hourly-sales':
        final hourly = (ext['hourly'] as List<dynamic>? ?? []);
        Map<String, dynamic>? peak;
        for (final raw in hourly) {
          final m = Map<String, dynamic>.from(raw as Map);
          if (peak == null || ((m['revenue'] as num?) ?? 0) > ((peak['revenue'] as num?) ?? 0)) {
            peak = m;
          }
        }
        kpis = [
          MobileReportKpi(
            label: 'Jam Tersibuk',
            formatted: peak != null ? '${peak['hour_num'].toString().padLeft(2, '0')}:00' : '-',
            tone: 'positive',
          ),
          MobileReportKpi(
            label: 'Omzet Jam Puncak',
            formatted: IdrCurrencyFormatter.format((peak?['revenue'] as num?)?.toDouble() ?? 0),
            numericValue: (peak?['revenue'] as num?)?.toDouble() ?? 0,
            type: 'currency',
          ),
        ];
        columns = ['Jam', 'Transaksi', 'Omzet'];
        items = hourly.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final hr = (m['hour_num'] as num?)?.toInt() ?? 0;
          final label = '${hr.toString().padLeft(2, '0')}:00 - ${hr.toString().padLeft(2, '0')}:59';
          final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
          final cnt = (m['tx_count'] as num?)?.toInt() ?? 0;
          return MobileReportRowItem(
            title: label,
            subtitle: '$cnt transaksi',
            primaryValue: IdrCurrencyFormatter.format(rev),
            primaryNumeric: rev,
            details: {
              'Jam': label,
              'Transaksi': '$cnt',
              'Omzet': IdrCurrencyFormatter.format(rev),
            },
          );
        }).toList();
        break;

      case 'basket-size':
        final sales = _filterLocalSales(range.start, range.end);
        double totalItems = 0, totalRev = 0;
        for (final s in sales) {
          totalRev += (s['grand_total'] as num?)?.toDouble() ?? 0;
          for (final it in (s['items'] as List<dynamic>? ?? [])) {
            totalItems += (it['quantity'] as num?)?.toDouble() ?? 1;
          }
        }
        final aov = sales.isNotEmpty ? totalRev / sales.length : 0.0;
        final avgQty = sales.isNotEmpty ? totalItems / sales.length : 0.0;
        kpis = [
          MobileReportKpi(label: 'Rata-rata Nilai Nota (AOV)', formatted: IdrCurrencyFormatter.format(aov), numericValue: aov, type: 'currency', tone: 'positive'),
          MobileReportKpi(label: 'Rata-rata Item / Nota', formatted: '${avgQty.toStringAsFixed(1)} item', numericValue: avgQty, type: 'count'),
          MobileReportKpi(label: 'Total Transaksi', formatted: '${sales.length}', numericValue: sales.length, type: 'count'),
        ];
        columns = ['No. Nota', 'Jumlah Item', 'Total Belanja'];
        items = sales.take(50).map((s) {
          final qty = (s['items'] as List<dynamic>? ?? []).fold<double>(
            0,
            (sum, it) => sum + ((it['quantity'] as num?)?.toDouble() ?? 1),
          );
          final grand = (s['grand_total'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (s['number'] ?? '#INV').toString(),
            subtitle: '${IdrCurrencyFormatter.formatQty(qty)} item',
            primaryValue: IdrCurrencyFormatter.format(grand),
            primaryNumeric: grand,
            details: {
              'No. Nota': (s['number'] ?? '#INV').toString(),
              'Jumlah Item': IdrCurrencyFormatter.formatQty(qty),
              'Total Belanja': IdrCurrencyFormatter.format(grand),
            },
          );
        }).toList();
        break;

      case 'quotation-pipeline':
        final quotes = offlineDb.getLocalQuotations();
        final totalVal = quotes.fold<double>(0, (s, q) => s + ((q['grand_total'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Total Penawaran', formatted: '${quotes.length}', numericValue: quotes.length, type: 'count'),
          MobileReportKpi(label: 'Nilai Pipeline', formatted: IdrCurrencyFormatter.format(totalVal), numericValue: totalVal, type: 'currency', tone: 'positive'),
        ];
        columns = ['Nomor', 'Pelanggan', 'Status', 'Total'];
        items = quotes.map((q) {
          final tot = (q['grand_total'] as num?)?.toDouble() ?? 0;
          final st = (q['status'] ?? 'draft').toString();
          return MobileReportRowItem(
            title: (q['number'] ?? 'QT').toString(),
            subtitle: (q['customer_name'] ?? 'Pelanggan').toString(),
            badge: st.toUpperCase(),
            badgeTone: st == 'accepted' ? 'positive' : 'warning',
            primaryValue: IdrCurrencyFormatter.format(tot),
            primaryNumeric: tot,
            details: {
              'Nomor': (q['number'] ?? 'QT').toString(),
              'Pelanggan': (q['customer_name'] ?? 'Pelanggan').toString(),
              'Status': st.toUpperCase(),
              'Total': IdrCurrencyFormatter.format(tot),
            },
          );
        }).toList();
        break;

      case 'low-stock':
        final prods = offlineDb.getCachedProducts().where((p) {
          final isService = (p['type'] ?? '').toString().toLowerCase() == 'service';
          final stock = (p['stock'] as num?)?.toDouble() ?? 0;
          final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 5;
          return !isService && stock <= reorder;
        }).toList()
          ..sort((a, b) => ((a['stock'] as num?)?.toDouble() ?? 0).compareTo((b['stock'] as num?)?.toDouble() ?? 0));
        final outOfStock = prods.where((p) => ((p['stock'] as num?)?.toDouble() ?? 0) <= 0).length;
        kpis = [
          MobileReportKpi(label: 'Total SKU Kritis', formatted: '${prods.length}', numericValue: prods.length, type: 'count', tone: prods.isNotEmpty ? 'warning' : 'positive'),
          MobileReportKpi(label: 'Stok Habis / Minus', formatted: '$outOfStock SKU', numericValue: outOfStock, type: 'count', tone: outOfStock > 0 ? 'danger' : 'positive'),
        ];
        columns = ['Produk', 'SKU', 'Stok Tersisa', 'Batas Minimum', 'Harga Modal'];
        items = prods.map((p) {
          final stock = (p['stock'] as num?)?.toDouble() ?? 0;
          final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 5;
          final unit = (p['unit_code'] ?? 'pcs').toString();
          return MobileReportRowItem(
            title: (p['name'] ?? 'Produk').toString(),
            subtitle: 'SKU ${(p['sku'] ?? '-')} • Min ${IdrCurrencyFormatter.formatQty(reorder)} $unit',
            badge: stock <= 0 ? 'HABIS' : 'KRITIS',
            badgeTone: stock <= 0 ? 'danger' : 'warning',
            primaryValue: '${IdrCurrencyFormatter.formatQty(stock)} $unit',
            primaryNumeric: stock,
            details: {
              'Produk': (p['name'] ?? 'Produk').toString(),
              'SKU': (p['sku'] ?? '-').toString(),
              'Stok Tersisa': '${IdrCurrencyFormatter.formatQty(stock)} $unit',
              'Batas Minimum': '${IdrCurrencyFormatter.formatQty(reorder)} $unit',
              'Harga Modal': IdrCurrencyFormatter.format((p['cost_price'] as num?)?.toDouble() ?? 0),
            },
          );
        }).toList();
        break;

      case 'oversold':
        final oversold = offlineDb.getCachedProducts().where((p) {
          final isService = (p['type'] ?? '').toString().toLowerCase() == 'service';
          final stock = (p['stock'] as num?)?.toDouble() ?? 0;
          return !isService && stock < 0;
        }).toList();
        kpis = [
          MobileReportKpi(
            label: 'SKU Saldo Minus',
            formatted: '${oversold.length} SKU',
            numericValue: oversold.length,
            type: 'count',
            tone: oversold.isEmpty ? 'positive' : 'danger',
          ),
        ];
        columns = ['Produk', 'SKU', 'Stok Minus', 'Satuan'];
        items = oversold.map((p) {
          final stock = (p['stock'] as num?)?.toDouble() ?? 0;
          final unit = (p['unit_code'] ?? 'pcs').toString();
          return MobileReportRowItem(
            title: (p['name'] ?? 'Produk').toString(),
            subtitle: 'SKU ${(p['sku'] ?? '-')}',
            badge: 'MINUS',
            badgeTone: 'danger',
            primaryValue: '${IdrCurrencyFormatter.formatQty(stock)} $unit',
            primaryNumeric: stock,
            details: {
              'Produk': (p['name'] ?? 'Produk').toString(),
              'SKU': (p['sku'] ?? '-').toString(),
              'Stok Minus': IdrCurrencyFormatter.formatQty(stock),
              'Satuan': unit,
            },
          );
        }).toList();
        break;

      case 'inventory-valuation':
        final val = Map<String, dynamic>.from((ext['valuation'] as Map?) ?? {});
        final costVal = (val['total_cost_value'] as num?)?.toDouble() ?? 0;
        final retailVal = (val['total_retail_value'] as num?)?.toDouble() ?? 0;
        final pot = (val['potential_profit'] as num?)?.toDouble() ?? 0;
        final skus = (val['skus_in_stock'] as num?)?.toInt() ?? 0;
        kpis = [
          MobileReportKpi(label: 'Nilai Modal (HPP)', formatted: IdrCurrencyFormatter.format(costVal), numericValue: costVal, type: 'currency'),
          MobileReportKpi(label: 'Potensi Nilai Jual', formatted: IdrCurrencyFormatter.format(retailVal), numericValue: retailVal, type: 'currency', tone: 'positive'),
          MobileReportKpi(label: 'Potensi Laba Stok', formatted: IdrCurrencyFormatter.format(pot), numericValue: pot, type: 'currency', tone: 'positive'),
          MobileReportKpi(label: 'SKU Berstok', formatted: '$skus SKU', numericValue: skus, type: 'count'),
        ];
        columns = ['Produk', 'SKU', 'Stok', 'Nilai Modal', 'Nilai Jual'];
        final topItems = (val['top_items'] as List<dynamic>? ?? []);
        items = topItems.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final cv = (m['cost_value'] as num?)?.toDouble() ?? 0;
          final rv = (m['retail_value'] as num?)?.toDouble() ?? 0;
          final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (m['name'] ?? 'Produk').toString(),
            subtitle: 'SKU ${m['sku'] ?? '-'} • Stok ${IdrCurrencyFormatter.formatQty(qty)}',
            primaryValue: IdrCurrencyFormatter.format(cv),
            primaryNumeric: cv,
            secondaryValue: 'Jual ${IdrCurrencyFormatter.format(rv)}',
            details: {
              'Produk': (m['name'] ?? 'Produk').toString(),
              'SKU': (m['sku'] ?? '-').toString(),
              'Stok': IdrCurrencyFormatter.formatQty(qty),
              'Nilai Modal': IdrCurrencyFormatter.format(cv),
              'Nilai Jual': IdrCurrencyFormatter.format(rv),
            },
          );
        }).toList();
        break;

      case 'fast-dead-stock':
        final fast = (ext['fast_stock'] as List<dynamic>? ?? []);
        final dead = (ext['dead_stock'] as List<dynamic>? ?? []);
        kpis = [
          MobileReportKpi(label: 'Produk Laris (30h)', formatted: '${fast.length} SKU', numericValue: fast.length, type: 'count', tone: 'positive'),
          MobileReportKpi(label: 'Dead Stock (0 Terjual)', formatted: '${dead.length} SKU', numericValue: dead.length, type: 'count', tone: dead.isNotEmpty ? 'warning' : 'positive'),
        ];
        columns = ['Produk', 'Kategori Perputaran', 'Qty / Stok', 'Nilai Modal Tertahan'];
        for (final raw in fast) {
          final m = Map<String, dynamic>.from(raw as Map);
          final sold = (m['sold_30d'] as num?)?.toDouble() ?? 0;
          items.add(MobileReportRowItem(
            title: (m['name'] ?? 'Produk').toString(),
            subtitle: 'SKU ${m['sku'] ?? '-'} • Terjual 30 hari',
            badge: 'FAST',
            badgeTone: 'positive',
            primaryValue: '${IdrCurrencyFormatter.formatQty(sold)} terjual',
            primaryNumeric: sold,
            details: {
              'Produk': (m['name'] ?? 'Produk').toString(),
              'Kategori Perputaran': 'Fast Moving',
              'Qty / Stok': IdrCurrencyFormatter.formatQty(sold),
              'Nilai Modal Tertahan': '-',
            },
          ));
        }
        for (final raw in dead) {
          final m = Map<String, dynamic>.from(raw as Map);
          final cv = (m['cost_value'] as num?)?.toDouble() ?? 0;
          final qty = (m['quantity'] as num?)?.toDouble() ?? 0;
          items.add(MobileReportRowItem(
            title: (m['name'] ?? 'Produk').toString(),
            subtitle: 'SKU ${m['sku'] ?? '-'} • Stok ${IdrCurrencyFormatter.formatQty(qty)} (0 penjualan 30h)',
            badge: 'DEAD',
            badgeTone: 'danger',
            primaryValue: IdrCurrencyFormatter.format(cv),
            primaryNumeric: cv,
            details: {
              'Produk': (m['name'] ?? 'Produk').toString(),
              'Kategori Perputaran': 'Dead Stock',
              'Qty / Stok': IdrCurrencyFormatter.formatQty(qty),
              'Nilai Modal Tertahan': IdrCurrencyFormatter.format(cv),
            },
          ));
        }
        break;

      case 'stock-movements':
      case 'stock-adjustments':
        final moves = offlineDb.getLocalStockMovements(
          type: definition.id == 'stock-adjustments' ? 'adjustment' : null,
        );
        kpis = [
          MobileReportKpi(label: 'Total Mutasi Tercatat', formatted: '${moves.length}', numericValue: moves.length, type: 'count'),
        ];
        columns = ['Produk', 'Tipe', 'Delta', 'Stok Akhir', 'Catatan'];
        items = moves.take(80).map((m) {
          final delta = (m['quantity_delta'] as num?)?.toDouble() ?? 0;
          final after = (m['quantity_after'] as num?)?.toDouble() ?? 0;
          final unit = (m['unit_code'] ?? 'pcs').toString();
          return MobileReportRowItem(
            title: (m['product_name'] ?? 'Produk').toString(),
            subtitle: '${(m['type'] ?? '-')} • ${(m['notes'] ?? '-')}',
            badge: delta >= 0 ? 'MASUK' : 'KELUAR',
            badgeTone: delta >= 0 ? 'positive' : 'warning',
            primaryValue: '${delta >= 0 ? '+' : ''}${IdrCurrencyFormatter.formatQty(delta)} $unit',
            primaryNumeric: delta,
            secondaryValue: 'Saldo ${IdrCurrencyFormatter.formatQty(after)} $unit',
            details: {
              'Produk': (m['product_name'] ?? 'Produk').toString(),
              'Tipe': (m['type'] ?? '-').toString(),
              'Delta': '${delta >= 0 ? '+' : ''}${IdrCurrencyFormatter.formatQty(delta)} $unit',
              'Stok Akhir': '${IdrCurrencyFormatter.formatQty(after)} $unit',
              'Catatan': (m['notes'] ?? '-').toString(),
            },
          );
        }).toList();
        break;

      case 'top-customers':
      case 'customer-rfm':
        final list = (ext['top_customers'] as List<dynamic>? ?? []);
        final totalSpent = list.fold<double>(0, (s, c) => s + ((c['total_spent'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Pelanggan Aktif', formatted: '${list.length}', numericValue: list.length, type: 'count'),
          MobileReportKpi(label: 'Total Belanja Member', formatted: IdrCurrencyFormatter.format(totalSpent), numericValue: totalSpent, type: 'currency', tone: 'positive'),
        ];
        columns = ['Pelanggan', 'Telepon', 'Frekuensi', 'Total Belanja'];
        items = list.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final spent = (m['total_spent'] as num?)?.toDouble() ?? 0;
          final cnt = (m['tx_count'] as num?)?.toInt() ?? 0;
          final phone = (m['phone'] ?? '').toString();
          return MobileReportRowItem(
            title: (m['name'] ?? 'Pelanggan').toString(),
            subtitle: '$cnt transaksi • ${phone.isEmpty ? '-' : phone}',
            badge: cnt >= 5 ? 'LOYAL' : (cnt >= 2 ? 'REPEAT' : 'BARU'),
            badgeTone: cnt >= 5 ? 'positive' : 'neutral',
            primaryValue: IdrCurrencyFormatter.format(spent),
            primaryNumeric: spent,
            phone: phone.length >= 8 ? phone : null,
            details: {
              'Pelanggan': (m['name'] ?? 'Pelanggan').toString(),
              'Telepon': phone.isEmpty ? '-' : phone,
              'Frekuensi': '$cnt transaksi',
              'Total Belanja': IdrCurrencyFormatter.format(spent),
            },
          );
        }).toList();
        break;

      case 'aged-receivables':
      case 'customer-ledger':
        final ar = offlineDb.getLocalReceivables();
        final totalAr = ar.fold<double>(0, (s, r) => s + ((r['balance_due'] as num?)?.toDouble() ?? 0));
        final overdueCnt = ar.where((r) => ((r['age_days'] as num?)?.toInt() ?? 0) > 0).length;
        kpis = [
          MobileReportKpi(label: 'Total Piutang Aktif', formatted: IdrCurrencyFormatter.format(totalAr), numericValue: totalAr, type: 'currency', tone: totalAr > 0 ? 'warning' : 'positive'),
          MobileReportKpi(label: 'Nota Belum Lunas', formatted: '${ar.length}', numericValue: ar.length, type: 'count'),
          MobileReportKpi(label: 'Lewat Jatuh Tempo', formatted: '$overdueCnt nota', numericValue: overdueCnt, type: 'count', tone: overdueCnt > 0 ? 'danger' : 'positive'),
        ];
        columns = ['Pelanggan', 'No. Nota', 'Sisa Piutang', 'Jatuh Tempo', 'Umur (Hari)'];
        items = ar.map((r) {
          final bal = (r['balance_due'] as num?)?.toDouble() ?? 0;
          final age = (r['age_days'] as num?)?.toInt() ?? 0;
          final phone = (r['customer_phone'] ?? '').toString();
          return MobileReportRowItem(
            title: (r['customer_name'] ?? 'Pelanggan').toString(),
            subtitle: '${r['invoice_number'] ?? '-'} • Tempo ${r['due_date'] ?? '-'}',
            badge: age > 0 ? 'OVERDUE ${age}H' : 'AKTIF',
            badgeTone: age > 0 ? 'danger' : 'warning',
            primaryValue: IdrCurrencyFormatter.format(bal),
            primaryNumeric: bal,
            phone: phone.length >= 8 ? phone : null,
            details: {
              'Pelanggan': (r['customer_name'] ?? 'Pelanggan').toString(),
              'No. Nota': (r['invoice_number'] ?? '-').toString(),
              'Sisa Piutang': IdrCurrencyFormatter.format(bal),
              'Jatuh Tempo': (r['due_date'] ?? '-').toString(),
              'Umur (Hari)': '$age hari',
            },
          );
        }).toList();
        break;

      case 'loyalty-points':
        final custs = offlineDb.getCachedCustomers()
          ..sort((a, b) => ((b['points_balance'] as num?)?.toDouble() ?? 0)
              .compareTo((a['points_balance'] as num?)?.toDouble() ?? 0));
        final totalPts = custs.fold<double>(0, (s, c) => s + ((c['points_balance'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Total Poin Beredar', formatted: '${totalPts.toStringAsFixed(0)} poin', numericValue: totalPts, type: 'count', tone: 'positive'),
          MobileReportKpi(label: 'Total Member', formatted: '${custs.length}', numericValue: custs.length, type: 'count'),
        ];
        columns = ['Pelanggan', 'Telepon', 'Saldo Poin', 'Deposit'];
        items = custs.take(80).map((c) {
          final pts = (c['points_balance'] as num?)?.toDouble() ?? 0;
          final dep = (c['store_credit_balance'] as num?)?.toDouble() ?? 0;
          final phone = (c['phone'] ?? '').toString();
          return MobileReportRowItem(
            title: (c['name'] ?? 'Pelanggan').toString(),
            subtitle: phone.isEmpty ? 'Member' : phone,
            primaryValue: '${pts.toStringAsFixed(0)} poin',
            primaryNumeric: pts,
            secondaryValue: dep > 0 ? 'Deposit ${IdrCurrencyFormatter.format(dep)}' : null,
            phone: phone.length >= 8 ? phone : null,
            details: {
              'Pelanggan': (c['name'] ?? 'Pelanggan').toString(),
              'Telepon': phone.isEmpty ? '-' : phone,
              'Saldo Poin': '${pts.toStringAsFixed(0)} poin',
              'Deposit': IdrCurrencyFormatter.format(dep),
            },
          );
        }).toList();
        break;

      case 'purchases-report':
        final pos = offlineDb.getLocalPurchases();
        final totalPo = pos.fold<double>(0, (s, p) => s + ((p['grand_total'] as num?)?.toDouble() ?? 0));
        final totalDue = pos.fold<double>(0, (s, p) => s + ((p['balance_due'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Total Pembelian', formatted: IdrCurrencyFormatter.format(totalPo), numericValue: totalPo, type: 'currency'),
          MobileReportKpi(label: 'Sisa Hutang PO', formatted: IdrCurrencyFormatter.format(totalDue), numericValue: totalDue, type: 'currency', tone: totalDue > 0 ? 'warning' : 'positive'),
          MobileReportKpi(label: 'Jumlah Dokumen PO', formatted: '${pos.length}', numericValue: pos.length, type: 'count'),
        ];
        columns = ['No. PO', 'Supplier', 'Tanggal', 'Total', 'Sisa Hutang'];
        items = pos.map((p) {
          final tot = (p['grand_total'] as num?)?.toDouble() ?? 0;
          final due = (p['balance_due'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (p['number'] ?? 'PO').toString(),
            subtitle: '${p['supplier_name'] ?? 'Supplier'} • ${p['purchase_date'] ?? '-'}',
            badge: due <= 0.5 ? 'LUNAS' : 'HUTANG',
            badgeTone: due <= 0.5 ? 'positive' : 'warning',
            primaryValue: IdrCurrencyFormatter.format(tot),
            primaryNumeric: tot,
            secondaryValue: due > 0.5 ? 'Sisa ${IdrCurrencyFormatter.format(due)}' : null,
            details: {
              'No. PO': (p['number'] ?? 'PO').toString(),
              'Supplier': (p['supplier_name'] ?? 'Supplier').toString(),
              'Tanggal': (p['purchase_date'] ?? '-').toString(),
              'Total': IdrCurrencyFormatter.format(tot),
              'Sisa Hutang': IdrCurrencyFormatter.format(due),
            },
          );
        }).toList();
        break;

      case 'purchase-returns':
        final rets = offlineDb.getLocalPurchaseReturns();
        final totalRet = rets.fold<double>(0, (s, r) => s + ((r['grand_total'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Total Retur Beli', formatted: IdrCurrencyFormatter.format(totalRet), numericValue: totalRet, type: 'currency', tone: 'warning'),
          MobileReportKpi(label: 'Jumlah Retur', formatted: '${rets.length}', numericValue: rets.length, type: 'count'),
        ];
        columns = ['No. Retur', 'No. PO', 'Supplier', 'Tanggal', 'Nilai Retur'];
        items = rets.map((r) {
          final tot = (r['grand_total'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (r['number'] ?? 'PR').toString(),
            subtitle: '${r['supplier_name'] ?? 'Supplier'} • ${r['return_date'] ?? '-'}',
            primaryValue: IdrCurrencyFormatter.format(tot),
            primaryNumeric: tot,
            details: {
              'No. Retur': (r['number'] ?? 'PR').toString(),
              'No. PO': (r['purchase_number'] ?? '-').toString(),
              'Supplier': (r['supplier_name'] ?? 'Supplier').toString(),
              'Tanggal': (r['return_date'] ?? '-').toString(),
              'Nilai Retur': IdrCurrencyFormatter.format(tot),
            },
          );
        }).toList();
        break;

      case 'aged-payables':
      case 'supplier-ledger':
      case 'top-suppliers':
        final payables = offlineDb.getLocalPayables();
        final totalAp = payables.fold<double>(0, (s, p) => s + ((p['balance_due'] as num?)?.toDouble() ?? 0));
        final overdue = payables.where((p) => p['is_overdue'] == true).length;
        kpis = [
          MobileReportKpi(label: 'Total Hutang Supplier', formatted: IdrCurrencyFormatter.format(totalAp), numericValue: totalAp, type: 'currency', tone: totalAp > 0 ? 'warning' : 'positive'),
          MobileReportKpi(label: 'Tagihan Terbuka', formatted: '${payables.length}', numericValue: payables.length, type: 'count'),
          MobileReportKpi(label: 'Lewat Tempo', formatted: '$overdue tagihan', numericValue: overdue, type: 'count', tone: overdue > 0 ? 'danger' : 'positive'),
        ];
        columns = ['Supplier', 'Faktur / PO', 'Total Tagihan', 'Sisa Hutang', 'Jatuh Tempo'];
        items = payables.map((p) {
          final due = (p['balance_due'] as num?)?.toDouble() ?? 0;
          final tot = (p['total_amount'] as num?)?.toDouble() ?? 0;
          final sup = p['supplier'] is Map ? Map<String, dynamic>.from(p['supplier'] as Map) : const <String, dynamic>{};
          final supName = (sup['name'] ?? p['supplier_name'] ?? 'Supplier').toString();
          final phone = (sup['phone'] ?? p['supplier_phone'] ?? '').toString();
          return MobileReportRowItem(
            title: supName,
            subtitle: '${p['invoice_number'] ?? '-'} • Tempo ${p['due_date'] ?? '-'}',
            badge: p['is_overdue'] == true ? 'OVERDUE' : (due <= 0.5 ? 'LUNAS' : 'TERBUKA'),
            badgeTone: p['is_overdue'] == true ? 'danger' : (due <= 0.5 ? 'positive' : 'warning'),
            primaryValue: IdrCurrencyFormatter.format(due),
            primaryNumeric: due,
            secondaryValue: 'Total ${IdrCurrencyFormatter.format(tot)}',
            phone: phone.length >= 8 ? phone : null,
            details: {
              'Supplier': supName,
              'Faktur / PO': (p['invoice_number'] ?? '-').toString(),
              'Total Tagihan': IdrCurrencyFormatter.format(tot),
              'Sisa Hutang': IdrCurrencyFormatter.format(due),
              'Jatuh Tempo': (p['due_date'] ?? '-').toString(),
            },
          );
        }).toList();
        break;

      case 'expenses-report':
        final exps = offlineDb.getLocalExpenses();
        final byCat = (ext['expenses_by_category'] as List<dynamic>? ?? []);
        final totalExp = exps.fold<double>(0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Total Pengeluaran', formatted: IdrCurrencyFormatter.format(totalExp), numericValue: totalExp, type: 'currency', tone: 'warning'),
          MobileReportKpi(label: 'Kategori Biaya', formatted: '${byCat.length}', numericValue: byCat.length, type: 'count'),
          MobileReportKpi(label: 'Jumlah Transaksi', formatted: '${exps.length}', numericValue: exps.length, type: 'count'),
        ];
        columns = ['Deskripsi', 'Kategori', 'Metode', 'Tanggal', 'Nominal'];
        items = exps.map((e) {
          final amt = (e['amount'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (e['description'] ?? 'Biaya Operasional').toString(),
            subtitle: '${e['category_name'] ?? 'Operasional'} • ${e['expense_date'] ?? '-'}',
            badge: (e['payment_method'] ?? 'Tunai').toString(),
            primaryValue: IdrCurrencyFormatter.format(amt),
            primaryNumeric: amt,
            details: {
              'Deskripsi': (e['description'] ?? 'Biaya Operasional').toString(),
              'Kategori': (e['category_name'] ?? 'Operasional').toString(),
              'Metode': (e['payment_method'] ?? 'Tunai').toString(),
              'Tanggal': (e['expense_date'] ?? '-').toString(),
              'Nominal': IdrCurrencyFormatter.format(amt),
            },
          );
        }).toList();
        break;

      case 'cash-flow':
        final ledger = offlineDb.computeLocalCashLedger();
        final summary = Map<String, dynamic>.from((ledger['summary'] as Map?) ?? {});
        final totalIn = (summary['total_in'] as num?)?.toDouble() ?? 0;
        final totalOut = (summary['total_out'] as num?)?.toDouble() ?? 0;
        final netCash = (summary['net_cash_flow'] as num?)?.toDouble() ?? 0;
        final cashBal = (summary['cash_balance'] as num?)?.toDouble() ?? 0;
        kpis = [
          MobileReportKpi(label: 'Arus Kas Masuk', formatted: IdrCurrencyFormatter.format(totalIn), numericValue: totalIn, type: 'currency', tone: 'positive'),
          MobileReportKpi(label: 'Arus Kas Keluar', formatted: IdrCurrencyFormatter.format(totalOut), numericValue: totalOut, type: 'currency', tone: 'warning'),
          MobileReportKpi(label: 'Arus Kas Bersih', formatted: IdrCurrencyFormatter.format(netCash), numericValue: netCash, type: 'currency', tone: netCash >= 0 ? 'positive' : 'danger'),
          MobileReportKpi(label: 'Saldo Laci Tunai', formatted: IdrCurrencyFormatter.format(cashBal), numericValue: cashBal, type: 'currency'),
        ];
        columns = ['Transaksi', 'Kategori', 'Arah', 'Kanal', 'Nominal'];
        final entries = (ledger['entries'] as List<dynamic>? ?? []);
        items = entries.map((raw) {
          final e = Map<String, dynamic>.from(raw as Map);
          final amt = (e['amount'] as num?)?.toDouble() ?? 0;
          final isIn = e['direction'] == 'in';
          return MobileReportRowItem(
            title: (e['title'] ?? 'Mutasi Kas').toString(),
            subtitle: '${e['category'] ?? '-'} • ${e['method_name'] ?? '-'}',
            badge: isIn ? 'MASUK' : 'KELUAR',
            badgeTone: isIn ? 'positive' : 'danger',
            primaryValue: '${isIn ? '+' : '-'}${IdrCurrencyFormatter.format(amt)}',
            primaryNumeric: isIn ? amt : -amt,
            details: {
              'Transaksi': (e['title'] ?? 'Mutasi Kas').toString(),
              'Kategori': (e['category'] ?? '-').toString(),
              'Arah': isIn ? 'Kas Masuk' : 'Kas Keluar',
              'Kanal': (e['method_name'] ?? '-').toString(),
              'Nominal': IdrCurrencyFormatter.format(amt),
            },
          );
        }).toList();
        break;

      case 'shifts-by-cashier':
        final shifts = offlineDb.getLocalShiftsHistory();
        final varianceCnt = shifts.where((s) => (((s['variance'] as num?)?.toDouble() ?? 0).abs()) > 100).length;
        kpis = [
          MobileReportKpi(label: 'Total Shift Tercatat', formatted: '${shifts.length}', numericValue: shifts.length, type: 'count'),
          MobileReportKpi(label: 'Shift Berselisih', formatted: '$varianceCnt', numericValue: varianceCnt, type: 'count', tone: varianceCnt > 0 ? 'danger' : 'positive'),
        ];
        columns = ['No. Shift', 'Kasir', 'Status', 'Kas Ekspektasi', 'Selisih'];
        items = shifts.map((sh) {
          final exp = (sh['expected_cash'] as num?)?.toDouble() ?? 0;
          final v = (sh['variance'] as num?)?.toDouble() ?? 0;
          final st = (sh['status'] ?? 'open').toString();
          return MobileReportRowItem(
            title: (sh['shift_number'] ?? 'SHIFT').toString(),
            subtitle: '${sh['cashier_name'] ?? 'Kasir'} • ${(sh['opened_at'] ?? '').toString().split('T').first}',
            badge: st == 'open' ? 'AKTIF' : (v.abs() > 100 ? 'SELISIH' : 'KLOP'),
            badgeTone: st == 'open' ? 'warning' : (v.abs() > 100 ? 'danger' : 'positive'),
            primaryValue: IdrCurrencyFormatter.format(exp),
            primaryNumeric: exp,
            secondaryValue: st == 'closed' ? 'Selisih ${IdrCurrencyFormatter.format(v)}' : null,
            details: {
              'No. Shift': (sh['shift_number'] ?? 'SHIFT').toString(),
              'Kasir': (sh['cashier_name'] ?? 'Kasir').toString(),
              'Status': st.toUpperCase(),
              'Kas Ekspektasi': IdrCurrencyFormatter.format(exp),
              'Selisih': IdrCurrencyFormatter.format(v),
            },
          );
        }).toList();
        break;

      case 'void-refund-audit':
        final list = (ext['void_refund_list'] as List<dynamic>? ?? []);
        final totalVoid = list.fold<double>(0, (s, e) => s + ((e['grand_total'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Nota Void / Refund', formatted: '${list.length}', numericValue: list.length, type: 'count', tone: list.isNotEmpty ? 'danger' : 'positive'),
          MobileReportKpi(label: 'Total Nilai Dibatalkan', formatted: IdrCurrencyFormatter.format(totalVoid), numericValue: totalVoid, type: 'currency', tone: totalVoid > 0 ? 'danger' : 'positive'),
        ];
        columns = ['No. Nota', 'Status', 'Kasir', 'Alasan', 'Nominal'];
        items = list.map((raw) {
          final m = Map<String, dynamic>.from(raw as Map);
          final amt = (m['grand_total'] as num?)?.toDouble() ?? 0;
          final st = (m['status'] ?? 'voided').toString();
          return MobileReportRowItem(
            title: (m['number'] ?? '-').toString(),
            subtitle: '${m['cashier_name'] ?? 'Kasir'} • ${m['reason'] ?? '-'}',
            badge: st.toUpperCase(),
            badgeTone: 'danger',
            primaryValue: IdrCurrencyFormatter.format(amt),
            primaryNumeric: amt,
            details: {
              'No. Nota': (m['number'] ?? '-').toString(),
              'Status': st.toUpperCase(),
              'Kasir': (m['cashier_name'] ?? 'Kasir').toString(),
              'Alasan': (m['reason'] ?? '-').toString(),
              'Nominal': IdrCurrencyFormatter.format(amt),
            },
          );
        }).toList();
        break;

      case 'discounts':
        final sales = _filterLocalSales(range.start, range.end)
            .where((s) => ((s['discount_total'] as num?)?.toDouble() ?? 0) > 0)
            .toList();
        final totalDisc = sales.fold<double>(0, (sum, s) => sum + ((s['discount_total'] as num?)?.toDouble() ?? 0));
        kpis = [
          MobileReportKpi(label: 'Total Diskon Diberikan', formatted: IdrCurrencyFormatter.format(totalDisc), numericValue: totalDisc, type: 'currency', tone: 'warning'),
          MobileReportKpi(label: 'Nota Berdiskon', formatted: '${sales.length}', numericValue: sales.length, type: 'count'),
        ];
        columns = ['No. Nota', 'Kasir', 'Diskon', 'Grand Total'];
        items = sales.map((s) {
          final disc = (s['discount_total'] as num?)?.toDouble() ?? 0;
          final grand = (s['grand_total'] as num?)?.toDouble() ?? 0;
          return MobileReportRowItem(
            title: (s['number'] ?? '#INV').toString(),
            subtitle: '${s['cashier_name'] ?? 'Kasir'} • Total ${IdrCurrencyFormatter.format(grand)}',
            badge: 'DISKON',
            badgeTone: 'warning',
            primaryValue: IdrCurrencyFormatter.format(disc),
            primaryNumeric: disc,
            details: {
              'No. Nota': (s['number'] ?? '#INV').toString(),
              'Kasir': (s['cashier_name'] ?? 'Kasir').toString(),
              'Diskon': IdrCurrencyFormatter.format(disc),
              'Grand Total': IdrCurrencyFormatter.format(grand),
            },
          );
        }).toList();
        break;

      case 'profit-and-loss':
        final netSales = (base['net_sales'] as num?)?.toDouble() ?? 0;
        final cogs = (base['total_cogs'] as num?)?.toDouble() ?? 0;
        final grossP = (base['gross_profit'] as num?)?.toDouble() ?? 0;
        final expenses = (base['store_expenses'] as num?)?.toDouble() ?? 0;
        final netP = (base['net_profit'] as num?)?.toDouble() ?? 0;
        final margin = (base['profit_margin'] as num?)?.toDouble() ?? 0;
        kpis = [
          MobileReportKpi(label: 'Pendapatan Bersih', formatted: IdrCurrencyFormatter.format(netSales), numericValue: netSales, type: 'currency'),
          MobileReportKpi(label: 'Laba Kotor', formatted: IdrCurrencyFormatter.format(grossP), numericValue: grossP, type: 'currency', tone: 'positive'),
          MobileReportKpi(label: 'Beban Operasional', formatted: IdrCurrencyFormatter.format(expenses), numericValue: expenses, type: 'currency', tone: 'warning'),
          MobileReportKpi(label: 'Laba Bersih', formatted: IdrCurrencyFormatter.format(netP), numericValue: netP, type: 'currency', tone: netP >= 0 ? 'positive' : 'danger'),
        ];
        columns = ['Pos Laba Rugi', 'Nominal', 'Keterangan'];
        items = [
          MobileReportRowItem(title: 'Pendapatan Penjualan Bersih', primaryValue: IdrCurrencyFormatter.format(netSales), primaryNumeric: netSales, details: {'Pos Laba Rugi': 'Pendapatan Penjualan Bersih', 'Nominal': IdrCurrencyFormatter.format(netSales), 'Keterangan': 'Data POS lokal'}),
          MobileReportRowItem(title: 'Harga Pokok Penjualan (HPP / COGS)', primaryValue: '-${IdrCurrencyFormatter.format(cogs)}', primaryNumeric: -cogs, details: {'Pos Laba Rugi': 'HPP / COGS', 'Nominal': IdrCurrencyFormatter.format(cogs), 'Keterangan': 'Estimasi modal produk'}),
          MobileReportRowItem(title: 'Laba Kotor (Gross Profit)', isTotal: true, primaryValue: IdrCurrencyFormatter.format(grossP), primaryNumeric: grossP, details: {'Pos Laba Rugi': 'Laba Kotor', 'Nominal': IdrCurrencyFormatter.format(grossP), 'Keterangan': 'Pendapatan - HPP'}),
          MobileReportRowItem(title: 'Total Beban Operasional Toko', primaryValue: '-${IdrCurrencyFormatter.format(expenses)}', primaryNumeric: -expenses, details: {'Pos Laba Rugi': 'Beban Operasional', 'Nominal': IdrCurrencyFormatter.format(expenses), 'Keterangan': 'Buku pengeluaran lokal'}),
          MobileReportRowItem(title: 'Laba Bersih Operasional (Net Profit)', isTotal: true, badge: '${margin.toStringAsFixed(1)}%', badgeTone: netP >= 0 ? 'positive' : 'danger', primaryValue: IdrCurrencyFormatter.format(netP), primaryNumeric: netP, details: {'Pos Laba Rugi': 'Laba Bersih', 'Nominal': IdrCurrencyFormatter.format(netP), 'Keterangan': 'Margin ${margin.toStringAsFixed(1)}%'}),
        ];
        break;

      default:
        offlineNotice =
            'Laporan "${definition.title}" membutuhkan agregasi langsung dari server OXORA Cloud (Buku Besar / Multi-Cabang / Pajak). Hubungkan perangkat ke internet atau LAN Edge untuk menarik data lengkap.';
        kpis = [
          MobileReportKpi(
            label: 'Omzet Lokal Tersimpan',
            formatted: IdrCurrencyFormatter.format((base['net_sales'] as num?)?.toDouble() ?? 0),
            type: 'currency',
          ),
          MobileReportKpi(
            label: 'Status Sinkronisasi',
            formatted: 'Mode Offline',
            tone: 'warning',
          ),
        ];
        break;
    }

    if (search.trim().isNotEmpty) {
      items = items.where((i) => i.matchesSearch(search)).toList();
    }

    final wa = buildWhatsAppSummary(
      definition: definition,
      storeLabel: storeLabel,
      periodLabel: range.label,
      kpis: kpis,
      items: items,
      isOfflineData: true,
      lastSyncLabel: lastSync,
    );

    final draftPayload = MobileReportPayload(
      reportId: definition.id,
      title: definition.title,
      subtitle: definition.subtitle,
      dateMode: definition.dateMode,
      storeLabel: storeLabel,
      periodLabel: range.label,
      startDate: startStr,
      endDate: endStr,
      kpis: kpis,
      columns: columns,
      items: items,
      totalRows: items.length,
      whatsappSummary: wa,
      csvContent: '',
      isOfflineData: true,
      lastSyncLabel: lastSync,
      offlineNotice: offlineNotice,
    );

    return MobileReportPayload(
      reportId: draftPayload.reportId,
      title: draftPayload.title,
      subtitle: draftPayload.subtitle,
      dateMode: draftPayload.dateMode,
      storeLabel: draftPayload.storeLabel,
      periodLabel: draftPayload.periodLabel,
      startDate: draftPayload.startDate,
      endDate: draftPayload.endDate,
      kpis: draftPayload.kpis,
      columns: draftPayload.columns,
      items: draftPayload.items,
      totalRows: draftPayload.totalRows,
      whatsappSummary: draftPayload.whatsappSummary,
      csvContent: buildCsvFromPayload(draftPayload),
      isOfflineData: true,
      lastSyncLabel: lastSync,
      offlineNotice: offlineNotice,
    );
  }

  List<Map<String, dynamic>> _filterLocalSales(DateTime start, DateTime end) {
    final result = <Map<String, dynamic>>[];
    for (final s in offlineDb.getLocalSalesHistory()) {
      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided' || status == 'refunded') continue;
      final rawDate = (s['created_at'] ?? s['sale_datetime'] ?? '').toString();
      final dt = DateTime.tryParse(rawDate);
      if (dt != null) {
        if (dt.isBefore(start) || dt.isAfter(end)) continue;
      }
      result.add(s);
    }
    return result;
  }
}
