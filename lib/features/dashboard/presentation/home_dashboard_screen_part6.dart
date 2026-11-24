// ignore_for_file: invalid_use_of_protected_member
part of 'home_dashboard_screen.dart';

extension _HomeDashboardScreenStatePart6Ext on _HomeDashboardScreenState {

  void _showBranchSwitcherModal(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih Cabang Toko Aktif',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...session.availableStores.map(
              (branch) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: branch.id == session.activeStore.id
                      ? tokens.accent
                      : tokens.accentSoft,
                  child: Icon(
                    Icons.store_rounded,
                    color: branch.id == session.activeStore.id ? Colors.white : tokens.accent,
                  ),
                ),
                title: Text(
                  branch.name,
                  style: TextStyle(fontWeight: FontWeight.w700, color: tokens.textPrimary),
                ),
                subtitle: Text(
                  'Kode: ${branch.code} • ${branch.city ?? 'Indonesia'}',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                trailing: branch.id == session.activeStore.id
                    ? Icon(Icons.check_circle_rounded, color: tokens.positive)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  if (branch.id == session.activeStore.id) return;
                  await context.read<AuthCubit>().switchStoreBranch(branch);
                  if (context.mounted) {
                    await context.read<PosCubit>().syncWithCloud(force: true);
                  }
                  if (mounted) {
                    await _loadDashboard(storeId: branch.id);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildLocalTrialUpgradeBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    int activeStoreId,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.32),
          width: tokens.borderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tokens.accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.cloud_upload_outlined, color: tokens.accentDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Usaha Mandiri (Tersimpan di HP ini)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cadangkan ke OXORA Cloud agar aman jika HP ganti atau rusak.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final migrated = await showCloudMigrationSheet(context);
                if (migrated == true && mounted) {
                  await _loadDashboard(storeId: activeStoreId);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.cloud_sync_rounded, size: 18),
              label: const Text(
                'Hubungkan Akun Cloud',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
