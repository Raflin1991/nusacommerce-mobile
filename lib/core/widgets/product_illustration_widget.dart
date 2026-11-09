import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Crisp Vector/Illustrated Product & Store Graphics matching Mockup KasirKu
class ProductIllustrationWidget extends StatelessWidget {
  final String iconType;
  final String? imageUrl;
  final double size;

  const ProductIllustrationWidget({
    super.key,
    required this.iconType,
    this.imageUrl,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildVectorBadge(),
        ),
      );
    }
    return _buildVectorBadge();
  }

  Widget _buildVectorBadge() {
    late Color bgColor;
    late Color accentColor;
    late IconData icon;
    late String badgeText;

    switch (iconType) {
      case 'water':
        bgColor = const Color(0xFFE0F2FE);
        accentColor = const Color(0xFF0284C7);
        icon = Icons.water_drop_rounded;
        badgeText = '600ml';
        break;
      case 'tea':
        bgColor = const Color(0xFFFEF3C7);
        accentColor = const Color(0xFFB45309);
        icon = Icons.local_drink_rounded;
        badgeText = 'SOSRO';
        break;
      case 'noodle':
        bgColor = const Color(0xFFFEE2E2);
        accentColor = const Color(0xFFDC2626);
        icon = Icons.ramen_dining_rounded;
        badgeText = 'MIE';
        break;
      case 'bread':
        bgColor = const Color(0xFFFEF9C3);
        accentColor = const Color(0xFFD97706);
        icon = Icons.bakery_dining_rounded;
        badgeText = 'ROTI';
        break;
      case 'biscuit':
        bgColor = const Color(0xFFFFEDD5);
        accentColor = const Color(0xFFEA580C);
        icon = Icons.cookie_rounded;
        badgeText = 'ROMA';
        break;
      case 'milk':
        bgColor = const Color(0xFFDBEAFE);
        accentColor = const Color(0xFF1D4ED8);
        icon = Icons.breakfast_dining_rounded;
        badgeText = 'UHT';
        break;
      case 'rice':
        bgColor = const Color(0xFFD1FAE5);
        accentColor = const Color(0xFF059669);
        icon = Icons.scale_rounded;
        badgeText = 'CURAH';
        break;
      case 'digital':
        bgColor = const Color(0xFFEDE9FE);
        accentColor = const Color(0xFF7C3AED);
        icon = Icons.bolt_rounded;
        badgeText = 'PLN';
        break;
      default:
        bgColor = AppColors.primarySoft;
        accentColor = AppColors.primary;
        icon = Icons.inventory_2_rounded;
        badgeText = 'POS';
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.18)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: size * 0.54, color: accentColor),
          Positioned(
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3D-Style Storefront Illustration matching Splash & Profil Toko Mockup Screens
class Store3DIllustrationWidget extends StatelessWidget {
  final double height;
  final bool showChartBadge;

  const Store3DIllustrationWidget({
    super.key,
    this.height = 170,
    this.showChartBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft circular halo
          Container(
            width: height * 1.15,
            height: height * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withOpacity(0.16),
                  AppColors.primary.withOpacity(0.02),
                ],
              ),
            ),
          ),
          // Store building body
          Container(
            width: height * 0.92,
            height: height * 0.78,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFDE68A), width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.14),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                // Blue Awning Roof (Striped like KasirKu Mockup)
                Container(
                  height: height * 0.24,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      5,
                      (index) => Container(
                        width: 16,
                        height: height * 0.18,
                        decoration: BoxDecoration(
                          color: index.isEven ? Colors.white.withOpacity(0.9) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Storefront Windows & Door
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Door
                      Container(
                        width: height * 0.24,
                        height: height * 0.36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF93C5FD),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1D4ED8), width: 2),
                        ),
                      ),
                      // Display Window
                      Container(
                        width: height * 0.36,
                        height: height * 0.28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2563EB), width: 2),
                        ),
                        child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 24),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Rising Growth Chart Card on Bottom Right (Matches Splash Mockup)
          if (showChartBadge)
            Positioned(
              right: 22,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up_rounded, color: AppColors.primary, size: 22),
                    SizedBox(width: 4),
                    Icon(Icons.bar_chart_rounded, color: AppColors.success, size: 22),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
