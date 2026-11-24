// ignore_for_file: invalid_use_of_protected_member
part of 'products_inventory_screen.dart';

extension _ProductsInventoryScreenStatePart1Ext on _ProductsInventoryScreenState {

  void _showAddOrEditProductModal(BuildContext context, {ProductModel? existing}) {
    final posState = context.read<PosCubit>().state;
    final activeStoreName = context.read<AuthCubit>().state.session.activeStore.name;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? 'PRD-${DateTime.now().millisecond}');
    final barcodeCtrl = TextEditingController(text: existing?.barcode ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.sellingPrice.toInt().toString() : '',
    );
    final costCtrl = TextEditingController(
      text: existing != null ? existing.costPrice.toInt().toString() : '',
    );
    final stockCtrl = TextEditingController(
      text: existing != null ? IdrCurrencyFormatter.formatQty(existing.stock) : '25',
    );
    final shelfCtrl = TextEditingController(text: existing?.shelfLocation ?? 'Rak Utama');
    final reorderCtrl = TextEditingController(
      text: IdrCurrencyFormatter.formatQty(existing?.reorderLevel ?? 5),
    );

    final selectableCats = posState.categories.where((c) => (c['id'] as num?)?.toInt() != 0).toList();
    int? selectedCatId = existing?.categoryId ??
        (selectableCats.isNotEmpty ? (selectableCats.first['id'] as num?)?.toInt() : null);
    final bool isRestaurantMode = posState.currentVertical == BusinessVertical.restaurant;
    bool isRawMaterialCatName(String? name) {
      final clean = (name ?? '').trim().toLowerCase();
      if (clean.isEmpty) return false;
      return RegExp(r'\b(bahan(\s+(baku|dapur|mentah|masakan|tambahan))?|bumbu|ingredient|ingredients|raw\s*materials?|kemasan|packaging)\b')
          .hasMatch(clean);
    }

