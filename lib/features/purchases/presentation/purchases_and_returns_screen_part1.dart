// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_and_returns_screen.dart';

extension _PurchasesAndReturnsScreenStatePart1Ext on _PurchasesAndReturnsScreenState {

  List<Map<String, dynamic>> _getPaymentMethods() {
    final cached = _offlineDb.getCachedPaymentMethods();
    if (cached.isNotEmpty) return cached;
    try {
      final posMethods = context.read<PosCubit>().state.paymentMethods;
      if (posMethods.isNotEmpty) return posMethods;
    } catch (_) {}
    return [
      {'id': 1, 'name': 'Tunai'},
      {'id': 2, 'name': 'Transfer Bank'},
    ];
  }


  Future<void> _loadData() async {
    setState(() => _loading = true);
    var localPurchases = _offlineDb.getLocalPurchases();
    var localReturns = _offlineDb.getLocalPurchaseReturns();
    List<Map<String, dynamic>> suggestions = context
        .read<PosCubit>()
        .state
        .allProducts
        .where((p) => !p.isServiceOrNonStockItem && p.stock <= p.reorderLevel)
        .map((p) => {
              'product_id': p.id,
              'name': p.name,
              'sku': p.sku,
              'unit_code': p.unitCode,
              'current_stock': p.stock,
              'reorder_level': p.reorderLevel,
              'suggested_qty': ((p.reorderLevel * 2) - p.stock).clamp(5.0, 50.0),
              'cost_price': p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7,
              'supplier_name': null,
            })
        .toList();

    if (!_isLocalStandalone) {
      try {
        final pRes = await _repo.fetchPurchases();
        final rawP = pRes.data['data'] as List<dynamic>?;
        if (rawP != null) {
          localPurchases = rawP.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      try {
        final rRes = await _repo.fetchPurchaseReturns();
        final rawR = rRes.data['data'] as List<dynamic>?;
        if (rawR != null) {
          localReturns = rawR.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      try {
        final aiRes = await _repo.fetchPurchaseAiReorder();
        final rawAi = aiRes.data['data'] as List<dynamic>?;
        if (rawAi != null) {
          suggestions = rawAi.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _purchases = localPurchases;
      _returns = localReturns;
      _reorderSuggestions = suggestions;
      _loading = false;
    });
  }


  void _openCreatePurchaseModal({
    List<Map<String, dynamic>>? initialLines,
    int? initialSupplierId,
  }) {
    final posState = context.read<PosCubit>().state;
    final suppliers = posState.suppliers;
    final products = posState.allProducts.where((p) => !p.isServiceOrNonStockItem).toList();

    Map<String, dynamic>? selectedSupplier = (initialSupplierId != null
            ? suppliers.where((s) => (s['id'] as num?)?.toInt() == initialSupplierId).firstOrNull
            : null) ??
        (suppliers.isNotEmpty ? suppliers.first : null);
    final invoiceCtrl = TextEditingController();
    final paidCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String paymentMode = 'paid'; // paid, partial, credit
    final List<Map<String, dynamic>> lines = initialLines != null
        ? initialLines.map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
    bool saving = false;
    String? modalError;

    double computeTotal() =>
        lines.fold(0.0, (s, e) => s + ((e['quantity'] as num).toDouble() * (e['unit_cost'] as num).toDouble()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final total = computeTotal();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.88,
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
                      const Text('Buat Pembelian Stok (PO)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (suppliers.isEmpty)
                          NusaCard(
                            backgroundColor: NusaThemeTokens.of(ctx).warningSoft,
                            child: Text(
                              'Belum ada data Pemasok. Anda tetap bisa mencatat stok dengan pemasok umum atau tambahkan pemasok terlebih dahulu.',
                              style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).warning),
                            ),
                          )
                        else
                          DropdownButtonFormField<int>(
                            value: (selectedSupplier?['id'] as num?)?.toInt(),
                            decoration: const InputDecoration(
                              labelText: 'Pilih Pemasok / Supplier',
                              prefixIcon: Icon(Icons.local_shipping_outlined),
                            ),
                            items: suppliers
                                .map((s) => DropdownMenuItem<int>(
                                      value: (s['id'] as num).toInt(),
                                      child: Text(s['name'].toString()),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setModal(() {
                                selectedSupplier = suppliers.where((s) => (s['id'] as num).toInt() == v).firstOrNull;
                              });
                            },
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: invoiceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'No. Faktur Supplier (Opsional)',
                            prefixIcon: Icon(Icons.receipt_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickProductForPurchase(ctx, products, (line) {
                                  setModal(() {
                                    lines.removeWhere((e) => e['product_id'] == line['product_id']);
                                    lines.add(line);
                                  });
                                }),
                                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                label: const Text('Tambah Barang'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!_isLocalStandalone && _reorderSuggestions.isEmpty) {
                                  try {
                                    final aiRes = await _repo.fetchPurchaseAiReorder();
                                    final rawAi = aiRes.data['data'] as List<dynamic>?;
                                    if (rawAi != null && mounted) {
                                      _reorderSuggestions =
                                          rawAi.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                                    }
                                  } catch (_) {}
                                }
                                setModal(() {
                                  if (_reorderSuggestions.isNotEmpty) {
                                    for (final s in _reorderSuggestions.take(15)) {
                                      final pid = (s['product_id'] as num).toInt();
                                      lines.removeWhere((e) => e['product_id'] == pid);
                                      lines.add({
                                        'product_id': pid,
                                        'product_name': (s['name'] ?? 'Produk').toString(),
                                        'sku': (s['sku'] ?? '-').toString(),
                                        'unit_code': (s['unit_code'] ?? 'pcs').toString(),
                                        'quantity': (s['suggested_qty'] as num?)?.toDouble() ?? 10.0,
                                        'unit_cost': (s['cost_price'] as num?)?.toDouble() ?? 0.0,
                                      });
                                    }
                                  } else {
                                    final lowItems = products
                                        .where((p) => p.stock <= p.reorderLevel)
                                        .take(10)
                                        .toList();
                                    for (final p in lowItems) {
                                      final qty = ((p.reorderLevel * 2) - p.stock).clamp(5.0, 50.0);
                                      lines.removeWhere((e) => e['product_id'] == p.id);
                                      lines.add({
                                        'product_id': p.id,
                                        'product_name': p.name,
                                        'sku': p.sku,
                                        'unit_code': p.unitCode,
                                        'quantity': qty,
                                        'unit_cost': p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7,
                                      });
                                    }
                                  }
                                });
                              },
                              icon: Icon(Icons.auto_awesome_rounded, size: 18, color: NusaThemeTokens.of(ctx).accent),
                              label: const Text('Saran AI'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (lines.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text('Belum ada item barang dipilih.',
                                  style: TextStyle(color: NusaThemeTokens.of(ctx).textSecondary)),
                            ),
                          )
                        else
                          ...lines.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: NusaCard(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['product_name'].toString(),
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                            Text(
                                              '${IdrCurrencyFormatter.formatQty((item['quantity'] as num).toDouble())} ${item['unit_code']} x ${IdrCurrencyFormatter.format((item['unit_cost'] as num).toDouble())}',
                                              style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        IdrCurrencyFormatter.format(
                                            (item['quantity'] as num) * (item['unit_cost'] as num)),
                                        style: AppTheme.moneyStyle(fontSize: 13.5),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.close, color: NusaThemeTokens.of(ctx).danger, size: 18),
                                        onPressed: () => setModal(() => lines.remove(item)),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                        const SizedBox(height: 10),
                        const Text('Metode Pembayaran Pembelian',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'paid', label: Text('Lunas')),
                            ButtonSegment(value: 'partial', label: Text('DP Sebagian')),
                            ButtonSegment(value: 'credit', label: Text('Hutang Tempo')),
                          ],
                          selected: {paymentMode},
                          onSelectionChanged: (s) => setModal(() => paymentMode = s.first),
                        ),
                        if (paymentMode == 'partial') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: paidCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Nominal DP Dibayar (Rp)'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(labelText: 'Catatan Pembelian'),
                        ),
                      ],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Pembelian', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        IdrCurrencyFormatter.format(total),
                        style: AppTheme.moneyStyle(fontSize: 18, color: NusaThemeTokens.of(ctx).accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  NusaButton(
                    label: 'Simpan & Terima Stok',
                    isLoading: saving,
                    variant: NusaButtonVariant.success,
                    icon: Icons.check_circle_rounded,
                    onPressed: (saving || lines.isEmpty)
                        ? null
                        : () async {
                            setModal(() {
                              saving = true;
                              modalError = null;
                            });
                            final paid = paymentMode == 'paid'
                                ? total
                                : (paymentMode == 'partial'
                                    ? IdrCurrencyFormatter.parse(paidCtrl.text)
                                    : 0.0);
                            final supId = (selectedSupplier?['id'] as num?)?.toInt() ?? 0;
                            final supName = (selectedSupplier?['name'] ?? 'Pemasok Umum').toString();

                            bool cloudOk = false;
                            if (!_isLocalStandalone) {
                              try {
                                await _repo.createPurchase({
                                  if (supId > 0) 'supplier_id': supId,
                                  'supplier_name': supName,
                                  'supplier_invoice_number': invoiceCtrl.text.trim(),
                                  'payment_mode': paymentMode,
                                  'paid_amount': paid,
                                  'notes': notesCtrl.text.trim(),
                                  'items': lines,
                                });
                                cloudOk = true;
                              } catch (e) {
                                if (!ApiClient.isNetworkOfflineError(e)) {
                                  final errMsg = ApiClient.extractErrorMessage(e);
                                  setModal(() {
                                    saving = false;
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
                                  return;
                                }
                              }
                            }
                            if (!cloudOk) {
                              await _offlineDb.addLocalPurchase(
                                supplierId: supId,
                                supplierName: supName,
                                supplierPhone: selectedSupplier?['phone']?.toString(),
                                invoiceNumber: invoiceCtrl.text.trim(),
                                items: lines,
                                paymentMode: paymentMode,
                                paidAmount: paid,
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
          );
        },
      ),
    );
  }


  void _pickProductForPurchase(
    BuildContext parentCtx,
    List<ProductModel> products,
    void Function(Map<String, dynamic> line) onAdd,
  ) {
    String q = '';
    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final filtered = products.where((p) {
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q.toLowerCase()) ||
                p.sku.toLowerCase().contains(q.toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Pilih Barang Dibeli'),
            content: SizedBox(
              width: 340,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setDlg(() => q = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari barang...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, idx) {
                        final p = filtered[idx];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text('HPP: ${IdrCurrencyFormatter.format(p.costPrice)} • Stok: ${IdrCurrencyFormatter.formatQty(p.stock)}'),
                          onTap: () {
                            Navigator.pop(ctx);
                            final qtyCtrl = TextEditingController(text: '10');
                            final costCtrl = TextEditingController(
                              text: (p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7).toInt().toString(),
                            );
                            final batchCtrl = TextEditingController();
                            showDialog(
                              context: parentCtx,
                              builder: (qCtx) => AlertDialog(
                                title: Text(p.name),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: qtyCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(labelText: 'Jumlah Beli (${p.unitCode})'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: costCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Harga Beli Satuan (Rp)'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: batchCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Nomor Batch / Lot (Opsional)',
                                        hintText: 'Kosongkan untuk auto-batch',
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(qCtx), child: const Text('Batal')),
                                  FilledButton(
                                    onPressed: () {
                                      final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                                      final cost = IdrCurrencyFormatter.parse(costCtrl.text);
                                      final batchNum = batchCtrl.text.trim();
                                      onAdd({
                                        'product_id': p.id,
                                        'product_name': p.name,
                                        'sku': p.sku,
                                        'unit_code': p.unitCode,
                                        'quantity': qty,
                                        'unit_cost': cost,
                                        if (batchNum.isNotEmpty) 'batch_number': batchNum,
                                      });
                                      Navigator.pop(qCtx);
                                    },
                                    child: const Text('Tambahkan'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
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
