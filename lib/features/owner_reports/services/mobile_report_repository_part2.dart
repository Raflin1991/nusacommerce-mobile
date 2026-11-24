// ignore_for_file: invalid_use_of_protected_member
part of 'mobile_report_repository.dart';

extension MobileReportRepositoryPart2Ext on MobileReportRepository {


  ({
    List<MobileReportKpi> kpis,
    List<String> columns,
    List<MobileReportRowItem> items,
    String? offlineNotice,
  }) _buildLocalInventoryAndFinanceSection({
    required MobileReportDefinition definition,
    required ({DateTime start, DateTime end, String label}) range,
    required Map<String, dynamic> base,
    required Map<String, dynamic> ext,
  }) {
    List<MobileReportKpi> kpis = [];
    List<String> columns = [];
    List<MobileReportRowItem> items = [];
    String? offlineNotice;

    switch (definition.id) {
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
    return (kpis: kpis, columns: columns, items: items, offlineNotice: offlineNotice);
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
