// ignore_for_file: invalid_use_of_protected_member
part of 'products_inventory_screen.dart';

extension _ProductsInventoryScreenStatePart2Ext on _ProductsInventoryScreenState {

  void _showInstantCameraOpnameModal(BuildContext context, List<ProductModel> allProducts) {
    ProductModel? scannedProduct;
    final physicalCtrl = TextEditingController();
    final manualCodeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void resolveCode(String code) {
            final q = code.trim().toLowerCase();
            final found = allProducts.where(
              (p) => p.barcode.toLowerCase() == q || p.sku.toLowerCase() == q || p.name.toLowerCase().contains(q),
            );
            if (found.isNotEmpty) {
              setModalState(() {
                scannedProduct = found.first;
                physicalCtrl.text = IdrCurrencyFormatter.formatQty(found.first.stock);
              });
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(backgroundColor: NusaThemeTokens.of(ctx).danger, content: Text('Produk "$code" tidak ditemukan.')),
              );
            }
          }

          final actualQty = double.tryParse(physicalCtrl.text.replaceAll(',', '.').trim()) ?? 0.0;
          final systemQty = scannedProduct?.stock ?? 0.0;
          final variance = actualQty - systemQty;

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
                      const Text(
                        'Stock Opname Kamera Instan',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      if (scannedProduct != null)
                        TextButton(
                          onPressed: () => setModalState(() => scannedProduct = null),
                          child: const Text('Scan Ulang'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (scannedProduct == null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: NusaBarcodeScannerView(
                          stopOnFirstDetection: false,
                          onDetect: (raw) {
                            if (scannedProduct != null) return;
                            resolveCode(raw);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: manualCodeCtrl,
                            decoration: const InputDecoration(hintText: 'Ketik Barcode / SKU / Nama...'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => resolveCode(manualCodeCtrl.text),
                          child: const Text('Cari'),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: NusaThemeTokens.of(ctx).accentSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scannedProduct!.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'SKU: ${scannedProduct!.sku} • Rak: ${scannedProduct!.shelfLocation ?? '-'}',
                            style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Stok Sistem Tercatat: ${IdrCurrencyFormatter.formatQty(systemQty, unitCode: scannedProduct!.unitCode)}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: NusaThemeTokens.of(ctx).accent),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: physicalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Jumlah Fisik Aktual di Rak (${scannedProduct!.unitCode})',
                        prefixIcon: const Icon(Icons.fact_check_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: variance == 0
                            ? NusaThemeTokens.of(ctx).positiveSoft
                            : (variance > 0 ? NusaThemeTokens.of(ctx).accentSoft : NusaThemeTokens.of(ctx).dangerSoft),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Selisih Opname (Variance): ${variance > 0 ? '+' : ''}${IdrCurrencyFormatter.formatQty(variance, unitCode: scannedProduct!.unitCode)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: variance == 0
                              ? NusaThemeTokens.of(ctx).positive
                              : (variance > 0 ? NusaThemeTokens.of(ctx).accent : NusaThemeTokens.of(ctx).danger),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final updated = ProductModel(
                            id: scannedProduct!.id,
                            name: scannedProduct!.name,
                            sku: scannedProduct!.sku,
                            barcode: scannedProduct!.barcode,
                            type: scannedProduct!.type,
                            sellingPrice: scannedProduct!.sellingPrice,
                            costPrice: scannedProduct!.costPrice,
                            stock: actualQty,
                            unitCode: scannedProduct!.unitCode,
                            categoryId: scannedProduct!.categoryId,
                            categoryName: scannedProduct!.categoryName,
                            isLowStock: actualQty <= 5,
                            soldByWeight: scannedProduct!.soldByWeight,
                            scalePlu: scannedProduct!.scalePlu,
                            digitalTargetLabel: scannedProduct!.digitalTargetLabel,
                            shelfLocation: scannedProduct!.shelfLocation,
                            iconType: scannedProduct!.iconType,
                            imageUrl: scannedProduct!.imageUrl,
                            variants: scannedProduct!.variants,
                            batches: scannedProduct!.batches,
                          );
                          final result = await context.read<PosCubit>().saveProductInventory(
                                updated,
                                isNew: false,
                                notes: 'Stock Opname Kamera (Selisih ${variance >= 0 ? '+' : ''}$variance)',
                              );
                          if (!ctx.mounted) return;
                          if (!result.ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: NusaThemeTokens.of(ctx).danger,
                                content: Text(result.errorMessage ?? 'Gagal menyimpan penyesuaian stok.'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: result.syncedToCloud ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).warning,
                              content: Text('Stock Opname "${updated.name}" diperbarui menjadi $actualQty.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('Simpan Penyesuaian Stok'),
                      ),
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


  Widget _buildQuickSubModuleStrip(BuildContext context, NusaThemeTokens tokens) {
    final shortcuts = [
      (label: '🏷️ Kategori & Merek', route: '/catalog-taxonomies?tab=0'),
      (label: '📏 Satuan Unit', route: '/catalog-taxonomies?tab=2'),
      (label: '🔍 Opname Multi-Item', route: '/inventory-ops?tab=1'),
      (label: '📊 Kartu Mutasi', route: '/inventory-ops?tab=2'),
      (label: '🖨️ Cetak Barcode', route: '/catalog-taxonomies?tab=3'),
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


  Widget _inventoryMetricTile(
    NusaThemeTokens tokens, {
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: tokens.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.moneyStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: valueColor),
          ),
        ],
      ),
    );
  }
}
