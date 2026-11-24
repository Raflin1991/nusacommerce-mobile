// ignore_for_file: invalid_use_of_protected_member
part of 'transactions_history_screen.dart';

extension _TransactionsHistoryScreenStatePart2Ext on _TransactionsHistoryScreenState {

  void _showReturnReasonsManager(BuildContext context) {
    final posCubit = context.read<PosCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BlocBuilder<PosCubit, PosState>(
        builder: (ctx, state) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Kelola Alasan Retur / Void',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  FilledButton.icon(
                    onPressed: () {
                      final ctrl = TextEditingController();
                      showDialog(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Alasan Retur Baru'),
                          content: TextField(
                            controller: ctrl,
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'Nama Alasan (cth: Barang Cacat)'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Batal')),
                            FilledButton(
                              onPressed: () async {
                                final nm = ctrl.text.trim();
                                if (nm.isEmpty) return;
                                await posCubit.saveReturnReason({'name': nm});
                                if (dCtx.mounted) Navigator.pop(dCtx);
                              },
                              child: const Text('Simpan'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.returnReasons.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Belum ada alasan retur terdaftar.', style: TextStyle(color: NusaThemeTokens.of(ctx).textSecondary)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: state.returnReasons.length,
                    itemBuilder: (_, idx) {
                      final r = state.returnReasons[idx];
                      final id = (r['id'] as num?)?.toInt() ?? 0;
                      return ListTile(
                        title: Text((r['name'] ?? r['code'] ?? '-').toString()),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: NusaThemeTokens.of(ctx).danger),
                          onPressed: () => posCubit.deleteReturnReason(id),
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
  }


  Widget _buildTransactionShortcutsStrip(BuildContext context, NusaThemeTokens tokens) {
    final shortcuts = [
      (label: '💳 Buku Bon & Pelunasan', route: '/debts'),
      (label: '📝 Surat Penawaran', route: '/quotations'),
      (label: '📒 Buku Kas Toko', route: '/cash-ledger'),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shortcuts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final item = shortcuts[i];
          return InkWell(
            onTap: () => context.push(item.route),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.3),
                  width: tokens.borderWidth,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.accentDark,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
