// ignore_for_file: invalid_use_of_protected_member
part of 'settings_screen.dart';

extension _SettingsScreenStatePart3Ext on _SettingsScreenState {

  IconData _verticalIcon(BusinessVertical vertical) {
    switch (vertical) {
      case BusinessVertical.retail:
        return Icons.storefront_rounded;
      case BusinessVertical.restaurant:
        return Icons.restaurant_menu_rounded;
      case BusinessVertical.pharmacy:
        return Icons.local_pharmacy_outlined;
      case BusinessVertical.workshop:
        return Icons.build_circle_outlined;
      case BusinessVertical.laundry:
        return Icons.local_laundry_service_outlined;
      case BusinessVertical.salon:
        return Icons.content_cut_rounded;
    }
  }


  void _showBusinessVerticalModal(BuildContext context) {
    final currentVertical = context.read<PosCubit>().state.currentVertical;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final tokens = NusaThemeTokens.of(ctx);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode Bisnis Toko',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sesuaikan tampilan dan alur kerja Kasir POS dengan jenis usaha Anda. Perubahan langsung aktif tanpa restart.',
                  style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                ),
                const SizedBox(height: 16),
                ...BusinessVertical.values.map((v) {
                  final isSelected = v == currentVertical;
                  final caps = VerticalConfig.getCapabilities(v);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: NusaCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderColor: isSelected ? tokens.accent : tokens.borderSubtle,
                      borderWidth: isSelected ? 1.5 : tokens.borderWidth,
                      backgroundColor: isSelected ? tokens.accentSoft : tokens.bgElevated,
                    onTap: () async {
                      await context.read<PosCubit>().setBusinessVertical(v);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: NusaThemeTokens.of(ctx).positive,
                            content: Text(
                              'Mode bisnis aktif diubah ke ${v.label} (${caps.posDisplayName}).',
                            ),
                          ),
                        );
                      }
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? NusaThemeTokens.of(ctx).accent.withOpacity(0.14)
                                : NusaThemeTokens.of(ctx).bgElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _verticalIcon(v),
                            size: 21,
                            color: isSelected ? NusaThemeTokens.of(ctx).accent : NusaThemeTokens.of(ctx).textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: NusaThemeTokens.of(ctx).textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                v.shortDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isSelected)
                          const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
      },
    );
  }


  void _showAboutDialog(BuildContext context, PosState posState) {
    final printerName = _printerService.isWifiMode
        ? _printerService.activePrinterLabel
        : (_printerService.connectedPrinter?.name ?? 'Belum Terhubung');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.storefront_rounded, color: NusaThemeTokens.of(ctx).accent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'OXORA Mobile',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Versi 2.0.0 Enterprise (Multi-Industry POS)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text('Mode Bisnis: ${posState.currentVertical.label}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Database Lokal: SQLite Terindeks (${posState.allProducts.length} SKU)', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Printer Thermal ESC/POS: $printerName (${_printerService.paperWidth})', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Status Cloud: ${posState.isOnline ? 'Online & Sinkron' : 'Mode Offline Aman'}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            Text(
              'Platform Kasir POS Offline-First, Operasional Toko & 50 Laporan Bisnis oleh OXORA.',
              style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).textSecondary),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }


  Future<void> _handleSyncData(BuildContext context) async {
    final syncedCount = await context.read<PosCubit>().syncOfflineTransactions();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).positive,
          content: Text(
            syncedCount > 0
                ? '$syncedCount item offline berhasil disinkronkan ke Cloud!'
                : 'Seluruh data usaha sudah 100% tersinkronisasi dengan OXORA Cloud.',
          ),
        ),
      );
    }
  }


  void _showOfflinePinModal(BuildContext context) {
    final authCubit = context.read<AuthCubit>();
    final hasPin = authCubit.hasStandalonePin;
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? inlineError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) {
          final tokens = NusaThemeTokens.of(mCtx);
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(mCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasPin ? 'Ubah / Hapus PIN Kasir Offline' : 'Atur PIN Kasir Offline (Opsional)',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PIN melindungi akses masuk kembali ke toko offline Anda setelah kasir keluar sesi (logout).',
                    style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) => setModalState(() => inlineError = null),
                    decoration: const InputDecoration(
                      labelText: 'PIN Baru (4 - 6 digit)',
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) => setModalState(() => inlineError = null),
                    decoration: const InputDecoration(
                      labelText: 'Konfirmasi PIN Baru',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      counterText: '',
                    ),
                  ),
                  if (inlineError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tokens.danger),
                      ),
                      child: Text(
                        inlineError!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tokens.danger,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (hasPin) ...[
                        Expanded(
                          child: NusaButton(
                            label: 'Hapus PIN',
                            variant: NusaButtonVariant.outline,
                            minHeight: 46,
                            onPressed: () async {
                              await authCubit.setStandaloneCashierPin(null);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN Kasir Offline dihapus.')),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: NusaButton(
                          label: 'Simpan PIN',
                          icon: Icons.verified_user_outlined,
                          minHeight: 46,
                          onPressed: () async {
                            final pin = pinCtrl.text.trim();
                            final confirm = confirmCtrl.text.trim();
                            if (pin.length < 4) {
                              setModalState(() => inlineError = 'PIN minimal 4 digit angka.');
                              return;
                            }
                            if (pin != confirm) {
                              setModalState(() => inlineError = 'Konfirmasi PIN tidak cocok.');
                              return;
                            }
                            await authCubit.setStandaloneCashierPin(pin);
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(mCtx).positive,
                                  content: Text('PIN Kasir Offline berhasil disimpan.'),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  void _showDeadLetterQueueModal(BuildContext context) {
    final processingIds = <String>{};
    String? inlineError;
    String? inlineSuccess;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) {
          final tokens = NusaThemeTokens.of(mCtx);
          final items = mCtx.watch<PosCubit>().state.deadLetterItems;
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(mCtx).size.height * 0.82,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.report_problem_outlined, color: tokens.warning, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dead-Letter Queue (${items.length})',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Text(
                      'Payload offline yang ditolak server dikarantina di sini agar antrean kasir lain tetap lancar sinkron ke Cloud.',
                      style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    if (inlineError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.danger),
                        ),
                        child: Text(
                          inlineError!,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.danger),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (inlineSuccess != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.positiveSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.positive),
                        ),
                        child: Text(
                          inlineSuccess!,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.positive),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_outline_rounded, size: 42, color: tokens.positive),
                              const SizedBox(height: 8),
                              Text(
                                'Antrean Bersih! Tidak ada payload yang ditolak server.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, idx) {
                            final item = items[idx];
                            final id = (item['id'] ?? '').toString();
                            final title = (item['reference_label'] ?? item['title'] ?? item['entity_type'] ?? 'Payload Offline').toString();
                            final entityType = (item['entity_type'] ?? '').toString();
                            final errCode = (item['error_code'] ?? '').toString();
                            final errMsg = (item['error_message'] ?? 'Ditolak oleh server').toString();
                            final httpStatus = (item['http_status'] as num?)?.toInt() ?? 0;
                            final busy = processingIds.contains(id);

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: tokens.bgElevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: tokens.borderSubtle),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: tokens.textPrimary,
                                          ),
                                        ),
                                      ),
                                      NusaBadge(
                                        label: httpStatus > 0 ? 'HTTP $httpStatus' : entityType.toUpperCase(),
                                        variant: NusaBadgeVariant.danger,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    errMsg,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: tokens.danger,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  setModalState(() {
                                                    processingIds.add(id);
                                                    inlineError = null;
                                                    inlineSuccess = null;
                                                  });
                                                  await mCtx.read<PosCubit>().discardDeadLetterItem(id);
                                                  if (!mCtx.mounted) return;
                                                  setModalState(() {
                                                    processingIds.remove(id);
                                                    inlineSuccess = 'Item "$title" dihapus dari antrean.';
                                                  });
                                                },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: tokens.danger,
                                            side: BorderSide(color: tokens.danger),
                                          ),
                                          child: const Text('Hapus'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: busy
                                              ? null
                                              : () async {
                                                  setModalState(() {
                                                    processingIds.add(id);
                                                    inlineError = null;
                                                    inlineSuccess = null;
                                                  });
                                                  Map<String, dynamic>? overrides;
                                                  if (entityType == 'shift_closure' &&
                                                      errCode == 'VarianceReasonRequired') {
                                                    overrides = {
                                                      'variance_reason': 'miscount',
                                                      'variance_notes': 'Rekonsiliasi selisih shift offline',
                                                    };
                                                  }
                                                  final res = await mCtx.read<PosCubit>().retryDeadLetterItem(
                                                        id,
                                                        payloadOverrides: overrides,
                                                      );
                                                  if (!mCtx.mounted) return;
                                                  setModalState(() {
                                                    processingIds.remove(id);
                                                    if (res.success) {
                                                      inlineSuccess =
                                                          'Item "$title" berhasil dikirim ulang ke Cloud!';
                                                    } else {
                                                      inlineError = res.errorMessage ?? 'Masih ditolak server.';
                                                    }
                                                  });
                                                },
                                          child: Text(busy ? 'Mengirim...' : 'Kirim Ulang'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
