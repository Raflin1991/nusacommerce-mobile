import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/constants/api_endpoints.dart';
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
import '../../../core/network/repositories/backoffice_repository.dart';
import '../../../core/network/repositories/sale_repository.dart';

part 'home_dashboard_screen_part1.dart';
part 'home_dashboard_screen_part2.dart';
part 'home_dashboard_screen_part3.dart';
part 'home_dashboard_screen_part4.dart';
part 'home_dashboard_screen_part5.dart';
part 'home_dashboard_screen_part6.dart';

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

  late final BackofficeRepository _backofficeRepo = BackofficeRepository.resolve(_api);

  late final SaleRepository _saleRepo = SaleRepository.resolve(_api);

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
}
