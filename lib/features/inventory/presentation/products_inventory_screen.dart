import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_barcode_scanner_view.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

part 'products_inventory_screen_part1.dart';
part 'products_inventory_screen_part2.dart';

/// LAYAR 7 — DATA BARANG & STOK (TAB 3 NAVIGASI)
/// OXORA Mobile Enterprise Inventory & Stock Opname Screen
class ProductsInventoryScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;

  const ProductsInventoryScreen({super.key, required this.onOpenDrawer});

  @override
  State<ProductsInventoryScreen> createState() => _ProductsInventoryScreenState();
}


class _ProductsInventoryScreenState extends State<ProductsInventoryScreen> {
  String _searchQuery = '';

  String _filterMode = 'Semua'; // 'Semua', 'Stok Menipis', 'FEFO (< 30 Hari)'

  final TextEditingController _searchCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PosCubit>().syncWithCloud(force: false);
      }
    });
  }


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final allProducts = context.watch<PosCubit>().state.allProducts;
    final lowStockCount = allProducts.where((p) => p.isLowStock).length;
    final totalStockAssetValue = allProducts.fold<double>(0.0, (s, p) => s + (p.stock * p.costPrice));

    final filtered = allProducts.where((p) {
      if (_filterMode == 'Stok Menipis' && !p.isLowStock) return false;
      if (_filterMode == 'FEFO (< 30 Hari)' && !p.hasExpiringSoonBatch) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('Barang & Inventaris'),
        actions: [
          IconButton(
            tooltip: 'Kategori, Merek & Satuan',
            icon: Icon(Icons.category_outlined, color: tokens.accent),
            onPressed: () => context.push('/catalog-taxonomies'),
          ),
          IconButton(
            tooltip: 'Operasi Gudang & Mutasi Stok',
            icon: Icon(Icons.inventory_outlined, color: tokens.accent),
            onPressed: () => context.push('/inventory-ops'),
          ),
          IconButton(
            tooltip: 'Sinkronkan Data Produk',
            icon: Icon(Icons.sync_rounded, color: tokens.accent),
            onPressed: () async {
              await context.read<PosCubit>().syncWithCloud(force: false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Katalog barang berhasil disinkronkan.')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 3-Column Summary Metric Strip + Search + Filter Chips
          Container(
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _inventoryMetricTile(
                        tokens,
                        label: 'SKU Aktif',
                        value: '${allProducts.length}',
                        valueColor: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _inventoryMetricTile(
                        tokens,
                        label: 'Stok Menipis',
                        value: '$lowStockCount',
                        valueColor: lowStockCount > 0 ? tokens.danger : tokens.positive,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _inventoryMetricTile(
                        tokens,
                        label: 'Nilai Stok (HPP)',
                        value: IdrCurrencyFormatter.formatCompact(totalStockAssetValue),
                        valueColor: tokens.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Cari nama barang, SKU, atau barcode...',
                    prefixIcon: Icon(Icons.search_rounded, color: tokens.textTertiary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final mode in const ['Semua', 'Stok Menipis', 'FEFO (< 30 Hari)'])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: NusaPillFilter(
                            label: mode,
                            selected: _filterMode == mode,
                            onTap: () => setState(() => _filterMode = mode),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _buildQuickSubModuleStrip(context, tokens),
              ],
            ),
          ),

          // 2. High-Density Inventory Product List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => context.read<PosCubit>().syncWithCloud(force: false),
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        NusaEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Belum Ada Produk Cocok',
                          subtitle: 'Ubah filter stok atau tambah barang baru ke database toko.',
                          actionLabel: 'Tambah Barang',
                          onAction: () => _showAddOrEditProductModal(context),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final product = filtered[idx];
                        final marginPct = product.sellingPrice > 0 && product.costPrice > 0
                            ? ((product.sellingPrice - product.costPrice) / product.sellingPrice) * 100
                            : null;
                        final isOutOfStock = product.stock <= 0;

                        return NusaCard(
                          padding: const EdgeInsets.all(12),
                          onTap: () => _showAddOrEditProductModal(context, existing: product),
                          child: Row(
                            children: [
                              ProductIllustrationWidget(
                                iconType: product.iconType,
                                imageUrl: product.imageUrl,
                                size: 54,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            'SKU: ${product.sku}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                                          ),
                                        ),
                                        if (product.shelfLocation != null && product.shelfLocation!.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          NusaBadge(
                                            label: 'Rak ${product.shelfLocation}',
                                            variant: NusaBadgeVariant.neutral,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (!product.canBeSold)
                                          const NusaBadge(
                                            label: 'Bahan Baku',
                                            variant: NusaBadgeVariant.neutral,
                                          ),
                                        NusaBadge(
                                          label: isOutOfStock
                                              ? 'Stok Habis (0)'
                                              : 'Stok ${IdrCurrencyFormatter.formatQty(product.stock, unitCode: product.unitCode)}',
                                          variant: isOutOfStock
                                              ? NusaBadgeVariant.danger
                                              : (product.isLowStock
                                                  ? NusaBadgeVariant.warning
                                                  : NusaBadgeVariant.success),
                                        ),
                                        if (product.hasExpiringSoonBatch)
                                          const NusaBadge(
                                            label: 'FEFO < 30H',
                                            variant: NusaBadgeVariant.warning,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        NusaPriceTag(amount: product.sellingPrice, fontSize: 13.5),
                                        if (product.costPrice > 0) ...[
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'HPP ${IdrCurrencyFormatter.formatCompact(product.costPrice)}'
                                              '${marginPct != null ? ' (${marginPct.toStringAsFixed(0)}%)' : ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: tokens.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Inline >= 44dp Quick Opname Button
                              InkWell(
                                onTap: () => _showAddOrEditProductModal(context, existing: product),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: tokens.accentSoft,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.3),
                                      width: tokens.borderWidth,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.edit_note_rounded, size: 18, color: tokens.accent),
                                      Text(
                                        'Opname',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: tokens.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      // Thumb-Zone Primary CTAs
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          border: Border(top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: NusaButton(
                  label: 'Scan Opname',
                  icon: Icons.qr_code_scanner_rounded,
                  variant: NusaButtonVariant.outline,
                  onPressed: () => _showInstantCameraOpnameModal(context, allProducts),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NusaButton(
                  label: '+ Barang Baru',
                  icon: Icons.add_box_outlined,
                  onPressed: () => _showAddOrEditProductModal(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
