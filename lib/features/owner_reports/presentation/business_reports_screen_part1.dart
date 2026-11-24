// ignore_for_file: invalid_use_of_protected_member
part of 'business_reports_screen.dart';

extension _BusinessReportsScreenStatePart1Ext on _BusinessReportsScreenState {

  (DateTime?, DateTime?) _resolveLocalDateRange() {
    final info = MobileReportRepository.resolveDateRange(
      _periodKey,
      customStart: _customStartDate,
      customEnd: _customEndDate,
    );
    return (info.start, info.end);
  }


  void _applyLocalReport() {
    final (start, end) = _resolveLocalDateRange();
    final report =
        _offlineDb.computeLocalBusinessReport(startDate: start, endDate: end);
    final fraud =
        Map<String, dynamic>.from((report['fraud_indicators'] as Map?) ?? {});
    final trend = (report['daily_trend'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!mounted) return;
    setState(() {
      _isOfflineMode = true;
      _profitVisible = true;
      _netSales = (report['net_sales'] as num?)?.toDouble() ?? 0;
      _grossProfit = (report['gross_profit'] as num?)?.toDouble() ?? 0;
      _netProfit = (report['net_profit'] as num?)?.toDouble() ?? 0;
      _marginPercent = (report['profit_margin'] as num?)?.toDouble() ?? 0;
      _expensesTotal = (report['store_expenses'] as num?)?.toDouble() ?? 0;
      _growthPercent = 0;
      _transactionsCount = (report['transactions_count'] as num?)?.toInt() ?? 0;
      _receivablesTotal =
          (report['total_receivables'] as num?)?.toDouble() ?? 0;
      _payablesTotal = (report['total_payables'] as num?)?.toDouble() ?? 0;
      _voidCount = (fraud['void_count'] as num?)?.toInt() ?? 0;
      _refundCount = (fraud['refund_count'] as num?)?.toInt() ?? 0;
      _varianceShiftsCount =
          (fraud['variance_shifts_count'] as num?)?.toInt() ?? 0;
      _noSaleOpensCount = (fraud['no_sale_opens_count'] as num?)?.toInt() ?? 0;
      _trend7d = trend;
      _error = null;
      _loading = false;
    });
  }


  Future<void> _fetchReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final authSession = context.read<AuthCubit>().state.session;
    if (authSession.isLocalTrial || !(await _connectivity.checkOnline())) {
      _applyLocalReport();
      return;
    }

    final params = <String, dynamic>{
      'period': _periodKey,
      'store_id': _selectedStoreScope,
    };
    if (_periodKey == 'custom' &&
        _customStartDate != null &&
        _customEndDate != null) {
      params['start_date'] = DateFormat('yyyy-MM-dd').format(_customStartDate!);
      params['end_date'] = DateFormat('yyyy-MM-dd').format(_customEndDate!);
    }

    // Load store scopes in parallel without blocking KPI error surfacing
    _loadStoreCatalogSilently();

    try {
      final res = await _backofficeRepo.fetchOwnerDashboard(params);

      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final filter =
          Map<String, dynamic>.from((data['filter'] as Map?) ?? {});
      final kpi = Map<String, dynamic>.from((data['kpi'] as Map?) ?? {});
      final alerts = Map<String, dynamic>.from(
          (data['operational_alerts'] as Map?) ?? {});
      final antiFraud = Map<String, dynamic>.from(
          (data['anti_fraud_summary'] as Map?) ?? {});
      final trend = (data['sales_trend_7d'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final branches = (data['branch_comparison'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _isOfflineMode = false;
        _profitVisible = filter['profit_visible'] == true;
        _netSales = (kpi['net_sales'] as num?)?.toDouble() ?? 0;
        _grossProfit = (kpi['gross_profit'] as num?)?.toDouble() ?? 0;
        _netProfit = (kpi['net_profit'] as num?)?.toDouble() ?? 0;
        _marginPercent = (kpi['margin_percent'] as num?)?.toDouble() ?? 0;
        _expensesTotal = (kpi['expenses_total'] as num?)?.toDouble() ?? 0;
        _growthPercent =
            (kpi['growth_vs_yesterday_percent'] as num?)?.toDouble() ?? 0;
        _transactionsCount = (kpi['transactions_count'] as num?)?.toInt() ?? 0;
        _receivablesTotal =
            (alerts['receivables_total'] as num?)?.toDouble() ?? 0;
        _payablesTotal = (alerts['payables_total'] as num?)?.toDouble() ?? 0;
        _voidCount = (antiFraud['voided_sales_count'] as num?)?.toInt() ?? 0;
        _refundCount = (antiFraud['refunds_count'] as num?)?.toInt() ?? 0;
        _varianceShiftsCount =
            (antiFraud['shift_variance_alerts_count'] as num?)?.toInt() ?? 0;
        _noSaleOpensCount =
            (antiFraud['no_sale_drawer_opens_count'] as num?)?.toInt() ?? 0;
        _trend7d = trend;
        if (branches.isNotEmpty) {
          _availableStores = branches
              .map((b) => {
                    'id': b['store_id'],
                    'name': b['store_name'],
                  })
              .toList();
        }
        _loading = false;
      });
    } catch (e) {
      try {
        final summaryRes = await _backofficeRepo.fetchSalesSummary(params);
        final summaryData =
            Map<String, dynamic>.from((summaryRes.data['data'] as Map?) ?? {});
        final summary =
            Map<String, dynamic>.from((summaryData['summary'] as Map?) ?? {});
        final dailyBreakdown =
            (summaryData['daily_breakdown'] as List<dynamic>? ?? [])
                .map((el) => Map<String, dynamic>.from(el as Map))
                .toList();

        if (!mounted) return;
        setState(() {
          _isOfflineMode = false;
          _profitVisible = false;
          _netSales = (summary['net_sales'] as num?)?.toDouble() ?? 0;
          _grossProfit = 0;
          _netProfit = 0;
          _marginPercent = 0;
          _expensesTotal = 0;
          _growthPercent = 0;
          _transactionsCount =
              (summary['transactions_count'] as num?)?.toInt() ?? 0;
          _receivablesTotal = 0;
          _payablesTotal = 0;
          _voidCount = (summary['void_count'] as num?)?.toInt() ?? 0;
          _refundCount = (summary['refund_count'] as num?)?.toInt() ?? 0;
          _varianceShiftsCount = 0;
          _noSaleOpensCount = 0;
          _trend7d = dailyBreakdown;
          _loading = false;
        });
      } catch (fallbackErr) {
        final isOffline = ApiClient.isNetworkOfflineError(e) ||
            ApiClient.isNetworkOfflineError(fallbackErr);
        // STRICT SECURITY CONTRACT: Only fallback to local data on genuine network outage,
        // NEVER mask HTTP 401/403/422/500 permission or validation rejections!
        if (isOffline) {
          _applyLocalReport();
          return;
        }
        if (!mounted) return;
        setState(() {
          _isOfflineMode = false;
          _error = ApiClient.extractErrorMessage(e);
          _loading = false;
        });
      }
    }
  }


  Future<void> _loadStoreCatalogSilently() async {
    try {
      final res = await _backofficeRepo.fetchReportCatalog();
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final stores = (data['stores'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted && stores.isNotEmpty) {
        setState(() => _availableStores = stores);
      }
    } catch (_) {
      // Non-blocking catalog metadata refresh
    }
  }


  String _currentStoreLabel() {
    if (_selectedStoreScope == 'all') return 'Semua Cabang';
    for (final s in _availableStores) {
      if ((s['id'] ?? s['store_id']).toString() == _selectedStoreScope) {
        return (s['name'] ?? s['store_name'] ?? 'Cabang Terpilih').toString();
      }
    }
    final activeStoreName =
        context.read<AuthCubit>().state.session.activeStore.name;
    return activeStoreName.isNotEmpty ? activeStoreName : 'Cabang Terpilih';
  }


  Future<void> _selectQuickPeriod(String key, String label) async {
    if (key == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        initialDateRange: _customStartDate != null && _customEndDate != null
            ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 6)),
                end: now,
              ),
      );
      if (picked == null || !mounted) return;
      final df = DateFormat('dd/MM/yyyy');
      setState(() {
        _periodKey = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedDateRange = '${df.format(picked.start)} - ${df.format(picked.end)}';
      });
      await _fetchReports();
      return;
    }

