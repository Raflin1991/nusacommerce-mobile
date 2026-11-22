import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/widgets/cascade_entitlement_teaser.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../approvals/presentation/owner_approvals_screen.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';
import '../../copilot/presentation/nusa_copilot_sheet.dart';
import '../../inventory/presentation/inventory_operations_screen.dart';
import '../../inventory/presentation/products_inventory_screen.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../purchases/presentation/purchases_and_returns_screen.dart';
import '../../sales_history/presentation/transactions_history_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shifts/presentation/shift_management_screen.dart';
import 'all_modules_directory_view.dart';
import 'home_dashboard_screen.dart';

/// Role-Adaptive 5-Slot Navigation Shell (4 IndexedStack Tabs + Center Role CTA) — Gelombang 5:
/// - Cashier   -> POS Fast-Lane (Fast-Lane | Cek Harga | [Kasir POS] | Riwayat | Shift Kasir)
/// - Owner     -> Owner Pulse   (Beranda   | Katalog   | [Kasir POS] | Transaksi | Semua Menu) + Switcher
/// - Manager   -> Manager Desk  (Desk      | Katalog   | [Kasir POS] | Transaksi | Semua Menu)
/// - Warehouse -> Warehouse     (Gudang    | Stok SKU  | [Opname]    | PO & Retur | Operasi)
/// - HR/Staff  -> ESS & HR      (Beranda   | Presensi  | [Absensi]   | Pengaturan | Menu)
/// Preserves adaptive NavigationRail at width >= 768dp and strict RBAC isolation.
class MainNavigationShell extends StatefulWidget {
  final int initialIndex;
  final MobileWorkspaceRole? initialWorkspaceOverride;

