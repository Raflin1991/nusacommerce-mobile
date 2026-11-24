part of 'offline_database.dart';

extension OfflineDatabaseReportsNumberingExt on OfflineDatabase {
  // ===========================================================================
  // 10. LOCAL BUSINESS REPORT & REAL-TIME PROFIT CALCULATION ENGINE
  // ===========================================================================
  Map<String, dynamic> computeLocalBusinessReport({
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final products = getCachedProducts();
    final costById = <int, double>{};
    int lowStockCount = 0;
    for (final p in products) {
      final pid = (p['id'] as num?)?.toInt();
      if (pid != null) {
        costById[pid] = (p['cost_price'] as num?)?.toDouble() ?? 0.0;
      }
      final stock = (p['stock'] as num?)?.toDouble() ?? 0.0;
      final reorder = (p['reorder_level'] as num?)?.toDouble() ?? 5.0;
      final isService = (p['type'] ?? '').toString().toLowerCase() == 'service';
      if (!isService && stock <= reorder) {
        lowStockCount++;
      }
    }

    final sales = getLocalSalesHistory();
    double grossSales = 0.0;
    double netSales = 0.0;
    double discountTotal = 0.0;
    double totalCogs = 0.0;
    int txCount = 0;
    int voidCount = 0;
    int refundCount = 0;

    final paymentTotals = <String, double>{};
    final paymentCounts = <String, int>{};
    final productStats = <String, Map<String, dynamic>>{};
    final dailyMap = <String, Map<String, dynamic>>{};

    for (final s in sales) {
      final saleDt = _parseFlexDateTime(s['created_at'] ?? s['sale_datetime']);
      if (saleDt != null) {
        if (startDate != null && saleDt.isBefore(startDate)) continue;
        if (endDate != null && saleDt.isAfter(endDate)) continue;
      }

      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided') {
        voidCount++;
        continue;
      }
      if (status == 'refunded') {
        refundCount++;
        continue;
      }

      txCount++;
      final saleGrandTotal = (s['grand_total'] as num?)?.toDouble() ?? 0.0;
      final saleDiscount = (s['discount_total'] as num?)?.toDouble() ?? 0.0;
      final saleSubtotal = (s['subtotal'] as num?)?.toDouble() ?? (saleGrandTotal + saleDiscount);

      grossSales += saleSubtotal;
      netSales += saleGrandTotal;
      discountTotal += saleDiscount;

      // Daily trend grouping
      final dayKey = saleDt != null
          ? '${saleDt.year}-${saleDt.month.toString().padLeft(2, '0')}-${saleDt.day.toString().padLeft(2, '0')}'
          : DateTime.now().toIso8601String().split('T').first;
      final parts = dayKey.split('-');
      final dayLabel = parts.length == 3 ? '${parts[2]}/${parts[1]}' : dayKey;
      dailyMap.putIfAbsent(
        dayKey,
        () => {'date': dayKey, 'day_label': dayLabel, 'revenue': 0.0, 'transactions': 0},
      );
      dailyMap[dayKey]!['revenue'] = ((dailyMap[dayKey]!['revenue'] as double?) ?? 0.0) + saleGrandTotal;
      dailyMap[dayKey]!['transactions'] = ((dailyMap[dayKey]!['transactions'] as int?) ?? 0) + 1;

      // Payment breakdown
      final payments = s['payments'];
      if (payments is List && payments.isNotEmpty) {
        final changeReturned = (s['change_returned'] as num?)?.toDouble() ?? 0.0;
        for (int i = 0; i < payments.length; i++) {
          final p = payments[i];
          if (p is! Map) continue;
          final method = (p['method_name'] ?? p['payment_method_name'] ?? p['name'] ?? 'Tunai').toString();
          var amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          if (i == 0 && changeReturned > 0 && method.toLowerCase().contains('tunai')) {
            amt = (amt - changeReturned).clamp(0.0, double.infinity);
          }
          paymentTotals[method] = (paymentTotals[method] ?? 0.0) + amt;
          paymentCounts[method] = (paymentCounts[method] ?? 0) + 1;
        }
        final balDue = (s['balance_due'] as num?)?.toDouble() ?? 0.0;
        if (balDue > 0.5) {
          paymentTotals['Kasbon'] = (paymentTotals['Kasbon'] ?? 0.0) + balDue;
          paymentCounts['Kasbon'] = (paymentCounts['Kasbon'] ?? 0) + 1;
        }
      } else {
        final methods = s['payment_methods'] as List?;
        final label = (methods != null && methods.isNotEmpty) ? methods.first.toString() : 'Tunai';
        paymentTotals[label] = (paymentTotals[label] ?? 0.0) + saleGrandTotal;
        paymentCounts[label] = (paymentCounts[label] ?? 0) + 1;
      }

      // Items COGS & Top Products
      final items = s['items'] as List? ?? [];
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        if (rawItem['is_exchange_return'] == true) continue;
        final pid = (rawItem['product_id'] as num?)?.toInt();
        final pName = (rawItem['product_name'] ?? 'Produk').toString();
        final qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0.0;
        final mult = (rawItem['multiplier'] as num?)?.toDouble() ?? 1.0;
        final lineTotal = (rawItem['line_total'] as num?)?.toDouble() ?? 0.0;
        final itemCost = (rawItem['cost_price'] as num?)?.toDouble() ?? (pid != null ? (costById[pid] ?? 0.0) : 0.0);
        final lineCogs = qty * mult * itemCost;
        totalCogs += lineCogs;

        productStats.putIfAbsent(
          pName,
          () => {'name': pName, 'qty': 0.0, 'revenue': 0.0, 'profit': 0.0},
        );
        productStats[pName]!['qty'] = ((productStats[pName]!['qty'] as double?) ?? 0.0) + qty;
        productStats[pName]!['revenue'] = ((productStats[pName]!['revenue'] as double?) ?? 0.0) + lineTotal;
        productStats[pName]!['profit'] =
            ((productStats[pName]!['profit'] as double?) ?? 0.0) + (lineTotal - lineCogs);
      }
    }

