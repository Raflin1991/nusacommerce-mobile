import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// LAYAR 7 — DATA BARANG & STOK (TAB 3 NAVIGASI)
/// Matches 1:1 with Screen 6 of `Papan Konsep UI KasirKu Modern-1.png`
class ProductsInventoryScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;

  const ProductsInventoryScreen({super.key, required this.onOpenDrawer});

  @override
  State<ProductsInventoryScreen> createState() => _ProductsInventoryScreenState();
}

class _ProductsInventoryScreenState extends State<ProductsInventoryScreen> {
  String _searchQuery = '';
  String _filterMode = 'Semua'; // 'Semua', 'Aktif', 'Stok Menipis'

  void _showAddOrEditProductModal(BuildContext context, {ProductModel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? 'PRD-${DateTime.now().millisecond}');
    final priceCtrl = TextEditingController(
      text: existing != null ? existing.sellingPrice.toInt().toString() : '',
    );
    final stockCtrl = TextEditingController(
      text: existing != null ? existing.stock.toInt().toString() : '25',
    );
    final shelfCtrl = TextEditingController(text: existing?.shelfLocation ?? 'Rak A1 • Baris 2');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
              Text(
                existing == null ? 'Tambah Barang Baru' : 'Detail & Stock Opname — ${existing.name}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              if (existing != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📍 Lokasi Rak: ${existing.shelfLocation ?? 'Rak Utama'}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🏢 Stok Lintas Cabang: Toko Kemang (${existing.stock.toInt()} ${existing.unitCode}) • Cabang Bandung (32 ${existing.unitCode})',
                        style: const TextStyle(fontSize: 12, color: AppColors.slate700),
                      ),
                      if (existing.fefoBatch != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '⏳ Batch FEFO Aktif: ${existing.fefoBatch!.batchNumber} (Exp: ${existing.fefoBatch!.expiryDate})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warningDark),
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
                  labelText: 'Nama Barang',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Harga Jual (Rp)',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Stok Fisik (Opname)',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shelfCtrl,
                decoration: const InputDecoration(
                  labelText: 'Koordinat Rak Gudang / Toko',
                  prefixIcon: Icon(Icons.shelves),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final price = IdrCurrencyFormatter.parse(priceCtrl.text);
                    final stock = double.tryParse(stockCtrl.text) ?? 0.0;

                    final updated = ProductModel(
                      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                      name: name,
                      sku: skuCtrl.text.trim(),
                      barcode: existing?.barcode ?? '899${DateTime.now().millisecond}',
                      sellingPrice: price > 0 ? price : 5000,
                      costPrice: existing?.costPrice ?? (price * 0.7),
                      stock: stock,
                      unitCode: existing?.unitCode ?? 'pcs',
                      isLowStock: stock <= 10,
                      shelfLocation: shelfCtrl.text.trim(),
                      iconType: existing?.iconType ?? 'default',
                      variants: existing?.variants ?? const [],
                      batches: existing?.batches ?? const [],
                    );

                    context.read<PosCubit>().saveProductInventory(updated);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Data barang "${updated.name}" berhasil disimpan.')),
                    );
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: Text(existing == null ? 'Simpan Barang Baru' : 'Simpan Hasil Stock Opname'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allProducts = context.watch<PosCubit>().state.allProducts;

    final filtered = allProducts.where((p) {
      if (_filterMode == 'Stok Menipis' && !p.isLowStock) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('Barang'),
        actions: [
          // Blue Circle (+) Button in Top Right (Persis Mockup Screen 6)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              onTap: () => _showAddOrEditProductModal(context),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filter Chips ("Semua", "Aktif", "Stok Menipis" Persis Mockup Screen 6)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Cari barang...',
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.slate400),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: ['Semua', 'Aktif', 'Stok Menipis'].map((mode) {
                    final selected = _filterMode == mode;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(mode),
                        selected: selected,
                        onSelected: (_) => setState(() => _filterMode = mode),
                        selectedColor: AppColors.primary,
                        backgroundColor: const Color(0xFFF1F5F9),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppColors.slate700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: BorderSide.none,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // 2. Product List Items (Persis Mockup Screen 6)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final product = filtered[idx];
                return InkWell(
                  onTap: () => _showAddOrEditProductModal(context, existing: product),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Row(
                      children: [
                        ProductIllustrationWidget(
                          iconType: product.iconType,
                          imageUrl: product.imageUrl,
                          size: 56,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Stok: ${IdrCurrencyFormatter.formatQty(product.stock, unitCode: product.unitCode)}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: product.isLowStock ? AppColors.slate600 : AppColors.successDark,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                IdrCurrencyFormatter.format(product.sellingPrice),
                                style: AppTheme.moneyStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Warning triangle "Stok Menipis" on right side (Persis Mockup Screen 6)
                        if (product.isLowStock)
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppColors.danger,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Stok Menipis',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.slate500,
                                ),
                              ),
                            ],
                          )
                        else
                          const Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
