// ignore_for_file: invalid_use_of_protected_member
part of 'mobile_report_repository.dart';

extension MobileReportRepositoryPart1Ext on MobileReportRepository {

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
    final range = MobileReportRepository.resolveDateRange(
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
        : MobileReportRepository.buildCsvFromPayload(payload);
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

      default:
        final sec = _buildLocalInventoryAndFinanceSection(
          definition: definition,
          range: range,
          base: base,
          ext: ext,
        );
        kpis = sec.kpis;
        columns = sec.columns;
        items = sec.items;
        offlineNotice = sec.offlineNotice;
        break;
    }

    if (search.trim().isNotEmpty) {
      items = items.where((i) => i.matchesSearch(search)).toList();
    }

    final wa = MobileReportRepository.buildWhatsAppSummary(
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
      csvContent: MobileReportRepository.buildCsvFromPayload(draftPayload),
      isOfflineData: true,
      lastSyncLabel: lastSync,
      offlineNotice: offlineNotice,
    );
  }
}
