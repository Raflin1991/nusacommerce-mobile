import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../models/mobile_report_catalog.dart';
import '../services/mobile_report_repository.dart';
import 'mobile_report_detail_screen.dart';

/// LAYAR 7 — PUSAT LAPORAN BISNIS & MOBILE BI (PARITAS 50 LAPORAN CLOUD)
class BusinessReportsScreen extends StatefulWidget {
  const BusinessReportsScreen({super.key});

  /// SEC #18 CSV formula neutralization + RFC-4180 double-quote escaping.
  static String sanitizeCsvCell(String raw) =>
      MobileReportRepository.sanitizeCsvCell(raw);

  @override
  State<BusinessReportsScreen> createState() => _BusinessReportsScreenState();
}

class _BusinessReportsScreenState extends State<BusinessReportsScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final NetworkConnectivityService _connectivity =
      GetIt.instance<NetworkConnectivityService>();
  late final MobileReportRepository _repo;
  final TextEditingController _catalogSearchCtrl = TextEditingController();

  String _periodKey = '7d';
  String _selectedDateRange = '7 Hari Terakhir';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _selectedStoreScope = 'all';
  String _selectedCategoryCode = 'all';
  String _catalogQuery = '';

  bool _loading = true;
  bool _isOfflineMode = false;
  bool _showTrendChart = false;
  String? _error;
  bool _profitVisible = true;

  double _netSales = 0;
  double _grossProfit = 0;
  double _netProfit = 0;
  double _marginPercent = 0;
  double _expensesTotal = 0;
  double _growthPercent = 0;
  double _receivablesTotal = 0;
  double _payablesTotal = 0;
  int _transactionsCount = 0;

  int _voidCount = 0;
  int _refundCount = 0;
  int _varianceShiftsCount = 0;
  int _noSaleOpensCount = 0;

  List<Map<String, dynamic>> _trend7d = [];
  List<Map<String, dynamic>> _availableStores = [];

  @override
  void initState() {
    super.initState();
    _repo = MobileReportRepository(
      api: _api,
      offlineDb: _offlineDb,
      connectivity: _connectivity,
    );
    _fetchReports();
  }

  @override
  void dispose() {
    _catalogSearchCtrl.dispose();
    super.dispose();
  }

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
      final res = await _api.dio.get(
        ApiEndpoints.ownerDashboard,
        queryParameters: params,
      );

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
        final summaryRes = await _api.dio.get(
          ApiEndpoints.salesSummary,
          queryParameters: params,
        );
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
      final res = await _api.dio.get(ApiEndpoints.reportCatalog);
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

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final authSession = context.watch<AuthCubit>().state.session;
    final storeLabel = _currentStoreLabel();

    final visibleCategories =
        MobileReportCatalog.visibleCategoriesFor(authSession);
    final totalVisibleReports = visibleCategories.fold<int>(
      0,
      (sum, c) => sum + c.reports.length,
    );

    final filteredCategories = <MobileReportCategory>[];
    for (final cat in visibleCategories) {
      if (_selectedCategoryCode != 'all' && cat.code != _selectedCategoryCode) {
        continue;
      }
      final matches = cat.reports
          .where((r) => r.matchesQuery(_catalogQuery))
          .toList();
      if (matches.isNotEmpty) {
        filteredCategories.add(cat.copyWithReports(matches));
      }
    }

    final antiFraudAlerts =
        _voidCount + _refundCount + _varianceShiftsCount + _noSaleOpensCount;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pusat Laporan Bisnis',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            Text(
              '$totalVisibleReports Laporan Cloud-Parity • $storeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ekspor CSV Ringkasan',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _exportExecutiveCsv,
            icon: Icon(Icons.download_rounded, size: 20, color: tokens.accent),
          ),
          IconButton(
            tooltip: 'Tanya AI Copilot',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _showAiCopilotSheet,
            icon: Icon(Icons.auto_awesome_rounded, size: 20, color: tokens.accent),
          ),
          IconButton(
            tooltip: 'Bagikan ke WhatsApp (1-Klik)',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _shareExecutiveWhatsApp,
            icon: Icon(Icons.share_rounded, size: 20, color: NusaThemeTokens.of(context).whatsapp),
          ),
          IconButton(
            tooltip: 'Muat Ulang',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _fetchReports,
            icon: Icon(Icons.refresh_rounded, size: 20, color: tokens.textSecondary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchReports,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Global Control Bar (Branch Scope + Quick Periods + Live Search across 50 Reports)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _showStoreScopeSheet,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.bgSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: tokens.borderSubtle,
                                  width: tokens.borderWidth,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.storefront_rounded,
                                    size: 17,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      storeLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: tokens.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _selectQuickPeriod('custom', 'Kustom'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 42),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _periodKey == 'custom'
                                  ? tokens.accentSoft
                                  : tokens.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _periodKey == 'custom'
                                    ? tokens.accent
                                    : tokens.borderSubtle,
                                width: tokens.borderWidth,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 16,
                                  color: _periodKey == 'custom'
                                      ? tokens.accent
                                      : tokens.textSecondary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _periodKey == 'custom'
                                      ? _selectedDateRange
                                      : 'Kalender',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _periodKey == 'custom'
                                        ? tokens.accent
                                        : tokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 35,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final p in const [
                            ('today', 'Hari Ini'),
                            ('yesterday', 'Kemarin'),
                            ('7d', '7 Hari Terakhir'),
                            ('30d', '30 Hari'),
                            ('month', 'Bulan Ini'),
                            ('last_month', 'Bulan Lalu'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: NusaPillFilter(
                                label: p.$2,
                                selected: _periodKey == p.$1,
                                onTap: () => _selectQuickPeriod(p.$1, p.$2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _catalogSearchCtrl,
                      onChanged: (val) => setState(() => _catalogQuery = val),
                      style: TextStyle(fontSize: 13, color: tokens.textPrimary),
                      decoration: InputDecoration(
                        hintText:
                            'Cari 50 laporan (mis. laba nota, stok kritis, aging, pajak)...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: tokens.textTertiary,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: tokens.textTertiary,
                        ),
                        suffixIcon: _catalogQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  _catalogSearchCtrl.clear();
                                  setState(() => _catalogQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: tokens.bgSurface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.borderSubtle),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.borderSubtle),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.accent, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Offline Data Indicator Banner
            if (_isOfflineMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.warningSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.warning.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 17,
                          color: tokens.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Data Offline (Sinkronisasi Terakhir: ${_repo.formatLastSyncLabel(isLocalTrial: authSession.isLocalTrial)})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 3. Online Error Banner (NEVER masked as fake local data!)
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: NusaCard(
                    backgroundColor: tokens.dangerSoft,
                    borderColor: tokens.danger.withOpacity(0.35),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: tokens.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: tokens.danger,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _fetchReports,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 4. Drill-Down Executive Pulse Strip (compact, zero vanity bloat)
            if (_catalogQuery.trim().isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: _loading
                      ? Container(
                          height: 112,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tokens.bgSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                          child: const CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : _buildExecutivePulseCard(tokens, antiFraudAlerts),
                ),
              ),

            // 5. 8-Category Horizontal Filter Pills + Oversold Quick Audit Chip
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: NusaPillFilter(
                              label: 'Semua ($totalVisibleReports)',
                              selected: _selectedCategoryCode == 'all',
                              onTap: () =>
                                  setState(() => _selectedCategoryCode = 'all'),
                            ),
                          ),
                          for (final cat in visibleCategories)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: NusaPillFilter(
                                label: '${cat.shortTitle} (${cat.reports.length})',
                                selected: _selectedCategoryCode == cat.code,
                                onTap: () => setState(
                                    () => _selectedCategoryCode = cat.code),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_catalogQuery.trim().isEmpty &&
                        (_selectedCategoryCode == 'all' ||
                            _selectedCategoryCode == 'inventory_stock')) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _openReport(
                            MobileReportCatalog.oversoldAuditDefinition),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.dangerSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: tokens.danger.withOpacity(0.28),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.remove_shopping_cart_outlined,
                                size: 18,
                                color: tokens.danger,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Audit Cepat: Barang Terjual Minus (Oversold)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.danger,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: tokens.danger,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 6. Categorized 50-Report Interactive Directory
            if (filteredCategories.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                  child: NusaCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 36,
                            color: tokens.textTertiary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tidak ditemukan laporan untuk "$_catalogQuery".',
                            style: TextStyle(
                              fontSize: 13,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, idx) =>
                        _buildCategorySection(tokens, filteredCategories[idx]),
                    childCount: filteredCategories.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutivePulseCard(NusaThemeTokens tokens, int antiFraudAlerts) {
    final isUp = _growthPercent >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openReportById('sales-report'),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Omzet Bersih ($_selectedDateRange)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_growthPercent != 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isUp
                                    ? tokens.positiveSoft
                                    : tokens.dangerSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${isUp ? '+' : ''}${_growthPercent.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isUp ? tokens.positive : tokens.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          IdrCurrencyFormatter.format(_netSales),
                          style: AppTheme.moneyStyle(
                            fontSize: 22,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '$_transactionsCount transaksi • Ketuk untuk rincian',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_trend7d.isNotEmpty)
                IconButton(
                  tooltip: _showTrendChart ? 'Sembunyikan Grafik' : 'Lihat Grafik Tren',
                  onPressed: () =>
                      setState(() => _showTrendChart = !_showTrendChart),
                  icon: Icon(
                    _showTrendChart
                        ? Icons.expand_less_rounded
                        : Icons.bar_chart_rounded,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDrillMetricPill(
                  tokens: tokens,
                  label: _profitVisible ? 'Laba Bersih' : 'Beban Toko',
                  value: IdrCurrencyFormatter.format(
                    _profitVisible ? _netProfit : _expensesTotal,
                  ),
                  badge: _profitVisible
                      ? '${_marginPercent.toStringAsFixed(1)}%'
                      : null,
                  accent: _profitVisible
                      ? (_netProfit >= 0 ? tokens.positive : tokens.danger)
                      : tokens.warning,
                  onTap: () => _openReportById(
                    _profitVisible ? 'profit-and-loss' : 'expenses-report',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDrillMetricPill(
                  tokens: tokens,
                  label: 'Piutang / AR',
                  value: IdrCurrencyFormatter.format(_receivablesTotal),
                  accent: _receivablesTotal > 0
                      ? tokens.warning
                      : tokens.textSecondary,
                  onTap: () => _openReportById('aged-receivables'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDrillMetricPill(
                  tokens: tokens,
                  label: 'Audit Kasir',
                  value: '$antiFraudAlerts isu',
                  accent: antiFraudAlerts > 0 ? tokens.danger : tokens.positive,
                  onTap: () => _openReportById('void-refund-audit'),
                ),
              ),
            ],
          ),
          if (_showTrendChart && _trend7d.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= _trend7d.length) {
                            return const SizedBox.shrink();
                          }
                          final lbl = (_trend7d[idx]['day_label'] ??
                                  _trend7d[idx]['date'] ??
                                  '')
                              .toString();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              lbl.length > 5 ? lbl.substring(lbl.length - 5) : lbl,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: tokens.textTertiary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < _trend7d.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: ((_trend7d[i]['revenue'] ??
                                        _trend7d[i]['net_sales'] ??
                                        0) as num)
                                .toDouble(),
                            color: tokens.accent,
                            width: 14,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDrillMetricPill({
    required NusaThemeTokens tokens,
    required String label,
    required String value,
    required Color accent,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                if (badge != null)
                  Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTheme.moneyStyle(fontSize: 12.5, color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(
    NusaThemeTokens tokens,
    MobileReportCategory category,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: category.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  category.icon,
                  size: 17,
                  color: category.accentColor,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      category.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.bgElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '${category.reports.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (_, constraints) {
              final twoCol = constraints.maxWidth >= 620;
              if (!twoCol) {
                return Column(
                  children: [
                    for (final r in category.reports)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: _buildReportCard(tokens, category, r),
                      ),
                  ],
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: category.reports.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 74,
                ),
                itemBuilder: (_, idx) =>
                    _buildReportCard(tokens, category, category.reports[idx]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(
    NusaThemeTokens tokens,
    MobileReportCategory category,
    MobileReportDefinition report,
  ) {
    return InkWell(
      onTap: () => _openReport(report),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tokens.borderSubtle,
            width: tokens.borderWidth,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: category.accentColor.withOpacity(0.11),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                report.icon,
                size: 19,
                color: category.accentColor,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          report.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (_isOfflineMode && report.supportsOfflineLocal) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.positiveSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Offline',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.positive,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: tokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AiCopilotSheet extends StatefulWidget {
  const _AiCopilotSheet({required this.api});

  final ApiClient api;

  @override
  State<_AiCopilotSheet> createState() => _AiCopilotSheetState();
}

class _AiCopilotSheetState extends State<_AiCopilotSheet> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _sending = false;

  static const List<String> _quickPrompts = [
    'Ringkas performa penjualan periode ini',
    'Produk apa yang paling laris & perlu restok?',
    'Cek anomali void, refund, atau selisih kasir',
    'Saran strategi tingkatkan margin profit',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty || _sending) return;

    final historyPayload = _messages
        .where((m) => m['isError'] != true)
        .map((m) => <String, String>{
              'role': m['role'].toString(),
              'text': m['text'].toString(),
            })
        .toList();

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _sending = true;
      if (preset == null) _inputController.clear();
    });
    _scrollToBottom();

    try {
      final res = await widget.api.dio.post(
        ApiEndpoints.copilotChat,
        data: {
          'message': text,
          'history': historyPayload,
        },
      );
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final reply = (data['reply'] ?? '').toString().trim();
      final provider = (data['provider'] ?? '').toString().trim();
      final tokens = (data['tokens_used'] as num?)?.toInt();

      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'model',
          'text': reply.isEmpty ? 'Copilot tidak mengembalikan jawaban.' : reply,
          'meta': [
            if (provider.isNotEmpty) provider.toUpperCase(),
            if (tokens != null) '$tokens token',
          ].join(' • '),
        });
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'model',
          'text': ApiClient.extractErrorMessage(e),
          'isError': true,
        });
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: BoxDecoration(
          color: tokens.bgPage,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.borderDefault,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.auto_awesome_rounded,
                          color: tokens.accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OXORA AI Copilot',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          Text(
                            'Analisa omzet, stok, & risiko kasir berbasis data toko',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: tokens.bgSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: tokens.borderSubtle),
                            ),
                            child: Text(
                              'Ajukan pertanyaan operasional atau analisa keuangan toko Anda. Copilot akan membaca ringkasan transaksi, margin, stok menipis, dan audit shift terbaru.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Pertanyaan Cepat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _quickPrompts
                                .map(
                                  (q) => ActionChip(
                                    label: Text(
                                      q,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    backgroundColor: tokens.bgElevated,
                                    side: BorderSide(color: tokens.borderSubtle),
                                    onPressed: () => _sendMessage(q),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (_, idx) {
                          if (_sending && idx == _messages.length) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'AI sedang menganalisa data toko...',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: tokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final msg = _messages[idx];
                          final isUser = msg['role'] == 'user';
                          final isError = msg['isError'] == true;
                          final meta = (msg['meta'] ?? '').toString();
                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.8,
                              ),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? tokens.accent
                                    : (isError
                                        ? tokens.dangerSoft
                                        : tokens.bgSurface),
                                borderRadius: BorderRadius.circular(14),
                                border: isUser
                                    ? null
                                    : Border.all(
                                        color: isError
                                            ? tokens.danger.withOpacity(0.45)
                                            : tokens.borderSubtle,
                                      ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    msg['text'].toString(),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.4,
                                      color: isUser
                                          ? Colors.white
                                          : (isError
                                              ? tokens.danger
                                              : tokens.textPrimary),
                                    ),
                                  ),
                                  if (meta.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      meta,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textTertiary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(top: BorderSide(color: tokens.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(color: tokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Tanya AI Copilot tentang performa toko...',
                          hintStyle: TextStyle(color: tokens.textTertiary),
                          isDense: true,
                          filled: true,
                          fillColor: tokens.bgElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : () => _sendMessage(),
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
