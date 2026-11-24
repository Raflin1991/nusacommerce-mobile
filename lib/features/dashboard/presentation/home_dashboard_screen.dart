import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/cascade_entitlement_teaser.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';
import '../../auth/presentation/cloud_upgrade_sheet.dart';
import '../../copilot/presentation/nusa_copilot_sheet.dart';
import '../../notifications/presentation/alert_notifications_modal.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 2 — PUSAT KENDALI OPERASIONAL ROLE-ADAPTIVE OXORA (Gelombang 5)
/// - Role-Adaptive Workspaces: Owner Pulse, Manager Desk, POS Fast-Lane, Warehouse Workbench, ESS & HR
/// - Parallel API Fetch (`Future.wait`) eliminating 5-call serial waterfall
/// - Shimmer Skeleton Loading + CDO Warm Linen (Light / Dark / High-Contrast Outdoor POS)
/// - OXORA Copilot Mobile AI trigger + Inline Modal Error Guard
class HomeDashboardScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSwitchTab;
  final MobileWorkspaceRole? activeWorkspace;
  final ValueChanged<MobileWorkspaceRole>? onSelectWorkspace;
  final VoidCallback? onOpenCopilot;

  const HomeDashboardScreen({
    super.key,
    required this.onOpenDrawer,
    required this.onSwitchTab,
    this.activeWorkspace,
    this.onSelectWorkspace,
    this.onOpenCopilot,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();

  Future<void>? _activeLoadFuture;

  bool _loading = true;
  String? _error;
  String _selectedPeriod = 'month';
  String _growthLabel = 'vs bln lalu';
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

  String get _periodTitle {
    switch (_selectedPeriod) {
      case 'month':
        return 'Omzet Bulan Ini (MTD)';
      case 'today':
        return 'Omzet Bersih Hari Ini';
      case 'yesterday':
        return 'Omzet Bersih Kemarin';
      case '7d':
        return 'Omzet 7 Hari Terakhir';
      case '30d':
        return 'Omzet 30 Hari Terakhir';
      default:
        return 'Omzet Bersih';
    }
  }

  String get _grossProfitTitle {
    switch (_selectedPeriod) {
      case 'month':
        return 'Laba Kotor Bulan Ini';
      case 'today':
        return 'Laba Kotor Hari Ini';
      case 'yesterday':
        return 'Laba Kotor Kemarin';
      case '7d':
        return 'Laba Kotor 7 Hari';
      case '30d':
        return 'Laba Kotor 30 Hari';
      default:
        return 'Laba Kotor';
    }
  }

  // Shift fast-lane summary (Blind Drop compliant: never stores expected_cash for cashiers)
  bool _hasOpenShift = false;
  bool _shiftBlindDropEnforced = true;
  String _shiftTerminalLabel = '';

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

  MobileWorkspaceRole _effectiveWorkspace(AuthSessionModel session) {
    return MobileWorkspaceResolver.sanitizeActiveWorkspace(
      session,
      widget.activeWorkspace,
    );
  }

  void _openCopilot(AuthSessionModel session) {
    if (widget.onOpenCopilot != null) {
      widget.onOpenCopilot!();
    } else {
      showNusaCopilotSheet(context, workspace: _effectiveWorkspace(session));
    }
  }

  ThemeCubit? _maybeThemeCubit(BuildContext context) {
    try {
      return context.watch<ThemeCubit>();
    } catch (_) {
      return null;
    }
  }

  void _applyLocalDashboardMetrics({int? storeId, String? period}) {
    final now = DateTime.now();
    final p = period ?? _selectedPeriod;
    DateTime startDate;
    if (p == 'month') {
      startDate = DateTime(now.year, now.month, 1);
    } else if (p == '7d') {
      startDate = now.subtract(const Duration(days: 6));
    } else if (p == '30d') {
      startDate = now.subtract(const Duration(days: 29));
    } else if (p == 'yesterday') {
      final y = now.subtract(const Duration(days: 1));
      startDate = DateTime(y.year, y.month, y.day);
    } else {
      startDate = DateTime(now.year, now.month, now.day);
    }
    final report = _offlineDb.computeLocalBusinessReport(
      startDate: startDate,
      endDate: now,
    );
    final fraud = Map<String, dynamic>.from((report['fraud_indicators'] as Map?) ?? {});
    final receivables = _offlineDb.getLocalReceivables();
    final localShift = _offlineDb.getCurrentLocalShift();
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
      _growthLabel = _selectedPeriod == 'month' ? 'vs bln lalu' : 'vs kemarin';
      _totalReceivables = (report['total_receivables'] as num?)?.toDouble() ?? 0;
      _totalPayables = (report['total_payables'] as num?)?.toDouble() ?? 0;
      _lowStockCount = (report['low_stock_count'] as num?)?.toInt() ?? 0;
      _expiringCount = expiring;
      _pendingOnlineOrdersCount = 0;
      _voidCount = (fraud['void_count'] as num?)?.toInt() ?? 0;
      _varianceShiftsCount = (fraud['variance_shifts_count'] as num?)?.toInt() ?? 0;
      _hasOpenShift = localShift != null;
      _shiftBlindDropEnforced = true;
      _shiftTerminalLabel = localShift != null ? 'Kasir Mandiri Lokal' : '';
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

  Future<Response<dynamic>?> _safeGet(
    String path, {
    Map<String, dynamic>? queryParameters,
    void Function(Object err)? onFatalError,
  }) async {
    try {
      return await _api.dio.get(path, queryParameters: queryParameters);
    } catch (e) {
      if (onFatalError != null) {
        onFatalError(e);
      }
      return null;
    }
  }

  Future<void> _loadDashboard({int? storeId, String? period}) {
    if (_activeLoadFuture != null) {
      return _activeLoadFuture!;
    }
    final future = _executeDashboardLoad(storeId: storeId, period: period);
    _activeLoadFuture = future;
    future.whenComplete(() {
      if (identical(_activeLoadFuture, future)) {
        _activeLoadFuture = null;
      }
    });
    return future;
  }

  Future<void> _executeDashboardLoad({int? storeId, String? period}) async {
    final activePeriod = period ?? _selectedPeriod;
    if (period != null && period != _selectedPeriod) {
      _selectedPeriod = period;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final session = context.read<AuthCubit>().state.session;
    if (session.isLocalTrial || !(await _connectivity.checkOnline())) {
      _applyLocalDashboardMetrics(storeId: storeId, period: activePeriod);
      return;
    }

    final workspace = _effectiveWorkspace(session);
    final activeStoreId = storeId ?? session.activeStore.id;
    final params = <String, dynamic>{'period': activePeriod};
    if (activeStoreId > 0) {
      params['store_id'] = activeStoreId;
    }

    final shouldFetchOwner = MobileWorkspaceResolver.canViewOwnerDashboard(session);
    final shouldFetchApprovals = MobileWorkspaceResolver.canViewApprovals(session);
    final shouldFetchConflicts = MobileWorkspaceResolver.canUsePos(session);
    final shouldFetchReceivables = MobileWorkspaceResolver.canViewReceivables(session) &&
        workspace != MobileWorkspaceRole.warehouseWorkbench &&
        workspace != MobileWorkspaceRole.employeeEss;
    final shouldFetchShift = MobileWorkspaceResolver.canUsePos(session);

    Object? primaryError;

    // PARALLELIZED BATCH (`Future.wait`) — Eliminates serial API round-trips
    final futures = <Future<Response<dynamic>?>>[
      shouldFetchOwner
          ? _safeGet(
              ApiEndpoints.ownerDashboard,
              queryParameters: params,
              onFatalError: (e) => primaryError = e,
            )
          : Future.value(null),
      _safeGet(ApiEndpoints.tasks),
      shouldFetchApprovals ? _safeGet(ApiEndpoints.approvals) : Future.value(null),
      shouldFetchConflicts ? _safeGet(ApiEndpoints.offlineConflicts) : Future.value(null),
      shouldFetchReceivables
          ? _safeGet(ApiEndpoints.receivables, queryParameters: params)
          : Future.value(null),
      shouldFetchShift ? _safeGet(ApiEndpoints.currentShift) : Future.value(null),
    ];

    final responses = await Future.wait(futures);
    if (!mounted) return;

    final ownerRes = responses[0];
    final tasksRes = responses[1];
    final approvalsRes = responses[2];
    final conflictsRes = responses[3];
    final receivablesRes = responses[4];
    final shiftRes = responses[5];

    // If owner dashboard failed catastrophically AND no other endpoint succeeded, handle gracefully
    if (shouldFetchOwner && ownerRes == null && primaryError != null && tasksRes == null) {
      if (_offlineDb.getCachedProducts().isNotEmpty ||
          _offlineDb.getLocalSalesHistory().isNotEmpty) {
        _applyLocalDashboardMetrics(storeId: storeId);
        return;
      }
      setState(() {
        _error = ApiClient.extractErrorMessage(primaryError!);
        _loading = false;
      });
      return;
    }

    final rawOwnerData = ownerRes?.data is Map ? ownerRes!.data['data'] : null;
    final ownerData = rawOwnerData is Map
        ? Map<String, dynamic>.from(rawOwnerData)
        : <String, dynamic>{};
    final kpi = ownerData['kpi'] is Map
        ? Map<String, dynamic>.from(ownerData['kpi'] as Map)
        : <String, dynamic>{};
    final alerts = ownerData['operational_alerts'] is Map
        ? Map<String, dynamic>.from(ownerData['operational_alerts'] as Map)
        : <String, dynamic>{};
    final rawAudit = ownerData['anti_fraud_summary'] ?? ownerData['audit_watch'];
    final auditWatch = rawAudit is Map
        ? Map<String, dynamic>.from(rawAudit)
        : <String, dynamic>{};

    final tasksList = <Map<String, dynamic>>[];
    if (tasksRes?.data is Map && tasksRes!.data['data'] is List) {
      final raw = tasksRes.data['data'] as List<dynamic>;
      for (final item in raw) {
        if (item is Map) tasksList.add(Map<String, dynamic>.from(item));
      }
    }

    final approvalsList = <Map<String, dynamic>>[];
    if (approvalsRes?.data is Map && approvalsRes!.data['data'] is List) {
      final raw = approvalsRes.data['data'] as List<dynamic>;
      for (final item in raw) {
        if (item is Map) approvalsList.add(Map<String, dynamic>.from(item));
      }
    }

    final conflictsList = <Map<String, dynamic>>[];
    if (conflictsRes?.data is Map && conflictsRes!.data['data'] is List) {
      final raw = conflictsRes.data['data'] as List<dynamic>;
      for (final item in raw) {
        if (item is Map) conflictsList.add(Map<String, dynamic>.from(item));
      }
    }

    final overdueList = <Map<String, dynamic>>[];
    if (receivablesRes?.data is Map) {
      final rawData = receivablesRes!.data['data'];
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
          if (dueAmt > 0) overdueList.add(map);
        }
      }
    }

    bool hasOpenShift = false;
    bool blindDropEnforced = true;
    String shiftTerminal = '';
    final rawShiftData = shiftRes?.data is Map ? shiftRes!.data['data'] : null;
    if (rawShiftData is Map) {
      final sData = Map<String, dynamic>.from(rawShiftData);
      hasOpenShift = sData['has_open_shift'] == true && sData['shift'] is Map;
      blindDropEnforced = sData['blind_drop_enforced'] == true;
      if (hasOpenShift) {
        final sMap = Map<String, dynamic>.from(sData['shift'] as Map);
        final term = sMap['terminal'] as Map?;
        shiftTerminal = (term?['name'] ?? 'POS Utama').toString();
      }
    }

    setState(() {
      _todaySales = (kpi['net_sales'] as num?)?.toDouble() ?? 0;
      _todayTxCount = (kpi['transactions_count'] as num?)?.toInt() ?? 0;
      _grossProfit = (kpi['gross_profit'] as num?)?.toDouble() ?? 0;
      _growthPercent = ((kpi['growth_percent'] ?? kpi['growth_vs_yesterday_percent']) as num?)?.toDouble() ?? 0;
      _growthLabel = (kpi['growth_label'] as String?) ?? (_selectedPeriod == 'month' ? 'vs bln lalu' : 'vs kemarin');
      _totalReceivables = (alerts['receivables_total'] as num?)?.toDouble() ?? 0;
      _totalPayables = (alerts['payables_total'] as num?)?.toDouble() ?? 0;
      _lowStockCount = (alerts['low_stock_count'] as num?)?.toInt() ?? 0;
      _expiringCount = (alerts['expiring_batches_count'] as num?)?.toInt() ?? 0;
      _pendingOnlineOrdersCount =
          (alerts['pending_online_orders_count'] as num?)?.toInt() ?? 0;
      _voidCount = ((auditWatch['voided_sales_count'] ?? auditWatch['void_count']) as num?)
              ?.toInt() ??
          0;
      _varianceShiftsCount =
          ((auditWatch['shift_variance_alerts_count'] ?? auditWatch['variance_shifts_count'])
                      as num?)
                  ?.toInt() ??
              0;
      _hasOpenShift = hasOpenShift;
      _shiftBlindDropEnforced = blindDropEnforced;
      _shiftTerminalLabel = shiftTerminal;
      _overdueReceivables = overdueList;
      _tasksList = tasksList;
      _approvalsList = approvalsList;
      _offlineConflictsList = conflictsList;
      _openTasksCount = tasksList.length;
      _pendingApprovalsCount = approvalsList.length;
      _lastStoreId = activeStoreId;
      _error = null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final authState = context.watch<AuthCubit>().state;
    final posState = context.watch<PosCubit>().state;
    final session = authState.session;
    final workspace = _effectiveWorkspace(session);
    final activeStoreId = session.activeStore.id;

    if (_lastStoreId != null && activeStoreId != _lastStoreId && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDashboard(storeId: activeStoreId);
      });
    }

    final displayName =
        session.userName.trim().isEmpty ? 'Operator Toko' : session.userName.trim();
    final localLowStock = posState.allProducts.where((p) => p.isLowStock).length;
    final localExpiring = posState.allProducts.where((p) => p.hasExpiringSoonBatch).length;
    final effectiveLowStock = _lowStockCount > 0 ? _lowStockCount : localLowStock;
    final effectiveExpiring = _expiringCount > 0 ? _expiringCount : localExpiring;
    final mergedConflicts = _mergedOfflineConflicts(posState.localSyncConflicts);

    final badgeCount = effectiveLowStock +
        effectiveExpiring +
        _voidCount +
        _varianceShiftsCount +
        _overdueReceivables.length +
        _openTasksCount +
        _pendingApprovalsCount +
        mergedConflicts.length +
        _pendingOnlineOrdersCount;

    final canSwitchWorkspaces =
        MobileWorkspaceResolver.canSwitchWorkspaces(session) &&
            widget.onSelectWorkspace != null;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      body: SafeArea(
        child: RefreshIndicator(
          color: tokens.accent,
          onRefresh: () => _loadDashboard(storeId: activeStoreId),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopHeader(
                  context,
                  tokens,
                  session,
                  posState.offlinePendingCount,
                  badgeCount,
                  activeStoreId,
                  mergedConflicts,
                ),
                const SizedBox(height: 10),

                if (canSwitchWorkspaces) ...[
                  _buildWorkspaceSwitcherStrip(tokens, workspace),
                  const SizedBox(height: 10),
                ],

                if (_loading)
                  NusaDashboardSkeleton(
                    compactCashierLayout:
                        workspace == MobileWorkspaceRole.posFastLane ||
                            workspace == MobileWorkspaceRole.employeeEss,
                  )
                else ...[
                  if (posState.localSyncConflicts.isNotEmpty &&
                      MobileWorkspaceResolver.canUsePos(session))
                    _buildSyncConflictBanner(
                      context,
                      tokens,
                      session,
                      posState,
                      mergedConflicts,
                    ),

                  if (session.isLocalTrial)
                    _buildLocalTrialUpgradeBanner(context, tokens, activeStoreId),

                  if (_error != null)
                    _buildErrorBanner(context, tokens, activeStoreId),

                  // Role-Adaptive Workspace Body
                  if (workspace == MobileWorkspaceRole.posFastLane)
                    _buildPosFastLaneWorkspace(
                      context,
                      tokens,
                      session,
                      posState,
                      displayName,
                      mergedConflicts,
                    )
                  else if (workspace == MobileWorkspaceRole.warehouseWorkbench)
                    _buildWarehouseWorkbenchWorkspace(
                      context,
                      tokens,
                      session,
                      posState,
                      displayName,
                      effectiveLowStock,
                      effectiveExpiring,
                    )
                  else if (workspace == MobileWorkspaceRole.employeeEss)
                    _buildEmployeeEssWorkspace(
                      context,
                      tokens,
                      session,
                      displayName,
                    )
                  else if (workspace == MobileWorkspaceRole.managerDesk)
                    _buildManagerDeskWorkspace(
                      context,
                      tokens,
                      session,
                      posState,
                      displayName,
                      effectiveLowStock,
                      effectiveExpiring,
                      mergedConflicts,
                    )
                  else
                    _buildOwnerPulseWorkspace(
                      context,
                      tokens,
                      session,
                      posState,
                      displayName,
                      effectiveLowStock,
                      effectiveExpiring,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceSwitcherStrip(
    NusaThemeTokens tokens,
    MobileWorkspaceRole current,
  ) {
    return SizedBox(
      key: const Key('workspace_switcher_strip'),
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final role in MobileWorkspaceResolver.operationalWorkspaces) ...[
            NusaPillFilter(
              key: Key('workspace_chip_${role.name}'),
              label: MobileWorkspaceResolver.specFor(role).title,
              icon: MobileWorkspaceResolver.specFor(role).icon,
              selected: role == current,
              onTap: () => widget.onSelectWorkspace?.call(role),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildOwnerPulseWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    int lowStock,
    int expiring,
  ) {
    return Column(
      key: const Key('workspace_owner_pulse'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.ownerPulse),
        const SizedBox(height: 12),
        _buildPrimaryActionStrip(context, tokens, posState.capabilities),
        const SizedBox(height: 14),
        _buildExecutivePulseCard(context, tokens),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.ownerPulse),
        const SizedBox(height: 12),
        _buildQuickActionSpeedDial(context, tokens, session),
        const SizedBox(height: 12),
        _buildOperationalMetricsGrid(context, tokens, lowStock, expiring),
        const SizedBox(height: 12),
        _buildAllModulesBanner(context, tokens),
        const SizedBox(height: 18),
        Text(
          'Direktori Operasional Toko',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Akses 1-ketuk seluruh alur kerja kasir, stok, piutang & kontrol cabang.',
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        const SizedBox(height: 12),
        _buildModulesDirectory(context, tokens, posState.capabilities),
      ],
    );
  }

  Widget _buildManagerDeskWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    int lowStock,
    int expiring,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final canViewProfit = MobileWorkspaceResolver.canViewProfit(session);
    final canUsePos = MobileWorkspaceResolver.canUsePos(session);
    final canViewShifts = MobileWorkspaceResolver.canViewShifts(session);
    final canViewReports = MobileWorkspaceResolver.canViewOwnerDashboard(session);
    return Column(
      key: const Key('workspace_manager_desk'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.managerDesk),
        const SizedBox(height: 12),
        if (canUsePos || canViewShifts) ...[
          _buildPrimaryActionStrip(context, tokens, posState.capabilities),
          const SizedBox(height: 12),
        ] else if (canViewReports) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/reports'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.analytics_rounded, size: 20),
              label: const Text(
                'Buka Laporan & Audit Terpadu',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Action-first Operational Queue Strip
        NusaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Antrean Pengawasan Cabang',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NusaBadge(
                    label: '${_pendingApprovalsCount + _openTasksCount + _varianceShiftsCount} Item',
                    variant: (_pendingApprovalsCount + _varianceShiftsCount) > 0
                        ? NusaBadgeVariant.warning
                        : NusaBadgeVariant.success,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: MobileWorkspaceResolver.canViewApprovals(session)
                          ? () => context.push('/approvals')
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      child: _compactStatChip(
                        tokens,
                        label: 'Approval',
                        value: '$_pendingApprovalsCount',
                        accent: tokens.warning,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactStatChip(
                      tokens,
                      label: 'Tugas',
                      value: '$_openTasksCount',
                      accent: tokens.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactStatChip(
                      tokens,
                      label: 'Selisih Shift',
                      value: '$_varianceShiftsCount',
                      accent: _varianceShiftsCount > 0 ? tokens.danger : tokens.positive,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (canViewReports) ...[
          _buildExecutivePulseCard(context, tokens),
          const SizedBox(height: 12),
        ],
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.managerDesk),
        const SizedBox(height: 12),
        if (canViewProfit)
          _buildOperationalMetricsGrid(context, tokens, lowStock, expiring)
        else
          Row(
            children: [
              Expanded(
                child: _buildOperationalMetricTile(
                  tokens,
                  icon: Icons.inventory_2_outlined,
                  accentColor: (lowStock + expiring) > 0 ? tokens.danger : tokens.positive,
                  label: 'Stok Menipis & FEFO',
                  value: '$lowStock Menipis • $expiring FEFO',
                  onTap: () => widget.onSwitchTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildOperationalMetricTile(
                  tokens,
                  icon: Icons.sync_problem_outlined,
                  accentColor: mergedConflicts.isNotEmpty ? tokens.danger : tokens.positive,
                  label: 'Konflik & Order Online',
                  value: '${mergedConflicts.length} Konflik • $_pendingOnlineOrdersCount Web',
                  onTap: () => context.push('/online-orders'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        _buildQuickActionSpeedDial(context, tokens, session),
      ],
    );
  }

  Widget _buildPosFastLaneWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final themeCubit = _maybeThemeCubit(context);
    final isOutdoor = tokens.isHighContrast;
    final canCustomers = MobileWorkspaceResolver.canViewCustomers(session);
    final storeName = session.activeStore.name.isEmpty
        ? 'OXORA POS'
        : session.activeStore.name;

    return Column(
      key: const Key('workspace_pos_fast_lane'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.posFastLane),
        const SizedBox(height: 12),

        // Giant Thumb-Zone Primary POS Fast-Lane CTA
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton.icon(
            key: const Key('fast_lane_open_pos_btn'),
            onPressed: () => context.push('/pos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.point_of_sale_rounded, size: 24),
            label: Text(
              'Mulai Transaksi Kasir (${posState.capabilities.posDisplayName})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Strict Blind Drop Shift Status Hero (NEVER shows expected_cash)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _hasOpenShift ? tokens.accentGradientColors : tokens.heroGradientColors,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NusaBadge(
                      label: _hasOpenShift
                          ? 'SHIFT AKTIF • ${_shiftTerminalLabel.isEmpty ? 'POS' : _shiftTerminalLabel}'
                          : 'SHIFT BELUM DIBUKA',
                      variant: _hasOpenShift ? NusaBadgeVariant.success : NusaBadgeVariant.warning,
                    ),
                    if (_shiftBlindDropEnforced)
                      const NusaBadge(
                        label: 'Strict Blind Drop',
                        variant: NusaBadgeVariant.navy,
                        icon: Icons.lock_outline_rounded,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _hasOpenShift
                    ? 'Kas Laci Terkunci (Blind Drop Aktif)'
                    : 'Buka Shift Kasir Sebelum Melayani Pembeli',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _hasOpenShift
                    ? 'Total kas sistem disembunyikan server hingga tutup shift diverifikasi.'
                    : 'Catat modal awal laci kas untuk memulai shift operasional cabang.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/shifts'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.lock_clock_rounded, size: 18),
                  label: Text(
                    _hasOpenShift ? 'Kelola & Tutup Shift (Blind Drop)' : 'Buka Shift Sekarang',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Fast-Lane Status Chips (Held Carts, Offline Queue, High-Contrast Outdoor Toggle)
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.pause_circle_outline_rounded,
                accentColor: tokens.accent,
                label: 'Keranjang Ditahan',
                value: '${posState.heldCarts.length} Transaksi',
                onTap: () => context.push('/pos'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.task_alt_rounded,
                accentColor: tokens.positive,
                label: 'Tugas Cabang',
                value: '$_openTasksCount Terbuka',
                onTap: () => showAlertNotificationsModal(
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
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (themeCubit != null) ...[
          NusaCard(
            onTap: () => themeCubit.toggleOutdoorHighContrast(),
            child: Row(
              children: [
                Icon(
                  Icons.contrast_rounded,
                  color: isOutdoor ? tokens.accent : tokens.textPrimary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Kontras Tinggi (Outdoor POS)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                      Text(
                        isOutdoor
                            ? 'Aktif — kontras maksimal untuk sinar matahari langsung'
                            : 'Tingkatkan ketajaman huruf & border untuk area terang',
                        style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isOutdoor,
                  activeColor: tokens.accent,
                  onChanged: (_) => themeCubit.toggleOutdoorHighContrast(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Cashier Fast-Lane Quick Grid (RBAC Safe — NO financial P&L / AP / Approvals)
        NusaCard(
          child: Row(
            children: [
              _fastLaneTile(tokens, Icons.point_of_sale_rounded, 'Kasir POS', () => context.push('/pos')),
              _fastLaneTile(tokens, Icons.lock_clock_rounded, 'Shift', () => context.push('/shifts')),
              _fastLaneTile(tokens, Icons.receipt_long_rounded, 'Riwayat', () => widget.onSwitchTab(2)),
              if (canCustomers)
                _fastLaneTile(tokens, Icons.groups_outlined, 'Pelanggan', () => context.push('/customers'))
              else
                _fastLaneTile(tokens, Icons.inventory_2_outlined, 'Cek Harga', () => widget.onSwitchTab(1)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.posFastLane),
      ],
    );
  }

  Widget _buildWarehouseWorkbenchWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    int lowStock,
    int expiring,
  ) {
    final canPurchases = MobileWorkspaceResolver.canManagePurchases(session);
    final canSuppliers = MobileWorkspaceResolver.canViewSuppliers(session);
    return Column(
      key: const Key('workspace_warehouse_workbench'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.warehouseWorkbench),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/inventory-ops?tab=1'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text(
                    'Scan Opname Stok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            if (canPurchases) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/purchases?tab=0'),
                    icon: Icon(Icons.local_shipping_outlined, size: 18, color: tokens.positive),
                    label: const Text(
                      'Terima PO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: tokens.heroGradientColors),
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
                      'Kesehatan Stok Gudang',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NusaBadge(
                    label: '${posState.allProducts.length} SKU',
                    variant: NusaBadgeVariant.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$lowStock Menipis • $expiring Batch FEFO',
                  style: AppTheme.moneyStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_openTasksCount tugas gudang aktif • $_pendingApprovalsCount persetujuan stok menunggu',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.warehouseWorkbench),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.swap_horiz_rounded,
                accentColor: tokens.accent,
                label: 'Transfer Antar Cabang',
                value: 'Kirim & Terima',
                onTap: () => context.push('/inventory-ops?tab=3'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: canPurchases
                  ? _buildOperationalMetricTile(
                      tokens,
                      icon: Icons.auto_awesome_outlined,
                      accentColor: tokens.positive,
                      label: 'Saran Kulakan AI',
                      value: 'Reorder PO',
                      onTap: () => context.push('/purchases?tab=2'),
                    )
                  : _buildOperationalMetricTile(
                      tokens,
                      icon: Icons.tune_rounded,
                      accentColor: tokens.positive,
                      label: 'Penyesuaian Stok',
                      value: 'Koreksi Gudang',
                      onTap: () => context.push('/inventory-ops?tab=0'),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.swap_vert_rounded,
                accentColor: tokens.warning,
                label: 'Kartu Mutasi Stok',
                value: 'Audit Keluar/Masuk',
                onTap: () => context.push('/inventory-ops?tab=2'),
              ),
            ),
            if (canSuppliers) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _buildOperationalMetricTile(
                  tokens,
                  icon: Icons.business_outlined,
                  accentColor: tokens.textPrimary,
                  label: 'Data Pemasok',
                  value: 'Vendor & PO',
                  onTap: () => context.push('/suppliers'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEmployeeEssWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    String displayName,
  ) {
    final canApprovals = MobileWorkspaceResolver.canViewApprovals(session);
    return Column(
      key: const Key('workspace_employee_ess'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.employeeEss),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: tokens.heroGradientColors),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NusaBadge(
                label: 'PORTAL STAF OPERASIONAL',
                variant: NusaBadgeVariant.primary,
              ),
              const SizedBox(height: 10),
              Text(
                '$_openTasksCount Tugas Cabang Aktif',
                style: AppTheme.moneyStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Administrasi HRD, absensi, slip gaji, PPh 21 & BPJS dikelola secara terpusat di OXORA Cloud Web (/admin).',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (canApprovals) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/approvals'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.verified_user_outlined, size: 20),
                    label: Text(
                      'Meja Persetujuan ($_pendingApprovalsCount Menunggu)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.employeeEss),
        const SizedBox(height: 12),
        Text(
          'Tugas Operasional Anda ($_openTasksCount)',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (_tasksList.isEmpty)
          const NusaEmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'Tidak Ada Tugas Tertunda',
            subtitle: 'Seluruh tugas operasional Anda hari ini dalam status selesai.',
          )
        else
          ..._tasksList.take(5).map(
                (t) => NusaCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.assignment_outlined, color: tokens.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (t['title'] ?? 'Tugas Cabang').toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: tokens.textPrimary,
                              ),
                            ),
                            if (t['description'] != null)
                              Text(
                                t['description'].toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  Widget _fastLaneTile(
    NusaThemeTokens tokens,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: tokens.isHighContrast ? tokens.borderDefault : Colors.transparent,
                    width: tokens.borderWidth,
                  ),
                ),
                child: Icon(icon, color: tokens.accentDark, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactStatChip(
    NusaThemeTokens tokens, {
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: tokens.textSecondary),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTheme.moneyStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildCopilotBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    MobileWorkspaceRole ws,
  ) {
    return NusaCard(
      onTap: () => _openCopilot(session),
      backgroundColor: tokens.accentSoft,
      borderColor: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: tokens.accentGradientColors),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tanya OXORA Copilot AI (Chat & Suara)',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ws == MobileWorkspaceRole.posFastLane
                      ? 'Cek stok produk, jumlah transaksi Anda & tugas kasir lewat suara/chat.'
                      : 'Ringkas omzet, stok kritis, approval & operasional cabang instan.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.mic_none_rounded, size: 20, color: tokens.accentDark),
        ],
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

  Widget _buildSyncConflictBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    return GestureDetector(
      onTap: () {
        showAlertNotificationsModal(
          context,
          voidCountFromServer: _voidCount,
          varianceShiftsCount: _varianceShiftsCount,
          overdueReceivables: _overdueReceivables,
          storeName: session.activeStore.name.isEmpty
              ? 'OXORA POS'
              : session.activeStore.name,
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
          color: tokens.dangerSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tokens.danger.withOpacity(tokens.isHighContrast ? 1.0 : 0.5),
            width: tokens.borderWidth,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.danger.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.sync_problem_rounded, color: tokens.danger, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    posState.localSyncConflicts.every((c) {
                      final code = (c['conflict_code'] ?? '').toString();
                      return code.isEmpty ||
                          code == 'InsufficientStock' ||
                          code.toLowerCase().contains('stock');
                    })
                        ? '${posState.localSyncConflicts.length} Konflik Stok Sinkronisasi Offline'
                        : '${posState.localSyncConflicts.length} Nota Offline Tertahan Validasi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: tokens.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    posState.localSyncConflicts.every((c) {
                      final code = (c['conflict_code'] ?? '').toString();
                      return code.isEmpty ||
                          code == 'InsufficientStock' ||
                          code.toLowerCase().contains('stock');
                    })
                        ? 'Stok habis di server saat sinkronisasi. Ketuk untuk tindak lanjut.'
                        : 'Transaksi offline ditolak server (mis. Shift Kasir / validasi). Ketuk untuk tindak lanjut.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: tokens.danger),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    int activeStoreId,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.dangerSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.danger, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: tokens.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: tokens.danger,
                    fontWeight: FontWeight.w700,
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
                  foregroundColor: tokens.danger,
                  side: BorderSide(color: tokens.danger),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Login Ulang', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    int offlinePendingCount,
    int badgeCount,
    int activeStoreId,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final storeName = session.activeStore.name.isEmpty
        ? 'OXORA POS'
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
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                ),
                child: Icon(Icons.menu_rounded, size: 22, color: tokens.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _showBranchSwitcherModal(context, tokens, session),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 15, color: tokens.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          session.activeStore.name.isEmpty
                              ? 'Cabang Aktif'
                              : session.activeStore.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: tokens.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const Key('home_copilot_button'),
              tooltip: 'OXORA Copilot AI',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openCopilot(session),
              icon: Icon(Icons.auto_awesome_rounded, size: 21, color: tokens.accent),
            ),
            IconButton(
              tooltip: 'Muat ulang dasbor',
              visualDensity: VisualDensity.compact,
              onPressed: _loading ? null : () => _loadDashboard(storeId: activeStoreId),
              icon: Icon(Icons.refresh_rounded, size: 21, color: tokens.textSecondary),
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
                  icon: Icon(Icons.notifications_none_rounded, size: 23, color: tokens.textPrimary),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: tokens.danger,
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
              onTap: () async {
                final cubit = ctx.read<PosCubit>();
                final synced = await cubit.syncOfflineTransactions();
                if (!ctx.mounted) return;
                if (synced > 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.successDark,
                      content: Text('$synced nota offline berhasil disinkronkan ke Cloud.'),
                    ),
                  );
                } else if (cubit.state.localSyncConflicts.isNotEmpty) {
                  showAlertNotificationsModal(
                    ctx,
                    voidCountFromServer: _voidCount,
                    varianceShiftsCount: _varianceShiftsCount,
                    overdueReceivables: _overdueReceivables,
                    storeName: storeName,
                    approvals: _approvalsList,
                    tasks: _tasksList,
                    offlineConflicts: _mergedOfflineConflicts(cubit.state.localSyncConflicts),
                    pendingOnlineOrdersCount: _pendingOnlineOrdersCount,
                    onDecideApproval: _decideApproval,
                    onOpenOnlineOrders: () => _showOnlineOrdersSheet(ctx),
                  );
                }
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildOperatorStrip(
    NusaThemeTokens tokens,
    AuthSessionModel session,
    String displayName,
    MobileWorkspaceRole workspace,
  ) {
    final storeCode = session.activeStore.code.isEmpty ? '-' : session.activeStore.code;
    final wsSpec = MobileWorkspaceResolver.specFor(workspace);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(wsSpec.icon, size: 20, color: tokens.accentDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selamat bertugas, $displayName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${wsSpec.title} • ${session.userRole.isEmpty ? 'Operator' : session.userRole} • $storeCode',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                width: tokens.borderWidth,
              ),
            ),
            child: Text(
              (session.planName.isEmpty ? 'Starter' : session.planName).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: tokens.accentDark,
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
    NusaThemeTokens tokens,
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
                  backgroundColor: tokens.accent,
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
                  foregroundColor: tokens.textPrimary,
                  backgroundColor: tokens.bgSurface,
                  side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(Icons.lock_clock_outlined, size: 18, color: tokens.positive),
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
                backgroundColor: tokens.accent,
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
                foregroundColor: tokens.textPrimary,
                backgroundColor: tokens.bgSurface,
                side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.table_restaurant_outlined, size: 18, color: tokens.accent),
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
                foregroundColor: tokens.textPrimary,
                backgroundColor: tokens.bgSurface,
                side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.lock_clock_outlined, size: 18, color: tokens.positive),
              label: const Text('Shift', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodPill(String key, String label, NusaThemeTokens tokens) {
    final isSelected = _selectedPeriod == key;
    return InkWell(
      onTap: () {
        if (_selectedPeriod == key) return;
        setState(() {
          _selectedPeriod = key;
        });
        _loadDashboard(period: key);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accent : tokens.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.borderSubtle,
            width: tokens.borderWidth,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : tokens.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildExecutivePulseCard(BuildContext context, NusaThemeTokens tokens) {
    final isUp = _growthPercent >= 0;
    final sign = _growthPercent > 0 ? '+' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPeriodPill('month', 'Bulan Ini (MTD)', tokens),
              const SizedBox(width: 6),
              _buildPeriodPill('today', 'Hari Ini', tokens),
              const SizedBox(width: 6),
              _buildPeriodPill('7d', '7 Hari', tokens),
              const SizedBox(width: 6),
              _buildPeriodPill('30d', '30 Hari', tokens),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => context.push('/reports'),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.heroGradientColors,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: tokens.isHighContrast ? null : AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _periodTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$_todayTxCount Transaksi',
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    IdrCurrencyFormatter.format(_todaySales),
                    style: AppTheme.moneyStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                            color: isUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '$sign${_growthPercent.toStringAsFixed(1)}% $_growthLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
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
        ),
      ],
    );
  }

  Widget _buildQuickActionSpeedDial(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
  ) {
    final canPos = MobileWorkspaceResolver.canUsePos(session);
    final canCashWrite = session.isOwner ||
        session.isLocalTrial ||
        MobileWorkspaceResolver.hasAnyPermission(session, const [
          'accounting.petty_cash',
          'expenses.create',
        ]);
    final canCreateProduct = session.isOwner ||
        session.isLocalTrial ||
        MobileWorkspaceResolver.hasAnyPermission(session, const [
          'products.create',
          'products.update',
        ]);
    final canOpname = MobileWorkspaceResolver.canManageInventory(session);

    final actions = [
      if (canPos)
        (
          label: 'Kasir POS',
          icon: Icons.point_of_sale_rounded,
          color: tokens.accent,
          onTap: () => context.push('/pos'),
        ),
      if (canCashWrite)
        (
          label: 'Catat Kas',
          icon: Icons.account_balance_wallet_rounded,
          color: tokens.positive,
          onTap: () => context.push('/cash-ledger'),
        ),
      if (canCreateProduct)
        (
          label: '+ Barang',
          icon: Icons.add_box_rounded,
          color: AppColors.purple,
          onTap: () => widget.onSwitchTab(1),
        ),
      if (canOpname)
        (
          label: 'Scan Opname',
          icon: Icons.qr_code_scanner_rounded,
          color: tokens.warning,
          onTap: () => context.push('/inventory-ops?tab=1'),
        ),
    ];

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'AKSI CEPAT OPERASIONAL',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: tokens.textSecondary,
              ),
            ),
          ),
          Row(
            children: [
              for (final action in actions)
                Expanded(
                  child: InkWell(
                    onTap: action.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: action.color,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(action.icon, color: Colors.white, size: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllModulesBanner(BuildContext context, NusaThemeTokens tokens) {
    return InkWell(
      onTap: () => widget.onSwitchTab(3),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.grid_view_rounded, color: tokens.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semua Fitur & Modul Usaha',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kategori, PO Beli, Retur, Buku Kas, Penawaran, KDS & Toko Online.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Buka →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tokens.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationalMetricsGrid(
    BuildContext context,
    NusaThemeTokens tokens,
    int lowStock,
    int expiring,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.monetization_on_outlined,
                accentColor: tokens.positive,
                label: _grossProfitTitle,
                value: IdrCurrencyFormatter.format(_grossProfit),
                onTap: () => context.push('/reports'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.receipt_long_outlined,
                accentColor: tokens.warning,
                label: 'Piutang Pelanggan (Bon)',
                value: IdrCurrencyFormatter.format(_totalReceivables),
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
                tokens,
                icon: Icons.local_shipping_outlined,
                accentColor: tokens.accent,
                label: 'Hutang Supplier Tempo',
                value: IdrCurrencyFormatter.format(_totalPayables),
                onTap: () => context.push('/debts?tab=payables'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.inventory_2_outlined,
                accentColor: (lowStock + expiring) > 0 ? tokens.danger : AppColors.purple,
                label: 'Stok Menipis & FEFO',
                value: '$lowStock Menipis • $expiring FEFO',
                onTap: () => widget.onSwitchTab(1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOperationalMetricTile(
    NusaThemeTokens tokens, {
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
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
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
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
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
                  color: tokens.textPrimary,
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
    NusaThemeTokens tokens,
    VerticalCapabilities capabilities,
  ) {
    final session = context.watch<AuthCubit>().state.session;
    final onlineGated = session.isModuleGated('online_store');

    final modules = [
      (
        icon: Icons.point_of_sale_rounded,
        color: tokens.accent,
        title: capabilities.posDisplayName,
        subtitle: capabilities.posSubtitle,
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/pos'),
      ),
      (
        icon: Icons.analytics_outlined,
        color: const Color(0xFF0284C7),
        title: 'Pusat Laporan Bisnis (50)',
        subtitle: '50 laporan paritas Cloud, WA & PDF',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/reports'),
      ),
      (
        icon: Icons.verified_user_outlined,
        color: tokens.warning,
        title: 'Meja Persetujuan Owner',
        subtitle: _pendingApprovalsCount > 0
            ? '$_pendingApprovalsCount permintaan menunggu keputusan'
            : 'Otorisasi Maker-Checker, Void & PO',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/approvals'),
      ),
      (
        icon: Icons.inventory_2_outlined,
        color: AppColors.purple,
        title: 'Katalog & Opname Stok',
        subtitle: 'Produk, HPP, FEFO & kamera',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => widget.onSwitchTab(1),
      ),
      (
        icon: Icons.local_shipping_outlined,
        color: tokens.warning,
        title: 'Pemasok & Stok Masuk',
        subtitle: 'Supplier, rekening & beli stok',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/suppliers?tab=stock-in'),
      ),
      (
        icon: Icons.people_outline_rounded,
        color: tokens.accentDark,
        title: 'Pelanggan & Member',
        subtitle: 'Diskon grup, poin & kasbon',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/customers'),
      ),
      (
        icon: Icons.menu_book_outlined,
        color: tokens.danger,
        title: 'Buku Bon & Biaya Toko',
        subtitle: 'Piutang, hutang & pengeluaran',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/debts'),
      ),
      (
        icon: Icons.lock_clock_outlined,
        color: tokens.positive,
        title: 'Shift Kasir & Z-Report',
        subtitle: 'Kas laci, mutasi & blind count',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/shifts'),
      ),
      if (capabilities.hasTableManagement)
        (
          icon: Icons.table_restaurant_outlined,
          color: tokens.accentDark,
          title: 'Denah Meja & Resto F&B',
          subtitle: 'Open tab, pindah meja & KOT',
          isGated: false,
          requiredTier: 'STARTER',
          onTap: () => context.push('/restaurant'),
        ),
      (
        icon: Icons.shopping_bag_outlined,
        color: tokens.accent,
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
    ];

    return Column(
      children: [
        for (int i = 0; i < modules.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildModuleDirectoryCard(
                  tokens,
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
                        tokens,
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

  Widget _buildModuleDirectoryCard(
    NusaThemeTokens tokens, {
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
          color: isGated ? tokens.warningSoft : tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isGated ? tokens.warning : tokens.borderSubtle,
            width: tokens.borderWidth,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
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
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
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
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.textSecondary,
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
    final tokens = NusaThemeTokens.of(context);
    List<Map<String, dynamic>> orders = [];
    bool loadingOrders = true;
    String? ordersError;
    String? modalActionError;
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

    Future<void> updateOrderInline(
      int orderId,
      String newStatus,
      StateSetter setModalState, {
      String? trackingNumber,
    }) async {
      setModalState(() => modalActionError = null);
      try {
        await _api.dio.post(
          ApiEndpoints.updateOnlineOrderStatus(orderId),
          data: {
            'online_order_status': newStatus,
            if (trackingNumber != null && trackingNumber.trim().isNotEmpty)
              'shipping_tracking_number': trackingNumber.trim(),
          },
        );
        await fetchOrders(setModalState);
      } catch (e) {
        setModalState(() => modalActionError = ApiClient.extractErrorMessage(e));
      }
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
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
                        Text(
                          'Pesanan Toko Online (Webstore)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: loadingOrders ? null : () => fetchOrders(setModalState),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
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
                    if (modalActionError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.danger),
                        ),
                        child: Text(
                          modalActionError!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.danger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: loadingOrders
                          ? const NusaListSkeleton(itemCount: 4)
                          : ordersError != null
                              ? Center(
                                  child: Text(
                                    ordersError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: tokens.danger),
                                  ),
                                )
                              : orders.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Belum ada pesanan toko online pada filter ini.',
                                        style: TextStyle(color: tokens.textSecondary),
                                      ),
                                    )
                                  : ListView.separated(
                                      controller: scrollCtrl,
                                      itemCount: orders.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (_, idx) {
                                        final o = orders[idx];
                                        final id = (o['id'] as num?)?.toInt() ?? 0;
                                        final status =
                                            (o['online_order_status'] ?? 'pending_payment').toString();
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
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 13,
                                                        color: tokens.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    IdrCurrencyFormatter.format(total),
                                                    style: AppTheme.moneyStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w800,
                                                      color: tokens.accent,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${o['items_count'] ?? 0} item • Status: ${status.toUpperCase()}'
                                                '${o['tracking_number'] != null ? ' • Resi: ${o['tracking_number']}' : ''}',
                                                style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  if (status == 'pending_payment' || status == 'paid')
                                                    OutlinedButton(
                                                      onPressed: () => updateOrderInline(
                                                        id,
                                                        'processing',
                                                        setModalState,
                                                      ),
                                                      style: OutlinedButton.styleFrom(
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                      child: const Text('Proses Order'),
                                                    ),
                                                  if (status == 'processing' || status == 'paid')
                                                    ElevatedButton(
                                                      onPressed: () => _promptShipOnlineOrder(
                                                        ctx,
                                                        id,
                                                        (tracking) => updateOrderInline(
                                                          id,
                                                          'shipped',
                                                          setModalState,
                                                          trackingNumber: tracking,
                                                        ),
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                      child: const Text('Input Resi & Kirim'),
                                                    ),
                                                  if (status == 'shipped')
                                                    ElevatedButton(
                                                      onPressed: () => updateOrderInline(
                                                        id,
                                                        'completed',
                                                        setModalState,
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: tokens.positive,
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

  Future<void> _promptShipOnlineOrder(
    BuildContext context,
    int orderId,
    Future<void> Function(String tracking) onConfirm,
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
      await onConfirm(resiCtrl.text);
    }
  }

  void _showBranchSwitcherModal(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih Cabang Toko Aktif',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...session.availableStores.map(
              (branch) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: branch.id == session.activeStore.id
                      ? tokens.accent
                      : tokens.accentSoft,
                  child: Icon(
                    Icons.store_rounded,
                    color: branch.id == session.activeStore.id ? Colors.white : tokens.accent,
                  ),
                ),
                title: Text(
                  branch.name,
                  style: TextStyle(fontWeight: FontWeight.w700, color: tokens.textPrimary),
                ),
                subtitle: Text(
                  'Kode: ${branch.code} • ${branch.city ?? 'Indonesia'}',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                trailing: branch.id == session.activeStore.id
                    ? Icon(Icons.check_circle_rounded, color: tokens.positive)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  if (branch.id == session.activeStore.id) return;
                  await context.read<AuthCubit>().switchStoreBranch(branch);
                  if (context.mounted) {
                    await context.read<PosCubit>().syncWithCloud(force: true);
                  }
                  if (mounted) {
                    await _loadDashboard(storeId: branch.id);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTrialUpgradeBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    int activeStoreId,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.32),
          width: tokens.borderWidth,
        ),
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
                  color: tokens.accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.cloud_upload_outlined, color: tokens.accentDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Usaha Mandiri (Tersimpan di HP ini)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cadangkan ke OXORA Cloud agar aman jika HP ganti atau rusak.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.textSecondary,
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
                backgroundColor: tokens.accent,
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
