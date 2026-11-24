// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosWarehouseAndPriceSheetsExt on _PosCatalogScreenState {
  /// Switch Active Store / Warehouse Branch directly inside POS (Multi-Gudang Parity)
  void _showStoreWarehouseSwitcherSheet(BuildContext context) {
    final authState = context.read<AuthCubit>().state;
    final stores = authState.session.availableStores;
    final activeId = authState.session.activeStore.id;
    final tokens = NusaThemeTokens.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warehouse_rounded, color: NusaThemeTokens.of(ctx).accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pilih Cabang / Gudang Aktif POS',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Katalog POS otomatis menyaring hanya produk dengan stok tersedia (> 0) pada gudang/cabang terpilih.',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: stores.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final branch = stores[idx];
                      final isSelected = branch.id == activeId;
                      return InkWell(
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (!isSelected) {
                            await context.read<AuthCubit>().switchStoreBranch(branch);
                            if (context.mounted) {
                              await context.read<PosCubit>().syncWithCloud(
                                    force: true,
                                    preserveActiveCart: false,
                                  );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? tokens.accentSoft : tokens.bgElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? tokens.accent : tokens.borderSubtle,
                              width: isSelected ? 1.5 : tokens.borderWidth,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                branch.isWarehouse ? Icons.warehouse_rounded : Icons.storefront_rounded,
                                color: isSelected ? tokens.accent : tokens.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      branch.name,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${branch.isWarehouse ? 'Gudang' : 'Gerai'} • ${branch.code}${branch.city != null && branch.city!.isNotEmpty ? ' • ${branch.city}' : ''}',
                                      style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Multi-Warehouse Stock Lookup Modal (Endless Aisle Parity with Cloud Web POS)
  void _showWarehouseStockSheet(
    BuildContext context, {
    ProductModel? initialProduct,
    String initialQuery = '',
  }) {
    final posCubit = context.read<PosCubit>();
    final queryCtrl = TextEditingController(
      text: initialProduct?.sku ?? initialQuery,
    );
    final tokens = NusaThemeTokens.of(context);
    bool isLoading = true;
    String? inlineError;
    List<Map<String, dynamic>> results = [];
    bool initialized = false;

    Future<void> runLookup(
      StateSetter setModalState,
      BuildContext sheetCtx, {
      int? productId,
      String? query,
    }) async {
      setModalState(() {
        isLoading = true;
        inlineError = null;
      });
      final res = await posCubit.fetchWarehouseStock(
        productId: productId,
        query: query ?? queryCtrl.text,
      );
      if (sheetCtx.mounted) {
        setModalState(() {
          isLoading = false;
          results = res.results;
          inlineError = res.error;
        });
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            if (!initialized) {
              initialized = true;
              Future.microtask(
                () => runLookup(
                  setModalState,
                  modalCtx,
                  productId: initialProduct?.id,
                  query: queryCtrl.text,
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 14,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(modalCtx).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warehouse_rounded, color: NusaThemeTokens.of(modalCtx).warning, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cek Stok Multi-Gudang & Cabang',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: queryCtrl,
                            onSubmitted: (_) => runLookup(setModalState, modalCtx),
                            decoration: const InputDecoration(
                              hintText: 'Cari produk, SKU, atau barcode di seluruh gudang...',
                              prefixIcon: Icon(Icons.search_rounded, size: 19),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isLoading ? null : () => runLookup(setModalState, modalCtx),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          child: const Text('Cari'),
                        ),
                      ],
                    ),
                    if (inlineError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: NusaThemeTokens.of(modalCtx).dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: NusaThemeTokens.of(modalCtx).danger.withOpacity(0.4)),
                        ),
                        child: Text(
                          inlineError!,
                          style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(modalCtx).danger, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Tidak ada data stok multi-gudang untuk kata kunci tersebut.',
                            style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, idx) {
                            final item = results[idx];
                            final warehouses = (item['warehouses'] as List<dynamic>? ?? [])
                                .whereType<Map>()
                                .map((e) => Map<String, dynamic>.from(e))
                                .toList();
                            final curAvail = (item['current_store_available'] as num?)?.toDouble() ?? 0.0;
                            final totalNetwork = (item['total_network_stock'] as num?)?.toDouble() ?? curAvail;
                            final unit = (item['unit'] ?? 'pcs').toString();

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: tokens.bgElevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (item['name'] ?? 'Produk').toString(),
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: tokens.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              'SKU: ${item['sku'] ?? '-'} • Total Jaringan: ${IdrCurrencyFormatter.formatQty(totalNetwork)} $unit',
                                              style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      NusaBadge(
                                        label: 'Gerai Ini: ${IdrCurrencyFormatter.formatQty(curAvail)}',
                                        variant: curAvail > 0 ? NusaBadgeVariant.success : NusaBadgeVariant.danger,
                                      ),
                                    ],
                                  ),
                                  if (warehouses.isNotEmpty) ...[
                                    const Divider(height: 14),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: warehouses.map((wh) {
                                        final avail = (wh['available'] as num?)?.toDouble() ?? 0.0;
                                        final isWh = wh['is_warehouse'] == true;
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: tokens.bgSurface,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: avail > 0
                                                  ? NusaThemeTokens.of(modalCtx).positive.withOpacity(0.35)
                                                  : tokens.borderSubtle,
                                            ),
                                          ),
                                          child: Text(
                                            '${isWh ? 'Gudang' : 'Cabang'} ${wh['store_name']}: ${IdrCurrencyFormatter.formatQty(avail)} $unit',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: avail > 0 ? NusaThemeTokens.of(modalCtx).positive : tokens.textSecondary,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Fast-Lane Quick Price & Stock Checker Modal (Scan barcode or type SKU/name)
  void _showQuickPriceCheckerSheet(BuildContext context) {
    final searchCtrl = TextEditingController();
    final tokens = NusaThemeTokens.of(context);
    final cubit = context.read<PosCubit>();
    ProductModel? selectedProduct;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final q = searchCtrl.text.trim().toLowerCase();
          final matches = cubit.state.allProducts.where((p) {
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q) ||
                p.sku.toLowerCase().contains(q) ||
                p.barcode.toLowerCase().contains(q) ||
                (p.brandName?.toLowerCase().contains(q) ?? false);
          }).take(15).toList();

          if (q.isNotEmpty && matches.length == 1) {
            selectedProduct = matches.first;
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.82,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: tokens.borderDefault,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.price_check_rounded, color: tokens.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cek Harga & Stok Cepat',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Scan Barcode',
                          onPressed: () {
                            showModalBottomSheet<void>(
                              context: ctx,
                              backgroundColor: tokens.bgSurface,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                              ),
                              builder: (scanCtx) => Padding(
                                padding: const EdgeInsets.all(16),
                                child: SizedBox(
                                  height: 220,
                                  child: NusaBarcodeScannerView(
                                    onDetect: (code) {
                                      Navigator.pop(scanCtx);
                                      searchCtrl.text = code;
                                      setModalState(() {
                                        selectedProduct = cubit.state.allProducts
                                            .where((p) =>
                                                p.barcode.toLowerCase() == code.toLowerCase() ||
                                                p.sku.toLowerCase() == code.toLowerCase())
                                            .firstOrNull;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: Icon(Icons.qr_code_scanner_rounded, color: tokens.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      onChanged: (_) => setModalState(() {
                        if (searchCtrl.text.trim().isEmpty) selectedProduct = null;
                      }),
                      decoration: InputDecoration(
                        hintText: 'Scan barcode atau ketik nama / SKU produk...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setModalState(() => selectedProduct = null);
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedProduct != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: tokens.bgElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: tokens.accent.withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedProduct!.name,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'SKU: ${selectedProduct!.sku} • Barcode: ${selectedProduct!.barcode.isEmpty ? '-' : selectedProduct!.barcode}',
                              style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                            ),
                            if (selectedProduct!.shelfLocation != null &&
                                selectedProduct!.shelfLocation!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Lokasi Rak: ${selectedProduct!.shelfLocation}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.accent,
                                ),
                              ),
                            ],
                            const Divider(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Harga Jual',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${IdrCurrencyFormatter.format(selectedProduct!.sellingPrice)} / ${selectedProduct!.unitCode}',
                                  style: AppTheme.moneyStyle(
                                    fontSize: 18,
                                    color: tokens.accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Stok Gerai Ini',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                                Text(
                                  '${IdrCurrencyFormatter.formatQty(selectedProduct!.stock)} ${selectedProduct!.unitCode}'
                                  '${selectedProduct!.otherWarehousesStock > 0 ? ' (+${IdrCurrencyFormatter.formatQty(selectedProduct!.otherWarehousesStock)} gdg lain)' : ''}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: selectedProduct!.stock > 0
                                        ? NusaThemeTokens.of(ctx).positive
                                        : NusaThemeTokens.of(ctx).danger,
                                  ),
                                ),
                              ],
                            ),
                            if (selectedProduct!.volumeTiers.isNotEmpty) ...[
                              const Divider(height: 16),
                              Text(
                                'Harga Grosir Bertingkat:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final t in selectedProduct!.volumeTiers)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Min ${IdrCurrencyFormatter.formatQty(t.minQuantity)} ${selectedProduct!.unitCode}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: tokens.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        IdrCurrencyFormatter.format(t.tierPrice),
                                        style: AppTheme.moneyStyle(
                                          fontSize: 12.5,
                                          color: NusaThemeTokens.of(ctx).positive,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            if (selectedProduct!.isSellableInPos) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: tokens.accent,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _onProductTapped(context, selectedProduct!);
                                  },
                                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                  label: const Text('Tambahkan ke Keranjang'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else
                      Flexible(
                        child: matches.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  'Produk tidak ditemukan untuk "${searchCtrl.text}".',
                                  style: TextStyle(color: tokens.textSecondary),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: matches.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, idx) {
                                  final p = matches[idx];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    subtitle: Text(
                                      'SKU ${p.sku} • Stok ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                    trailing: Text(
                                      IdrCurrencyFormatter.format(p.sellingPrice),
                                      style: AppTheme.moneyStyle(
                                        fontSize: 13.5,
                                        color: tokens.accent,
                                      ),
                                    ),
                                    onTap: () => setModalState(() => selectedProduct = p),
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
