import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../bloc/auth_cubit.dart';

/// LAYAR 1 — PORTAL PENGANTAR RESMI NUSACOMMERCE MOBILE
class SplashWelcomeScreen extends StatelessWidget {
  const SplashWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.watch<AuthCubit>().state.isAuthenticated;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildBrandEmblem(),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'NusaCommerce',
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.navyDark,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'POS & Store Operations Super-App',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Pusat kendali operasional harian toko fisik & F&B yang terhubung langsung ke Cloud multi-tenant.',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.slate600,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppColors.cardShadow,
                          ),
                          child: const Column(
                            children: [
                              _CapabilityRow(
                                icon: Icons.qr_code_scanner_rounded,
                                title: 'Kasir POS Retail & Multi-Industri',
                                subtitle: 'Scan barcode & timbangan digital, multi-satuan grosir, cetak thermal & struk WA.',
                              ),
                              Divider(height: 1, indent: 64),
                              _CapabilityRow(
                                icon: Icons.inventory_2_outlined,
                                title: 'Inventaris Real-Time & Opname FEFO',
                                subtitle: 'Pantau stok menipis, batch kadaluwarsa, lokasi rak & stock opname kamera.',
                              ),
                              Divider(height: 1, indent: 64),
                              _CapabilityRow(
                                icon: Icons.account_balance_wallet_outlined,
                                title: 'Pelanggan, Pemasok & Buku Bon',
                                subtitle: 'Diskon member, poin loyalitas, stok masuk supplier & penagihan piutang WA.',
                              ),
                              Divider(height: 1, indent: 64),
                              _CapabilityRow(
                                icon: Icons.analytics_outlined,
                                title: 'Shift Blind-Count & Laporan SAK EMKM',
                                subtitle: 'Rekonsiliasi kas laci anti-manipulasi, Z-Report, dan radar anti-fraud cabang.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primaryLight),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_user_outlined, size: 18, color: AppColors.primary),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Multi-Tenant Cloud Sync • Offline-First Idempotent Queue',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: () => context.go(isAuthenticated ? '/home' : '/login'),
                            icon: const Icon(Icons.login_rounded, size: 20),
                            label: Text(
                              isAuthenticated
                                  ? 'Lanjutkan ke Ruang Kerja Toko'
                                  : 'Masuk ke Ruang Kerja Toko',
                            ),
                          ),
                        ),
                        if (isAuthenticated) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: const Text(
                              'Ganti Akun atau Subdomain Toko',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.slate600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandEmblem() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.executiveNavyGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.navyDark.withOpacity(0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 30),
        ),
        Positioned(
          right: -6,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Text(
              'NC',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _CapabilityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
