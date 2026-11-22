import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Gold Crown pill badge shown on All-Sidebar-Active menu items that require a
/// higher Cascade subscription tier (`PRO` or `ENTERPRISE`).
class CascadeCrownBadge extends StatelessWidget {
  final String requiredTier;

  const CascadeCrownBadge({
    super.key,
    required this.requiredTier,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = requiredTier.trim().toUpperCase();
    final isEnterprise = normalized.contains('ENT');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEnterprise
              ? const [Color(0xFFFEF3C7), Color(0xFFFDE68A)]
              : const [Color(0xFFFEF9C3), Color(0xFFFEF08A)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isEnterprise ? const Color(0xFFD97706) : const Color(0xFFEAB308),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('👑', style: TextStyle(fontSize: 10)),
          const SizedBox(width: 3),
          Text(
            isEnterprise ? 'ENT' : 'PRO',
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF92400E),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive In-App Teaser modal when a user taps a gated Cascade module.
Future<void> showCascadeModuleTeaserModal(
  BuildContext context, {
  required String moduleKey,
  required String moduleTitle,
  required String requiredTier,
  required String currentTier,
  required String description,
  required List<String> benefits,
}) {
  final normalizedRequired = requiredTier.trim().toUpperCase();
  final normalizedCurrent = currentTier.trim().isEmpty ? 'STARTER' : currentTier.trim().toUpperCase();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE68A).withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFBBF24)),
                      ),
                      child: const Center(
                        child: Text('👑', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            moduleTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Paket Anda: $normalizedCurrent  •  Tersedia di: $normalizedRequired',
                            style: const TextStyle(
                              color: Color(0xFFFDE68A),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.slate700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Keunggulan yang Langsung Terbuka:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              ...benefits.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 17,
                        color: AppColors.successDark,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.slate700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primaryDark),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Catatan Dual-Plane Cascade: Data transaksi kasir, stok, dan bon pelanggan tetap berjalan aman 100% dan langsung tersinkron saat paket diaktifkan.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.navyDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Nanti Saja', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.navyDark,
                            content: Text(
                              'Hubungi Owner / Panel Web OXO.ID → Paket Langganan untuk mengaktifkan modul "$moduleTitle" ($normalizedRequired).',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                      label: Text(
                        'Upgrade ke $normalizedRequired',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
