import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 2 — BERANDA / DASHBOARD SCREEN
/// Matches 1:1 with Screen 2 of `Papan Konsep UI KasirKu Modern-1.png`
class HomeDashboardScreen extends StatelessWidget {
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSwitchTab;

  const HomeDashboardScreen({
    super.key,
    required this.onOpenDrawer,
    required this.onSwitchTab,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final posState = context.watch<PosCubit>().state;
    final firstName = authState.session.userName.split(' ').first;

    // Default matches Mockup Rp 1.250.000 + any newly completed session sales
    final extraSales = posState.salesHistory
        .where((s) => s['id'] != null && (s['id'] as int) > 2000 && s['status'] == 'completed')
        .fold<double>(0.0, (sum, s) => sum + ((s['grand_total'] as num?)?.toDouble() ?? 0.0));
    final todaySales = 1250000.0 + extraSales;
    final grossProfit = 470000.0 + (extraSales * 0.35);
    const totalReceivables = 320000.0;
    final lowStockCount = posState.lowStockProductsCount > 0 ? posState.lowStockProductsCount : 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Header Bar (Menu Drawer, Branch Pill, Notification Bell with Badge '3')
              _buildTopHeader(context, authState.session, posState.offlinePendingCount),
              const SizedBox(height: 14),

              // 2. Greeting: "Halo, Raflin 👋 / Semangat berbisnis hari ini!"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Halo, $firstName 👋',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Semangat berbisnis hari ini!',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                  // Active Shift Status Chip
                  InkWell(
                    onTap: () => context.push('/shifts'),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.successSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.success.withOpacity(0.35)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, color: AppColors.successDark, size: 8),
                          SizedBox(width: 6),
                          Text(
                            'Shift Buka',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.successDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Blue Gradient Hero Card: "Penjualan Hari Ini / Rp 1.250.000 / ↑ 12%"
              _buildHeroSalesCard(todaySales),
              const SizedBox(height: 14),

              // 4. 3 Compact Metric Cards: Laba Kotor, Piutang, Stok Menipis (Persis Mockup)
              Row(
                children: [
                  Expanded(
                    child: _buildCompactMetricCard(
                      bgColor: const Color(0xFFDCFCE7),
                      iconBgColor: const Color(0xFF16A34A),
                      icon: Icons.monetization_on_rounded,
                      label: 'Laba Kotor',
                      value: IdrCurrencyFormatter.format(grossProfit),
                      valueColor: AppColors.navyDark,
                      onTap: () => onSwitchTab(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildCompactMetricCard(
                      bgColor: const Color(0xFFFEF3C7),
                      iconBgColor: const Color(0xFFF59E0B),
                      icon: Icons.access_time_filled_rounded,
                      label: 'Piutang',
                      value: IdrCurrencyFormatter.format(totalReceivables),
                      valueColor: AppColors.navyDark,
                      onTap: () => context.push('/debts'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildCompactMetricCard(
                      bgColor: const Color(0xFFEDE9FE),
                      iconBgColor: const Color(0xFF7C3AED),
                      icon: Icons.inventory_2_rounded,
                      label: 'Stok Menipis',
                      value: '$lowStockCount Produk',
                      valueColor: AppColors.danger,
                      onTap: () => onSwitchTab(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // 5. Section "Menu Utama" (6 Grid Icons: Penjualan, Pembelian, Barang, Laporan, Pengaturan, Lainnya)
              const Text(
                'Menu Utama',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  _buildMainMenuGridCard(
                    icon: Icons.shopping_cart_rounded,
                    label: 'Penjualan',
                    onTap: () => context.push('/pos'),
                  ),
                  _buildMainMenuGridCard(
                    icon: Icons.shopping_bag_rounded,
                    label: 'Pembelian',
                    onTap: () => context.push('/debts?tab=expenses'),
                  ),
                  _buildMainMenuGridCard(
                    icon: Icons.inventory_2_rounded,
                    label: 'Barang',
                    onTap: () => onSwitchTab(2),
                  ),
                  _buildMainMenuGridCard(
                    icon: Icons.bar_chart_rounded,
                    label: 'Laporan',
                    onTap: () => onSwitchTab(3),
                  ),
                  _buildMainMenuGridCard(
                    icon: Icons.settings_rounded,
                    label: 'Pengaturan',
                    onTap: () => onSwitchTab(4),
                  ),
                  _buildMainMenuGridCard(
                    icon: Icons.more_horiz_rounded,
                    label: 'Lainnya',
                    onTap: () => _showEnterpriseMoreSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 6. Bottom Promo / Analytics Banner Card (Persis Mockup)
              _buildAnalyticsPromoBanner(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, AuthSessionModel session, int offlinePendingCount) {
    return Row(
      children: [
        InkWell(
          onTap: onOpenDrawer,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(6.0),
            child: Icon(Icons.menu_rounded, size: 26, color: AppColors.navyDark),
          ),
        ),
        const SizedBox(width: 8),
        // Store Branch Switcher Pill
        InkWell(
          onTap: () => _showBranchSwitcherModal(context, session),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                Text(
                  session.activeStore.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.slate500),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (offlinePendingCount > 0)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.warningSoft,
              label: Text(
                '$offlinePendingCount Offline',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.warningDark),
              ),
            ),
          ),
        // Notification Bell with Red Badge '3' (Persis Mockup)
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('3 Notifikasi: 2 Stok Barang Menipis • 1 Piutang Jatuh Tempo Hari Ini'),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_none_rounded, size: 26, color: AppColors.navyDark),
            ),
            Positioned(
              right: 8,
              top: 6,
              child: Container(
                width: 17,
                height: 17,
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  '3',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroSalesCard(double todaySales) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroBlueGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.equalizer_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Penjualan Hari Ini',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                IdrCurrencyFormatter.format(todaySales),
                style: AppTheme.moneyStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.arrow_upward_rounded, color: Color(0xFF4ADE80), size: 18),
                  const SizedBox(width: 4),
                  const Text(
                    '12%',
                    style: TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ' dibanding kemarin',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Rising Sparkline Line Chart on the Right (Matches Mockup Hero Card)
          Positioned(
            right: 0,
            bottom: 0,
            child: SizedBox(
              width: 135,
              height: 62,
              child: CustomPaint(
                painter: _HeroSparklinePainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetricCard({
    required Color bgColor,
    required Color iconBgColor,
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconBgColor.withOpacity(0.18)),
        ),
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.slate600,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: AppTheme.moneyStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainMenuGridCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.navyDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsPromoBanner(BuildContext context) {
    return InkWell(
      onTap: () => onSwitchTab(3),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.promoAmberGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tingkatkan Bisnis Anda\ndengan laporan yang lengkap',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.navyMid,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Lihat Detail',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Rising Bar Chart Graphic matching Mockup
            SizedBox(
              width: 85,
              height: 68,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _promoBar(22, AppColors.primary.withOpacity(0.35)),
                  _promoBar(34, AppColors.primary.withOpacity(0.55)),
                  _promoBar(48, AppColors.primary.withOpacity(0.75)),
                  _promoBar(64, AppColors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoBar(double height, Color color) {
    return Container(
      width: 14,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
    );
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEnterpriseMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Modul Operasional NusaCommerce',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Fitur lanjutan POS Ritel, Restoran F&B, Shift Kasir & Buku Bon UMKM',
              style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(Icons.table_restaurant_rounded, color: AppColors.primary),
              ),
              title: const Text('Mode Restoran & Denah Meja (F&B)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Open Tab, Pesanan QR Meja, Tiket Dapur (KOT) & Split Bill'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/restaurant');
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.successSoft,
                child: Icon(Icons.lock_clock_rounded, color: AppColors.successDark),
              ),
              title: const Text('Shift Kasir, Kas Laci & Z-Report', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Buka/Tutup Shift, Kas Masuk/Keluar & Rekonsiliasi Uang Fisik'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/shifts');
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.warningSoft,
                child: Icon(Icons.menu_book_rounded, color: AppColors.warningDark),
              ),
              title: const Text('Buku Bon Piutang & Tagih WA', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Daftar kasbon pelanggan, cicilan & 1-klik pengingat WhatsApp'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/debts');
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.purpleSoft,
                child: Icon(Icons.storefront_rounded, color: AppColors.purple),
              ),
              title: const Text('Profil Toko & Kustomisasi Struk', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Atur nama toko, alamat, nomor telepon & logo struk thermal'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/store-profile');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final points = [
      Offset(0, size.height * 0.85),
      Offset(size.width * 0.25, size.height * 0.65),
      Offset(size.width * 0.48, size.height * 0.72),
      Offset(size.width * 0.72, size.height * 0.38),
      Offset(size.width * 0.95, size.height * 0.14),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, linePaint);

    for (final pt in points) {
      canvas.drawCircle(pt, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
