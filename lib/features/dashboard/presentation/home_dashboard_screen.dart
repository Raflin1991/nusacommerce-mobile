import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/cascade_entitlement_teaser.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';
import '../../auth/presentation/cloud_upgrade_sheet.dart';
import '../../notifications/presentation/alert_notifications_modal.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 2 — PUSAT KENDALI OPERASIONAL NUSACOMMERCE (Task-First Enterprise Home)
class HomeDashboardScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSwitchTab;

  const HomeDashboardScreen({
    super.key,
    required this.onOpenDrawer,
    required this.onSwitchTab,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();

  bool _loading = true;
  String? _error;
  double _todaySales = 0;
  int _todayTxCount = 0;
  double _grossProfit = 0;
  double _totalReceivables = 0;
  double _totalPayables = 0;
  int _lowStockCount = 0;
  int _expiringCount = 0;
  double _growthPercent = 0;
  int _openTasksCount = 0;
  int _pendingApprovalsCount = 0;
  int _pendingOnlineOrdersCount = 0;
  int _voidCount = 0;
  int _varianceShiftsCount = 0;
  List<Map<String, dynamic>> _approvalsList = [];
  List<Map<String, dynamic>> _tasksList = [];
  List<Map<String, dynamic>> _offlineConflictsList = [];
  List<Map<String, dynamic>> _overdueReceivables = [];
  int? _lastStoreId;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !context.read<AuthCubit>().state.session.isLocalTrial) {
        context.read<PosCubit>().syncWithCloud(force: false);
      }
    });
  }

  void _applyLocalDashboardMetrics({int? storeId}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final report = _offlineDb.computeLocalBusinessReport(
      startDate: todayStart,
      endDate: now,
    );
    final fraud = Map<String, dynamic>.from((report['fraud_indicators'] as Map?) ?? {});
    final receivables = _offlineDb.getLocalReceivables();
    final expiring = context
        .read<PosCubit>()
        .state
        .allProducts
        .where((p) => p.hasExpiringSoonBatch)
        .length;

    if (!mounted) return;
    setState(() {
      _todaySales = (report['net_sales'] as num?)?.toDouble() ?? 0;
      _todayTxCount = (report['transactions_count'] as num?)?.toInt() ?? 0;
      _grossProfit = (report['gross_profit'] as num?)?.toDouble() ?? 0;
      _growthPercent = 0;
      _totalReceivables = (report['total_receivables'] as num?)?.toDouble() ?? 0;
      _totalPayables = (report['total_payables'] as num?)?.toDouble() ?? 0;
      _lowStockCount = (report['low_stock_count'] as num?)?.toInt() ?? 0;
      _expiringCount = expiring;
      _pendingOnlineOrdersCount = 0;
      _voidCount = (fraud['void_count'] as num?)?.toInt() ?? 0;
      _varianceShiftsCount = (fraud['variance_shifts_count'] as num?)?.toInt() ?? 0;
      _overdueReceivables = receivables;
      _tasksList = const [];
      _approvalsList = const [];
      _offlineConflictsList = const [];
      _openTasksCount = 0;
      _pendingApprovalsCount = 0;
      _lastStoreId = storeId ?? context.read<AuthCubit>().state.session.activeStore.id;
      _error = null;
      _loading = false;
    });
  }

  Future<void> _loadDashboard({int? storeId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final session = context.read<AuthCubit>().state.session;
    if (session.isLocalTrial || !(await _connectivity.checkOnline())) {
      _applyLocalDashboardMetrics(storeId: storeId);
      return;
    }

    try {
      final activeStoreId = storeId ?? context.read<AuthCubit>().state.session.activeStore.id;
      final params = <String, dynamic>{'period': 'today'};
      if (activeStoreId > 0) {
        params['store_id'] = activeStoreId;
      }

      final res = await _api.dio.get(ApiEndpoints.ownerDashboard, queryParameters: params);
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final kpi = Map<String, dynamic>.from((data['kpi'] as Map?) ?? {});
      final alerts = Map<String, dynamic>.from((data['operational_alerts'] as Map?) ?? {});
      final auditWatch = Map<String, dynamic>.from(
        (data['anti_fraud_summary'] as Map?) ?? (data['audit_watch'] as Map?) ?? {},
      );

      final List<Map<String, dynamic>> tasksList = [];
      final List<Map<String, dynamic>> approvalsList = [];
      final List<Map<String, dynamic>> conflictsList = [];
      final List<Map<String, dynamic>> overdueList = [];
      try {
        final tRes = await _api.dio.get(ApiEndpoints.tasks);
        final tList = (tRes.data['data'] as List<dynamic>?) ?? [];
        for (final raw in tList) {
          if (raw is Map) tasksList.add(Map<String, dynamic>.from(raw));
        }
      } catch (_) {}

      try {
        final aRes = await _api.dio.get(ApiEndpoints.approvals);
        final aList = (aRes.data['data'] as List<dynamic>?) ?? [];
        for (final raw in aList) {
          if (raw is Map) approvalsList.add(Map<String, dynamic>.from(raw));
        }
      } catch (_) {}

      try {
        final cRes = await _api.dio.get(ApiEndpoints.offlineConflicts);
        final cList = (cRes.data['data'] as List<dynamic>?) ?? [];
        for (final raw in cList) {
          if (raw is Map) conflictsList.add(Map<String, dynamic>.from(raw));
        }
      } catch (_) {}

      try {
        final rRes = await _api.dio.get(ApiEndpoints.receivables, queryParameters: params);
        final rawData = rRes.data is Map ? rRes.data['data'] : null;
        final rawList = rawData is List
            ? rawData
            : (rawData is Map && rawData['items'] is List
                ? rawData['items'] as List
                : const <dynamic>[]);
        for (final raw in rawList) {
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            final dueAmt = ((map['balance_due'] ??
                    map['remaining_amount'] ??
                    map['amount'] ??
                    0) as num)
                .toDouble();
            if (dueAmt > 0) {
              overdueList.add(map);
            }
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _todaySales = (kpi['net_sales'] as num?)?.toDouble() ?? 0;
        _todayTxCount = (kpi['transactions_count'] as num?)?.toInt() ?? 0;
        _grossProfit = (kpi['gross_profit'] as num?)?.toDouble() ?? 0;
        _growthPercent = (kpi['growth_vs_yesterday_percent'] as num?)?.toDouble() ?? 0;
        _totalReceivables = (alerts['receivables_total'] as num?)?.toDouble() ?? 0;
        _totalPayables = (alerts['payables_total'] as num?)?.toDouble() ?? 0;
        _lowStockCount = (alerts['low_stock_count'] as num?)?.toInt() ?? 0;
        _expiringCount = (alerts['expiring_batches_count'] as num?)?.toInt() ?? 0;
        _pendingOnlineOrdersCount = (alerts['pending_online_orders_count'] as num?)?.toInt() ?? 0;
        _voidCount = ((auditWatch['voided_sales_count'] ?? auditWatch['void_count']) as num?)?.toInt() ?? 0;
        _varianceShiftsCount = ((auditWatch['shift_variance_alerts_count'] ?? auditWatch['variance_shifts_count']) as num?)?.toInt() ?? 0;
        _overdueReceivables = overdueList;
        _tasksList = tasksList;
        _approvalsList = approvalsList;
        _offlineConflictsList = conflictsList;
        _openTasksCount = tasksList.length;
        _pendingApprovalsCount = approvalsList.length;
        _lastStoreId = activeStoreId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final isLocalTrial = context.read<AuthCubit>().state.session.isLocalTrial;
      if (isLocalTrial ||
          _offlineDb.getCachedProducts().isNotEmpty ||
          _offlineDb.getLocalSalesHistory().isNotEmpty) {
        _applyLocalDashboardMetrics(storeId: storeId);
        return;
      }
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final posState = context.watch<PosCubit>().state;
    final activeStoreId = authState.session.activeStore.id;
    if (_lastStoreId != null && activeStoreId != _lastStoreId && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDashboard(storeId: activeStoreId);
      });
    }

    final displayName = authState.session.userName.trim().isEmpty
        ? 'Operator Toko'
        : authState.session.userName.trim();
    final localLowStock = posState.allProducts.where((p) => p.isLowStock).length;
    final localExpiring = posState.allProducts.where((p) => p.hasExpiringSoonBatch).length;
    final localVoidAndDiscount = posState.salesHistory
        .where((s) =>
            (s['status'] ?? '').toString().toUpperCase() == 'VOID' ||
            ((s['discount_total'] ?? s['discount_amount'] ?? 0) as num).toDouble() > 50000)
        .length;
    final mergedConflicts = _mergedOfflineConflicts(posState.localSyncConflicts);

    final badgeCount = (_lowStockCount > 0 ? _lowStockCount : localLowStock) +
        (_expiringCount > 0 ? _expiringCount : localExpiring) +
        _voidCount +
        localVoidAndDiscount +
        _varianceShiftsCount +
        _overdueReceivables.length +
        _openTasksCount +
        _pendingApprovalsCount +
        mergedConflicts.length +
        _pendingOnlineOrdersCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadDashboard(storeId: activeStoreId),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopHeader(
                  context,
                  authState.session,
                  posState.offlinePendingCount,
                  badgeCount,
                  activeStoreId,
                  mergedConflicts,
                ),
                const SizedBox(height: 12),

                if (posState.localSyncConflicts.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      showAlertNotificationsModal(
                        context,
                        voidCountFromServer: _voidCount,
                        varianceShiftsCount: _varianceShiftsCount,
                        overdueReceivables: _overdueReceivables,
                        storeName: authState.session.activeStore.name.isEmpty
                            ? 'NusaCommerce POS'
                            : authState.session.activeStore.name,
                        approvals: _approvalsList,
                        tasks: _tasksList,
                        offlineConflicts: mergedConflicts,
                        pendingOnlineOrdersCount: _pendingOnlineOrdersCount,
                        onDecideApproval: _decideApproval,
                        onOpenOnlineOrders: () => _showOnlineOrdersSheet(context),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.danger.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.sync_problem_rounded,
                              color: AppColors.dangerDark,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${posState.localSyncConflicts.length} Konflik Stok Sinkronisasi Offline',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.dangerDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Stok habis di server saat sinkronisasi. Ketuk untuk Setujui Oversell atau Batalkan & Refund Manual.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.slate700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.dangerDark,
                          ),
                        ],
                      ),
                    ),
                  ),

                if (authState.session.isLocalTrial)
                  _buildLocalTrialUpgradeBanner(context, activeStoreId),

                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.dangerDark, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.dangerDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _loadDashboard(storeId: activeStoreId),
                              child: const Text('Muat Ulang', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final posCubit = context.read<PosCubit>();
                                await context.read<AuthCubit>().logout();
                                await posCubit.resetForLogout();
                                if (context.mounted) {
                                  context.go('/login');
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.dangerDark,
                                side: const BorderSide(color: AppColors.danger),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('Login Ulang', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Compact Operator Strip
                _buildOperatorStrip(authState.session, displayName),
                const SizedBox(height: 12),

                // Primary Action Strip (Task-First Launch Bar)
                _buildPrimaryActionStrip(context, posState.capabilities),
                const SizedBox(height: 16),

                // Executive Pulse Card
                _buildExecutivePulseCard(context),
                const SizedBox(height: 12),

                // 2x2 Operational Metrics Grid
                _buildOperationalMetricsGrid(context),
                const SizedBox(height: 20),

                // Store Operations Directory (8 Core Modules Exposed Directly)
                const Text(
                  'Direktori Operasional Toko',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Akses 1-ketuk seluruh alur kerja kasir, stok, piutang & kontrol cabang.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate500),
                ),
                const SizedBox(height: 12),
                _buildModulesDirectory(context, posState.capabilities),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _mergedOfflineConflicts(
    List<Map<String, dynamic>> localConflicts,
  ) {
    final byUuid = <String, Map<String, dynamic>>{};
    for (final c in _offlineConflictsList) {
      final uuid = (c['local_uuid'] ?? c['id'] ?? '').toString();
      if (uuid.isNotEmpty) byUuid[uuid] = Map<String, dynamic>.from(c);
    }
    for (final c in localConflicts) {
      final uuid = (c['local_uuid'] ?? c['id'] ?? '').toString();
      if (uuid.isNotEmpty) {
        byUuid[uuid] = {
          ...?byUuid[uuid],
          ...Map<String, dynamic>.from(c),
        };
      }
    }
    return byUuid.values.toList();
  }

  Widget _buildTopHeader(
    BuildContext context,
    AuthSessionModel session,
    int offlinePendingCount,
    int badgeCount,
    int activeStoreId,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final storeName = session.activeStore.name.isEmpty
        ? 'NusaCommerce POS'
        : session.activeStore.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: widget.onOpenDrawer,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.menu_rounded, size: 22, color: AppColors.navyDark),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _showBranchSwitcherModal(context, session),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storefront_rounded, size: 15, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          session.activeStore.name.isEmpty ? 'Cabang Aktif' : session.activeStore.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.slate500),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Muat ulang dasbor',
              visualDensity: VisualDensity.compact,
              onPressed: _loading ? null : () => _loadDashboard(storeId: activeStoreId),
              icon: const Icon(Icons.refresh_rounded, size: 21, color: AppColors.slate700),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Pusat Radar Operasional Toko',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showAlertNotificationsModal(
                      context,
                      voidCountFromServer: _voidCount,
                      varianceShiftsCount: _varianceShiftsCount,
                      overdueReceivables: _overdueReceivables,
                      storeName: storeName,
                      approvals: _approvalsList,
                      tasks: _tasksList,
                      offlineConflicts: mergedConflicts,
                      pendingOnlineOrdersCount: _pendingOnlineOrdersCount,
                      onDecideApproval: _decideApproval,
                      onOpenOnlineOrders: () => _showOnlineOrdersSheet(context),
                    );
                  },
                  icon: const Icon(Icons.notifications_none_rounded, size: 23, color: AppColors.navyDark),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        BlocBuilder<PosCubit, PosState>(
          builder: (ctx, posState) {
            final effectivePending = posState.offlinePendingCount > 0
                ? posState.offlinePendingCount
                : offlinePendingCount;
            return NusaSyncStatusPill(
              isOnline: posState.isOnline,
              isSyncing: posState.isSyncingOfflineQueue,
              offlinePendingCount: effectivePending,
              onTap: () => ctx.read<PosCubit>().syncOfflineTransactions(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOperatorStrip(AuthSessionModel session, String displayName) {
    final storeCode = session.activeStore.code.isEmpty ? '-' : session.activeStore.code;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_outline_rounded, size: 22, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selamat bertugas, $displayName',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${session.userRole.isEmpty ? 'Operator' : session.userRole} • Kode Cabang: $storeCode',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.navyDark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              (session.planName.isEmpty ? 'Starter' : session.planName).toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionStrip(
    BuildContext context,
    VerticalCapabilities capabilities,
  ) {
    if (!capabilities.hasTableManagement) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/pos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.point_of_sale_rounded, size: 20),
                label: const Text(
                  'Buka Kasir POS',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/shifts'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navyDark,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.lock_clock_outlined, size: 18, color: AppColors.successDark),
                label: const Text(
                  'Shift Kasir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/pos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.point_of_sale_rounded, size: 20),
              label: const Text(
                'Buka Kasir POS',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/restaurant'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navyDark,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.table_restaurant_outlined, size: 18, color: AppColors.primary),
              label: const Text('Meja', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/shifts'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navyDark,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.lock_clock_outlined, size: 18, color: AppColors.successDark),
              label: const Text('Shift', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExecutivePulseCard(BuildContext context) {
    final isUp = _growthPercent >= 0;
    final sign = _growthPercent > 0 ? '+' : '';
    return InkWell(
      onTap: () => widget.onSwitchTab(3),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.executiveNavyGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Omzet Bersih Hari Ini',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _loading ? 'Memuat...' : '$_todayTxCount Transaksi',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _loading ? 'Memuat...' : IdrCurrencyFormatter.format(_todaySales),
              style: AppTheme.moneyStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: isUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$sign${_growthPercent.toStringAsFixed(1)}% vs kemarin',
                      style: TextStyle(
                        color: isUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Row(
                  children: [
                    Text(
                      'Detail Laporan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationalMetricsGrid(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                icon: Icons.monetization_on_outlined,
                accentColor: AppColors.successDark,
                label: 'Laba Kotor Hari Ini',
                value: _loading ? '...' : IdrCurrencyFormatter.format(_grossProfit),
                onTap: () => widget.onSwitchTab(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                icon: Icons.receipt_long_outlined,
                accentColor: AppColors.warningDark,
                label: 'Piutang Pelanggan (Bon)',
                value: _loading ? '...' : IdrCurrencyFormatter.format(_totalReceivables),
                onTap: () => context.push('/debts'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                icon: Icons.local_shipping_outlined,
                accentColor: AppColors.primary,
                label: 'Hutang Supplier Tempo',
                value: _loading ? '...' : IdrCurrencyFormatter.format(_totalPayables),
                onTap: () => context.push('/debts?tab=payables'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                icon: Icons.inventory_2_outlined,
                accentColor: (_lowStockCount + _expiringCount) > 0 ? AppColors.dangerDark : AppColors.purple,
                label: 'Stok Menipis & FEFO',
                value: _loading ? '...' : '$_lowStockCount Menipis • $_expiringCount FEFO',
                onTap: () => widget.onSwitchTab(2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOperationalMetricTile({
    required IconData icon,
    required Color accentColor,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTheme.moneyStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModulesDirectory(
    BuildContext context,
    VerticalCapabilities capabilities,
  ) {
    final session = context.watch<AuthCubit>().state.session;
    final onlineGated = session.isModuleGated('online_store');
    final accountingGated = session.isModuleGated('accounting');
    final hrGated = session.isModuleGated('hr');

    final modules = [
      (
        icon: Icons.point_of_sale_rounded,
        color: AppColors.primary,
        title: capabilities.posDisplayName,
        subtitle: capabilities.posSubtitle,
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/pos'),
      ),
      (
        icon: Icons.local_shipping_outlined,
        color: AppColors.warningDark,
        title: 'Pemasok & Stok Masuk',
        subtitle: 'Supplier, rekening & beli stok',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/suppliers?tab=stock-in'),
      ),
      (
        icon: Icons.inventory_2_outlined,
        color: AppColors.purple,
        title: 'Katalog & Opname Stok',
        subtitle: 'Produk, HPP, FEFO & kamera',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => widget.onSwitchTab(2),
      ),
      (
        icon: Icons.people_outline_rounded,
        color: AppColors.primaryDark,
        title: 'Pelanggan & Member',
        subtitle: 'Diskon grup, poin & kasbon',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/customers'),
      ),
      (
        icon: Icons.menu_book_outlined,
        color: AppColors.dangerDark,
        title: 'Buku Bon & Biaya Toko',
        subtitle: 'Piutang, hutang & pengeluaran',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/debts'),
      ),
      (
        icon: Icons.lock_clock_outlined,
        color: AppColors.successDark,
        title: 'Shift Kasir & Z-Report',
        subtitle: 'Kas laci, mutasi & blind count',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/shifts'),
      ),
      if (capabilities.hasTableManagement)
        (
          icon: Icons.table_restaurant_outlined,
          color: AppColors.navyMid,
          title: 'Denah Meja & Resto F&B',
          subtitle: 'Open tab, pindah meja & KOT',
          isGated: false,
          requiredTier: 'STARTER',
          onTap: () => context.push('/restaurant'),
        ),
      (
        icon: Icons.analytics_outlined,
        color: AppColors.navyDark,
        title: 'Laporan Laba Rugi Owner',
        subtitle: accountingGated
            ? 'Ringkasan kas & SAK EMKM'
            : 'SAK EMKM, metode & anti-fraud',
        isGated: accountingGated,
        requiredTier: 'PRO',
        onTap: () {
          if (accountingGated) {
            showCascadeModuleTeaserModal(
              context,
              moduleKey: 'accounting',
              moduleTitle: 'Laporan Keuangan & Akuntansi SAK EMKM',
              requiredTier: 'PRO',
              currentTier: session.tier,
              description:
                  'Buka laporan neraca lengkap, buku besar, dan jurnal otomatis standar SAK EMKM.',
              benefits: const [
                'Laporan Laba Rugi & Neraca otomatis per cabang',
                'Buku besar & jurnal transaksi kasir real-time',
                'Kontrol biaya & anti-fraud kasir menyeluruh',
              ],
            );
          } else {
            widget.onSwitchTab(3);
          }
        },
      ),
      (
        icon: Icons.shopping_bag_outlined,
        color: AppColors.primary,
        title: 'Pesanan Toko Online',
        subtitle: onlineGated
            ? 'Etalase web & order otomatis'
            : (_pendingOnlineOrdersCount > 0
                ? '$_pendingOnlineOrdersCount pesanan menunggu proses'
                : 'Kelola webstore, status & resi'),
        isGated: onlineGated,
        requiredTier: 'PRO',
        onTap: () {
          if (onlineGated) {
            showCascadeModuleTeaserModal(
              context,
              moduleKey: 'online_store',
              moduleTitle: 'Pesanan Toko Online (Webstore)',
              requiredTier: 'PRO',
              currentTier: session.tier,
              description:
                  'Terima order online pelanggan langsung ke POS dengan potong stok terpusat.',
              benefits: const [
                'Katalog web toko siap pakai dengan subdomain toko',
                'Proses order online & resi langsung dari HP kasir',
                'Terhubung dengan saldo & pelanggan member',
              ],
            );
          } else {
            _showOnlineOrdersSheet(context);
          }
        },
      ),
      (
        icon: Icons.badge_outlined,
        color: AppColors.navyMid,
        title: 'HRD & Absensi Staf',
        subtitle: 'Jadwal shift, foto & komisi',
        isGated: hrGated,
        requiredTier: 'ENTERPRISE',
        onTap: () {
          if (hrGated) {
            showCascadeModuleTeaserModal(
              context,
              moduleKey: 'hr',
              moduleTitle: 'HRD, Shift & Absensi Karyawan',
              requiredTier: 'ENTERPRISE',
              currentTier: session.tier,
              description:
                  'Pantau absensi foto/GPS staf cabang dan komisi kasir otomatis.',
              benefits: const [
                'Absensi kasir berbasis shift dengan foto & lokasi',
                'Rekap keterlambatan & lembur karyawan cabang',
                'Perhitungan komisi kasir per transaksi otomatis',
              ],
            );
          } else {
            context.push('/shifts');
          }
        },
      ),
    ];

    return Column(
      children: [
        for (int i = 0; i < modules.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildModuleDirectoryCard(
                  icon: modules[i].icon,
                  color: modules[i].color,
                  title: modules[i].title,
                  subtitle: modules[i].subtitle,
                  isGated: modules[i].isGated,
                  requiredTier: modules[i].requiredTier,
                  onTap: modules[i].onTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < modules.length
                    ? _buildModuleDirectoryCard(
                        icon: modules[i + 1].icon,
                        color: modules[i + 1].color,
                        title: modules[i + 1].title,
                        subtitle: modules[i + 1].subtitle,
                        isGated: modules[i + 1].isGated,
                        requiredTier: modules[i + 1].requiredTier,
                        onTap: modules[i + 1].onTap,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildModuleDirectoryCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isGated = false,
    String requiredTier = 'PRO',
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isGated ? const Color(0xFFFFFBEB) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isGated ? const Color(0xFFFDE68A) : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDark,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (isGated) ...[
                        const SizedBox(width: 4),
                        CascadeCrownBadge(requiredTier: requiredTier),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.slate500,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _decideApproval(int approvalId, String decision, {String? notes}) async {
    try {
      final res = await _api.dio.post(
        ApiEndpoints.decideApproval(approvalId),
        data: {
          'decision': decision,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      if (res.data is Map && res.data['success'] == true) {
        if (mounted) {
          setState(() {
            _approvalsList.removeWhere((a) => (a['id'] as num?)?.toInt() == approvalId);
            _pendingApprovalsCount = _approvalsList.length;
          });
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _showOnlineOrdersSheet(BuildContext context) async {
    List<Map<String, dynamic>> orders = [];
    bool loadingOrders = true;
    String? ordersError;
    String selectedFilter = 'all';

    Future<void> fetchOrders(StateSetter setModalState) async {
      setModalState(() {
        loadingOrders = true;
        ordersError = null;
      });
      try {
        final params = <String, dynamic>{};
        if (selectedFilter != 'all') {
          params['online_order_status'] = selectedFilter;
        }
        final res = await _api.dio.get(ApiEndpoints.onlineOrders, queryParameters: params);
        final raw = (res.data['data'] as List<dynamic>?) ?? [];
        orders = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        ordersError = ApiClient.extractErrorMessage(e);
      } finally {
        setModalState(() => loadingOrders = false);
      }
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool initialized = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!initialized) {
              initialized = true;
              Future.microtask(() => fetchOrders(setModalState));
            }
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              maxChildSize: 0.94,
              builder: (_, scrollCtrl) => Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pesanan Toko Online (Webstore)',
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: loadingOrders ? null : () => fetchOrders(setModalState),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final f in const [
                            ('all', 'Semua'),
                            ('pending_payment', 'Menunggu Bayar'),
                            ('paid', 'Sudah Dibayar'),
                            ('processing', 'Diproses'),
                            ('shipped', 'Dikirim'),
                            ('completed', 'Selesai'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: NusaPillFilter(
                                label: f.$2,
                                selected: selectedFilter == f.$1,
                                onTap: () {
                                  selectedFilter = f.$1;
                                  fetchOrders(setModalState);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loadingOrders
                          ? const Center(child: CircularProgressIndicator())
                          : ordersError != null
                              ? Center(
                                  child: Text(
                                    ordersError!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.dangerDark),
                                  ),
                                )
                              : orders.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Belum ada pesanan toko online pada filter ini.',
                                        style: TextStyle(color: AppColors.slate500),
                                      ),
                                    )
                                  : ListView.separated(
                                      controller: scrollCtrl,
                                      itemCount: orders.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (_, idx) {
                                        final o = orders[idx];
                                        final id = (o['id'] as num?)?.toInt() ?? 0;
                                        final status = (o['online_order_status'] ?? 'pending_payment').toString();
                                        final total = (o['grand_total'] as num?)?.toDouble() ?? 0;
                                        return NusaCard(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '${o['number'] ?? '#ONLINE'} • ${o['customer_name'] ?? 'Pelanggan'}',
                                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                                    ),
                                                  ),
                                                  Text(
                                                    IdrCurrencyFormatter.format(total),
                                                    style: AppTheme.moneyStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w800,
                                                      color: AppColors.primary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${o['items_count'] ?? 0} item • Status: ${status.toUpperCase()}'
                                                '${o['tracking_number'] != null ? ' • Resi: ${o['tracking_number']}' : ''}',
                                                style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                                              ),
                                              if (o['shipping_address'] != null && o['shipping_address'].toString().isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    o['shipping_address'].toString(),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                                                  ),
                                                ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  if (status == 'pending_payment' || status == 'paid')
                                                    OutlinedButton(
                                                      onPressed: () async {
                                                        await _updateOnlineOrder(id, 'processing', setModalState, fetchOrders);
                                                      },
                                                      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                                      child: const Text('Proses Order'),
                                                    ),
                                                  if (status == 'processing' || status == 'paid')
                                                    ElevatedButton(
                                                      onPressed: () => _promptShipOnlineOrder(ctx, id, setModalState, fetchOrders),
                                                      style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                                                      child: const Text('Input Resi & Kirim'),
                                                    ),
                                                  if (status == 'shipped')
                                                    ElevatedButton(
                                                      onPressed: () async {
                                                        await _updateOnlineOrder(id, 'completed', setModalState, fetchOrders);
                                                      },
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: AppColors.successDark,
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                      child: const Text('Tandai Selesai'),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      await _loadDashboard();
    }
  }

  Future<void> _updateOnlineOrder(
    int orderId,
    String newStatus,
    StateSetter setModalState,
    Future<void> Function(StateSetter) reload, {
    String? trackingNumber,
  }) async {
    try {
      await _api.dio.post(
        ApiEndpoints.updateOnlineOrderStatus(orderId),
        data: {
          'online_order_status': newStatus,
          if (trackingNumber != null && trackingNumber.trim().isNotEmpty)
            'shipping_tracking_number': trackingNumber.trim(),
        },
      );
      await reload(setModalState);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(ApiClient.extractErrorMessage(e)),
          ),
        );
      }
    }
  }

  Future<void> _promptShipOnlineOrder(
    BuildContext context,
    int orderId,
    StateSetter setModalState,
    Future<void> Function(StateSetter) reload,
  ) async {
    final resiCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kirim Pesanan Online', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: resiCtrl,
          decoration: const InputDecoration(
            labelText: 'Nomor Resi / Kurir (Opsional)',
            hintText: 'Contoh: JNE-102938475',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
        ],
      ),
    );
    if (ok == true) {
      await _updateOnlineOrder(
        orderId,
        'shipped',
        setModalState,
        reload,
        trackingNumber: resiCtrl.text,
      );
    }
  }

  void _showBranchSwitcherModal(BuildContext context, AuthSessionModel session) {
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
            const Text(
              'Pilih Cabang Toko Aktif',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...session.availableStores.map(
              (branch) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: branch.id == session.activeStore.id
                      ? AppColors.primary
                      : AppColors.primarySoft,
                  child: Icon(
                    Icons.store_rounded,
                    color: branch.id == session.activeStore.id ? Colors.white : AppColors.primary,
                  ),
                ),
                title: Text(branch.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Kode: ${branch.code} • ${branch.city ?? 'Indonesia'}'),
                trailing: branch.id == session.activeStore.id
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                    : null,
                onTap: () {
                  context.read<AuthCubit>().switchStoreBranch(branch);
                  Navigator.pop(ctx);
                  _loadDashboard(storeId: branch.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTrialUpgradeBanner(BuildContext context, int activeStoreId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Usaha Mandiri (Tersimpan di HP ini)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cadangkan ke NusaCommerce Cloud agar aman jika HP ganti atau rusak.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final migrated = await showCloudMigrationSheet(context);
                if (migrated == true && mounted) {
                  await _loadDashboard(storeId: activeStoreId);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.cloud_sync_rounded, size: 18),
              label: const Text(
                'Hubungkan Akun Cloud',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
