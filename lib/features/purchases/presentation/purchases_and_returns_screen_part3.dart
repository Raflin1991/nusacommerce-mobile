// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_and_returns_screen.dart';

extension _PurchasesAndReturnsScreenStatePart3Ext on _PurchasesAndReturnsScreenState {

  void _openReceivePurchaseModal(Map<String, dynamic> po) {
    final tokens = NusaThemeTokens.of(context);
    final purchaseId = (po['id'] as num?)?.toInt() ?? 0;
    final poNumber = (po['number'] ?? po['purchase_number'] ?? '-').toString();
    final supplierName = (po['supplier_name'] ?? 'Pemasok').toString();
    final items = (po['items'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).danger,
          content: Text('Rincian barang dalam pesanan pembelian ini tidak ditemukan.'),
        ),
      );
      return;
    }

    final maxReceivableQtys = <int, double>{};
    final receiveQtys = <int, double>{};

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
      final alreadyRec = (it['received_quantity'] as num?)?.toDouble() ?? 0.0;
      final rem = (it['unreceived_quantity'] as num?)?.toDouble() ?? (origQty - alreadyRec).clamp(0.0, double.infinity);
      maxReceivableQtys[i] = rem;
      receiveQtys[i] = rem;
    }

    final suratJalanCtrl = TextEditingController(
      text: (po['delivery_note_number'] ?? po['supplier_invoice_number'] ?? '').toString(),
    );
    final notesCtrl = TextEditingController();
    DateTime receivedDate = DateTime.now();
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final totalReceivingNow = receiveQtys.values.fold<double>(0.0, (sum, q) => sum + q);
          final totalRemainingMax = maxReceivableQtys.values.fold<double>(0.0, (sum, q) => sum + q);
          final isFullReceipt = totalReceivingNow >= totalRemainingMax - 0.0001 && totalRemainingMax > 0.0001;
          final isPartialReceipt = totalReceivingNow > 0.0001 && totalReceivingNow < totalRemainingMax - 0.0001;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: tokens.borderDefault,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: NusaThemeTokens.of(ctx).positiveSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.inventory_rounded, color: NusaThemeTokens.of(ctx).positive, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Penerimaan Barang (GRN)',
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '$poNumber • $supplierName',
                              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Surat Jalan & Tanggal Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.bgPage,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: suratJalanCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nomor Surat Jalan / DO Supplier',
                            hintText: 'Contoh: SJ-202611-0982',
                            prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: receivedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 30)),
                            );
                            if (picked != null) {
                              setModal(() => receivedDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: tokens.bgSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: tokens.borderDefault),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 18, color: NusaThemeTokens.of(ctx).accent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tanggal Diterima Fisik',
                                        style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                                      ),
                                      Text(
                                        '${receivedDate.day.toString().padLeft(2, '0')}-${receivedDate.month.toString().padLeft(2, '0')}-${receivedDate.year}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down, color: NusaThemeTokens.of(ctx).textTertiary),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Catatan Penerimaan (Opsional)',
                            hintText: 'Nama supir, kondisi fisik barang, kardus aman, dsb.',
                            prefixIcon: Icon(Icons.notes_rounded, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Rincian Diterima',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setModal(() {
                          for (int i = 0; i < items.length; i++) {
                            receiveQtys[i] = maxReceivableQtys[i] ?? 0.0;
                          }
                        }),
                        child: const Text('Terima Semua', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setModal(() {
                          for (int i = 0; i < items.length; i++) {
                            receiveQtys[i] = 0.0;
                          }
                        }),
                        child: Text('Reset 0', style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).textSecondary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Items list
                  ...List.generate(items.length, (i) {
                    final it = items[i];
                    final maxQty = maxReceivableQtys[i] ?? 0.0;
                    final curQty = receiveQtys[i] ?? 0.0;
                    final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                    final alreadyRec = (it['received_quantity'] as num?)?.toDouble() ?? 0.0;
                    final isExhausted = maxQty <= 0.0001;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isExhausted ? tokens.bgPage : tokens.bgSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExhausted ? tokens.borderDefault : (curQty > 0 ? NusaThemeTokens.of(ctx).positive.withOpacity(0.5) : tokens.borderDefault),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      it['product_name']?.toString() ?? 'Produk',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: isExhausted ? tokens.textSecondary : null,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'SKU: ${it['sku'] ?? '-'} • Dipesan: ${IdrCurrencyFormatter.formatQty(origQty)}'
                                      '${alreadyRec > 0 ? " • Sudah Diterima: ${IdrCurrencyFormatter.formatQty(alreadyRec)}" : ""}',
                                      style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (isExhausted)
                                const NusaBadge(label: 'Sudah Lengkap', variant: NusaBadgeVariant.success)
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: NusaThemeTokens.of(ctx).warningSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Sisa: ${IdrCurrencyFormatter.formatQty(maxQty)}',
                                    style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(ctx).warning, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                          if (!isExhausted) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Diterima:',
                                    style: TextStyle(fontSize: 12, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  iconSize: 22,
                                  onPressed: curQty > 0
                                      ? () => setModal(() => receiveQtys[i] = (curQty - 1).clamp(0.0, maxQty))
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Container(
                                  width: 44,
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: tokens.bgPage,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: tokens.borderDefault),
                                  ),
                                  child: Text(
                                    IdrCurrencyFormatter.formatQty(curQty),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  iconSize: 22,
                                  onPressed: curQty < maxQty
                                      ? () => setModal(() => receiveQtys[i] = (curQty + 1).clamp(0.0, maxQty))
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                const SizedBox(width: 4),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    minimumSize: const Size(36, 28),
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => setModal(() => receiveQtys[i] = maxQty),
                                  child: const Text('Maks', style: TextStyle(fontSize: 10.5)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Summary Status Badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isFullReceipt ? NusaThemeTokens.of(ctx).positiveSoft : (isPartialReceipt ? NusaThemeTokens.of(ctx).warningSoft : tokens.bgPage),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFullReceipt ? NusaThemeTokens.of(ctx).positive.withOpacity(0.4) : (isPartialReceipt ? NusaThemeTokens.of(ctx).warning.withOpacity(0.4) : tokens.borderDefault),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isFullReceipt
                                    ? 'Penerimaan Lengkap'
                                    : (isPartialReceipt ? 'Penerimaan Sebagian' : 'Pilih kuantitas barang'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isFullReceipt ? NusaThemeTokens.of(ctx).positive : (isPartialReceipt ? NusaThemeTokens.of(ctx).warning : tokens.textSecondary),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isPartialReceipt)
                                Text(
                                  'Sisa barang dapat diterima pada GRN berikutnya',
                                  style: TextStyle(fontSize: 10, color: NusaThemeTokens.of(ctx).warning),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${IdrCurrencyFormatter.formatQty(totalReceivingNow)} unit',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isFullReceipt ? NusaThemeTokens.of(ctx).positive : (isPartialReceipt ? NusaThemeTokens.of(ctx).warning : null),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (modalError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: NusaThemeTokens.of(ctx).dangerSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        modalError!,
                        style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).danger, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  NusaButton(
                    label: isFullReceipt
                        ? 'Konfirmasi Terima Lengkap (GRN)'
                        : (isPartialReceipt ? 'Simpan Penerimaan Sebagian (GRN)' : 'Pilih Jumlah Diterima'),
                    variant: NusaButtonVariant.primary,
                    icon: Icons.inventory_rounded,
                    isLoading: saving,
                    onPressed: (saving || totalReceivingNow <= 0.0001)
                        ? null
                        : () async {
                            setModal(() {
                              saving = true;
                              modalError = null;
                            });

                            final receiveLines = <Map<String, dynamic>>[];
                            for (int i = 0; i < items.length; i++) {
                              final q = receiveQtys[i] ?? 0.0;
                              if (q > 0.0001) {
                                final it = items[i];
                                receiveLines.add({
                                  'id': it['id'],
                                  'purchase_item_id': it['id'] ?? it['purchase_item_id'],
                                  'product_id': it['product_id'],
                                  'quantity': q,
                                });
                              }
                            }

                            final sjNumber = suratJalanCtrl.text.trim();
                            final dateStr = '${receivedDate.year}-${receivedDate.month.toString().padLeft(2, '0')}-${receivedDate.day.toString().padLeft(2, '0')}';
                            final noteStr = notesCtrl.text.trim();

                            try {
                              final isOnline = !_isLocalStandalone && (await _connectivity.checkOnline());
                              bool cloudSuccess = false;

                              if (isOnline && purchaseId > 0 && po['is_local'] != true) {
                                try {
                                  await _repo.receivePurchase(
                                    purchaseId,
                                    {
                                      if (sjNumber.isNotEmpty) 'delivery_note_number': sjNumber,
                                      'received_date': dateStr,
                                      if (noteStr.isNotEmpty) 'notes': noteStr,
                                      'items': receiveLines,
                                    },
                                  );
                                  cloudSuccess = true;
                                } catch (e) {
                                  if (!ApiClient.isNetworkOfflineError(e)) {
                                    final errMsg = ApiClient.extractErrorMessage(e);
                                    setModal(() {
                                      saving = false;
                                      modalError = errMsg;
                                    });
                                    return;
                                  }
                                }
                              }

                              if (!cloudSuccess) {
                                await _offlineDb.receiveLocalPurchase(
                                  purchaseId: purchaseId,
                                  poNumber: poNumber,
                                  deliveryNoteNumber: sjNumber.isNotEmpty ? sjNumber : null,
                                  receivedDate: dateStr,
                                  notes: noteStr.isNotEmpty ? noteStr : null,
                                  items: receiveLines,
                                );
                              }

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              await _loadData();

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: NusaThemeTokens.of(ctx).positive,
                                    content: Text(
                                      isFullReceipt
                                          ? 'Penerimaan fisik barang $poNumber selesai (Lengkap). Stok bertambah!'
                                          : 'Penerimaan sebagian $poNumber (${IdrCurrencyFormatter.formatQty(totalReceivingNow)} unit) berhasil dicatat.',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              setModal(() {
                                saving = false;
                                modalError = e.toString();
                              });
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
