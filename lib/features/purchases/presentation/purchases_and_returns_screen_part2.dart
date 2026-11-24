// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_and_returns_screen.dart';

extension _PurchasesAndReturnsScreenStatePart2Ext on _PurchasesAndReturnsScreenState {

  void _openReturnPurchaseModal(Map<String, dynamic> purchase) {
    final status = (purchase['status'] ?? '').toString().toLowerCase();
    final isDraft = status == 'draft' || status == 'submitted' || status == 'approved';
    if (isDraft) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).danger,
          content: Text('PO ${purchase['number'] ?? '-'} masih berstatus draf/pesanan. Barang belum diterima secara fisik di toko sehingga belum dapat diretur.'),
        ),
      );
      return;
    }

    if (purchase['is_fully_returned'] == true || purchase['is_returnable'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).warning,
          content: Text('Seluruh barang pada PO ${purchase['number'] ?? '-'} sudah habis diretur sebelumnya.'),
        ),
      );
      return;
    }

    final items = (purchase['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rincian barang pada PO ini tidak tersedia untuk diretur.')),
      );
      return;
    }

    final Map<int, double> maxReturnableQtys = {};
    final Map<int, double> returnQtys = {};
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
      final recQty = (it['received_quantity'] as num?)?.toDouble() ?? origQty;
      final retQty = (it['returned_quantity'] as num?)?.toDouble() ?? 0.0;
      final maxRem = (it['returnable_quantity'] as num?)?.toDouble() ?? (recQty - retQty).clamp(0.0, double.infinity);
      maxReturnableQtys[i] = maxRem;
      returnQtys[i] = maxRem > 0 ? maxRem : 0.0;
    }

    if (maxReturnableQtys.values.every((v) => v <= 0.0001)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).warning,
          content: Text('Seluruh barang pada PO ${purchase['number'] ?? '-'} sudah habis diretur sebelumnya.'),
        ),
      );
      return;
    }

    final notesCtrl = TextEditingController(text: 'Barang rusak / tidak sesuai pesanan');
    bool returning = false;
    String? returnModalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
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
              Text('Retur Pembelian: ${purchase['number'] ?? purchase['purchase_number'] ?? '-'}',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...List.generate(items.length, (i) {
                final it = items[i];
                final maxQty = maxReturnableQtys[i] ?? 0.0;
                final curQty = returnQtys[i] ?? 0.0;
                final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                final alreadyRet = (it['returned_quantity'] as num?)?.toDouble() ?? 0.0;
                final isExhausted = maxQty <= 0.0001;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isExhausted ? NusaThemeTokens.of(ctx).bgElevated : NusaThemeTokens.of(ctx).bgSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NusaThemeTokens.of(ctx).borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                it['product_name']?.toString() ?? 'Produk',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isExhausted ? NusaThemeTokens.of(ctx).textTertiary : NusaThemeTokens.of(ctx).textPrimary,
                                ),
                              ),
                            ),
                            if (isExhausted)
                              const NusaBadge(label: 'Habis Diretur', variant: NusaBadgeVariant.neutral)
                            else
                              Text(
                                'Sisa retur: ${IdrCurrencyFormatter.formatQty(maxQty)}',
                                style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).accent, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Dipesan: ${IdrCurrencyFormatter.formatQty(origQty)} • Sudah Diretur: ${IdrCurrencyFormatter.formatQty(alreadyRet)}',
                          style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).textSecondary),
                        ),
                        if (!isExhausted) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: curQty > 0
                                    ? () => setModal(() => returnQtys[i] = (curQty - 1).clamp(0, maxQty))
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(IdrCurrencyFormatter.formatQty(curQty), style: const TextStyle(fontWeight: FontWeight.w700)),
                              IconButton(
                                onPressed: curQty < maxQty
                                    ? () => setModal(() => returnQtys[i] = (curQty + 1).clamp(0, maxQty))
                                    : null,
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Alasan Retur ke Supplier'),
              ),
              if (returnModalError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(ctx).dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: NusaThemeTokens.of(ctx).danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          returnModalError!,
                          style: TextStyle(
                            color: NusaThemeTokens.of(ctx).danger,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setModal(() => returnModalError = null),
                        child: Icon(Icons.close_rounded, color: NusaThemeTokens.of(ctx).danger, size: 16),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              NusaButton(
                label: 'Proses Retur Pembelian',
                isLoading: returning,
                variant: NusaButtonVariant.danger,
                icon: Icons.assignment_return_outlined,
                onPressed: returning
                    ? null
                    : () async {
                        final selectedLines = <Map<String, dynamic>>[];
                        for (int i = 0; i < items.length; i++) {
                          final q = returnQtys[i] ?? 0.0;
                          final maxAllowed = maxReturnableQtys[i] ?? 0.0;
                          if (q > maxAllowed + 0.0001) {
                            setModal(() => returnModalError = 'Jumlah retur untuk ${items[i]['product_name']} ($q unit) melebihi batas sisa yang dapat diretur ($maxAllowed unit).');
                            return;
                          }
                          if (q > 0) {
                            selectedLines.add({
                              ...items[i],
                              'quantity': q,
                            });
                          }
                        }
                        if (selectedLines.isEmpty) {
                          setModal(() => returnModalError = 'Pilih minimal 1 barang dengan jumlah retur > 0.');
                          return;
                        }
                        setModal(() {
                          returning = true;
                          returnModalError = null;
                        });

                        bool cloudOk = false;
                        if (!_isLocalStandalone) {
                          try {
                            await _repo.createPurchaseReturn({
                              'purchase_id': purchase['id'],
                              'notes': notesCtrl.text.trim(),
                              'items': selectedLines,
                            });
                            cloudOk = true;
                          } catch (e) {
                            if (!ApiClient.isNetworkOfflineError(e)) {
                              final errMsg = ApiClient.extractErrorMessage(e);
                              setModal(() {
                                returning = false;
                                returnModalError = errMsg;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: NusaThemeTokens.of(ctx).danger,
                                    content: Text(errMsg),
                                  ),
                                );
                              }
                              return;
                            }
                          }
                        }
                        if (!cloudOk) {
                          await _offlineDb.addLocalPurchaseReturn(
                            purchaseId: (purchase['id'] as num?)?.toInt() ?? 0,
                            purchaseNumber: (purchase['number'] ?? purchase['purchase_number'] ?? '-').toString(),
                            supplierName: (purchase['supplier_name'] ?? 'Pemasok').toString(),
                            items: selectedLines,
                            notes: notesCtrl.text.trim(),
                          );
                        }
                        if (mounted) {
                          await context.read<PosCubit>().syncWithCloud(force: cloudOk, preserveActiveCart: true);
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _loadData();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
