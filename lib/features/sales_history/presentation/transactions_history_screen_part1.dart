// ignore_for_file: invalid_use_of_protected_member
part of 'transactions_history_screen.dart';

extension _TransactionsHistoryScreenStatePart1Ext on _TransactionsHistoryScreenState {

  Map<String, dynamic> _prepareReprintSalePayload(Map<String, dynamic> sale) {
    final saleKey = (sale['id'] ?? sale['number'] ?? sale.hashCode).toString();
    final existingCount = (sale['reprint_count'] as num?)?.toInt() ?? 0;
    final nextCount = (_reprintCounts[saleKey] ?? existingCount) + 1;
    _reprintCounts[saleKey] = nextCount;
    return {
      ...sale,
      'is_reprint': true,
      'reprint_count': nextCount,
      'cashier_name': sale['cashier_name'] ?? sale['cashier'] ?? 'Kasir POS',
    };
  }


  DateTime? _parseSaleDate(Map<String, dynamic> sale) {
    final raw = (sale['created_at'] ?? sale['sale_datetime'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();
    try {
      return DateFormat('dd MMM yyyy • HH:mm').parse(raw);
    } catch (_) {
      return null;
    }
  }


  bool _matchesPeriod(Map<String, dynamic> sale) {
    if (_periodFilter == 'Semua Waktu') return true;
    final dt = _parseSaleDate(sale);
    if (dt == null) return true;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (_periodFilter == 'Hari Ini') {
      return !dt.isBefore(todayStart);
    }
    if (_periodFilter == '7 Hari') {
      return !dt.isBefore(todayStart.subtract(const Duration(days: 6)));
    }
    if (_periodFilter == 'Bulan Ini') {
      return dt.year == now.year && dt.month == now.month;
    }
    return true;
  }


  Future<bool> _promptAndVerifyManagerPin(BuildContext rootContext, String action) async {
    final pinCtrl = TextEditingController();
    final pin = await showDialog<String>(
      context: rootContext,
      builder: (dCtx) => AlertDialog(
        title: const Text('Otorisasi PIN Manajer', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action == 'void'
                  ? 'Pembatalan (Void) nota memerlukan otorisasi PIN Manajer / Supervisor.'
                  : 'Retur barang (Refund) memerlukan otorisasi PIN Manajer / Supervisor.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Masukkan PIN / Sandi Manajer *',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, pinCtrl.text.trim()),
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );

    if (pin == null || pin.isEmpty || !rootContext.mounted) return false;
    final ok = await rootContext.read<PosCubit>().verifyManagerPin(
          pin,
          action: action,
          setApprovedState: false,
        );
    if (!ok && rootContext.mounted) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(rootContext).danger,
          content: Text('PIN / Sandi Manajer tidak valid atau ditolak server!'),
        ),
      );
    }
    return ok;
  }


