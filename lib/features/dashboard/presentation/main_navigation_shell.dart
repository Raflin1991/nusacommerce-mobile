import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../inventory/presentation/products_inventory_screen.dart';
import '../../owner_reports/presentation/business_reports_screen.dart';
import '../../sales_history/presentation/transactions_history_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'home_dashboard_screen.dart';

/// 5-Tab Bottom Navigation Shell matching `Papan Konsep UI KasirKu Modern-1.png`:
/// [0] Beranda  [1] Transaksi  [2] Barang  [3] Laporan  [4] Menu (Pengaturan)
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
                _buildNavItem(1, Icons.shopping_cart_rounded, Icons.shopping_cart_outlined, 'Transaksi'),
                _buildNavItem(2, Icons.inventory_2_rounded, Icons.inventory_2_outlined, 'Barang'),
                _buildNavItem(3, Icons.bar_chart_rounded, Icons.bar_chart_outlined, 'Laporan'),
                _buildNavItem(4, Icons.menu_rounded, Icons.menu_rounded, 'Menu'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.primary : AppColors.slate400;

    return Expanded(
      child: InkWell(
        onTap: () => _switchTab(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? activeIcon : inactiveIcon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
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

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 22),
            decoration: const BoxDecoration(gradient: AppColors.heroBlueGradient),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${session.userRole} • ${session.activeStore.name}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Tenant: ${session.tenantSubdomain}.nusco.id (${session.planName})',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _drawerTile(Icons.point_of_sale_rounded, 'Kasir Penjualan Baru (POS)', () {
                  Navigator.pop(context);
                  context.push('/pos');
                }),
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
                _drawerTile(Icons.receipt_long_rounded, 'Biaya Operasional & Pembelian', () {
                  Navigator.pop(context);
                  context.push('/debts?tab=expenses');
                }),
                const Divider(height: 24),
                _drawerTile(Icons.storefront_rounded, 'Profil Toko & Struk Header', () {
                  Navigator.pop(context);
                  context.push('/store-profile');
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.slate400),
      onTap: onTap,
    );
  }
}
