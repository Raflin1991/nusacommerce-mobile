import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../models/mobile_report_catalog.dart';
import '../services/mobile_report_repository.dart';

part 'mobile_report_detail_screen_part1.dart';
part 'mobile_report_detail_screen_part2.dart';

/// Mobile-First Report Detail & Drill-Down Viewer supporting all 50 Cloud-parity
/// reports (plus `oversold` audit) with stacked cards, bottom-sheet drill-down,
/// 1-click WhatsApp share, PDF/CSV export, and explicit offline resilience.
class MobileReportDetailScreen extends StatefulWidget {
  final MobileReportDefinition definition;
  final String initialPeriodKey;
  final DateTime? initialCustomStart;
  final DateTime? initialCustomEnd;
  final String initialStoreScope;
  final String initialStoreLabel;
  final List<Map<String, dynamic>> availableStores;

  const MobileReportDetailScreen({
    super.key,
    required this.definition,
    this.initialPeriodKey = '7d',
    this.initialCustomStart,
    this.initialCustomEnd,
    this.initialStoreScope = 'all',
    this.initialStoreLabel = 'Semua Cabang',
    this.availableStores = const [],
  });

  @override
  State<MobileReportDetailScreen> createState() =>
      _MobileReportDetailScreenState();
}


class _MobileReportDetailScreenState extends State<MobileReportDetailScreen> {
  late final MobileReportRepository _repo;

  final TextEditingController _searchCtrl = TextEditingController();


  late String _periodKey;

  DateTime? _customStart;

  DateTime? _customEnd;

  late String _storeScope;

  late String _storeLabel;

  String _searchQuery = '';


  bool _loading = true;

  String? _error;

  MobileReportPayload? _payload;


  @override
  void initState() {
    super.initState();
    _repo = MobileReportRepository(
      api: GetIt.instance<ApiClient>(),
      offlineDb: GetIt.instance<OfflineDatabase>(),
      connectivity: GetIt.instance<NetworkConnectivityService>(),
    );
    _periodKey = widget.initialPeriodKey;
    _customStart = widget.initialCustomStart;
    _customEnd = widget.initialCustomEnd;
    _storeScope = widget.initialStoreScope;
    _storeLabel = widget.initialStoreLabel;
    _loadReport();
  }


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final payload = _payload;
    final filteredItems = (payload?.items ?? const <MobileReportRowItem>[])
        .where((i) => i.matchesSearch(_searchQuery))
        .toList();

    final dateRangeInfo = MobileReportRepository.resolveDateRange(
      _periodKey,
      customStart: _customStart,
      customEnd: _customEnd,
    );

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.definition.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            Text(
              '$_storeLabel • ${dateRangeInfo.label}',
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
            tooltip: 'Bagikan ke WhatsApp (1-Klik)',
            onPressed: payload == null ? null : _shareWhatsApp,
            icon: Icon(Icons.share_rounded, color: NusaThemeTokens.of(context).whatsapp),
          ),
          IconButton(
            tooltip: 'Ekspor PDF / CSV',
            onPressed: payload == null ? null : _openExportSheet,
            icon: Icon(Icons.download_rounded, color: tokens.accent),
          ),
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _loadReport,
            icon: Icon(Icons.refresh_rounded, color: tokens.textSecondary),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Global Control Bar (Store + Quick Date Range + In-Report Search)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _openStorePicker,
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
                                    size: 16,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _storeLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
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
                        FilledButton.tonalIcon(
                          onPressed: payload == null ? null : _shareWhatsApp,
                          style: FilledButton.styleFrom(
                            backgroundColor: NusaThemeTokens.of(context).whatsapp.withOpacity(0.12),
                            foregroundColor: NusaThemeTokens.of(context).whatsapp,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text(
                            'WA 1-Klik',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
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
                            ('custom', 'Kustom Kalender'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: NusaPillFilter(
                                label: p.$1 == 'custom' && _periodKey == 'custom'
                                    ? dateRangeInfo.label
                                    : p.$2,
                                selected: _periodKey == p.$1,
                                onTap: () => _selectPeriod(p.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Cari di dalam ${widget.definition.title}...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: tokens.textTertiary,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: tokens.textTertiary,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
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

            // 2. Offline Data Banner
            if (payload != null && payload.isOfflineData)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
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
                            'Data Offline (Sinkronisasi Terakhir: ${payload.lastSyncLabel ?? '-'})',
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

            // 3. Error State (Online 401/403/422/500 — NEVER masked)
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  child: NusaCard(
                    backgroundColor: tokens.dangerSoft,
                    borderColor: tokens.danger.withOpacity(0.35),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: tokens.danger),
                        const SizedBox(width: 10),
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
                          onPressed: _loadReport,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 4. Loading State
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
              )
            else if (payload != null) ...[
              // 5. Offline Notice for Cloud-exclusive GL/Tax Reports
              if (payload.offlineNotice != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                    child: NusaCard(
                      backgroundColor: tokens.bgSurface,
                      borderColor: tokens.borderSubtle,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: tokens.accent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              payload.offlineNotice!,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 6. Dynamic KPI Summary Cards
              if (payload.kpis.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        final isThree = payload.kpis.length == 3;
                        final cols = constraints.maxWidth >= 720
                            ? (isThree ? 3 : 4)
                            : (isThree && constraints.maxWidth >= 310
                                ? 3
                                : (constraints.maxWidth < 310 ? 1 : 2));
                        final ratio = cols == 3
                            ? 1.55
                            : (cols == 4 ? 2.1 : (constraints.maxWidth < 310 ? 2.8 : 2.2));
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: payload.kpis.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: ratio,
                          ),
                          itemBuilder: (_, idx) =>
                              _buildKpiCard(tokens, payload.kpis[idx], isCompact: cols >= 3),
                        );
                      },
                    ),
                  ),
                ),

              // 7. Compact Visual Distribution Bars for Top Contributors
              if (_shouldShowVisualBars(filteredItems))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _buildTopBarsCard(tokens, filteredItems),
                  ),
                ),

              // 8. Section Header + Row Count
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Rincian Data (${filteredItems.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Ketuk baris untuk rincian',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tokens.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 9. Stacked Mobile-First Cards
              if (filteredItems.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                    child: NusaCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 38,
                              color: tokens.textTertiary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Tidak ada data yang cocok dengan "$_searchQuery".'
                                  : 'Belum ada data transaksi pada periode ${payload.periodLabel}.',
                              textAlign: TextAlign.center,
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
                          _buildStackedRowCard(tokens, filteredItems[idx]),
                      childCount: filteredItems.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
