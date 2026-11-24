// ignore_for_file: invalid_use_of_protected_member
part of 'main_navigation_shell.dart';

extension _MainNavigationShellStatePart1Ext on _MainNavigationShellState {

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
            // OXORA Copilot AI Quick Trigger on Tablet Rail
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: IconButton.filledTonal(
                key: const Key('rail_copilot_button'),
                tooltip: 'OXORA Copilot AI',
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
}
