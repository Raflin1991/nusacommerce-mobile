import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
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
import '../../../core/network/repositories/backoffice_repository.dart';

part 'business_reports_screen_part1.dart';
part 'business_reports_screen_part2.dart';
part 'business_reports_screen_widgets3.dart';

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
  late final BackofficeRepository _backofficeRepo = BackofficeRepository.resolve(_api);

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
}
