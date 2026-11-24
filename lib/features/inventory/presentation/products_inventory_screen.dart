import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_barcode_scanner_view.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// LAYAR 7 — DATA BARANG & STOK (TAB 3 NAVIGASI)
/// OXO.ID Mobile Enterprise Inventory & Stock Opname Screen
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
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
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
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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
                if (saveError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    child: Text(
                      saveError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600),
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
                              backgroundColor: result.syncedToCloud ? AppColors.successDark : AppColors.warningDark,
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
                                backgroundColor: AppColors.danger,
                                content: Text(result.errorMessage ?? 'Gagal menyimpan penyesuaian stok.'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: result.syncedToCloud ? AppColors.successDark : AppColors.warningDark,
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
