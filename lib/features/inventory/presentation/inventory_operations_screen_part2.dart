// ignore_for_file: invalid_use_of_protected_member
part of 'inventory_operations_screen.dart';

extension _InventoryOperationsScreenStatePart2Ext on _InventoryOperationsScreenState {

  Widget _buildFefoAndTransferTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Batch & Kedaluwarsa (FEFO)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_batches.isEmpty)
          NusaCard(
            child: Text(
              'Belum ada data batch tanggal kedaluwarsa. Batch akan muncul dari stok masuk pembelian atau data apotek/F&B.',
              style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(context).textSecondary),
            ),
          )
        else
          ..._batches.take(25).map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NusaCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((b['product_name'] ?? 'Produk').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              'Batch: ${b['batch_number'] ?? '-'} • Exp: ${(b['expiry_date'] ?? '-').toString().split('T').first}',
                              style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                            ),
                          ],
                        ),
                      ),
                      NusaBadge(
                        label: IdrCurrencyFormatter.formatQty((b['quantity'] as num?)?.toDouble() ?? 0),
                        variant: NusaBadgeVariant.warning,
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Transfer Stok Antar Cabang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            if (!_isLocalStandalone)
              FilledButton.icon(
                onPressed: _openCreateTransferModal,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Kirim Transfer'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_transfers.isEmpty)
          NusaCard(
            child: Text(
              _isLocalStandalone
                  ? 'Transfer antar cabang tersedia saat beralih ke OXORA Cloud Multi-Cabang.'
                  : 'Belum ada dokumen transfer antar gudang/cabang.',
              style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(context).textSecondary),
            ),
          )
        else
          ..._transfers.map((t) {
            final id = (t['id'] as num?)?.toInt() ?? 0;
            final status = (t['status'] ?? 'pending').toString();
            final activeStoreId = context.read<AuthCubit>().state.session.activeStore.id;
            final toStoreId = (t['to_store_id'] as num?)?.toInt() ?? 0;
            final canReceive = (status == 'in_transit' || status == 'pending') &&
                (toStoreId == 0 || toStoreId == activeStoreId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (t['number'] ?? t['transfer_number'] ?? 'TRF-$id').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${t['from_store_name'] ?? t['from_warehouse'] ?? 'Asal'} ➔ ${t['to_store_name'] ?? t['to_warehouse'] ?? 'Tujuan'}',
                            style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(context).textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (canReceive)
                      FilledButton(
                        onPressed: () async {
                          try {
                            await _productRepo.receiveStockTransfer(id);
                            if (mounted) {
                              await context.read<PosCubit>().syncWithCloud(force: true, preserveActiveCart: true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(context).positive,
                                  content: Text('Transfer stok berhasil diterima di cabang ini.'),
                                ),
                              );
                            }
                            await _loadInventoryOps();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(context).danger,
                                  content: Text(ApiClient.extractErrorMessage(e)),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Terima'),
                      )
                    else
                      NusaBadge(
                        label: status.toUpperCase(),
                        variant: status == 'received' ? NusaBadgeVariant.success : NusaBadgeVariant.warning,
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }


  void _openCreateTransferModal() {
    final session = context.read<AuthCubit>().state.session;
    final destStores = session.availableStores
        .where((s) => s.id != session.activeStore.id)
        .toList();
    if (destStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cabang tujuan transfer belum tersedia (akun Anda hanya terhubung ke 1 cabang).'),
        ),
      );
      return;
    }

    final products = context
        .read<PosCubit>()
        .state
        .allProducts
        .where((p) => !p.isServiceOrNonStockItem)
        .toList();
    if (products.isEmpty) return;

    int toStoreId = destStores.first.id;
    ProductModel selectedProduct = products.first;
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    final List<Map<String, dynamic>> lines = [];
    bool submitting = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Kirim Transfer Stok Cabang',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  'Asal: ${session.activeStore.name}',
                  style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: toStoreId,
                  decoration: const InputDecoration(labelText: 'Cabang Tujuan *'),
                  items: destStores
                      .map((s) => DropdownMenuItem<int>(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModal(() => toStoreId = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        value: selectedProduct.id,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Pilih Produk'),
                        items: products
                            .take(100)
                            .map((p) => DropdownMenuItem<int>(
                                  value: p.id,
                                  child: Text('${p.name} (Stok: ${IdrCurrencyFormatter.formatQty(p.stock)})'),
                                ))
                            .toList(),
                        onChanged: (pid) {
                          final match = products.where((p) => p.id == pid).firstOrNull;
                          if (match != null) setModal(() => selectedProduct = match);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () {
                        final q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                        if (q <= 0) return;
                        setModal(() {
                          lines.removeWhere((l) => l['product_id'] == selectedProduct.id);
                          lines.add({
                            'product_id': selectedProduct.id,
                            'product_name': selectedProduct.name,
                            'unit_code': selectedProduct.unitCode,
                            'quantity': q,
                          });
                        });
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan Pengiriman (Opsional)'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: lines.isEmpty
                      ? Center(
                          child: Text(
                            'Tambahkan barang yang akan dikirim ke cabang tujuan.',
                            style: TextStyle(color: NusaThemeTokens.of(ctx).textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: lines.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final line = lines[idx];
                            return NusaCard(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      line['product_name'].toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    '${IdrCurrencyFormatter.formatQty((line['quantity'] as num).toDouble())} ${line['unit_code']}',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close, color: NusaThemeTokens.of(ctx).danger, size: 18),
                                    onPressed: () => setModal(() => lines.removeAt(idx)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                if (modalError != null) ...[
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
                            modalError!,
                            style: TextStyle(
                              color: NusaThemeTokens.of(ctx).danger,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setModal(() => modalError = null),
                          child: Icon(Icons.close_rounded, color: NusaThemeTokens.of(ctx).danger, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                NusaButton(
                  label: 'Kirim Transfer Stok Sekarang',
                  isLoading: submitting,
                  icon: Icons.send_rounded,
                  onPressed: (submitting || lines.isEmpty)
                      ? null
                      : () async {
                          setModal(() {
                            submitting = true;
                            modalError = null;
                          });
                          try {
                            await _productRepo.submitStockTransfer({
                              'to_store_id': toStoreId,
                              'notes': notesCtrl.text.trim(),
                              'dispatch_now': true,
                              'items': lines
                                  .map((l) => {
                                        'product_id': l['product_id'],
                                        'quantity': l['quantity'],
                                      })
                                  .toList(),
                            });
                            if (mounted) {
                              await context.read<PosCubit>().syncWithCloud(force: true, preserveActiveCart: true);
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadInventoryOps();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(ctx).positive,
                                  content: Text('Transfer stok antar cabang berhasil dikirim!'),
                                ),
                              );
                            }
                          } catch (e) {
                            final errMsg = ApiClient.extractErrorMessage(e);
                            setModal(() {
                              submitting = false;
                              modalError = errMsg;
                            });
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(ctx).danger,
                                  content: Text(errMsg),
                                ),
                              );
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
