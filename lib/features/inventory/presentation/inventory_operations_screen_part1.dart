// ignore_for_file: invalid_use_of_protected_member
part of 'inventory_operations_screen.dart';

extension _InventoryOperationsScreenStatePart1Ext on _InventoryOperationsScreenState {

  Future<void> _loadInventoryOps() async {
    setState(() => _loading = true);
    final localMovements = _offlineDb.getLocalStockMovements(productId: _movementProductFilter);
    final products = context.read<PosCubit>().state.allProducts;
    final localBatches = <Map<String, dynamic>>[];
    for (final p in products) {
      for (final b in p.batches) {
        localBatches.add({
          'product_id': p.id,
          'product_name': p.name,
          'sku': p.sku,
          'batch_number': b.batchNumber,
          'expiry_date': b.expiryDate,
          'quantity': b.quantity,
        });
      }
    }

    if (_isLocalStandalone) {
      setState(() {
        _movements = localMovements;
        _batches = localBatches;
        _loading = false;
      });
      return;
    }

    Future<List<Map<String, dynamic>>?> safeFetchList(String path, [Map<String, dynamic>? query]) async {
      try {
        final res = await _productRepo.fetchInventoryCollection(path, queryParameters: query);
        return (res.data?['data'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        return null;
      }
    }

    try {
      final results = await Future.wait([
        safeFetchList(ApiEndpoints.stockMovements, {
          if (_movementProductFilter != null) 'product_id': _movementProductFilter,
        }),
        safeFetchList(ApiEndpoints.inventoryBatches),
        safeFetchList(ApiEndpoints.stockTransfers),
        safeFetchList(ApiEndpoints.adjustmentReasons),
      ]);

      final movData = results[0];
      final batchData = results[1];
      final transferData = results[2];
      final reasonData = results[3];

      if (!mounted) return;
      setState(() {
        _movements = (movData != null && movData.isNotEmpty) ? movData : localMovements;
        _batches = (batchData != null && batchData.isNotEmpty) ? batchData : localBatches;
        _transfers = transferData ?? _transfers;
        if (reasonData != null && reasonData.isNotEmpty) {
          _adjustmentReasons = reasonData;
          _opnameReason = reasonData.first['name'].toString();
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _movements = localMovements;
        _batches = localBatches;
        _loading = false;
      });
    }
  }


  void _openAddOpnameProductModal(List<ProductModel> allProducts) {
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final filtered = allProducts.where((p) {
            if (p.isServiceOrNonStockItem) return false;
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q.toLowerCase()) ||
                p.sku.toLowerCase().contains(q.toLowerCase());
          }).toList();

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih Produk untuk Opname / Penyesuaian',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setModal(() => q = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama barang atau SKU...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final p = filtered[idx];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Stok Sistem: ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}'),
                          trailing: Icon(Icons.add_circle_outline, color: NusaThemeTokens.of(ctx).accent),
                          onTap: () {
                            Navigator.pop(ctx);
                            _promptOpnameQty(p);
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


  void _promptOpnameQty(ProductModel p) {
    final qtyCtrl = TextEditingController(text: IdrCurrencyFormatter.formatQty(p.stock));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stok Tercatat: ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(ctx).textSecondary)),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stok Fisik Baru'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final physical = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? p.stock;
              Navigator.pop(ctx);
              setState(() {
                _opnameDraftItems.removeWhere((e) => e['product_id'] == p.id);
                _opnameDraftItems.add({
                  'product': p,
                  'product_id': p.id,
                  'product_name': p.name,
                  'sku': p.sku,
                  'unit_code': p.unitCode,
                  'system_qty': p.stock,
                  'physical_qty': physical,
                  'delta': physical - p.stock,
                });
              });
            },
            child: const Text('Tambahkan'),
          ),
        ],
      ),
    );
  }


  Future<void> _submitBatchOpname() async {
    if (_opnameDraftItems.isEmpty) return;
    setState(() => _loading = true);
    final cubit = context.read<PosCubit>();
    bool syncedCloud = false;

    if (!_isLocalStandalone) {
      try {
        await _productRepo.submitStockTake({
          'notes': '$_opnameReason${_opnameNotesCtrl.text.trim().isNotEmpty ? ' • ${_opnameNotesCtrl.text.trim()}' : ''}',
          'post_now': true,
          'counts': _opnameDraftItems.map((e) => {
                'product_id': e['product_id'],
                'counted_qty': e['physical_qty'],
              }).toList(),
        });
        syncedCloud = true;
      } catch (e) {
        if (!ApiClient.isNetworkOfflineError(e)) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: NusaThemeTokens.of(context).danger,
                content: Text(ApiClient.extractErrorMessage(e)),
              ),
            );
          }
          return;
        }
      }
    }

    for (final item in _opnameDraftItems) {
      final ProductModel prod = item['product'] as ProductModel;
      final newQty = (item['physical_qty'] as num).toDouble();
      final delta = newQty - prod.stock;
      if (!syncedCloud) {
        await _offlineDb.updateLocalProductStock(prod.id, newQty);
        await _offlineDb.recordLocalStockMovement(
          productId: prod.id,
          productName: prod.name,
          sku: prod.sku,
          unitCode: prod.unitCode,
          type: 'stock_opname',
          quantityDelta: delta,
          quantityAfter: newQty,
          unitCost: prod.costPrice,
          notes: '$_opnameReason ${_opnameNotesCtrl.text.trim()}'.trim(),
        );
      }
    }

    await cubit.syncWithCloud(force: syncedCloud, preserveActiveCart: true);
    if (!mounted) return;
    setState(() {
      _opnameDraftItems.clear();
      _opnameNotesCtrl.clear();
    });
    await _loadInventoryOps();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(syncedCloud
            ? 'Stock Opname multi-item berhasil disimpan ke Cloud!'
            : 'Stock Opname tersimpan di perangkat.'),
      ),
    );
  }


  Widget _buildStockMonitorTab(List<ProductModel> products) {
    final availableCount = products.where((p) => !p.isServiceOrNonStockItem && p.stock > p.reorderLevel).length;
    final lowCount = products.where((p) => !p.isServiceOrNonStockItem && p.stock >= 0 && p.stock <= p.reorderLevel).length;
    final minusCount = products.where((p) => !p.isServiceOrNonStockItem && p.stock < 0).length;

    final filtered = products.where((p) {
      if (_monitorFilter == 'Tersedia') return !p.isServiceOrNonStockItem && p.stock > p.reorderLevel;
      if (_monitorFilter == 'Menipis') return !p.isServiceOrNonStockItem && p.stock >= 0 && p.stock <= p.reorderLevel;
      if (_monitorFilter == 'Minus') return !p.isServiceOrNonStockItem && p.stock < 0;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              _kpiChip('Tersedia', '$availableCount', NusaThemeTokens.of(context).positive, NusaThemeTokens.of(context).positiveSoft),
              const SizedBox(width: 8),
              _kpiChip('Menipis', '$lowCount', NusaThemeTokens.of(context).warning, NusaThemeTokens.of(context).warningSoft),
              const SizedBox(width: 8),
              _kpiChip('Minus/Oversold', '$minusCount', NusaThemeTokens.of(context).danger, NusaThemeTokens.of(context).dangerSoft),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: ['Semua', 'Tersedia', 'Menipis', 'Minus'].map((f) {
              final active = _monitorFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f),
                  selected: active,
                  onSelected: (_) => setState(() => _monitorFilter = f),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, idx) {
              final p = filtered[idx];
              final isLow = !p.isServiceOrNonStockItem && p.stock <= p.reorderLevel;
              return NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          Text(
                            'SKU: ${p.sku} • Rak: ${(p.shelfLocation ?? '').isNotEmpty ? p.shelfLocation : "-"}',
                            style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        NusaBadge(
                          label: p.isServiceOrNonStockItem
                              ? 'JASA'
                              : '${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                          variant: p.stock < 0
                              ? NusaBadgeVariant.danger
                              : (isLow ? NusaBadgeVariant.warning : NusaBadgeVariant.success),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Min: ${IdrCurrencyFormatter.formatQty(p.reorderLevel)}',
                          style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(context).textSecondary),
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
    );
  }


  Widget _kpiChip(String label, String val, Color fg, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
            Text(val, style: AppTheme.moneyStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
          ],
        ),
      ),
    );
  }


  Widget _buildOpnameTab(List<ProductModel> products) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NusaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alasan Penyesuaian / Opname', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _adjustmentReasons.any((r) => r['name'] == _opnameReason)
                    ? _opnameReason
                    : null,
                items: _adjustmentReasons
                    .map((r) => DropdownMenuItem(
                          value: r['name'].toString(),
                          child: Text(r['name'].toString()),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _opnameReason = v);
                },
                decoration: const InputDecoration(prefixIcon: Icon(Icons.fact_check_outlined)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _opnameNotesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan Tambahan (Opsional)',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 12),
              NusaButton(
                label: 'Tambah Produk ke Daftar Opname',
                variant: NusaButtonVariant.outline,
                icon: Icons.add_box_outlined,
                onPressed: () => _openAddOpnameProductModal(products),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_opnameDraftItems.isEmpty)
          const NusaEmptyState(
            icon: Icons.inventory_outlined,
            title: 'Daftar Opname Kosong',
            subtitle: 'Klik "Tambah Produk" di atas untuk menghitung selisih stok fisik beberapa barang sekaligus.',
          )
        else ...[
          ..._opnameDraftItems.map((item) {
            final delta = (item['delta'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['product_name'].toString(),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            'Sistem: ${IdrCurrencyFormatter.formatQty((item['system_qty'] as num).toDouble())}  ➔  Fisik: ${IdrCurrencyFormatter.formatQty((item['physical_qty'] as num).toDouble())} ${item['unit_code']}',
                            style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(context).textSecondary),
                          ),
                        ],
                      ),
                    ),
                    NusaBadge(
                      label: '${delta >= 0 ? "+" : ""}${IdrCurrencyFormatter.formatQty(delta)}',
                      variant: delta < 0
                          ? NusaBadgeVariant.danger
                          : (delta > 0 ? NusaBadgeVariant.success : NusaBadgeVariant.neutral),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: NusaThemeTokens.of(context).danger),
                      onPressed: () => setState(() => _opnameDraftItems.remove(item)),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          NusaButton(
            label: 'Simpan Semua Penyesuaian (${_opnameDraftItems.length} Produk)',
            variant: NusaButtonVariant.success,
            icon: Icons.check_circle_outline,
            onPressed: _submitBatchOpname,
          ),
        ],
      ],
    );
  }


  Widget _buildMovementsTab(List<ProductModel> products) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<int?>(
            value: _movementProductFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Filter Produk Kartu Stok',
              prefixIcon: Icon(Icons.filter_list_rounded),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Semua Produk')),
              ...products.map((p) => DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) {
              setState(() => _movementProductFilter = v);
              _loadInventoryOps();
            },
          ),
        ),
        Expanded(
          child: _movements.isEmpty
              ? const NusaEmptyState(
                  icon: Icons.history_rounded,
                  title: 'Belum Ada Mutasi Stok',
                  subtitle: 'Setiap transaksi POS, retur, pembelian, dan stock opname akan terekam otomatis di kartu stok.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _movements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final m = _movements[idx];
                    final delta = (m['quantity_delta'] as num?)?.toDouble() ?? 0.0;
                    final isPositive = delta >= 0;
                    return NusaCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: isPositive ? NusaThemeTokens.of(context).positiveSoft : NusaThemeTokens.of(context).dangerSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                              color: isPositive ? NusaThemeTokens.of(context).positive : NusaThemeTokens.of(context).danger,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (m['product_name'] ?? 'Produk').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                Text(
                                  '${m['type'] ?? 'mutasi'} • ${m['notes'] ?? '-'}',
                                  style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                ),
                                Text(
                                  (m['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first,
                                  style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(context).textTertiary),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isPositive ? "+" : ""}${IdrCurrencyFormatter.formatQty(delta)} ${m['unit_code'] ?? 'pcs'}',
                                style: AppTheme.moneyStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isPositive ? NusaThemeTokens.of(context).positive : NusaThemeTokens.of(context).danger,
                                ),
                              ),
                              if (m['quantity_after'] != null)
                                Text(
                                  'Saldo: ${IdrCurrencyFormatter.formatQty((m['quantity_after'] as num).toDouble())}',
                                  style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
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
    );
  }
}