  void _showTransactionActionSheet(BuildContext context, Map<String, dynamic> sale) {
    final voidReasonCtrl = TextEditingController();
    final posCubit = context.read<PosCubit>();
    Map<String, dynamic> activeSale = Map<String, dynamic>.from(sale);
    bool loadingDetail = ((activeSale['items'] as List<dynamic>?) ?? []).isEmpty &&
        ((activeSale['id'] as num?)?.toInt() ?? 0) > 0 &&
        ((activeSale['id'] as num?)?.toInt() ?? 0) < 1000000000;
    bool initializedFetch = false;
    int? selectedReasonCodeId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (!initializedFetch) {
            initializedFetch = true;
            if (loadingDetail) {
              final saleId = (activeSale['id'] as num).toInt();
              Future.microtask(() async {
                final detail = await posCubit.fetchSaleDetail(saleId);
                if (!ctx.mounted) return;
                setModalState(() {
                  loadingDetail = false;
                  if (detail != null) {
                    activeSale = detail;
                  }
                });
              });
            }
            if (posCubit.state.returnReasons.isEmpty) {
              Future.microtask(() async {
                await posCubit.fetchReturnReasons();
                if (ctx.mounted) setModalState(() {});
              });
            }
          }

          final status = (activeSale['status'] ?? 'completed').toString().toLowerCase();
          final isVoided = status == 'voided' || status == 'refunded';
          final items = (activeSale['items'] as List<dynamic>? ?? []);
          final methods = (activeSale['payment_methods'] as List<dynamic>? ?? []);
          final customerName = (activeSale['customer'] is Map
                  ? activeSale['customer']['name']
                  : 'Pelanggan Umum')
              .toString();
          final returnReasons = posCubit.state.returnReasons;

          final tokens = NusaThemeTokens.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Nota ${activeSale['number']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      NusaBadge(
                        label: status == 'voided'
                            ? 'VOID / BATAL'
                            : (status == 'refunded' ? 'RETUR / REFUND' : 'LUNAS'),
                        variant: isVoided ? NusaBadgeVariant.danger : NusaBadgeVariant.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${activeSale['sale_datetime']} • $customerName'
                    '${methods.isNotEmpty ? ' • ${methods.join(', ')}' : ''}',
                    style: TextStyle(fontSize: 12.5, color: tokens.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  if (loadingDetail)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    NusaCard(
                      backgroundColor: tokens.bgElevated,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daftar Item (${items.length})',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tokens.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          ...items.take(6).map((raw) {
                            final it = raw is Map ? raw : <String, dynamic>{};
                            final name = (it['product_name'] ?? it['name'] ?? 'Produk').toString();
                            final qty = (it['quantity'] as num?) ?? 1;
                            final lineTotal = (it['line_total'] as num?) ?? ((it['unit_price'] as num?) ?? 0) * qty;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${IdrCurrencyFormatter.formatQty(qty)}× $name',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tokens.textPrimary),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  NusaPriceTag(amount: lineTotal, fontSize: 12.5),
                                ],
                              ),
                            );
                          }),
                          if (items.length > 6)
                            Text(
                              '+${items.length - 6} item lainnya (lihat di struk)',
                              style: TextStyle(fontSize: 11.5, color: tokens.accent, fontWeight: FontWeight.w700),
                            ),
                          Divider(height: 14, color: tokens.borderSubtle),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total Nota', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: tokens.textPrimary)),
                              NusaPriceTag(amount: activeSale['grand_total'], fontSize: 15, color: tokens.accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  NusaButton(
                    label: 'Buka Struk (Salinan / Reprint)',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () {
                      final reprintSale = _prepareReprintSalePayload(activeSale);
                      Navigator.pop(ctx);
                      context.push('/pos/receipt', extra: reprintSale);
                    },
                  ),
                  const SizedBox(height: 8),
                  NusaButton(
                    label: 'Cetak Ulang Struk (Reprint)',
                    icon: Icons.print_rounded,
                    variant: NusaButtonVariant.outline,
                    onPressed: () {
                      final reprintSale = _prepareReprintSalePayload(activeSale);
                      Navigator.pop(ctx);
                      context.push('/pos/receipt', extra: reprintSale);
                    },
                  ),
                  if (!isVoided) ...[
                    const SizedBox(height: 8),
                    NusaButton(
                      label: 'Tukar Barang (Exchange) 1-Klik',
                      icon: Icons.swap_horiz_rounded,
                      variant: NusaButtonVariant.outline,
                      onPressed: () {
                        if (items.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Item nota belum termuat. Tunggu sebentar atau sinkronkan riwayat.'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        _showExchangeItemSelectorSheet(context, posCubit, activeSale);
                      },
                    ),
                    Divider(height: 24, color: NusaThemeTokens.of(ctx).borderSubtle),
                    Text(
                      'Retur Barang / Pembatalan (Void) Transaksi',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(ctx).danger),
                    ),
                    if (returnReasons.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: returnReasons.map((r) {
                          final rid = (r['id'] as num?)?.toInt();
                          final rName = (r['name'] ?? r['code'] ?? 'Retur').toString();
                          final selected = rid != null && selectedReasonCodeId == rid;
                          return NusaPillFilter(
                            label: rName,
                            selected: selected,
                            onTap: () {
                              setModalState(() {
                                selectedReasonCodeId = rid;
                                voidReasonCtrl.text = rName;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: voidReasonCtrl,
                      decoration: InputDecoration(
                        hintText: 'Wajib isi alasan retur / void (misal: tukar barang / salah input)',
                        prefixIcon: Icon(Icons.warning_amber_rounded, color: NusaThemeTokens.of(ctx).danger),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: NusaButton(
                            label: 'Retur (Refund)',
                            icon: Icons.assignment_return_outlined,
                            variant: NusaButtonVariant.warning,
                            onPressed: () async {
                              final ok = await _promptAndVerifyManagerPin(context, 'refund');
                              if (!ok || !context.mounted) return;
                              final id = (activeSale['id'] as num?)?.toInt() ?? 0;
                              final notes = voidReasonCtrl.text.trim().isEmpty
                                  ? 'Retur Pelanggan'
                                  : voidReasonCtrl.text.trim();
                              await context.read<PosCubit>().refundSaleTransaction(
                                    id,
                                    notes: notes,
                                    reasonCodeId: selectedReasonCodeId,
                                  );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Retur nota ${activeSale['number']} berhasil diproses & stok dikembalikan.')),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NusaButton(
                            label: 'Void Nota',
                            icon: Icons.cancel_outlined,
                            variant: NusaButtonVariant.danger,
                            onPressed: () async {
                              if (voidReasonCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Alasan void wajib diisi!')),
                                );
                                return;
                              }
                              final ok = await _promptAndVerifyManagerPin(context, 'void');
                              if (!ok || !context.mounted) return;
                              final id = (activeSale['id'] as num?)?.toInt() ?? 0;
                              await context.read<PosCubit>().voidSaleTransaction(id, voidReasonCtrl.text.trim());
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Transaksi ${activeSale['number']} berhasil di-Void.')),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  void _showExchangeItemSelectorSheet(
    BuildContext rootContext,
    PosCubit posCubit,
    Map<String, dynamic> activeSale,
  ) {
    final rawItems = (activeSale['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (rawItems.isEmpty) return;

    final selectedQtys = <int, double>{
      for (int i = 0; i < rawItems.length; i++)
        i: ((rawItems[i]['quantity'] as num?)?.toDouble() ?? 1.0).abs(),
    };

    showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(rootContext).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final tokens = NusaThemeTokens.of(ctx);
          double totalCredit = 0.0;
          int selectedCount = 0;
          for (int i = 0; i < rawItems.length; i++) {
            final q = selectedQtys[i] ?? 0.0;
            if (q > 0) {
              selectedCount++;
              final unitPrice = (rawItems[i]['unit_price'] as num?)?.toDouble() ?? 0.0;
              totalCredit += (unitPrice * q);
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            maxChildSize: 0.88,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, color: tokens.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tukar Barang • ${activeSale['number'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pilih item & jumlah yang dikembalikan pelanggan, lalu tambahkan barang pengganti di layar Kasir POS.',
                    style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: rawItems.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: tokens.borderSubtle),
                      itemBuilder: (_, idx) {
                        final item = rawItems[idx];
                        final maxQty = ((item['quantity'] as num?)?.toDouble() ?? 1.0).abs();
                        final currentQty = selectedQtys[idx] ?? 0.0;
                        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                        final checked = currentQty > 0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Checkbox(
                                value: checked,
                                onChanged: (val) {
                                  setModalState(() {
                                    selectedQtys[idx] = (val == true) ? maxQty : 0.0;
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (item['product_name'] ?? 'Produk').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: tokens.textPrimary),
                                    ),
                                    Text(
                                      'Maks ${IdrCurrencyFormatter.formatQty(maxQty)} × ${IdrCurrencyFormatter.format(unitPrice)}',
                                      style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: tokens.bgElevated,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: tokens.borderSubtle),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.remove_rounded, size: 16, color: tokens.textPrimary),
                                      onPressed: currentQty <= 0
                                          ? null
                                          : () {
                                              setModalState(() {
                                                final next = (currentQty - 1).clamp(0.0, maxQty);
                                                selectedQtys[idx] = next;
                                              });
                                            },
                                    ),
                                    Text(
                                      IdrCurrencyFormatter.formatQty(currentQty),
                                      style: AppTheme.moneyStyle(fontSize: 13, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.add_rounded, size: 16, color: tokens.accent),
                                      onPressed: currentQty >= maxQty
                                          ? null
                                          : () {
                                              setModalState(() {
                                                final next = (currentQty + 1).clamp(0.0, maxQty);
                                                selectedQtys[idx] = next;
                                              });
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Kredit Retur ($selectedCount item)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NusaPriceTag(
                          amount: totalCredit,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: tokens.accent,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  NusaButton(
                    label: 'Lanjut ke Kasir POS (Tukar Barang)',
                    trailingIcon: Icons.arrow_forward_rounded,
                    minHeight: 48,
                    onPressed: selectedCount == 0
                        ? null
                        : () {
                            final returnedItems = <Map<String, dynamic>>[];
                            for (int i = 0; i < rawItems.length; i++) {
                              final qty = selectedQtys[i] ?? 0.0;
                              if (qty > 0) {
                                returnedItems.add({
                                  ...rawItems[i],
                                  'return_quantity': qty,
                                });
                              }
                            }
                            posCubit.startItemExchange(
                              originalSale: activeSale,
                              returnedItems: returnedItems,
                            );
                            Navigator.pop(ctx);
                            if (rootContext.mounted) {
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(ctx).accent,
                                  content: Text(
                                    'Mode Tukar Barang nota ${activeSale['number']} aktif — pilih barang pengganti di POS.',
                                  ),
                                ),
                              );
                              rootContext.go('/pos');
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
