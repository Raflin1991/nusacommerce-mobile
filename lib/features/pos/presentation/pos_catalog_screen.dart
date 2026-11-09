import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../bloc/pos_cubit.dart';
import '../models/pos_models.dart';

/// LAYAR 3 — PENJUALAN BARU (POS CATALOG & FLOATING CART)
/// Matches 1:1 with Screen 3 of `Papan Konsep UI KasirKu Modern-1.png`
class PosCatalogScreen extends StatefulWidget {
  const PosCatalogScreen({super.key});

  @override
  State<PosCatalogScreen> createState() => _PosCatalogScreenState();
}

class _PosCatalogScreenState extends State<PosCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onProductTapped(BuildContext context, ProductModel product) {
    final cubit = context.read<PosCubit>();

    // 1. Variable Product -> Open Variant Picker Bottom Sheet
    if (product.type == 'variable' && product.variants.isNotEmpty) {
      _showVariantPickerSheet(context, product);
      return;
    }

    // 2. Digital Product (Pulsa / Token PLN) -> Prompt Target Number
    if (product.type == 'digital') {
      _showDigitalTargetSheet(context, product);
      return;
    }

    // 3. Sold by Weight (Barang Curah / Timbangan) -> Prompt Decimal Weight (kg)
    if (product.soldByWeight) {
      _showWeightInputSheet(context, product);
      return;
    }

