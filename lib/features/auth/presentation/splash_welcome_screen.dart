import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/product_illustration_widget.dart';

/// LAYAR 1 — SPLASH & WELCOME SCREEN
/// Matches 1:1 with Top-Left Screen of `Papan Konsep UI KasirKu Modern-1.png`
class SplashWelcomeScreen extends StatelessWidget {
  const SplashWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top-right soft blue decorative wave matching mockup
          Positioned(
            top: -60,
            right: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // Shopping Bag Logo with 'K' / NusaPOS Icon (Persis Mockup)
                  _buildShoppingBagLogo(),
                  const SizedBox(height: 18),
                  const Text(
                    'KasirKu',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'NusaCommerce Enterprise Edition',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Kelola Usaha Lebih Mudah\nDalam Satu Aplikasi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate600,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // 3D Storefront & Rising Growth Chart Illustration
                  const Store3DIllustrationWidget(height: 195, showChartBadge: true),
                  const Spacer(flex: 3),
                  // Primary CTA Button: "Mulai Sekarang >"
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => context.go('/home'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.primary.withOpacity(0.35),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Mulai Sekarang',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Secondary Link: "Masuk ke Akun" (Multi-Tenant Cloud Login)
                  TextButton(
                    onPressed: () => context.push('/login'),
                    child: const Text(
                      'Masuk ke Akun',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShoppingBagLogo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bag Handle
        Container(
          width: 36,
          height: 16,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.primary, width: 5),
              left: BorderSide(color: AppColors.primary, width: 5),
              right: BorderSide(color: AppColors.primary, width: 5),
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
        ),
        // Bag Body
        Container(
          width: 76,
          height: 68,
          decoration: BoxDecoration(
            gradient: AppColors.heroBlueGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'K',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
