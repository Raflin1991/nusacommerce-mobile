// ignore_for_file: invalid_use_of_protected_member
part of 'settings_screen.dart';

extension _SettingsScreenStatePart1Ext on _SettingsScreenState {

  void _showSwitchStoreBranchModal(BuildContext context) {
    final session = context.read<AuthCubit>().state.session;
    final stores = session.availableStores;

    showModalBottomSheet(
      context: context,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final tokens = NusaThemeTokens.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ganti Cabang Toko Aktif',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih cabang aktif. Katalog produk dan stok otomatis disesuaikan dengan cabang ini.',
                style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
              ),
              const SizedBox(height: 14),
              if (stores.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Hanya 1 cabang aktif yang terdaftar pada akun ini.',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                )
              else
                ...stores.map((branch) {
                  final isCurrent = branch.id == session.activeStore.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NusaCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderColor: isCurrent ? tokens.accent : tokens.borderSubtle,
                      borderWidth: isCurrent ? 1.5 : tokens.borderWidth,
                      backgroundColor: isCurrent ? tokens.accentSoft : tokens.bgElevated,
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (isCurrent) return;
                        await context.read<AuthCubit>().switchStoreBranch(branch);
                        if (context.mounted) {
                          await context.read<PosCubit>().syncWithCloud(force: true);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cabang aktif dialihkan ke ${branch.name}')),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            color: isCurrent ? tokens.accent : tokens.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  branch.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                if (branch.address != null && branch.address!.isNotEmpty)
                                  Text(
                                    branch.address!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }


  void _showServerEndpointModal(BuildContext context) {
    final urlCtrl = TextEditingController(text: _apiClient.baseUrl);
    final edgeUrlCtrl = TextEditingController(
      text: _apiClient.edgeDiscovery.getEdgeBaseUrl() ?? '',
    );
    final nodeCtrl = TextEditingController(
      text: _apiClient.edgeDiscovery.getMobileNodeCode(),
    );
    String? inlineError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Server Cloud, OXORA Edge & Kode Terminal',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Kode Terminal mempartisi nomor struk offline (contoh: M01, M02, M4F9A) agar multi-perangkat kasir tidak pernah bentrok.',
                style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Endpoint REST API Cloud v1',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: edgeUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL OXORA Edge LAN Cabang (Opsional)',
                  hintText: 'http://192.168.1.10/api/v1',
                  prefixIcon: Icon(Icons.router_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nodeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Kode Terminal / Partisi Nota (Anti-Bentrok)',
                  hintText: 'M01 / M02 / M7A3C',
                  prefixIcon: Icon(Icons.tablet_android_outlined),
                  counterText: '',
                ),
              ),
              if (inlineError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(ctx).danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NusaThemeTokens.of(ctx).danger.withOpacity(0.4)),
                  ),
                  child: Text(
                    inlineError!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: NusaThemeTokens.of(ctx).danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final rawNode = nodeCtrl.text.trim().toUpperCase();
                    if (rawNode.isNotEmpty && !RegExp(r'^M?[A-Z0-9]{2,5}$').hasMatch(rawNode)) {
                      setModalState(() {
                        inlineError =
                            'Kode terminal harus 2–6 karakter alfanumerik (contoh: M01, M02, M4F9A).';
                      });
                      return;
                    }
                    await _apiClient.setBaseUrl(urlCtrl.text);
                    await _apiClient.edgeDiscovery.setEdgeBaseUrl(edgeUrlCtrl.text);
                    if (rawNode.isNotEmpty) {
                      await context.read<PosCubit>().updateTerminalNodeCode(rawNode);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Tersimpan • Terminal ${_apiClient.edgeDiscovery.getMobileNodeCode()} • ${_apiClient.baseUrl}',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Simpan Konfigurasi Server & Terminal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