  const MainNavigationShell({
    super.key,
    this.initialIndex = 0,
    this.initialWorkspaceOverride,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;
  MobileWorkspaceRole? _selectedWorkspace;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _lastSyncedSessionRevision = -1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _selectedWorkspace = widget.initialWorkspaceOverride;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authState = context.read<AuthCubit>().state;
      _bootstrapCatalogForSession(authState, resetBeforeInit: authState.sessionRevision > 0);
    });
  }

  Future<void> _bootstrapCatalogForSession(
    AuthState authState, {
    bool resetBeforeInit = false,
  }) async {
    if (!mounted || !authState.isAuthenticated) return;
    if (_lastSyncedSessionRevision == authState.sessionRevision) return;
    _lastSyncedSessionRevision = authState.sessionRevision;

    final posCubit = context.read<PosCubit>();
    if (resetBeforeInit) {
      await posCubit.resetForLogout();
    }
    if (!mounted) return;
    await posCubit.initializeCatalog(seedDefaultCart: false, awaitCloudSync: false);
  }

  void _switchTab(int index) {
    setState(() => _currentIndex = index.clamp(0, 3));
  }

  void _openProductsTabOrRoute(AuthSessionModel session, MobileWorkspaceRole workspace) {
    if (workspace != MobileWorkspaceRole.employeeEss) {
      _switchTab(1);
      return;
    }
    if (MobileWorkspaceResolver.canSwitchWorkspaces(session)) {
      setState(() {
        _selectedWorkspace = MobileWorkspaceRole.ownerPulse;
        _currentIndex = 1;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductsInventoryScreen(
          onOpenDrawer: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  void _openSalesHistoryTabOrRoute(AuthSessionModel session, MobileWorkspaceRole workspace) {
    if (workspace == MobileWorkspaceRole.ownerPulse ||
        workspace == MobileWorkspaceRole.managerDesk ||
        workspace == MobileWorkspaceRole.posFastLane) {
      _switchTab(2);
      return;
    }
    if (MobileWorkspaceResolver.canSwitchWorkspaces(session)) {
      setState(() {
        _selectedWorkspace = MobileWorkspaceRole.ownerPulse;
        _currentIndex = 2;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionsHistoryScreen(
          onOpenDrawer: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  void _selectWorkspace(AuthSessionModel session, MobileWorkspaceRole next) {
    if (!MobileWorkspaceResolver.canSwitchWorkspaces(session)) return;
    setState(() {
      _selectedWorkspace = next;
      _currentIndex = 0;
    });
  }

  ThemeCubit? _maybeThemeCubit(BuildContext context) {
    try {
      return context.watch<ThemeCubit>();
    } catch (_) {
      return null;
    }
  }

  List<Widget> _buildRoleScreens(
    AuthSessionModel session,
    MobileWorkspaceRole workspace,
  ) {
    final homeScreen = HomeDashboardScreen(
      onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      onSwitchTab: _switchTab,
      activeWorkspace: workspace,
      onSelectWorkspace: MobileWorkspaceResolver.canSwitchWorkspaces(session)
          ? (next) => _selectWorkspace(session, next)
          : null,
      onOpenCopilot: () => showNusaCopilotSheet(context, workspace: workspace),
    );

    switch (workspace) {
      case MobileWorkspaceRole.posFastLane:
        return [
          homeScreen,
          ProductsInventoryScreen(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          TransactionsHistoryScreen(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const ShiftManagementScreen(),
        ];

      case MobileWorkspaceRole.warehouseWorkbench:
        return [
          homeScreen,
          ProductsInventoryScreen(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const PurchasesAndReturnsScreen(initialTab: 0),
          const InventoryOperationsScreen(initialTab: 0),
        ];

      case MobileWorkspaceRole.employeeEss:
        return [
          homeScreen,
          MobileWorkspaceResolver.canViewApprovals(session)
              ? const OwnerApprovalsScreen()
              : const _MobileCloudWebPortalTab(),
          const SettingsScreen(),
          AllModulesDirectoryView(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            onSwitchTab: (idx) {
              if (idx == 1) {
                _openProductsTabOrRoute(session, workspace);
              } else if (idx == 2) {
                _openSalesHistoryTabOrRoute(session, workspace);
              } else if (MobileWorkspaceResolver.canSwitchWorkspaces(session)) {
                setState(() {
                  _selectedWorkspace = MobileWorkspaceRole.ownerPulse;
                  _currentIndex = idx.clamp(0, 3);
                });
              } else {
                _switchTab(idx);
              }
            },
          ),
        ];

      case MobileWorkspaceRole.ownerPulse:
      case MobileWorkspaceRole.managerDesk:
        return [
          homeScreen,
          ProductsInventoryScreen(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          TransactionsHistoryScreen(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          AllModulesDirectoryView(
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
            onSwitchTab: _switchTab,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final session = context.watch<AuthCubit>().state.session;
    final workspace = MobileWorkspaceResolver.sanitizeActiveWorkspace(
      session,
      _selectedWorkspace,
    );
    final spec = MobileWorkspaceResolver.specFor(workspace);
    final primaryCta = MobileWorkspaceResolver.primaryCtaForSession(session, workspace);
    final screens = _buildRoleScreens(session, workspace);
    final isTabletWide = MediaQuery.sizeOf(context).width >= 768;

    final posState = context.watch<PosCubit>().state;

    final mainContent = Column(
      children: [
        if (posState.isInitialRestoring)
          _buildInitialRestoreBanner(tokens, posState),
        Expanded(
          child: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
        ),
      ],
    );

    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (prev, curr) =>
          curr.isAuthenticated && prev.sessionRevision != curr.sessionRevision,
      listener: (context, authState) {
        _bootstrapCatalogForSession(authState, resetBeforeInit: true);
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: tokens.bgPage,
        drawer: _buildEnterpriseDrawer(context, tokens, session, workspace, primaryCta),
        body: isTabletWide
            ? Row(
                children: [
                  _buildTabletNavRail(context, tokens, spec, primaryCta, workspace),
                  VerticalDivider(
                    width: 1,
                    thickness: tokens.borderWidth,
                    color: tokens.borderSubtle,
                  ),
                  Expanded(child: mainContent),
                ],
              )
            : mainContent,
        bottomNavigationBar: isTabletWide
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(
                    top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                  ),
                  boxShadow: tokens.isHighContrast
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x0A1C1917),
                            blurRadius: 12,
                            offset: Offset(0, -3),
                          ),
                        ],
                ),
                child: SafeArea(
                  child: SizedBox(
                    height: 68,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(tokens, spec.tabs[0]),
                        _buildNavItem(tokens, spec.tabs[1]),
                        _buildCenterPrimaryAction(context, tokens, primaryCta),
                        _buildNavItem(tokens, spec.tabs[2]),
                        _buildNavItem(tokens, spec.tabs[3]),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInitialRestoreBanner(NusaThemeTokens tokens, PosState posState) {
    final pct = (posState.initialRestoreProgress.clamp(0.0, 1.0) * 100).round();
    final stepText = posState.initialRestoreStep ??
        'Memulihkan katalog produk & data master ke database lokal...';

    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.accentSoft,
          border: Border(
            bottom: BorderSide(color: tokens.accent.withOpacity(0.28), width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sinkronisasi Awal SQLite • $stepText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: posState.initialRestoreProgress > 0
                    ? posState.initialRestoreProgress.clamp(0.05, 1.0)
                    : null,
                minHeight: 4,
                backgroundColor: tokens.bgSurface,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletNavRail(
    BuildContext context,
    NusaThemeTokens tokens,
    MobileWorkspaceSpec spec,
    MobilePrimaryCtaSpec primaryCta,
    MobileWorkspaceRole workspace,
  ) {
    final themeCubit = _maybeThemeCubit(context);

    return Container(
      width: 100,
      color: tokens.bgSurface,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            IconButton(
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Menu Lengkap',
              icon: Icon(Icons.menu_rounded, color: tokens.textPrimary),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 80,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push(primaryCta.route),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Icon(primaryCta.icon, color: Colors.white, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        primaryCta.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: NavigationRail(
                backgroundColor: tokens.bgSurface,
                selectedIndex: _currentIndex,
                onDestinationSelected: _switchTab,
                labelType: NavigationRailLabelType.all,
                indicatorColor: tokens.accentSoft,
                selectedIconTheme: IconThemeData(color: tokens.accent),
                unselectedIconTheme: IconThemeData(color: tokens.textSecondary),
                selectedLabelTextStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tokens.accent,
                ),
                unselectedLabelTextStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary,
                ),
                destinations: spec.tabs
                    .map(
                      (t) => NavigationRailDestination(
                        icon: Icon(t.inactiveIcon),
                        selectedIcon: Icon(t.activeIcon),
                        label: Text(t.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            // OXO Copilot AI Quick Trigger on Tablet Rail
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: IconButton.filledTonal(
                key: const Key('rail_copilot_button'),
                tooltip: 'OXO Copilot AI',
                style: IconButton.styleFrom(
                  backgroundColor: tokens.accentSoft,
                  foregroundColor: tokens.accent,
                ),
                onPressed: () => showNusaCopilotSheet(context, workspace: workspace),
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              ),
            ),
            if (themeCubit != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: IconButton(
                  tooltip: 'Ganti Tema (${tokens.mode.shortLabel})',
                  onPressed: () => themeCubit.cycleThemeMode(),
                  icon: Icon(tokens.mode.icon, size: 20, color: tokens.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPrimaryAction(
    BuildContext context,
    NusaThemeTokens tokens,
    MobilePrimaryCtaSpec cta,
  ) {
    return Expanded(
      child: InkWell(
        key: const Key('bottom_bar_primary_cta'),
        onTap: () => context.push(cta.route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
                boxShadow: tokens.isHighContrast
                    ? null
                    : [
                        BoxShadow(
                          color: tokens.accent.withOpacity(0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Icon(cta.icon, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 2),
            Text(
              cta.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: tokens.accentDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(NusaThemeTokens tokens, MobileNavTabSpec tab) {
    final isSelected = _currentIndex == tab.index;
    final color = isSelected ? tokens.accent : tokens.textSecondary;

    return Expanded(
      child: InkWell(
        onTap: () => _switchTab(tab.index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? tokens.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                isSelected ? tab.activeIcon : tab.inactiveIcon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnterpriseDrawer(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    MobileWorkspaceRole workspace,
    MobilePrimaryCtaSpec primaryCta,
  ) {
    final capabilities = context.watch<PosCubit>().state.capabilities;
    final themeCubit = _maybeThemeCubit(context);
    final displayName =
        session.userName.trim().isEmpty ? 'Operator OXO.ID' : session.userName.trim();
    final roleLabel = session.userRole.isEmpty ? 'Operator' : session.userRole;
    final planLabel = session.planName.isEmpty ? 'Starter' : session.planName;
    final canSwitchWorkspaces = MobileWorkspaceResolver.canSwitchWorkspaces(session);
    final canPos = MobileWorkspaceResolver.canUsePos(session);
    final canSalesHistory = MobileWorkspaceResolver.canViewSalesHistory(session);
    final canProducts = MobileWorkspaceResolver.canViewProducts(session);
    final canWarehouse = MobileWorkspaceResolver.canManageInventory(session);
    final canPurchases = MobileWorkspaceResolver.canManagePurchases(session);
    final canCustomers = MobileWorkspaceResolver.canViewCustomers(session);
    final canFinance = MobileWorkspaceResolver.canViewCashLedger(session) ||
        MobileWorkspaceResolver.canViewOwnerDashboard(session);
    final canOnlineStore = MobileWorkspaceResolver.canManageOnlineStore(session);
    final canApprovals = MobileWorkspaceResolver.canViewApprovals(session);
    final spec = MobileWorkspaceResolver.specFor(workspace);

    return Drawer(
      backgroundColor: tokens.bgSurface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 46, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.heroGradientColors,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 23,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '$roleLabel • ${session.activeStore.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    session.isLocalTrial
                        ? 'Mode Toko Mandiri (Offline Lokal)'
                        : '${spec.title} • ${session.tenantSubdomain.isEmpty ? '-' : '${session.tenantSubdomain}.nusco.id'} ($planLabel)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                BlocBuilder<PosCubit, PosState>(
                  builder: (context, posState) {
                    return NusaSyncStatusPill(
                      isOnline: posState.isOnline,
                      isSyncing: posState.isSyncingOfflineQueue,
                      offlinePendingCount: posState.offlinePendingCount,
                      compact: true,
                      onTap: () => context.read<PosCubit>().syncOfflineTransactions(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(primaryCta.route);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: Icon(primaryCta.icon, size: 18),
                        label: Text(
                          primaryCta.shortLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showNusaCopilotSheet(context, workspace: workspace);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                      label: const Text('AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (canSwitchWorkspaces) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Text(
                      'WORKSPACE PERAN (OWNER / ADMIN)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: MobileWorkspaceResolver.operationalWorkspaces.map((r) {
                        final s = MobileWorkspaceResolver.specFor(r);
                        return NusaPillFilter(
                          label: s.shortTitle,
                          icon: s.icon,
                          selected: r == workspace,
                          onTap: () {
                            Navigator.pop(context);
                            _selectWorkspace(session, r);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  Divider(height: 18, color: tokens.borderSubtle),
                ],

                if (themeCubit != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: Text(
                      'TEMA TAMPILAN (WARM LINEN)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: NusaThemeMode.values.map((m) {
                        return NusaPillFilter(
                          label: m.shortLabel,
                          icon: m.icon,
                          selected: tokens.mode == m,
                          onTap: () => themeCubit.setThemeMode(m),
                        );
                      }).toList(),
                    ),
                  ),
                  Divider(height: 18, color: tokens.borderSubtle),
                ],

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Text(
                    'OPERASIONAL & BISNIS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),

                if (canPos)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.point_of_sale_outlined,
                    title: 'Kasir & Operasional',
                    initiallyExpanded: true,
                    children: [
                      _drawerSubTile(tokens, 'Layar Kasir POS', () {
                        Navigator.pop(context);
                        context.push('/pos');
                      }),
                      if (capabilities.hasTableManagement) ...[
                        _drawerSubTile(tokens, 'Denah Meja Restoran', () {
                          Navigator.pop(context);
                          context.push('/restaurant');
                        }),
                        _drawerSubTile(tokens, 'Layar Dapur KDS', () {
                          Navigator.pop(context);
                          context.push('/kds');
                        }),
                      ],
                      _drawerSubTile(tokens, 'Shift Kasir & Blind Drop', () {
                        Navigator.pop(context);
                        context.push('/shifts');
                      }),
                    ],
                  ),

                if (canSalesHistory)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.receipt_long_outlined,
                    title: 'Penjualan & Order',
                    children: [
                      _drawerSubTile(tokens, 'Riwayat Transaksi & Retur', () {
                        Navigator.pop(context);
                        _openSalesHistoryTabOrRoute(session, workspace);
                      }),
                      if (MobileWorkspaceResolver.canManageQuotations(session))
                        _drawerSubTile(tokens, 'Surat Penawaran (Quotation)', () {
                          Navigator.pop(context);
                          context.push('/quotations');
                        }),
                    ],
                  ),

                if (canProducts || canWarehouse)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.inventory_2_outlined,
                    title: 'Produk & Katalog',
                    children: [
                      _drawerSubTile(tokens, 'Data Barang & Harga', () {
                        Navigator.pop(context);
                        _openProductsTabOrRoute(session, workspace);
                      }),
                      if (MobileWorkspaceResolver.canManageCatalogTaxonomies(session)) ...[
                        _drawerSubTile(tokens, 'Kategori Produk', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=0');
                        }),
                        _drawerSubTile(tokens, 'Merek / Brand', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=1');
                        }),
                        _drawerSubTile(tokens, 'Satuan / Unit', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=2');
                        }),
                        _drawerSubTile(tokens, 'Cetak Label Barcode', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=3');
                        }),
                      ],
                    ],
                  ),

                if (canWarehouse)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.warehouse_outlined,
                    title: 'Inventaris & Gudang',
                    children: [
                      _drawerSubTile(tokens, 'Monitor Stok & Menipis', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=0');
                      }),
                      _drawerSubTile(tokens, 'Opname & Penyesuaian Multi-Item', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=1');
                      }),
                      _drawerSubTile(tokens, 'Kartu Mutasi Stok', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=2');
                      }),
                      _drawerSubTile(tokens, 'Batch FEFO & Transfer Cabang', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=3');
                      }),
                    ],
                  ),

                if (canPurchases)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.shopping_cart_outlined,
                    title: 'Pembelian & Pemasok',
                    children: [
                      _drawerSubTile(tokens, 'Pesanan Beli (PO) Multi-Item', () {
                        Navigator.pop(context);
                        context.push('/purchases?tab=0');
                      }),
                      _drawerSubTile(tokens, 'Retur Pembelian Supplier', () {
                        Navigator.pop(context);
                        context.push('/purchases?tab=1');
                      }),
                      _drawerSubTile(tokens, 'Saran Kulakan AI', () {
                        Navigator.pop(context);
                        context.push('/purchases?tab=2');
                      }),
                      _drawerSubTile(tokens, 'Data Pemasok / Supplier', () {
                        Navigator.pop(context);
                        context.push('/suppliers');
                      }),
                    ],
                  ),

                if (canCustomers)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.groups_outlined,
                    title: 'CRM & Pelanggan',
                    children: [
                      _drawerSubTile(tokens, 'Pelanggan, Member & Grup', () {
                        Navigator.pop(context);
                        context.push('/customers');
                      }),
                    ],
                  ),

                if (canFinance) ...[
                  _drawerAccordion(
                    tokens,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Kas, Piutang & Pelunasan',
                    children: [
                      _drawerSubTile(tokens, 'Buku Kas & Arus Kas', () {
                        Navigator.pop(context);
                        context.push('/cash-ledger');
                      }),
                      _drawerSubTile(tokens, 'Buku Bon Piutang & Kwitansi', () {
                        Navigator.pop(context);
                        context.push('/debts');
                      }),
                      _drawerSubTile(tokens, 'Hutang Tempo Supplier', () {
                        Navigator.pop(context);
                        context.push('/debts?tab=payables');
                      }),
                      _drawerSubTile(tokens, 'Biaya Operasional Toko', () {
                        Navigator.pop(context);
                        context.push('/debts?tab=expenses');
                      }),
                    ],
                  ),
                ],
                if (canOnlineStore)
                  _drawerTile(
                    tokens,
                    Icons.storefront_outlined,
                    'Toko Online & Pesanan Web',
                    () {
                      Navigator.pop(context);
                      if (session.isModuleGated('online_store')) {
                        showCascadeModuleTeaserModal(
                          context,
                          moduleKey: 'online_store',
                          moduleTitle: 'Toko Online & Katalog Web',
                          requiredTier: 'PRO',
                          currentTier: session.tier,
                          description:
                              'Terima pesanan online dari pelanggan langsung ke kasir POS dengan pemotongan stok otomatis secara real-time.',
                          benefits: const [
                            'Etalase web katalog toko siap pakai 24 jam',
                            'Notifikasi pesanan masuk real-time & cetak resi',
                            'Sinkronisasi stok tunggal antar kasir toko & webstore',
                          ],
                        );
                      } else {
                        context.push('/online-orders');
                      }
                    },
                    isGated: session.isModuleGated('online_store'),
                    requiredTier: 'PRO',
                  ),
                if (MobileWorkspaceResolver.canViewOwnerDashboard(session))
                  _drawerTile(tokens, Icons.analytics_outlined, 'Pusat Laporan Bisnis (50)', () {
                    Navigator.pop(context);
                    context.push('/reports');
                  }),
                if (canApprovals)
                  _drawerTile(tokens, Icons.verified_user_outlined, 'Meja Persetujuan Owner', () {
                    Navigator.pop(context);
                    context.push('/approvals');
                  }),

                Divider(height: 16, color: tokens.borderSubtle),
                _drawerTile(tokens, Icons.settings_outlined, 'Profil Toko, Printer & Tema', () {
                  Navigator.pop(context);
                  context.push('/settings');
                }),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    final posCubit = context.read<PosCubit>();
                    await context.read<AuthCubit>().logout();
                    await posCubit.resetForLogout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.danger,
                    side: BorderSide(color: tokens.danger.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text(
                    'Keluar Sesi (Logout)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerAccordion(
    NusaThemeTokens tokens, {
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Icon(icon, color: tokens.accent, size: 22),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        childrenPadding: const EdgeInsets.only(left: 24, right: 8, bottom: 4),
        children: children,
      ),
    );
  }

  Widget _drawerSubTile(NusaThemeTokens tokens, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 16, color: tokens.textTertiary),
      onTap: onTap,
    );
  }

  Widget _drawerTile(
    NusaThemeTokens tokens,
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isGated = false,
    String requiredTier = 'PRO',
  }) {
    return ListTile(
      leading: Icon(icon, color: isGated ? tokens.textSecondary : tokens.accent),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: isGated ? tokens.textSecondary : tokens.textPrimary,
        ),
      ),
      trailing: isGated
          ? CascadeCrownBadge(requiredTier: requiredTier)
          : Icon(Icons.chevron_right_rounded, size: 18, color: tokens.textTertiary),
      onTap: onTap,
    );
  }
}

class _MobileCloudWebPortalTab extends StatelessWidget {
  const _MobileCloudWebPortalTab();

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(title: const Text('Portal Cloud Web OXO.ID')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NusaCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.public_rounded, color: tokens.accent, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  'Administrasi HRD, Payroll & Back-Office di Cloud Web',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Aplikasi Mobile difokuskan pada kecepatan Kasir POS, Operasional Toko Harian, Stok Gudang, Persetujuan Owner, dan 50 Laporan Bisnis.\n\n'
                  'Pengelolaan absensi lengkap, penggajian (Payroll), PPh 21, BPJS, e-Faktur CoreTax XML, dan jurnal akuntansi lanjutan dapat diakses melalui OXO.ID Cloud Web (/admin).',
                  style: TextStyle(fontSize: 13, color: tokens.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