    int? selectedBrandId = existing?.brandId;
    int? selectedUnitId = existing?.unitId;
    String selectedType = existing?.type ?? 'physical';
    final initialCatName = selectableCats
        .where((c) => (c['id'] as num?)?.toInt() == selectedCatId)
        .firstOrNull?['name']
        ?.toString();
    bool canBeSold = existing != null
        ? existing.canBeSold
        : !(isRestaurantMode && isRawMaterialCatName(initialCatName));
    bool canBeSoldOverridden = existing != null;
    bool isSaving = false;
    String? saveError;

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        existing == null ? 'Tambah Barang Baru' : 'Detail & Stock Opname — ${existing.name}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (existing != null)
                      IconButton(
                        tooltip: 'Hapus Produk',
                        icon: Icon(Icons.delete_outline_rounded, color: NusaThemeTokens.of(ctx).danger),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (dCtx) => AlertDialog(
                              title: const Text('Hapus Produk?'),
                              content: Text('Yakin ingin menghapus "${existing.name}" dari katalog?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('Batal')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: NusaThemeTokens.of(dCtx).danger),
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  child: const Text('Hapus'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && ctx.mounted) {
                            await context.read<PosCubit>().deleteProduct(existing.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                      ),
                  ],
                ),
                if (existing != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NusaThemeTokens.of(ctx).accentSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📍 Lokasi Rak: ${existing.shelfLocation ?? 'Rak Utama'}',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: NusaThemeTokens.of(ctx).accent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '🏢 Stok $activeStoreName: ${IdrCurrencyFormatter.formatQty(existing.stock, unitCode: existing.unitCode)}',
                          style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).textPrimary),
                        ),
                        if (existing.fefoBatch != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⏳ Batch FEFO Aktif: ${existing.fefoBatch!.batchNumber} (Exp: ${existing.fefoBatch!.expiryDate ?? '-'})',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(ctx).warning),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Barang *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: selectableCats.any((c) => (c['id'] as num?)?.toInt() == selectedCatId)
                            ? selectedCatId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Kategori Produk',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: selectableCats
                            .map(
                              (c) => DropdownMenuItem<int>(
                                value: (c['id'] as num).toInt(),
                                child: Text(c['name'].toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setModalState(() {
                          selectedCatId = v;
                          if (existing == null && isRestaurantMode && !canBeSoldOverridden) {
                            final pickedName = selectableCats
                                .where((c) => (c['id'] as num?)?.toInt() == v)
                                .firstOrNull?['name']
                                ?.toString();
                            canBeSold = selectedType == 'kit' || !isRawMaterialCatName(pickedName);
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton(
                        onPressed: () {
                          final catCtrl = TextEditingController();
                          showDialog(
                            context: ctx,
                            builder: (cCtx) => AlertDialog(
                              title: const Text('Tambah Kategori Baru'),
                              content: TextField(
                                controller: catCtrl,
                                autofocus: true,
                                decoration: const InputDecoration(labelText: 'Nama Kategori'),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(cCtx), child: const Text('Batal')),
                                FilledButton(
                                  onPressed: () async {
                                    final nm = catCtrl.text.trim();
                                    if (nm.isEmpty) return;
                                    final res = await context.read<PosCubit>().saveCategory({'name': nm});
                                    if (cCtx.mounted) Navigator.pop(cCtx);
                                    if (res['success'] == true && res['data'] is Map) {
                                      setModalState(() {
                                        final newCat = Map<String, dynamic>.from(res['data'] as Map);
                                        selectableCats.add(newCat);
                                        selectedCatId = (newCat['id'] as num?)?.toInt();
                                      });
                                    }
                                  },
                                  child: const Text('Simpan'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('+ Kategori'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: posState.brands.any((b) => (b['id'] as num?)?.toInt() == selectedBrandId)
                            ? selectedBrandId
                            : null,
                        decoration: const InputDecoration(labelText: 'Merek (Opsional)'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Tanpa Merek')),
                          ...posState.brands.map((b) => DropdownMenuItem<int?>(
                                value: (b['id'] as num).toInt(),
                                child: Text(b['name'].toString()),
                              )),
                        ],
                        onChanged: (v) => setModalState(() => selectedBrandId = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: posState.units.any((u) => (u['id'] as num?)?.toInt() == selectedUnitId)
                            ? selectedUnitId
                            : null,
                        decoration: const InputDecoration(labelText: 'Satuan'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('Pcs / Default')),
                          ...posState.units.map((u) => DropdownMenuItem<int?>(
                                value: (u['id'] as num).toInt(),
                                child: Text('${u['name']} (${u['symbol'] ?? 'pcs'})'),
                              )),
                        ],
                        onChanged: (v) => setModalState(() => selectedUnitId = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedType == 'service' ? 'service' : 'physical',
                        decoration: const InputDecoration(labelText: 'Tipe Item'),
                        items: const [
                          DropdownMenuItem(value: 'physical', child: Text('Barang Fisik (Stok)')),
                          DropdownMenuItem(value: 'service', child: Text('Jasa / Non-Stok')),
                        ],
                        onChanged: (v) {
                          if (v != null) setModalState(() => selectedType = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: reorderCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Min. Stok Alert'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Dapat Dijual (POS & Toko Online)',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Matikan untuk bahan baku dapur agar tidak muncul di kasir POS maupun etalase online.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  value: canBeSold,
                  onChanged: (val) => setModalState(() {
                    canBeSold = val;
                    canBeSoldOverridden = true;
                  }),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: skuCtrl,
                        decoration: const InputDecoration(labelText: 'Kode SKU'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: barcodeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Barcode (EAN/SKU)',
                          suffixIcon: IconButton(
                            icon: Icon(Icons.qr_code_scanner_rounded, color: NusaThemeTokens.of(ctx).accent),
                            onPressed: () {
                              bool scanned = false;
                              showDialog(
                                context: ctx,
                                builder: (sCtx) => AlertDialog(
                                  title: const Text('Scan Barcode Produk'),
                                  content: SizedBox(
                                    height: 220,
                                    width: 280,
                                    child: NusaBarcodeScannerView(
                                      onDetect: (code) {
                                        if (scanned) return;
                                        scanned = true;
                                        barcodeCtrl.text = code;
                                        Navigator.pop(sCtx);
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: costCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Harga Modal (HPP)',
                          prefixIcon: Icon(Icons.request_quote_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setModalState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Harga Jual (Rp) *',
                          prefixIcon: Icon(Icons.sell_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                Builder(builder: (_) {
                  final modalCost = IdrCurrencyFormatter.parse(costCtrl.text);
                  final sellPrice = IdrCurrencyFormatter.parse(priceCtrl.text);
                  if (sellPrice <= 0) return const SizedBox.shrink();
                  final profit = sellPrice - modalCost;
                  final marginPct = sellPrice > 0 ? (profit / sellPrice) * 100 : 0.0;
                  final isNegative = profit < 0;
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NusaCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      backgroundColor: isNegative ? NusaThemeTokens.of(ctx).dangerSoft : NusaThemeTokens.of(ctx).positiveSoft,
                      borderColor: (isNegative ? NusaThemeTokens.of(ctx).danger : NusaThemeTokens.of(ctx).positive).withOpacity(0.3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isNegative ? 'Rugi per unit:' : 'Estimasi Laba / Margin:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isNegative ? NusaThemeTokens.of(ctx).danger : NusaThemeTokens.of(ctx).positive,
                            ),
                          ),
                          Text(
                            '${IdrCurrencyFormatter.format(profit)} (${marginPct.toStringAsFixed(1)}%)',
                            style: AppTheme.moneyStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isNegative ? NusaThemeTokens.of(ctx).danger : NusaThemeTokens.of(ctx).positive,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stockCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: existing == null ? 'Stok Awal' : 'Stok Fisik (Opname)',
                          prefixIcon: const Icon(Icons.numbers_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: shelfCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Lokasi Rak / Gudang',
                          prefixIcon: Icon(Icons.shelves),
                        ),
                      ),
                    ),
                  ],
                ),
                if (saveError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NusaThemeTokens.of(ctx).danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NusaThemeTokens.of(ctx).danger.withOpacity(0.4)),
                    ),
                    child: Text(
                      saveError!,
                      style: TextStyle(color: NusaThemeTokens.of(ctx).danger, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                NusaButton(
                  icon: Icons.save_rounded,
                  isLoading: isSaving,
                  label: existing == null ? 'Simpan Barang Baru' : 'Simpan Hasil Stock Opname',
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          final price = IdrCurrencyFormatter.parse(priceCtrl.text);
                          final cost = IdrCurrencyFormatter.parse(costCtrl.text);
                          final stock = double.tryParse(stockCtrl.text.replaceAll(',', '.')) ?? 0.0;
                          final catName = selectableCats
                                  .where((c) => (c['id'] as num?)?.toInt() == selectedCatId)
                                  .firstOrNull?['name']
                                  ?.toString() ??
                              existing?.categoryName ??
                              'Umum';

                          final reorderLvl = double.tryParse(reorderCtrl.text.replaceAll(',', '.')) ?? 5.0;
                          final matchedUnit = posState.units
                              .where((u) => (u['id'] as num?)?.toInt() == selectedUnitId)
                              .firstOrNull;
                          final matchedBrand = posState.brands
                              .where((b) => (b['id'] as num?)?.toInt() == selectedBrandId)
                              .firstOrNull;

                          final isCreatingNew = existing == null;
                          final updated = ProductModel(
                            id: existing?.id ?? -DateTime.now().millisecondsSinceEpoch,
                            name: name,
                            sku: skuCtrl.text.trim(),
                            barcode: barcodeCtrl.text.trim().isNotEmpty
                                ? barcodeCtrl.text.trim()
                                : (existing?.barcode ?? ''),
                            sellingPrice: price > 0 ? price : (existing?.sellingPrice ?? 0),
                            costPrice: cost > 0 ? cost : (existing?.costPrice ?? 0),
                            stock: stock,
                            unitId: selectedUnitId ?? existing?.unitId,
                            unitCode: (matchedUnit?['symbol'] ?? existing?.unitCode ?? 'pcs').toString(),
                            categoryId: selectedCatId ?? existing?.categoryId ?? 0,
                            categoryName: catName,
                            brandId: selectedBrandId ?? existing?.brandId,
                            brandName: matchedBrand?['name']?.toString() ?? existing?.brandName,
                            reorderLevel: reorderLvl,
                            trackStock: selectedType != 'service',
                            canBeSold: canBeSold,
                            isVisibleOnline: canBeSold,
                            type: selectedType == 'service' ? 'service' : 'simple',
                            isLowStock: selectedType != 'service' && stock <= reorderLvl,
                            shelfLocation: shelfCtrl.text.trim(),
                            iconType: existing?.iconType ?? 'default',
                            imageUrl: existing?.imageUrl,
                            variants: existing?.variants ?? const [],
                            batches: existing?.batches ?? const [],
                            isLocalOnly: existing?.isLocalOnly ?? isCreatingNew,
                            localUuid: existing?.localUuid,
                          );

                          setModalState(() {
                            isSaving = true;
                            saveError = null;
                          });
                          final result = await context
                              .read<PosCubit>()
                              .saveProductInventory(updated, isNew: existing == null);
                          if (!ctx.mounted) return;
                          if (!result.ok) {
                            setModalState(() {
                              isSaving = false;
                              saveError = result.errorMessage ?? 'Gagal menyimpan barang ke server Cloud.';
                            });
                            return;
                          }
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: result.syncedToCloud ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).warning,
                              content: Text(
                                result.syncedToCloud
                                    ? 'Data barang "${updated.name}" tersimpan & sinkron ke Cloud.'
                                    : 'Barang "${updated.name}" disimpan offline & akan disinkronkan saat online.',
                              ),
                            ),
                          );
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
