// ignore_for_file: invalid_use_of_protected_member
part of 'settings_screen.dart';

extension _SettingsScreenStatePart4Ext on _SettingsScreenState {

  Future<void> _showFactoryResetDialog(BuildContext context) async {
    final confirmCtrl = TextEditingController();
    final productCount = _offlineDb.getCachedProducts().length;
    final salesCount = _offlineDb.getLocalSalesHistory().length;
    final heldCount = _offlineDb.getHeldSales().length;
    final pendingCount = _offlineDb.totalOfflineQueueBadgeCount;
    bool resetting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !resetting,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setDialogState) {
          final tokens = NusaThemeTokens.of(dCtx);
          final canReset = confirmCtrl.text.trim().toUpperCase() == 'RESET' && !resetting;
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.delete_forever_rounded, color: tokens.danger),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Reset Pabrik / Hapus Database',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.danger),
                    ),
                    child: Text(
                      'TINDAKAN PERMANEN! Seluruh data lokal di perangkat ini akan dihapus bersih:\n'
                      '• $productCount Produk & Stok\n'
                      '• $salesCount Riwayat Transaksi Kasir\n'
                      '• $heldCount Nota Tahan (Hold Bill)\n'
                      '• $pendingCount Antrean Sinkronisasi & Profil Toko',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.danger,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ketik kata RESET di bawah ini untuk mengonfirmasi penghapusan seluruh database lokal:',
                    style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmCtrl,
                    enabled: !resetting,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Ketik RESET',
                      prefixIcon: Icon(Icons.warning_amber_rounded),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: resetting ? null : () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: !canReset
                    ? null
                    : () async {
                        setDialogState(() => resetting = true);
                        final authCubit = context.read<AuthCubit>();
                        final posCubit = context.read<PosCubit>();
                        await authCubit.factoryResetLocalDatabase();
                        await posCubit.resetForLogout();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                child: Text(resetting ? 'Menghapus...' : 'Hapus Permanen'),
              ),
            ],
          );
        },
      ),
    );
  }


  ThemeCubit? _maybeThemeCubit(BuildContext context) {
    try {
      return context.watch<ThemeCubit>();
    } catch (_) {
      return null;
    }
  }


  void _showThemeModeModal(BuildContext context, ThemeCubit themeCubit) {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tema Tampilan CDO Warm Linen',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih tampilan paling nyaman: Warm Linen Terang, Mode Gelap, atau Kontras Tinggi Outdoor POS.',
                style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
              ),
              const SizedBox(height: 14),
              ...NusaThemeMode.values.map((mode) {
                final selected = themeCubit.state == mode;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NusaCard(
                    backgroundColor: selected ? tokens.accentSoft : tokens.bgSurface,
                    borderColor: selected ? tokens.accent : tokens.borderSubtle,
                    borderWidth: selected ? 1.6 : tokens.borderWidth,
                    onTap: () async {
                      await themeCubit.setThemeMode(mode);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Row(
                      children: [
                        Icon(mode.icon, color: selected ? tokens.accent : tokens.textPrimary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            mode.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildSettingsTile(
    NusaThemeTokens tokens, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: tokens.textPrimary, size: 24),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: tokens.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: tokens.textSecondary,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: tokens.textTertiary),
      onTap: onTap,
    );
  }
}
