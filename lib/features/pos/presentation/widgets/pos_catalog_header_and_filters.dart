// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosCatalogHeaderAndFiltersExt on _PosCatalogScreenState {
  Widget _buildCatalogColumn(
    BuildContext context,
    PosState state,
    int gridColumns,
    double screenWidth, {
    required bool isTablet,
  }) {
    final tokens = NusaThemeTokens.of(context);
    final capabilities = state.capabilities;
    return Column(
      children: [
              // 1. Compact Operational Bar (Customer + Sync), Fixed Search/Scan & Category Chips
              Container(
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
                ),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(flex: 5, child: _buildCustomerStatusBar(context, state)),
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 4,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: NusaSyncStatusPill(
                              isOnline: state.isOnline,
                              isSyncing: state.isSyncingOfflineQueue,
                              offlinePendingCount: state.offlinePendingCount,
                              compact: true,
                              onTap: () async {
                                if (!state.isOnline) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          state.offlinePendingCount > 0
                                              ? 'Offline • ${state.offlinePendingCount} Nota tersimpan aman di perangkat.'
                                              : 'Perangkat sedang offline. Transaksi tetap dapat dilakukan.',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                if (state.offlinePendingCount > 0) {
                                  final synced = await context
                                      .read<PosCubit>()
                                      .syncOfflineTransactions();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          synced > 0
                                              ? '$synced nota offline berhasil disinkronkan ke Cloud.'
                                              : 'Belum ada nota yang berhasil disinkronkan.',
                                        ),
                                      ),
                                    );
                                  }
                                } else {
                                  await context
                                      .read<PosCubit>()
                                      .syncWithCloud(force: false, preserveActiveCart: true);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Contextual Vertical Metadata Bar (Apotek, Bengkel, Laundry, Salon)
                    if (capabilities.hasPrescriptionWorkflow ||
                        capabilities.hasVehicleWorkOrder ||
                        capabilities.hasLaundryOrderMetadata ||
                        capabilities.hasSalonStylistWorkflow) ...[
                      _buildVerticalMetadataBar(context, state),
                      if (capabilities.hasPrescriptionWorkflow &&
                          state.hasUnfulfilledPrescriptionRequirement) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showVerticalMetadataSheet(context, state),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: NusaThemeTokens.of(context).dangerSoft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.35)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.medical_information_rounded,
                                  color: NusaThemeTokens.of(context).danger,
                                  size: 17,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${state.prescriptionRequiredCartProducts.length} obat resep belum dilengkapi Nama Dokter & Pasien. Ketuk untuk isi.',
                                    style: TextStyle(
                                      color: NusaThemeTokens.of(context).danger,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: NusaThemeTokens.of(context).danger,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                    // Order Type Chips: Ritel | Dine-In | Takeaway | Delivery (Hanya tampil pada F&B/Resto)
                    if (capabilities.hasDineInTakeawayOrderType) ...[
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final ot in const [
                              ('retail', 'Ritel', Icons.storefront_outlined),
                              ('dine_in', 'Dine-In', Icons.restaurant_outlined),
                              ('takeaway', 'Takeaway', Icons.shopping_bag_outlined),
                              ('delivery', 'Delivery', Icons.delivery_dining_outlined),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: NusaPillFilter(
                                  label: ot.$2,
                                  icon: ot.$3,
                                  selected: state.orderType == ot.$1,
                                  selectedColor: NusaThemeTokens.of(context).textPrimary,
                                  onTap: () => context.read<PosCubit>().setOrderType(ot.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Search Bar + Fixed Scanner Button + Grid/List Toggle (Zero layout shift)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onChanged: (val) {
                                setState(() {});
                                context.read<PosCubit>().updateSearchQuery(val);
                              },
                              onSubmitted: (val) {
                                final cleaned = val.trim();
                                if (cleaned.isEmpty) return;
                                final cubit = context.read<PosCubit>();
                                final matched = cubit.handleBarcodeScanned(cleaned);
                                if (matched) {
                                  _searchController.clear();
                                  setState(() {});
                                  cubit.updateSearchQuery('');
                                }
                              },
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: 'Cari nama, barcode, atau SKU...',
                                prefixIcon: Icon(Icons.search_rounded, size: 20, color: NusaThemeTokens.of(context).textTertiary),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                          context.read<PosCubit>().updateSearchQuery('');
                                        },
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Scan Barcode Kamera',
                          child: Material(
                            color: NusaThemeTokens.of(context).accentSoft,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _openCameraBarcodeScanner(context),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: NusaThemeTokens.of(context).accent.withOpacity(0.25)),
                                ),
                                child: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: NusaThemeTokens.of(context).accent,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Cek Stok Multi-Gudang',
                          child: Material(
                            color: NusaThemeTokens.of(context).warningSoft,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _showWarehouseStockSheet(
                                context,
                                initialQuery: _searchController.text,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.35)),
                                ),
                                child: Icon(
                                  Icons.warehouse_outlined,
                                  color: NusaThemeTokens.of(context).warning,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: _isListView ? 'Tampilan Grid' : 'Tampilan Daftar',
                          child: Material(
                            color: tokens.bgElevated,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => setState(() => _isListView = !_isListView),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                                ),
                                child: Icon(
                                  _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                                  color: tokens.textPrimary,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Dynamic Database Category Chips (Only categories with sellable POS stock)
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: state.posCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, idx) {
                          final cat = state.posCategories[idx];
                          final id = (cat['id'] as num?)?.toInt() ?? 0;
                          final isSelected = state.selectedCategoryId == id;
                          return NusaPillFilter(
                            label: cat['name'].toString(),
                            selected: isSelected,
                            onTap: () => context.read<PosCubit>().selectCategory(id),
                          );
                        },
                      ),
                    ),
                    // Dynamic Brand Chips (Displayed when >1 brand exists in sellable catalog)
                    if (state.posBrands.length > 1) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 30,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: state.posBrands.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (context, idx) {
                            final brand = state.posBrands[idx];
                            final bid = (brand['id'] as num?)?.toInt() ?? 0;
                            final isSelected = state.selectedBrandId == bid;
                            return NusaPillFilter(
                              label: brand['name'].toString(),
                              icon: bid == 0 ? Icons.sell_outlined : null,
                              selected: isSelected,
                              selectedColor: const Color(0xFF0284C7),
                              onTap: () => context.read<PosCubit>().selectBrand(bid),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (state.isExchangeMode)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(context).warningSoft,
                    border: Border(
                      bottom: BorderSide(color: NusaThemeTokens.of(context).warning.withOpacity(0.45)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 18, color: NusaThemeTokens.of(context).warning),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Mode Tukar Barang • Nota ${state.exchangeSourceSale?['number'] ?? '-'}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: NusaThemeTokens.of(context).warning,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => context.read<PosCubit>().cancelExchangeMode(),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.5)),
                              ),
                              child: Text(
                                'Batal Tukar',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: NusaThemeTokens.of(context).danger,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Retur: -${IdrCurrencyFormatter.format(state.exchangeReturnCreditTotal)} • Pengganti: +${IdrCurrencyFormatter.format(state.replacementItemsSubtotal)}'
                        '${state.exchangeSurplusCredit > 0 ? ' • Kelebihan: ${IdrCurrencyFormatter.format(state.exchangeSurplusCredit)}' : ' • Kurang Bayar: ${IdrCurrencyFormatter.format(state.grandTotal)}'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: NusaThemeTokens.of(context).textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. Product Catalog Area (Grid or List View)
              Expanded(
                child: state.filteredProducts.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              NusaEmptyState(
                                icon: Icons.inventory_2_outlined,
                                title: 'Tidak Ada Produk Tersedia di POS',
                                subtitle:
                                    'Produk dengan stok 0 di cabang ini otomatis disembunyikan agar konsisten dengan Cloud POS.',
                                actionLabel: 'Reset Filter',
                                onAction: () {
                                  _searchController.clear();
                                  setState(() {});
                                  context.read<PosCubit>().updateSearchQuery('');
                                  context.read<PosCubit>().selectCategory(0);
                                  context.read<PosCubit>().selectBrand(0);
                                },
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () => _showWarehouseStockSheet(
                                  context,
                                  initialQuery: _searchController.text,
                                ),
                                icon: const Icon(Icons.warehouse_outlined, size: 18),
                                label: const Text('Cek Stok Multi-Gudang'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _isListView
                        ? ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            itemCount: state.filteredProducts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final product = state.filteredProducts[index];
                              return _buildPosProductListTile(context, state, product);
                            },
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: gridColumns,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: (screenWidth >= 600 ? 256.0 : 254.0) *
                                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.2),
                            ),
                            itemCount: state.filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = state.filteredProducts[index];
                              return _buildPosProductCard(context, state, product);
                            },
                          ),
              ),

              // 3. Thumb-Zone Sticky Expandable Cart Panel (Phone only; Tablet uses Pinned Side Cart)
              if (!isTablet) _buildBottomCartPanel(context, state),
            ],
          );
  }

  double _productQtyInCart(PosState state, int productId) {
    return state.cart
        .where((item) => item.product.id == productId)
        .fold(0.0, (sum, item) => sum + item.quantity);
  }
}
