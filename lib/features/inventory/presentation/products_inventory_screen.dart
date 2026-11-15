import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// LAYAR 7 — DATA BARANG & STOK (TAB 3 NAVIGASI)
/// NusaCommerce Mobile Enterprise Inventory & Stock Opname Screen
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

    final selectableCats = posState.categories.where((c) => (c['id'] as num?)?.toInt() != 0).toList();
    int? selectedCatId = existing?.categoryId ??
        (selectableCats.isNotEmpty ? (selectableCats.first['id'] as num?)?.toInt() : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                          '🏢 Stok $activeStoreName: ${IdrCurrencyFormatter.formatQty(existing.stock, unitCode: existing.unitCode)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.slate700),
                        ),
                        if (existing.fefoBatch != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⏳ Batch FEFO Aktif: ${existing.fefoBatch!.batchNumber} (Exp: ${existing.fefoBatch!.expiryDate ?? '-'})',
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
                    labelText: 'Nama Barang *',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                if (selectableCats.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
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
                    onChanged: (v) => setModalState(() => selectedCatId = v),
                  ),
                  const SizedBox(height: 10),
                ],
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
                            icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                            onPressed: () {
                              bool scanned = false;
                              showDialog(
                                context: ctx,
                                builder: (sCtx) => AlertDialog(
                                  title: const Text('Scan Barcode Produk'),
                                  content: SizedBox(
                                    height: 220,
                                    width: 280,
                                    child: MobileScanner(
                                      onDetect: (capture) {
                                        if (scanned) return;
                                        final code = capture.barcodes.isNotEmpty
                                            ? capture.barcodes.first.rawValue
                                            : null;
                                        if (code != null && code.isNotEmpty) {
                                          scanned = true;
                                          barcodeCtrl.text = code;
                                          Navigator.pop(sCtx);
                                        }
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
                      backgroundColor: isNegative ? AppColors.dangerSoft : AppColors.successSoft,
                      borderColor: (isNegative ? AppColors.danger : AppColors.success).withOpacity(0.3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isNegative ? 'Rugi per unit:' : 'Estimasi Laba / Margin:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isNegative ? AppColors.danger : AppColors.successDark,
                            ),
                          ),
                          Text(
                            '${IdrCurrencyFormatter.format(profit)} (${marginPct.toStringAsFixed(1)}%)',
                            style: AppTheme.moneyStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isNegative ? AppColors.danger : AppColors.successDark,
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
                const SizedBox(height: 16),
                NusaButton(
                  icon: Icons.save_rounded,
                  label: existing == null ? 'Simpan Barang Baru' : 'Simpan Hasil Stock Opname',
                  onPressed: () {
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

                    final updated = ProductModel(
                      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch,
                      name: name,
                      sku: skuCtrl.text.trim(),
                      barcode: barcodeCtrl.text.trim().isNotEmpty
                          ? barcodeCtrl.text.trim()
                          : (existing?.barcode ?? ''),
                      sellingPrice: price > 0 ? price : (existing?.sellingPrice ?? 0),
                      costPrice: cost > 0 ? cost : (existing?.costPrice ?? 0),
                      stock: stock,
                      unitCode: existing?.unitCode ?? 'pcs',
                      categoryId: selectedCatId ?? existing?.categoryId ?? 1,
                      categoryName: catName,
                      isLowStock: stock <= 5,
                      shelfLocation: shelfCtrl.text.trim(),
                      iconType: existing?.iconType ?? 'default',
                      imageUrl: existing?.imageUrl,
                      variants: existing?.variants ?? const [],
                      batches: existing?.batches ?? const [],
                    );

                    context.read<PosCubit>().saveProductInventory(updated, isNew: existing == null);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Data barang "${updated.name}" berhasil disimpan.')),
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

  void _showInstantCameraOpnameModal(BuildContext context, List<ProductModel> allProducts) {
    ProductModel? scannedProduct;
    final physicalCtrl = TextEditingController();
    final manualCodeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                SnackBar(backgroundColor: AppColors.danger, content: Text('Produk "$code" tidak ditemukan.')),
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
                        child: MobileScanner(
                          onDetect: (capture) {
                            if (scannedProduct != null) return;
                            final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
                            if (raw != null && raw.isNotEmpty) {
                              resolveCode(raw);
                            }
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
                        color: AppColors.primarySoft,
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
                            style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Stok Sistem Tercatat: ${IdrCurrencyFormatter.formatQty(systemQty, unitCode: scannedProduct!.unitCode)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
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
                            ? AppColors.successSoft
                            : (variance > 0 ? AppColors.primarySoft : AppColors.dangerSoft),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Selisih Opname (Variance): ${variance > 0 ? '+' : ''}${IdrCurrencyFormatter.formatQty(variance, unitCode: scannedProduct!.unitCode)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: variance == 0
                              ? AppColors.successDark
                              : (variance > 0 ? AppColors.primary : AppColors.dangerDark),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
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
                          context.read<PosCubit>().saveProductInventory(
                                updated,
                                isNew: false,
                                notes: 'Stock Opname Kamera (Selisih ${variance >= 0 ? '+' : ''}$variance)',
                              );
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.successDark,
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

  @override
  Widget build(BuildContext context) {
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('Barang & Inventaris'),
        actions: [
          IconButton(
            tooltip: 'Sinkronkan Data Produk',
            icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
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
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _inventoryMetricTile(
                        label: 'SKU Aktif',
                        value: '${allProducts.length}',
                        valueColor: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _inventoryMetricTile(
                        label: 'Stok Menipis',
                        value: '$lowStockCount',
                        valueColor: lowStockCount > 0 ? AppColors.danger : AppColors.successDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _inventoryMetricTile(
                        label: 'Nilai Stok (HPP)',
                        value: IdrCurrencyFormatter.formatCompact(totalStockAssetValue),
                        valueColor: AppColors.primary,
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
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate400),
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
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navyDark,
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
                                            style: const TextStyle(fontSize: 11, color: AppColors.slate500),
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
                                          Text(
                                            'HPP ${IdrCurrencyFormatter.formatCompact(product.costPrice)}'
                                            '${marginPct != null ? ' (${marginPct.toStringAsFixed(0)}%)' : ''}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.slate500,
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
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.edit_note_rounded, size: 18, color: AppColors.primary),
                                      Text(
                                        'Opname',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary,
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
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
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

  Widget _inventoryMetricTile({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.slate500),
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