    // Store Expenses from local_expenses
    double storeExpenses = 0.0;
    for (final e in getLocalExpenses()) {
      final dt = _parseFlexDateTime(e['created_at'] ?? e['expense_date']);
      if (dt != null) {
        if (startDate != null && dt.isBefore(startDate)) continue;
        if (endDate != null && dt.isAfter(endDate)) continue;
      }
      storeExpenses += (e['amount'] as num?)?.toDouble() ?? 0.0;
    }

    // Shifts Anti-Fraud metrics & standalone shift payouts
    int varianceShiftsCount = 0;
    int noSaleOpensCount = 0;
    for (final sh in getLocalShiftsHistory()) {
      final variance = (sh['variance'] as num?)?.toDouble() ?? 0.0;
      if ((sh['status'] ?? '').toString().toLowerCase() == 'closed' && variance.abs() > 100.0) {
        varianceShiftsCount++;
      }
      noSaleOpensCount += (sh['no_sale_opens_count'] as num?)?.toInt() ?? 0;
    }

    final grossProfit = netSales - totalCogs;
    final netProfit = grossProfit - storeExpenses;
    final profitMargin = netSales > 0 ? (netProfit / netSales) * 100.0 : 0.0;

    final topProducts = productStats.values.toList()
      ..sort((a, b) => ((b['revenue'] as double?) ?? 0.0).compareTo((a['revenue'] as double?) ?? 0.0));

    final paymentBreakdown = paymentTotals.entries
        .map((e) => {
              'method': e.key,
              'amount': e.value,
              'count': paymentCounts[e.key] ?? 1,
            })
        .toList()
      ..sort((a, b) => ((b['amount'] as double?) ?? 0.0).compareTo((a['amount'] as double?) ?? 0.0));

