import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/cascade_entitlement_teaser.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../inventory/presentation/products_inventory_screen.dart';
import '../../owner_reports/presentation/business_reports_screen.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../sales_history/presentation/transactions_history_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'home_dashboard_screen.dart';

/// 5-Tab Bottom Navigation Shell — NusaCommerce Mobile:
/// [0] Beranda  [1] Riwayat  [2] Inventaris  [3] Laporan  [4] Pengaturan
class MainNavigationShell extends StatefulWidget {
  final int initialIndex;

  const MainNavigationShell({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _switchTab(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeDashboardScreen(
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        onSwitchTab: _switchTab,
      ),
      TransactionsHistoryScreen(
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      ProductsInventoryScreen(
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      const BusinessReportsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildEnterpriseDrawer(context),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A0F172A),
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Beranda'),
                _buildNavItem(1, Icons.receipt_long_rounded, Icons.receipt_long_outlined, 'Riwayat'),
                _buildNavItem(2, Icons.inventory_2_rounded, Icons.inventory_2_outlined, 'Inventaris'),
                _buildNavItem(3, Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Laporan'),
                _buildNavItem(4, Icons.settings_rounded, Icons.settings_outlined, 'Pengaturan'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.primary : AppColors.slate500;

    return Expanded(
      child: InkWell(
        onTap: () => _switchTab(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(isSelected ? activeIcon : inactiveIcon, color: color, size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              label,
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

  Widget _buildEnterpriseDrawer(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    final capabilities = context.watch<PosCubit>().state.capabilities;
    final displayName = session.userName.trim().isEmpty ? 'Operator NusaCommerce' : session.userName.trim();
    final roleLabel = session.userRole.isEmpty ? 'Operator' : session.userRole;
    final planLabel = session.planName.isEmpty ? 'Starter' : session.planName;

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 18),
            decoration: const BoxDecoration(gradient: AppColors.executiveNavyGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person_rounded, color: Colors.white, size: 28),
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
                              fontSize: 16.5,
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
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    session.isLocalTrial
                        ? 'Mode Toko Mandiri (Offline Lokal)'
                        : 'Tenant: ${session.tenantSubdomain.isEmpty ? '-' : '${session.tenantSubdomain}.nusco.id'} ($planLabel)',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
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
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/pos');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: const Icon(Icons.point_of_sale_rounded, size: 19),
                    label: const Text('Buka Kasir POS Baru'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _drawerTile(Icons.people_alt_rounded, 'Pelanggan & Member', () {
                  Navigator.pop(context);
                  context.push('/customers');
                }),
                _drawerTile(Icons.local_shipping_rounded, 'Pemasok & Stok Masuk', () {
                  Navigator.pop(context);
                  context.push('/suppliers');
                }),
                if (capabilities.hasTableManagement)
                  _drawerTile(Icons.table_restaurant_rounded, 'Mode Restoran & Denah Meja', () {
                    Navigator.pop(context);
                    context.push('/restaurant');
                  }),
                _drawerTile(Icons.lock_clock_rounded, 'Shift Kasir & Laci Uang (Z-Report)', () {
                  Navigator.pop(context);
                  context.push('/shifts');
                }),
                _drawerTile(Icons.menu_book_rounded, 'Buku Bon Piutang & Tagih WA', () {
                  Navigator.pop(context);
                  context.push('/debts');
                }),
                _drawerTile(Icons.receipt_long_rounded, 'Biaya Operasional Toko', () {
                  Navigator.pop(context);
                  context.push('/debts?tab=expenses');
                }),
                const Divider(height: 20),
                _drawerTile(
                  Icons.shopping_bag_rounded,
                  'Pesanan Toko Online (Webstore)',
                  () {
                    Navigator.pop(context);
                    if (session.isModuleGated('online_store')) {
                      showCascadeModuleTeaserModal(
                        context,
                        moduleKey: 'online_store',
                        moduleTitle: 'Toko Online & Katalog Web',
                        requiredTier: 'PRO',
                        currentTier: session.tier,
                        description: 'Terima pesanan online dari pelanggan langsung ke kasir POS dengan pemotongan stok otomatis secara real-time.',
                        benefits: const [
                          'Etalase web katalog toko siap pakai 24 jam',
                          'Notifikasi pesanan masuk real-time & cetak resi',
                          'Sinkronisasi stok tunggal antar kasir toko & webstore',
                        ],
                      );
                    } else {
                      _switchTab(0);
                    }
                  },
                  isGated: session.isModuleGated('online_store'),
                  requiredTier: 'PRO',
                ),
                _drawerTile(
                  Icons.account_balance_rounded,
                  'Akuntansi & Jurnal Otomatis',
                  () {
                    Navigator.pop(context);
                    if (session.isModuleGated('accounting')) {
                      showCascadeModuleTeaserModal(
                        context,
                        moduleKey: 'accounting',
                        moduleTitle: 'Akuntansi SAK EMKM & Jurnal Otomatis',
                        requiredTier: 'PRO',
                        currentTier: session.tier,
                        description: 'Jurnal umum, neraca, buku besar, dan laporan arus kas tersusun otomatis di belakang layar dari setiap struk penjualan & pembelian.',
                        benefits: const [
                          'Neraca & Laba Rugi komprehensif standar SAK EMKM',
                          'Rekonsiliasi bank & buku kas per akun otomatis',
                          'Ekspor kesiapan pajak & audit akuntan',
                        ],
                      );
                    } else {
                      _switchTab(3);
                    }
                  },
                  isGated: session.isModuleGated('accounting'),
                  requiredTier: 'PRO',
                ),
                _drawerTile(
                  Icons.badge_rounded,
                  'HRD, Jadwal & Absensi Staf',
                  () {
                    Navigator.pop(context);
                    if (session.isModuleGated('hr')) {
                      showCascadeModuleTeaserModal(
                        context,
                        moduleKey: 'hr',
                        moduleTitle: 'HRD, Jadwal Shift & Absensi Karyawan',
                        requiredTier: 'ENTERPRISE',
                        currentTier: session.tier,
                        description: 'Kelola absensi foto/GPS, komisi kasir per penjualan, dan rekap jam kerja cabang langsung terintegrasi.',
                        benefits: const [
                          'Absensi kasir berbasis shift & selfie toko',
                          'Perhitungan komisi & insentif penjualan otomatis',
                          'Kontrol akses karyawan lintas cabang terpusat',
                        ],
                      );
                    } else {
                      context.push('/shifts');
                    }
                  },
                  isGated: session.isModuleGated('hr'),
                  requiredTier: 'ENTERPRISE',
                ),
                const Divider(height: 20),
                _drawerTile(Icons.storefront_rounded, 'Profil Toko & Struk Header', () {
                  Navigator.pop(context);
                  context.push('/store-profile');
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
                    await context.read<AuthCubit>().logout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerDark,
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text('Keluar Sesi (Logout)', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isGated = false,
    String requiredTier = 'PRO',
  }) {
    return ListTile(
      leading: Icon(icon, color: isGated ? AppColors.slate500 : AppColors.primary),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: isGated ? AppColors.slate600 : AppColors.navyDark,
        ),
      ),
      trailing: isGated
          ? CascadeCrownBadge(requiredTier: requiredTier)
          : const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.slate400),
      onTap: onTap,
    );
  }
}
