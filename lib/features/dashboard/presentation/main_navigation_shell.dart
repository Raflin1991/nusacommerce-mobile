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

part 'main_navigation_shell_part1.dart';
part 'main_navigation_shell_part2.dart';

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
}


class _MobileCloudWebPortalTab extends StatelessWidget {
  const _MobileCloudWebPortalTab();

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(title: const Text('Portal Cloud Web OXORA')),
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
                  'Pengelolaan absensi lengkap, penggajian (Payroll), PPh 21, BPJS, e-Faktur CoreTax XML, dan jurnal akuntansi lanjutan dapat diakses melalui OXORA Cloud Web (/admin).',
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