    final dailyTrend = dailyMap.values.toList()
      ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));

    final totalReceivables = getLocalReceivables().fold<double>(
      0.0,
      (sum, r) => sum + ((r['balance_due'] as num?)?.toDouble() ?? 0.0),
    );
    final totalPayables = getLocalPayables()
        .where((p) => ((p['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .fold<double>(
          0.0,
          (sum, p) => sum + ((p['balance_due'] as num?)?.toDouble() ?? 0.0),
        );

    return {
      'gross_sales': grossSales,
      'net_sales': netSales,
      'discount_total': discountTotal,
      'transactions_count': txCount,
      'average_basket': txCount > 0 ? (netSales / txCount) : 0.0,
      'total_cogs': totalCogs,
      'gross_profit': grossProfit,
      'store_expenses': storeExpenses,
      'net_profit': netProfit,
      'profit_margin': profitMargin,
      'total_receivables': totalReceivables,
      'total_payables': totalPayables,
      'low_stock_count': lowStockCount,
      'payment_breakdown': paymentBreakdown,
      'top_products': topProducts.take(10).toList(),
      'daily_trend': dailyTrend.take(7).toList(),
      'fraud_indicators': {
        'void_count': voidCount,
        'refund_count': refundCount,
        'variance_shifts_count': varianceShiftsCount,
        'no_sale_opens_count': noSaleOpensCount,
      },
    };
  }

  /// Cache Cloud-synced custom ERP document numbering formats locally for offline rendering.
  Future<void> cacheNumberingFormats(Map<String, dynamic> formats) async {
    await _prefs.setString(OfflineDatabase._keyNumberingFormats, jsonEncode(formats));
  }

  Map<String, dynamic> getCachedNumberingFormats() {
    final raw = _prefs.getString(OfflineDatabase._keyNumberingFormats);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return const {};
  }

  /// Resolve the explicitly customized numbering template for [docType], if any.
  String? getCustomNumberFormat(String docType) {
    final formats = getCachedNumberingFormats();
    final customMap = formats['_custom'];
    if (customMap is Map && customMap[docType] is String) {
      final val = (customMap[docType] as String).trim();
      if (val.isNotEmpty) return val;
    }
    return null;
  }


  /// Generates collision-free Tier-3 Mobile fallback document numbers partitioned
  /// by unique per-device mobile node code (e.g. `M01`..`M99` or auto `M4F9A`),
  /// honoring Cloud-synced custom formats with automatic `{node}` injection when offline.
  Future<String> generatePartitionedFallbackNumber({
    required String storeCode,
    String docPrefix = 'INV',
    String? docType,
    String? customFormat,
    String? nodeCode,
    DateTime? now,
    int maxLength = 32,
  }) async {
    final ts = now ?? DateTime.now();
    final cleanStore = storeCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final rawStoreSeg = cleanStore.isEmpty ? 'STORE' : cleanStore;
    final storeSeg = rawStoreSeg.length > 6 ? rawStoreSeg.substring(0, 6) : rawStoreSeg;

    String? resolvedNode = nodeCode ?? _prefs.getString('nusa_mobile_node_code');
    if (resolvedNode == null || resolvedNode.trim().isEmpty) {
      final hex4 = _uuid.v4().replaceAll('-', '').substring(0, 4).toUpperCase();
      resolvedNode = 'M$hex4';
      await _prefs.setString('nusa_mobile_node_code', resolvedNode);
    }
    final cleanNode = resolvedNode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final rawNodeSeg = cleanNode.isEmpty ? 'M01' : cleanNode;
    final nodeSeg = rawNodeSeg.length > 6 ? rawNodeSeg.substring(0, 6) : rawNodeSeg;

    final resolvedCustom = (customFormat != null && customFormat.trim().isNotEmpty)
        ? customFormat.trim()
        : (docType != null ? getCustomNumberFormat(docType) : null);

    if (resolvedCustom != null && resolvedCustom.isNotEmpty) {
      final periodKey = resolvedCustom.contains('{Ymd}')
          ? '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}'
          : resolvedCustom.contains('{Ym}')
              ? '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}'
              : (resolvedCustom.contains('{Y}') || resolvedCustom.contains('{y}'))
                  ? ts.year.toString().padLeft(4, '0')
                  : 'ALL';
      final keyType = (docType ?? docPrefix).trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final seqKey = 'nusa_edge_seq_${storeSeg}_${nodeSeg}_${keyType}_$periodKey';
      final nextSeq = (_prefs.getInt(seqKey) ?? 0) + 1;
      await _prefs.setInt(seqKey, nextSeq);

      return OfflineDatabase.renderNumberFormat(
        template: resolvedCustom,
        storeCode: storeSeg,
        nodeCode: nodeSeg,
        seq: nextSeq,
        now: ts,
        enforceOfflineNode: true,
        maxLength: maxLength,
      );
    }

    final cleanDoc = docPrefix.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final rawDocSeg = cleanDoc.isEmpty ? 'INV' : cleanDoc;
    final docSeg = rawDocSeg.length > 3 ? rawDocSeg.substring(0, 3) : rawDocSeg;

    final ym = '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}';
    final seqKey = 'nusa_edge_seq_${storeSeg}_${nodeSeg}_${docSeg}_$ym';
    final nextSeq = (_prefs.getInt(seqKey) ?? 0) + 1;
    await _prefs.setInt(seqKey, nextSeq);

    return '$docSeg-$storeSeg-$nodeSeg-$ym-${nextSeq.toString().padLeft(5, '0')}';
  }
}
