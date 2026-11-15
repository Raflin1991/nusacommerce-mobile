import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// LAYAR 7 — EXECUTIVE OWNER DASHBOARD & REPORTS (`PRD-07`, Live API Bound)
class BusinessReportsScreen extends StatefulWidget {
  const BusinessReportsScreen({super.key});

  @override
  State<BusinessReportsScreen> createState() => _BusinessReportsScreenState();
}

class _BusinessReportsScreenState extends State<BusinessReportsScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();

  String _periodKey = '7d';
  String _selectedDateRange = '7 Hari Terakhir';
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _selectedStoreScope = 'all';
  int _activeTabIndex = 0;

  bool _loading = true;
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
  List<Map<String, dynamic>> _paymentBreakdown = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _cashierPerformance = [];
  List<Map<String, dynamic>> _branchComparison = [];

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final params = <String, dynamic>{
      'period': _periodKey,
      'store_id': _selectedStoreScope,
    };
    if (_periodKey == 'custom' && _customStartDate != null && _customEndDate != null) {
      params['start_date'] = DateFormat('yyyy-MM-dd').format(_customStartDate!);
      params['end_date'] = DateFormat('yyyy-MM-dd').format(_customEndDate!);
    }

    try {
      final res = await _api.dio.get(
        ApiEndpoints.ownerDashboard,
        queryParameters: params,
      );

      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final filter = Map<String, dynamic>.from((data['filter'] as Map?) ?? {});
      final kpi = Map<String, dynamic>.from((data['kpi'] as Map?) ?? {});
      final alerts = Map<String, dynamic>.from((data['operational_alerts'] as Map?) ?? {});
      final antiFraud = Map<String, dynamic>.from((data['anti_fraud_summary'] as Map?) ?? {});
      final trend = (data['sales_trend_7d'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var payBreakdown = (data['payment_breakdown'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final topProds = (data['top_products'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final cashiers = (data['cashier_performance'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final branches = (data['branch_comparison'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (payBreakdown.isEmpty) {
        try {
          final summaryRes = await _api.dio.get(
            ApiEndpoints.salesSummary,
            queryParameters: params,
          );
          final summaryData = Map<String, dynamic>.from((summaryRes.data['data'] as Map?) ?? {});
          payBreakdown = (summaryData['payment_breakdown'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _profitVisible = filter['profit_visible'] == true;
        _netSales = (kpi['net_sales'] as num?)?.toDouble() ?? 0;
        _grossProfit = (kpi['gross_profit'] as num?)?.toDouble() ?? 0;
        _netProfit = (kpi['net_profit'] as num?)?.toDouble() ?? 0;
        _marginPercent = (kpi['margin_percent'] as num?)?.toDouble() ?? 0;
        _expensesTotal = (kpi['expenses_total'] as num?)?.toDouble() ?? 0;
        _growthPercent = (kpi['growth_vs_yesterday_percent'] as num?)?.toDouble() ?? 0;
        _transactionsCount = (kpi['transactions_count'] as num?)?.toInt() ?? 0;
        _receivablesTotal = (alerts['receivables_total'] as num?)?.toDouble() ?? 0;
        _payablesTotal = (alerts['payables_total'] as num?)?.toDouble() ?? 0;
        _voidCount = (antiFraud['voided_sales_count'] as num?)?.toInt() ?? 0;
        _refundCount = (antiFraud['refunds_count'] as num?)?.toInt() ?? 0;
        _varianceShiftsCount = (antiFraud['shift_variance_alerts_count'] as num?)?.toInt() ?? 0;
        _noSaleOpensCount = (antiFraud['no_sale_drawer_opens_count'] as num?)?.toInt() ?? 0;
        _trend7d = trend;
        _paymentBreakdown = payBreakdown;
        _topProducts = topProds;
        _cashierPerformance = cashiers;
        _branchComparison = branches;
        _loading = false;
      });
    } catch (e) {
      try {
        final summaryRes = await _api.dio.get(
          ApiEndpoints.salesSummary,
          queryParameters: params,
        );
        final summaryData = Map<String, dynamic>.from((summaryRes.data['data'] as Map?) ?? {});
        final summary = Map<String, dynamic>.from((summaryData['summary'] as Map?) ?? {});
        final dailyBreakdown = (summaryData['daily_breakdown'] as List<dynamic>? ?? [])
            .map((el) => Map<String, dynamic>.from(el as Map))
            .toList();
        final payBreakdown = (summaryData['payment_breakdown'] as List<dynamic>? ?? [])
            .map((el) => Map<String, dynamic>.from(el as Map))
            .toList();

        if (!mounted) return;
        setState(() {
          _profitVisible = false;
          _netSales = (summary['net_sales'] as num?)?.toDouble() ?? 0;
          _grossProfit = 0;
          _netProfit = 0;
          _marginPercent = 0;
          _expensesTotal = 0;
          _growthPercent = 0;
          _transactionsCount = (summary['transactions_count'] as num?)?.toInt() ?? 0;
          _receivablesTotal = 0;
          _payablesTotal = 0;
          _voidCount = (summary['void_count'] as num?)?.toInt() ?? 0;
          _refundCount = (summary['refund_count'] as num?)?.toInt() ?? 0;
          _varianceShiftsCount = 0;
          _noSaleOpensCount = 0;
          _trend7d = dailyBreakdown;
          _paymentBreakdown = payBreakdown;
          _topProducts = const [];
          _cashierPerformance = const [];
          _branchComparison = const [];
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = ApiClient.extractErrorMessage(e);
          _loading = false;
        });
      }
    }
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
            : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      );
      if (picked == null || !mounted) return;
      String fmt(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      setState(() {
        _periodKey = 'custom';
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedDateRange = '${fmt(picked.start)} - ${fmt(picked.end)}';
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

  @override
  Widget build(BuildContext context) {
    final storeLabel = _selectedStoreScope == 'all'
        ? 'Semua Cabang'
        : (_branchComparison.firstWhere(
              (b) => b['store_id'].toString() == _selectedStoreScope,
              orElse: () => {'store_name': 'Cabang Terpilih'},
            )['store_name'].toString());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Laporan Bisnis & Owner'),
        actions: [
          IconButton(
            tooltip: 'Tanya AI Copilot',
            onPressed: _showAiCopilotSheet,
            icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
          ),
          IconButton(
            tooltip: 'Bagikan ke WhatsApp Owner',
            onPressed: _shareReportToOwnerWhatsApp,
            icon: const Icon(Icons.share_rounded, color: AppColors.whatsapp),
          ),
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _fetchReports,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchReports,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Branch Scope & Custom Date Row
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _showStoreScopeSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.storefront_rounded, size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                storeLabel,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.slate400),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showDateRangeSheet,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range_rounded, size: 17, color: AppColors.navyMid),
                          const SizedBox(width: 6),
                          Text(
                            _periodKey == 'custom' ? _selectedDateRange : 'Periode',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Quick 1-Tap Horizontal Period Filter Pills (Zero Clipping)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final p in const [
                      ('today', 'Hari Ini'),
                      ('yesterday', 'Kemarin'),
                      ('7d', '7 Hari Terakhir'),
                      ('month', 'Bulan Ini'),
                      ('last_month', 'Bulan Lalu'),
                      ('custom', 'Rentang Tanggal'),
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
              const SizedBox(height: 14),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: NusaCard(
                    backgroundColor: AppColors.dangerSoft,
                    borderColor: AppColors.danger.withOpacity(0.35),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.dangerDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.dangerDark),
                          ),
                        ),
                        TextButton(onPressed: _fetchReports, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                ),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                // 3. View Focus Segmented Switch
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.slate200.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildSegmentTab(0, 'Ringkasan'),
                      _buildSegmentTab(1, 'Penjualan'),
                      _buildSegmentTab(2, 'Laba Rugi'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                _buildTotalPenjualanHeroCard(),
                const SizedBox(height: 12),

                // 4. SAK EMKM Financial & Working Capital Grid (6 Explicit Cards)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.05,
                  children: [
                    _buildReportMetricTile(
                      icon: Icons.monetization_on_rounded,
                      iconColor: AppColors.success,
                      label: 'Laba Kotor',
                      value: _profitVisible ? IdrCurrencyFormatter.format(_grossProfit) : 'Terkunci',
                    ),
                    _buildReportMetricTile(
                      icon: Icons.money_off_csred_rounded,
                      iconColor: AppColors.danger,
                      label: 'Biaya Operasional',
                      value: IdrCurrencyFormatter.format(_expensesTotal),
                    ),
                    _buildReportMetricTile(
                      icon: Icons.account_balance_wallet_rounded,
                      iconColor: AppColors.primary,
                      label: 'Laba Bersih',
                      value: _profitVisible ? IdrCurrencyFormatter.format(_netProfit) : 'Terkunci',
                    ),
                    _buildReportMetricTile(
                      icon: Icons.percent_rounded,
                      iconColor: AppColors.successDark,
                      label: 'Margin Laba Bersih',
                      value: _profitVisible ? '${_marginPercent.toStringAsFixed(1)}%' : '-',
                    ),
                    _buildReportMetricTile(
                      icon: Icons.schedule_rounded,
                      iconColor: AppColors.warning,
                      label: 'Piutang Bon',
                      value: IdrCurrencyFormatter.format(_receivablesTotal),
                    ),
                    _buildReportMetricTile(
                      icon: Icons.shopping_bag_rounded,
                      iconColor: AppColors.navyMid,
                      label: 'Hutang Supplier',
                      value: IdrCurrencyFormatter.format(_payablesTotal),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 5. 7-Day Trend Line Chart
                if (_activeTabIndex != 2) ...[
                  NusaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tren Penjualan 7 Hari',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                            ),
                            InkWell(
                              onTap: () => setState(() => _activeTabIndex = 2),
                              child: const Text(
                                'Laba Rugi →',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_trend7d.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text('Belum ada transaksi pada periode ini.', style: TextStyle(color: AppColors.slate500)),
                            ),
                          )
                        else
                          SizedBox(
                            height: 155,
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (_) => const FlLine(
                                    color: AppColors.border,
                                    strokeWidth: 1,
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 42,
                                      getTitlesWidget: (val, _) => Text(
                                        IdrCurrencyFormatter.formatCompact(val),
                                        style: const TextStyle(fontSize: 10, color: AppColors.slate400),
                                      ),
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (val, _) {
                                        final idx = val.toInt();
                                        if (idx < 0 || idx >= _trend7d.length) return const SizedBox.shrink();
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(
                                            (_trend7d[idx]['day_label'] ?? '').toString(),
                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.slate500),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: List.generate(
                                      _trend7d.length,
                                      (i) => FlSpot(i.toDouble(), ((_trend7d[i]['revenue'] as num?)?.toDouble() ?? 0)),
                                    ),
                                    isCurved: true,
                                    color: AppColors.primary,
                                    barWidth: 3,
                                    dotData: const FlDotData(show: true),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: AppColors.primary.withOpacity(0.14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _buildSakEmkmAndAntiFraudSection(),
                const SizedBox(height: 16),
                if (_activeTabIndex != 2) ...[
                  _buildPaymentBreakdownSection(),
                  const SizedBox(height: 16),
                  _buildTopProductsSection(),
                  const SizedBox(height: 16),
                  _buildCashierPerformanceSection(),
                  const SizedBox(height: 16),
                ] else ...[
                  _buildBranchComparisonSection(),
                  const SizedBox(height: 16),
                ],
                NusaButton(
                  label: 'Kirim Laporan Eksekutif ke WhatsApp Owner',
                  icon: Icons.chat_rounded,
                  variant: NusaButtonVariant.success,
                  minHeight: 50,
                  onPressed: _shareReportToOwnerWhatsApp,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentTab(int index, String label) {
    final isSelected = _activeTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTabIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [const BoxShadow(color: Color(0x140F172A), blurRadius: 6, offset: Offset(0, 2))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? AppColors.primary : AppColors.slate600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTotalPenjualanHeroCard() {
    final isUp = _growthPercent >= 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroNavyGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Omzet Bersih • $_transactionsCount Nota',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCBD5E1),
                ),
              ),
              NusaBadge(
                label: '${isUp ? '+' : '-'}${_growthPercent.abs().toStringAsFixed(1)}%',
                icon: isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                variant: isUp ? NusaBadgeVariant.success : NusaBadgeVariant.danger,
              ),
            ],
          ),
          const SizedBox(height: 6),
          NusaPriceTag(
            amount: _netSales,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildReportMetricTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return NusaCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTheme.moneyStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.navyDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSakEmkmAndAntiFraudSection() {
    return Column(
      children: [
        if (_profitVisible) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.executiveNavyGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Laba Bersih Operasional (SAK EMKM)',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    NusaBadge(
                      label: 'Margin ${_marginPercent.toStringAsFixed(1)}%',
                      variant: _netProfit >= 0 ? NusaBadgeVariant.success : NusaBadgeVariant.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                NusaPriceTag(
                  amount: _netProfit,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Text(
                  'Laba Kotor (${IdrCurrencyFormatter.format(_grossProfit)}) − Biaya Ops (${IdrCurrencyFormatter.format(_expensesTotal)})',
                  style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        // Structured 2x2 Anti-Fraud Radar Grid
        NusaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.danger, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Radar Anti-Fraud & Pengawasan Kasir',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.35,
                children: [
                  _fraudAlertTile('Void / Batal', '$_voidCount Nota', _voidCount > 0, isCritical: true),
                  _fraudAlertTile('Retur (Refund)', '$_refundCount Nota', _refundCount > 0),
                  _fraudAlertTile('Selisih Shift', '$_varianceShiftsCount Shift', _varianceShiftsCount > 0, isCritical: true),
                  _fraudAlertTile('No-Sale Laci', '$_noSaleOpensCount Kali', _noSaleOpensCount > 0),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fraudAlertTile(String label, String countText, bool hasAlert, {bool isCritical = false}) {
    final bg = !hasAlert
        ? AppColors.background
        : (isCritical ? AppColors.dangerSoft : AppColors.warningSoft);
    final border = !hasAlert
        ? AppColors.border
        : (isCritical ? AppColors.danger.withOpacity(0.35) : AppColors.warning.withOpacity(0.35));
    final color = !hasAlert
        ? AppColors.successDark
        : (isCritical ? AppColors.danger : AppColors.warningDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.slate600),
          ),
          const SizedBox(height: 2),
          Text(
            countText,
            style: AppTheme.moneyStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  num _numVal(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _intVal(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Color _methodColor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('tunai') || lower.contains('cash')) return AppColors.success;
    if (lower.contains('qris')) return AppColors.primary;
    if (lower.contains('transfer') || lower.contains('bank')) return const Color(0xFF4F46E5);
    if (lower.contains('edc') || lower.contains('kartu')) return const Color(0xFF0D9488);
    if (lower.contains('kasbon') || lower.contains('bon')) return AppColors.warning;
    return AppColors.slate500;
  }

  Widget _buildPaymentBreakdownSection() {
    final totalAllMethods = _paymentBreakdown.fold<double>(
      0.0,
      (sum, item) => sum + _numVal(item['total'] ?? item['amount'] ?? item['total_amount']).toDouble(),
    );

    return NusaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Rincian Metode Pembayaran',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_paymentBreakdown.isEmpty)
            const Text(
              'Belum ada transaksi pembayaran pada periode ini.',
              style: TextStyle(fontSize: 13, color: AppColors.slate500),
            )
          else
            for (var i = 0; i < _paymentBreakdown.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Builder(
                builder: (_) {
                  final item = _paymentBreakdown[i];
                  final label = (item['name'] ?? item['label'] ?? item['payment_method'] ?? item['method'] ?? item['code'] ?? '-').toString();
                  final count = _intVal(item['tx_count'] ?? item['count'] ?? item['transactions_count']);
                  final total = _numVal(item['total_amount'] ?? item['total'] ?? item['amount']).toDouble();
                  final ratio = totalAllMethods > 0 ? (total / totalAllMethods).clamp(0.0, 1.0) : 0.0;
                  final barColor = _methodColor(label);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$label ($count× • ${(ratio * 100).toStringAsFixed(0)}%)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navyDark),
                            ),
                          ),
                          NusaPriceTag(amount: total, fontSize: 13.5),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 7,
                          backgroundColor: AppColors.slate100,
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildTopProductsSection() {
    final maxProductRev = _topProducts.isEmpty
        ? 1.0
        : _topProducts
            .take(10)
            .map((e) => _numVal(e['total_revenue'] ?? e['revenue'] ?? e['omzet'] ?? e['total']).toDouble())
            .reduce((a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity);

    return NusaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.trending_up_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Top 10 Produk Terlaris',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_topProducts.isEmpty)
            const Text(
              'Belum ada produk terjual pada periode ini.',
              style: TextStyle(fontSize: 13, color: AppColors.slate500),
            )
          else
            for (var i = 0; i < _topProducts.length && i < 10; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Builder(
                builder: (_) {
                  final item = _topProducts[i];
                  final name = (item['product_name'] ?? item['name'] ?? 'Produk').toString();
                  final qty = _numVal(item['qty_sold'] ?? item['total_qty'] ?? item['qty'] ?? item['quantity']);
                  final revenue = _numVal(item['revenue'] ?? item['total_revenue'] ?? item['omzet'] ?? item['total']).toDouble();
                  final qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);
                  final ratio = (revenue / maxProductRev).clamp(0.0, 1.0);
                  return Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: i < 3 ? AppColors.navyDark : AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: i < 3 ? Colors.white : AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navyDark),
                                ),
                                Text(
                                  'Terjual: $qtyStr unit',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                ),
                              ],
                            ),
                          ),
                          NusaPriceTag(amount: revenue, fontSize: 13),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 4,
                          backgroundColor: AppColors.slate100,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            i < 3 ? AppColors.primary : AppColors.slate400,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildCashierPerformanceSection() {
    return NusaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Performa Kasir & Staf',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_cashierPerformance.isEmpty)
            const Text(
              'Belum ada aktivitas kasir pada periode ini.',
              style: TextStyle(fontSize: 13, color: AppColors.slate500),
            )
          else
            for (var i = 0; i < _cashierPerformance.length; i++) ...[
              if (i > 0) const Divider(height: 14, color: AppColors.border),
              Builder(
                builder: (_) {
                  final item = _cashierPerformance[i];
                  final name = (item['cashier_name'] ?? item['name'] ?? 'Kasir').toString();
                  final txCount = _intVal(item['tx_count'] ?? item['transactions_count'] ?? item['count']);
                  final sales = _numVal(item['revenue'] ?? item['total_sales'] ?? item['omzet'] ?? item['total']);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navyDark)),
                            Text(
                              '$txCount nota',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                            ),
                          ],
                        ),
                      ),
                      NusaPriceTag(amount: sales, fontSize: 13.5),
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildBranchComparisonSection() {
    return NusaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storefront_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Perbandingan Cabang',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_branchComparison.isEmpty)
            const Text(
              'Menampilkan ringkasan untuk cabang aktif terpilih.',
              style: TextStyle(fontSize: 13, color: AppColors.slate500),
            )
          else
            for (var i = 0; i < _branchComparison.length; i++) ...[
              if (i > 0) const Divider(height: 14, color: AppColors.border),
              Builder(
                builder: (_) {
                  final item = _branchComparison[i];
                  final name = (item['store_name'] ?? item['name'] ?? 'Cabang').toString();
                  final txCount = _intVal(item['tx_count'] ?? item['transactions_count'] ?? item['count']);
                  final sales = _numVal(item['revenue'] ?? item['net_sales'] ?? item['total_sales'] ?? item['omzet']);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navyDark)),
                            Text(
                              '$txCount transaksi',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                            ),
                          ],
                        ),
                      ),
                      NusaPriceTag(amount: sales, fontSize: 13.5),
                    ],
                  );
                },
              ),
            ],
        ],
      ),
    );
  }

  Future<void> _shareReportToOwnerWhatsApp() async {
    final session = context.read<AuthCubit>().state.session;
    var ownerPhone = (session.activeStore.phone ?? '').trim();

    if (ownerPhone.isEmpty) {
      final phoneCtrl = TextEditingController();
      final entered = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Nomor WhatsApp Owner'),
          content: TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'No. WhatsApp (contoh: 081234567890)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, phoneCtrl.text.trim()),
              child: const Text('Kirim Laporan'),
            ),
          ],
        ),
      );
      phoneCtrl.dispose();
      if (entered == null || entered.isEmpty || !mounted) return;
      ownerPhone = entered;
    }

    final netMarginPct = _netSales > 0 ? (_netProfit / _netSales) * 100 : 0.0;
    final branchLabel = _selectedStoreScope == 'all'
        ? 'Semua Cabang'
        : (_branchComparison.firstWhere(
              (b) => b['store_id'].toString() == _selectedStoreScope,
              orElse: () => {'store_name': 'Cabang Terpilih'},
            )['store_name'].toString());
    await WhatsAppService.sendExecutiveReportToOwner(
      ownerPhone: ownerPhone,
      storeName: session.activeStore.name,
      periodLabel: _selectedDateRange,
      branchLabel: branchLabel,
      netSales: _netSales,
      grossProfit: _grossProfit,
      expenses: _expensesTotal,
      netProfit: _netProfit,
      netMarginPct: netMarginPct,
      transactionsCount: _transactionsCount,
      voidCount: _voidCount,
      refundCount: _refundCount,
      varianceCount: _varianceShiftsCount,
    );
  }

  void _showDateRangeSheet() {
    final options = <Map<String, String>>[
      {'key': 'today', 'label': 'Hari Ini'},
      {'key': 'yesterday', 'label': 'Kemarin'},
      {'key': '7d', 'label': '7 Hari Terakhir'},
      {'key': 'month', 'label': 'Bulan Ini'},
      {'key': 'last_month', 'label': 'Bulan Lalu'},
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pilih Periode Laporan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final opt in options)
              ListTile(
                title: Text(opt['label']!, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: _periodKey == opt['key']
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() {
                    _periodKey = opt['key']!;
                    _selectedDateRange = opt['label']!;
                    _customStartDate = null;
                    _customEndDate = null;
                  });
                  Navigator.pop(ctx);
                  _fetchReports();
                },
              ),
            ListTile(
              leading: const Icon(Icons.date_range_rounded, color: AppColors.primary),
              title: const Text('Pilih Rentang Tanggal Kustom...', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: _periodKey == 'custom'
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year - 2),
                  lastDate: now,
                  initialDateRange: _customStartDate != null && _customEndDate != null
                      ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
                      : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
                );
                if (picked == null || !mounted) return;
                String fmt(DateTime d) =>
                    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                setState(() {
                  _periodKey = 'custom';
                  _customStartDate = picked.start;
                  _customEndDate = picked.end;
                  _selectedDateRange = '${fmt(picked.start)} - ${fmt(picked.end)}';
                });
                _fetchReports();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showStoreScopeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pilih Cakupan Cabang', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ListTile(
              title: const Text('Semua Cabang', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: _selectedStoreScope == 'all'
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _selectedStoreScope = 'all');
                Navigator.pop(ctx);
                _fetchReports();
              },
            ),
            ..._branchComparison.map((b) => ListTile(
                  title: Text(b['store_name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: _selectedStoreScope == b['store_id'].toString()
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() => _selectedStoreScope = b['store_id'].toString());
                    Navigator.pop(ctx);
                    _fetchReports();
                  },
                )),
          ],
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NusaCommerce AI Copilot',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Analisa omzet, stok, & risiko kasir berbasis data toko',
                            style: TextStyle(fontSize: 11.5, color: AppColors.slate600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
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
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Text(
                              'Ajukan pertanyaan operasional atau analisa keuangan toko Anda. Copilot akan membaca ringkasan transaksi, margin, stok menipis, dan audit shift terbaru.',
                              style: TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF334155)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Pertanyaan Cepat',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _quickPrompts
                                .map(
                                  (q) => ActionChip(
                                    label: Text(q, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
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
                            return const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text('AI sedang menganalisa data toko...', style: TextStyle(fontSize: 12.5, color: AppColors.slate600)),
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
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.8,
                              ),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? AppColors.primary
                                    : (isError ? const Color(0xFFFEF2F2) : Colors.white),
                                borderRadius: BorderRadius.circular(14),
                                border: isUser
                                    ? null
                                    : Border.all(
                                        color: isError ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
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
                                          : (isError ? const Color(0xFFB91C1C) : const Color(0xFF0F172A)),
                                    ),
                                  ),
                                  if (meta.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      meta,
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.slate600),
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Tanya AI Copilot tentang performa toko...',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : () => _sendMessage(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
