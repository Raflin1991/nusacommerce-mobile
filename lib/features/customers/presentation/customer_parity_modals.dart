part of 'customer_list_screen.dart';

extension _CustomerParityModalsExt on _CustomerListScreenState {
  Widget _buildCustomerGroupsTab(List<Map<String, dynamic>> groups) {
    final tokens = NusaThemeTokens.of(context);
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined, size: 48, color: tokens.textTertiary),
              const SizedBox(height: 10),
              const Text(
                'Belum Ada Grup Pelanggan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Kelompokkan pelanggan (misal: Member VIP, Reseller, Grosir) untuk memberikan diskon otomatis.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => _showAddOrEditGroupModal(),
                icon: const Icon(Icons.add),
                label: const Text('Buat Grup Pelanggan'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (itemCtx, idx) {
        final itemTokens = NusaThemeTokens.of(itemCtx);
        final g = groups[idx];
        final id = (g['id'] as num?)?.toInt() ?? 0;
        final disc = double.tryParse((g['default_discount_percent'] ?? g['discount_percent'] ?? 0).toString()) ?? 0.0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: itemTokens.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: itemTokens.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: itemTokens.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.workspace_premium_outlined, color: itemTokens.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      'Diskon Default: ${disc.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12.5, color: itemTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit_outlined, color: itemTokens.accent),
                onPressed: () => _showAddOrEditGroupModal(existing: g),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: itemTokens.danger),
                onPressed: () => context.read<PosCubit>().deleteCustomerGroup(id),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddOrEditGroupModal({Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final discCtrl = TextEditingController(
      text: (double.tryParse((existing?['default_discount_percent'] ?? existing?['discount_percent'] ?? 0).toString()) ?? 0.0)
          .round()
          .toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Tambah Grup Pelanggan' : 'Edit Grup Pelanggan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nama Grup (cth: VIP / Grosir) *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: discCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Diskon Default (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final nm = nameCtrl.text.trim();
              if (nm.isEmpty) return;
              final disc = (double.tryParse(discCtrl.text.trim()) ?? 0).clamp(0, 100);
              await context.read<PosCubit>().saveCustomerGroup(
                    {'name': nm, 'default_discount_percent': disc},
                    id: (existing?['id'] as num?)?.toInt(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomerStatementModal(
    Map<String, dynamic> customer,
    List<Map<String, dynamic>> localHistory,
  ) async {
    final custId = (customer['id'] as num?)?.toInt() ?? 0;
    final depositLogs = _offlineDb.getLocalCustomerDepositLogs(custId);
    final isLocalTrial = context.read<AuthCubit>().state.session.isLocalTrial;
    List<Map<String, dynamic>> entries = localHistory.map((s) {
      return {
        'title': 'Transaksi ${s['number'] ?? '-'}',
        'date': (s['sale_datetime'] ?? s['created_at'] ?? '').toString(),
        'amount': (s['grand_total'] as num?)?.toDouble() ?? 0.0,
        'balance_due': (s['balance_due'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();

    for (final d in depositLogs) {
      entries.add({
        'title': 'Top-up Deposit (${d['notes'] ?? '-'})',
        'date': (d['created_at'] ?? '').toString(),
        'amount': (d['amount'] as num?)?.toDouble() ?? 0.0,
        'balance_due': 0.0,
      });
    }

    if (!isLocalTrial && custId > 0) {
      try {
        final res = await _api.dio.get(ApiEndpoints.customerStatement(custId));
        final data = res.data['data'];
        if (data is Map) {
          final rawEntries = data['entries'] as List<dynamic>?;
          if (rawEntries != null && rawEntries.isNotEmpty) {
            entries = rawEntries.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          } else {
            final cloudEntries = <Map<String, dynamic>>[];
            for (final s in (data['sales'] as List<dynamic>? ?? [])) {
              final m = Map<String, dynamic>.from(s as Map);
              cloudEntries.add({
                'title': 'Belanja ${m['number'] ?? '#INV'}',
                'date': (m['sale_datetime'] ?? '').toString(),
                'amount': (m['grand_total'] as num?)?.toDouble() ?? 0.0,
                'balance_due': (m['balance_due'] as num?)?.toDouble() ?? 0.0,
              });
            }
            for (final p in (data['payments'] as List<dynamic>? ?? [])) {
              final m = Map<String, dynamic>.from(p as Map);
              cloudEntries.add({
                'title': 'Pembayaran (${m['method_name'] ?? 'Tunai'})',
                'date': (m['paid_at'] ?? '').toString(),
                'amount': (m['amount'] as num?)?.toDouble() ?? 0.0,
                'balance_due': 0.0,
              });
            }
            for (final l in (data['credit_and_loyalty_logs'] as List<dynamic>? ?? [])) {
              final m = Map<String, dynamic>.from(l as Map);
              cloudEntries.add({
                'title': (m['notes'] ?? m['type'] ?? 'Mutasi Deposit/Poin').toString(),
                'date': (m['created_at'] ?? '').toString(),
                'amount': (m['amount'] as num?)?.toDouble() ?? 0.0,
                'balance_due': 0.0,
              });
            }
            cloudEntries.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
            if (cloudEntries.isNotEmpty) {
              entries = cloudEntries;
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        builder: (_, sc) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kartu Piutang & Deposit • ${customer['name']}',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Saldo Piutang: ${IdrCurrencyFormatter.format((customer['outstanding_balance'] as num?)?.toDouble() ?? 0)}  •  Deposit: ${IdrCurrencyFormatter.format((customer['store_credit_balance'] as num?)?.toDouble() ?? 0)}',
                style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
              ),
              const Divider(height: 18),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('Belum ada riwayat kartu piutang / deposit.'))
                    : ListView.separated(
                        controller: sc,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final e = entries[idx];
                          final due = (e['balance_due'] as num?)?.toDouble() ?? 0.0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text((e['title'] ?? '-').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                            subtitle: Text((e['date'] ?? '-').toString()),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  IdrCurrencyFormatter.format((e['amount'] as num?)?.toDouble() ?? 0),
                                  style: AppTheme.moneyStyle(fontSize: 13.5),
                                ),
                                if (due > 0)
                                  Text(
                                    'Bon: ${IdrCurrencyFormatter.format(due)}',
                                    style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(ctx).danger),
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
  }

  void _showTopupDepositModal(Map<String, dynamic> customer) {
    final custId = (customer['id'] as num?)?.toInt() ?? 0;
    final amtCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: 'Top-up Deposit Member');
    final isLocalTrial = context.read<AuthCubit>().state.session.isLocalTrial;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Top-up Deposit • ${customer['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amtCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal Top-up (Rp)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Catatan'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
              if (amt <= 0) return;
              Navigator.pop(ctx);
              if (!isLocalTrial && custId > 0) {
                try {
                  await _api.dio.post(ApiEndpoints.customerStoreCreditTopup(custId), data: {
                    'amount': amt,
                    'notes': notesCtrl.text.trim(),
                  });
                } catch (_) {
                  await _offlineDb.topupLocalCustomerDeposit(
                    customerId: custId,
                    amount: amt,
                    notes: notesCtrl.text.trim(),
                  );
                }
              } else {
                await _offlineDb.topupLocalCustomerDeposit(
                  customerId: custId,
                  amount: amt,
                  notes: notesCtrl.text.trim(),
                );
              }
              if (mounted) {
                await context.read<PosCubit>().syncWithCloud(force: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deposit sebesar ${IdrCurrencyFormatter.format(amt)} berhasil ditambahkan!'),
                  ),
                );
              }
            },
            child: const Text('Simpan Deposit'),
          ),
        ],
      ),
    );
  }
}