    // 4. Standard / Kit Product -> Instant 1-Tap Add to Cart
    cubit.addToCart(product);
  }

  void _showVariantPickerSheet(BuildContext context, ProductModel product) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih Varian — ${product.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...product.variants.map(
              (v) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('SKU: ${v.sku} • Stok: ${v.stock.toInt()} ${product.unitCode}'),
                trailing: ElevatedButton(
                  onPressed: () {
                    context.read<PosCubit>().addToCart(product, variant: v);
                    Navigator.pop(ctx);
                  },
                  child: Text(IdrCurrencyFormatter.format(v.sellingPrice)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDigitalTargetSheet(BuildContext context, ProductModel product) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                labelText: product.digitalTargetLabel ?? 'Nomor HP / ID Pelanggan',
                prefixIcon: const Icon(Icons.bolt_rounded, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  context.read<PosCubit>().addToCart(
                        product,
                        digitalTargetValue: ctrl.text.trim(),
                        notes: 'No Tujuan: ${ctrl.text.trim()}',
                      );
                  Navigator.pop(ctx);
                },
                child: const Text('Masukkan ke Keranjang'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWeightInputSheet(BuildContext context, ProductModel product) {
    final ctrl = TextEditingController(text: '1.0');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timbangan Curah — ${product.name}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Harga: ${IdrCurrencyFormatter.format(product.sellingPrice)} / ${product.unitCode}',
              style: const TextStyle(fontSize: 13, color: AppColors.slate600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Berat (${product.unitCode}) — contoh: 0.5 atau 1.25',
                prefixIcon: const Icon(Icons.scale_rounded, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final weight = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 1.0;
                  context.read<PosCubit>().addToCart(product, quantity: weight);
                  Navigator.pop(ctx);
                },
                child: const Text('Tambahkan Barang Timbangan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCameraBarcodeScanner(BuildContext context) {
    final manualCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Scan Barcode / Timbangan Digital',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 210,
                width: double.infinity,
                child: MobileScanner(
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                      final code = barcodes.first.rawValue!;
                      final ok = context.read<PosCubit>().handleBarcodeScanned(code);
                      Navigator.pop(ctx);
                      if (ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Barcode $code berhasil ditambahkan!')),
                        );
                      }
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
                    controller: manualCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Atau ketik kode barcode / PLU (misal: 8992752011001)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (manualCtrl.text.trim().isNotEmpty) {
                      context.read<PosCubit>().handleBarcodeScanned(manualCtrl.text.trim());
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('Cari'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDiscountAndHoldModal(BuildContext context, PosState state) {
    final discountCtrl = TextEditingController(
      text: state.cartDiscountAmount > 0 ? state.cartDiscountAmount.toInt().toString() : '',
    );
    final pinCtrl = TextEditingController();
    final holdLabelCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Opsi Keranjang: Diskon & Tahan Pesanan (Hold)',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: discountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Diskon Nota (Rp)',
                prefixIcon: Icon(Icons.discount_outlined, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN Otorisasi Manajer (Wajib jika diskon > 15% • Default: 1234)',
                prefixIcon: Icon(Icons.verified_user_outlined, color: AppColors.warningDark),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<PosCubit>().holdCurrentCart(holdLabelCtrl.text);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Keranjang berhasil ditahan (Hold Cart).')),
                      );
                    },
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: const Text('Tahan (Hold)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final amt = IdrCurrencyFormatter.parse(discountCtrl.text);
                      final ok = context.read<PosCubit>().applyCartDiscount(
                            amt,
                            managerPin: pinCtrl.text.trim(),
                          );
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppColors.danger,
                            content: Text('Diskon > 15% memerlukan PIN Manajer yang valid (1234)!'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Terapkan Diskon'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosCubit, PosState>(
      listener: (context, state) {
        if (state.alertMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(state.alertMessage!),
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Penjualan Baru'),
                if (state.selectedTable != null)
                  Text(
                    'Meja: ${state.selectedTable!['name']} (${state.selectedTable!['section']})',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            actions: [
              // Held Carts Badge
              if (state.heldCarts.isNotEmpty)
                TextButton.icon(
                  onPressed: () => context.read<PosCubit>().resumeHeldCart(0),
                  icon: const Icon(Icons.restore_rounded, size: 18, color: AppColors.warningDark),
                  label: Text(
                    'Hold (${state.heldCarts.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.warningDark),
                  ),
                ),
              // Restaurant Mode Switcher Button
              IconButton(
                tooltip: 'Mode Meja Restoran (F&B)',
                onPressed: () => context.push('/restaurant'),
                icon: const Icon(Icons.table_restaurant_outlined, color: AppColors.slate700),
              ),
              // Barcode Scanner Icon in Top Right (Persis Mockup Screen 3)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  onTap: () => _openCameraBarcodeScanner(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 22),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. Search Bar & Category Chips Container
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => context.read<PosCubit>().updateSearchQuery(val),
                      decoration: InputDecoration(
                        hintText: 'Cari barang... (nama / barcode)',
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate400),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  context.read<PosCubit>().updateSearchQuery('');
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Horizontal Category Chips: Semua, Minuman, Snack, Pulsa (Persis Mockup)
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: state.categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final cat = state.categories[idx];
                          final id = (cat['id'] as num?)?.toInt() ?? 0;
                          final isSelected = state.selectedCategoryId == id;
                          return ChoiceChip(
                            label: Text(cat['name'].toString()),
                            selected: isSelected,
                            onSelected: (_) => context.read<PosCubit>().selectCategory(id),
                            selectedColor: AppColors.primary,
                            backgroundColor: const Color(0xFFF1F5F9),
                            showCheckmark: false,
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : AppColors.slate700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: BorderSide.none,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Product Grid (3 Columns matching Mockup Screen 3 layout)
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: state.filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = state.filteredProducts[index];
                    return _buildPosProductCard(context, product);
                  },
                ),
              ),

              // 3. Bottom Expandable Cart Panel (Persis Mockup Screen 3: "Keranjang (3)", "Hapus Semua", Steppers, "Bayar ->")
              _buildBottomCartPanel(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPosProductCard(BuildContext context, ProductModel product) {
    return InkWell(
      onTap: () => _onProductTapped(context, product),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ProductIllustrationWidget(
                    iconType: product.iconType,
                    imageUrl: product.imageUrl,
                    size: 56,
                  ),
                ),
                const Spacer(),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyDark,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  IdrCurrencyFormatter.format(product.sellingPrice),
                  style: AppTheme.moneyStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.slate800,
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
            // Blue Circle (+) Button at Bottom Right (Persis Mockup Screen 3)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 17),
              ),
            ),
            // Variant / Weight / FEFO Badge at Top Right
            if (product.type == 'variable' || product.soldByWeight)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    product.soldByWeight ? 'KG' : '${product.variants.length}V',
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCartPanel(BuildContext context, PosState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppColors.floatingCartShadow,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row: "Keranjang (3)" | Diskon/Hold | "🗑 Hapus Semua"
            Row(
              children: [
                Text(
                  'Keranjang (${IdrCurrencyFormatter.formatQty(state.totalItemsCount)})',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _showDiscountAndHoldModal(context, state),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      state.totalDiscount > 0
                          ? 'Diskon -${IdrCurrencyFormatter.format(state.totalDiscount)}'
                          : '+ Diskon / Hold',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (state.cart.isNotEmpty)
                  InkWell(
                    onTap: () => context.read<PosCubit>().clearCart(),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.danger),
                        SizedBox(width: 3),
                        Text(
                          'Hapus Semua',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Cart Items List (Constrained height so screen stays balanced like Mockup)
            if (state.cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Keranjang masih kosong. Ketuk produk di atas atau scan barcode.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.slate400),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 125),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: state.cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 10),
                  itemBuilder: (context, idx) {
                    final item = state.cart[idx];
                    return Row(
                      children: [
                        ProductIllustrationWidget(
                          iconType: item.product.iconType,
                          imageUrl: item.product.imageUrl,
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              Text(
                                '${IdrCurrencyFormatter.format(item.unitPrice)} × ${IdrCurrencyFormatter.formatQty(item.quantity)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.slate500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Stepper Pill: [ -  1  + ] (Persis Mockup Screen 3)
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => context.read<PosCubit>().decrementCartItem(idx),
                                borderRadius: BorderRadius.circular(999),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  child: Icon(Icons.remove_rounded, size: 16, color: AppColors.slate700),
                                ),
                              ),
                              Text(
                                IdrCurrencyFormatter.formatQty(item.quantity),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              InkWell(
                                onTap: () => context.read<PosCubit>().incrementCartItem(idx),
                                borderRadius: BorderRadius.circular(999),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  child: Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const Divider(height: 16),
            // Total Row: "Total" | "Rp 17.000"
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyDark,
                  ),
                ),
                Text(
                  IdrCurrencyFormatter.format(state.grandTotal),
                  style: AppTheme.moneyStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Full-Width Blue CTA Button: "Bayar ->" (Persis Mockup Screen 3)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: state.cart.isEmpty ? null : () => context.push('/pos/payment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Bayar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