    setState(() {
      _periodKey = key;
      _selectedDateRange = label;
      _customStartDate = null;
      _customEndDate = null;
    });
    await _fetchReports();
  }


  void _openReport(MobileReportDefinition definition) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileReportDetailScreen(
          definition: definition,
          initialPeriodKey: _periodKey,
          initialCustomStart: _customStartDate,
          initialCustomEnd: _customEndDate,
          initialStoreScope: _selectedStoreScope,
          initialStoreLabel: _currentStoreLabel(),
          availableStores: _availableStores,
        ),
      ),
    );
  }


  void _openReportById(String reportId) {
    final def = MobileReportCatalog.findById(reportId);
    if (def != null) _openReport(def);
  }


  Future<void> _shareExecutiveWhatsApp() async {
    final storeProfile = _offlineDb.getStoreProfile();
    final storeName = (storeProfile['name'] ?? 'OXORA POS').toString();
    final branchLabel = _currentStoreLabel();
    final syncTag = _isOfflineMode
        ? '\n📡 _Data Offline (Sinkronisasi Terakhir: ${_repo.formatLastSyncLabel(isLocalTrial: context.read<AuthCubit>().state.session.isLocalTrial)})_'
        : '';

    final message = '📈 *RINGKASAN EKSEKUTIF — ${storeName.toUpperCase()}*\n'
        '🏪 Cabang: *$branchLabel* | 📅 Periode: *$_selectedDateRange*$syncTag\n'
        '━━━━━━━━━━━━━━━━━━━━\n'
        '💰 Omzet Bersih: *${IdrCurrencyFormatter.format(_netSales)}* ($_transactionsCount nota)\n'
        '📊 Laba Kotor: ${IdrCurrencyFormatter.format(_grossProfit)}\n'
        '💸 Beban Operasional: ${IdrCurrencyFormatter.format(_expensesTotal)}\n'
        '✅ Laba Bersih: *${IdrCurrencyFormatter.format(_netProfit)}* (${_marginPercent.toStringAsFixed(1)}%)\n'
        '━━━━━━━━━━━━━━━━━━━━\n'
        '🧾 Piutang Pelanggan: ${IdrCurrencyFormatter.format(_receivablesTotal)}\n'
        '📦 Hutang Supplier: ${IdrCurrencyFormatter.format(_payablesTotal)}\n'
        '🛡️ Audit Kasir: Void $_voidCount | Refund $_refundCount | Selisih Shift $_varianceShiftsCount\n'
        '━━━━━━━━━━━━━━━━━━━━\n'
        '_Dikirim dari OXORA Mobile BI (50 Laporan)_';

    await Clipboard.setData(ClipboardData(text: message));
    final launched = await WhatsAppService.shareToAnyChat(text: message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'Ringkasan eksekutif siap dikirim ke WhatsApp.'
              : 'Ringkasan laporan telah disalin ke clipboard.',
        ),
        backgroundColor: NusaThemeTokens.of(context).whatsapp,
      ),
    );
  }


  Future<void> _exportExecutiveCsv() async {
    final buf = StringBuffer();
    buf.writeln(
      '${BusinessReportsScreen.sanitizeCsvCell('Metrik')},${BusinessReportsScreen.sanitizeCsvCell('Nilai')}',
    );
    for (final row in [
      ['Periode', _selectedDateRange],
      ['Cabang', _currentStoreLabel()],
      ['Omzet Bersih', IdrCurrencyFormatter.format(_netSales)],
      ['Jumlah Transaksi', '$_transactionsCount'],
      ['Laba Kotor', IdrCurrencyFormatter.format(_grossProfit)],
      ['Beban Operasional', IdrCurrencyFormatter.format(_expensesTotal)],
      ['Laba Bersih', IdrCurrencyFormatter.format(_netProfit)],
      ['Margin Bersih %', '${_marginPercent.toStringAsFixed(1)}%'],
      ['Total Piutang', IdrCurrencyFormatter.format(_receivablesTotal)],
      ['Total Hutang', IdrCurrencyFormatter.format(_payablesTotal)],
      ['Transaksi Void', '$_voidCount'],
      ['Transaksi Refund', '$_refundCount'],
      ['Selisih Shift', '$_varianceShiftsCount'],
    ]) {
      buf.writeln(
        '${BusinessReportsScreen.sanitizeCsvCell(row[0])},${BusinessReportsScreen.sanitizeCsvCell(row[1])}',
      );
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ringkasan CSV (aman formula) telah disalin ke clipboard.'),
      ),
    );
  }


  void _showStoreScopeSheet() {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih Cakupan Cabang',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.domain_rounded, color: tokens.accent),
                title: Text(
                  'Semua Cabang',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                trailing: _selectedStoreScope == 'all'
                    ? Icon(Icons.check_circle_rounded, color: tokens.accent)
                    : null,
                onTap: () {
                  setState(() => _selectedStoreScope = 'all');
                  Navigator.pop(ctx);
                  _fetchReports();
                },
              ),
              ..._availableStores.map(
                (b) => ListTile(
                  leading: Icon(
                    Icons.storefront_rounded,
                    color: tokens.textSecondary,
                  ),
                  title: Text(
                    (b['name'] ?? b['store_name'] ?? 'Cabang').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  trailing:
                      _selectedStoreScope == (b['id'] ?? b['store_id']).toString()
                          ? Icon(Icons.check_circle_rounded, color: tokens.accent)
                          : null,
                  onTap: () {
                    setState(() => _selectedStoreScope =
                        (b['id'] ?? b['store_id']).toString());
                    Navigator.pop(ctx);
                    _fetchReports();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _showAiCopilotSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiCopilotSheet(api: _api),
    );
  }
}
