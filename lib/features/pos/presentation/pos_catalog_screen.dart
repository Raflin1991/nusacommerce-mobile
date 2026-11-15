import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/pos_cubit.dart';
import '../models/pos_models.dart';

/// LAYAR 3 — PENJUALAN BARU (POS CATALOG & FLOATING CART)
/// NusaCommerce Mobile Enterprise POS Catalog Screen
class PosCatalogScreen extends StatefulWidget {
  const PosCatalogScreen({super.key});

  @override
  State<PosCatalogScreen> createState() => _PosCatalogScreenState();
}

class _PosCatalogScreenState extends State<PosCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isListView = false;
  bool _isCartExpanded = false;

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
    final holdLabelCtrl = TextEditingController(
      text: state.selectedCustomer != null
          ? state.selectedCustomer!['name'].toString()
          : (state.selectedTable != null ? state.selectedTable!['name'].toString() : ''),
    );
    String discMode = 'rp'; // 'rp' | 'pct'

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                const Text(
                  'Diskon Global & Parkir Keranjang (Hold)',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    NusaPillFilter(
                      label: 'Nominal (Rp)',
                      selected: discMode == 'rp',
                      onTap: () => setModalState(() {
                        discMode = 'rp';
                        discountCtrl.clear();
                      }),
                    ),
                    const SizedBox(width: 8),
                    NusaPillFilter(
                      label: 'Persen (%)',
                      selected: discMode == 'pct',
                      onTap: () => setModalState(() {
                        discMode = 'pct';
                        discountCtrl.clear();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: discMode == 'rp' ? 'Diskon Nota (Rp)' : 'Diskon Nota (%)',
                    prefixIcon: const Icon(Icons.discount_outlined, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'PIN / Sandi Manajer (Wajib jika diskon > 15%)',
                    prefixIcon: Icon(Icons.verified_user_outlined, color: AppColors.warningDark),
                  ),
                ),
                const Divider(height: 24),
                TextField(
                  controller: holdLabelCtrl,
                  decoration: InputDecoration(
                    labelText: state.capabilities.hasTableManagement
                        ? 'Label Parkir Antrean (Misal: Ibu Sari / Meja 4)'
                        : 'Label Parkir Antrean (Misal: Ibu Sari / Antrean 2)',
                    prefixIcon: const Icon(Icons.bookmark_border_rounded, color: AppColors.warningDark),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          context.read<PosCubit>().holdCurrentCart(holdLabelCtrl.text);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Keranjang berhasil diparkir (Hold Cart).')),
                          );
                        },
                        icon: const Icon(Icons.pause_circle_outline_rounded),
                        label: const Text('Tahan (Hold)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final rawVal = double.tryParse(discountCtrl.text.replaceAll(',', '.').trim()) ??
                              IdrCurrencyFormatter.parse(discountCtrl.text);
                          final amt = discMode == 'pct'
                              ? (state.subtotal * (rawVal.clamp(0, 100) / 100.0)).roundToDouble()
                              : rawVal;
                          final posCubit = context.read<PosCubit>();
                          final pin = pinCtrl.text.trim();
                          if (pin.isNotEmpty) {
                            await posCubit.verifyManagerPin(pin, action: 'discount');
                          }
                          final ok = posCubit.applyCartDiscount(amt);
                          if (!ok) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: AppColors.danger,
                                  content: Text('Diskon > 15% memerlukan PIN / Sandi Manajer yang sah!'),
                                ),
                              );
                            }
                            return;
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Terapkan Diskon'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showHeldCartsSheet(BuildContext context, PosState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Antrean Keranjang Diparkir (${state.heldCarts.length})',
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (state.heldCarts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('Belum ada keranjang ditahan.', style: TextStyle(color: AppColors.slate500)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: state.heldCarts.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, idx) {
                    final held = state.heldCarts[idx];
                    final items = (held['cart_items'] as List?) ?? [];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.pause_circle_filled_rounded, color: AppColors.warningDark),
                      ),
                      title: Text(
                        (held['held_label'] ?? held['number'] ?? 'Antrean').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${held['held_at'] ?? ''} • ${items.length} item • ${IdrCurrencyFormatter.format((held['subtotal'] as num?) ?? 0)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          context.read<PosCubit>().resumeHeldCart(idx);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Buka'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEditCartItemModal(BuildContext context, int idx, CartItemModel item) {
    final qtyCtrl = TextEditingController(text: IdrCurrencyFormatter.formatQty(item.quantity));
    final discCtrl = TextEditingController(
      text: item.discountAmount > 0 ? item.discountAmount.toInt().toString() : '',
    );
    final noteCtrl = TextEditingController(text: item.notes ?? '');
    final pinCtrl = TextEditingController();
    String discMode = 'rp';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                  item.displayName,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Harga Satuan: ${IdrCurrencyFormatter.format(item.unitPrice)} / ${item.product.unitCode}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Kuantitas (Mendukung desimal misal 0.5)',
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    NusaPillFilter(
                      label: 'Diskon Item (Rp)',
                      selected: discMode == 'rp',
                      onTap: () => setModalState(() {
                        discMode = 'rp';
                        discCtrl.clear();
                      }),
                    ),
                    const SizedBox(width: 8),
                    NusaPillFilter(
                      label: 'Diskon Item (%)',
                      selected: discMode == 'pct',
                      onTap: () => setModalState(() {
                        discMode = 'pct';
                        discCtrl.clear();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: discCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: discMode == 'rp' ? 'Diskon Item (Rp)' : 'Diskon Item (%)',
                    prefixIcon: const Icon(Icons.local_offer_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN Manajer (Wajib jika diskon > 15%)',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan Item (Opsional)',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        context.read<PosCubit>().removeCartItem(idx);
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Hapus'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final parsedQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim()) ?? item.quantity;
                          final rawDisc = double.tryParse(discCtrl.text.replaceAll(',', '.').trim()) ??
                              IdrCurrencyFormatter.parse(discCtrl.text);
                          final lineSub = parsedQty * item.unitPrice;
                          final discRp = discMode == 'pct'
                              ? (lineSub * (rawDisc.clamp(0, 100) / 100.0)).roundToDouble()
                              : rawDisc;

                          final posCubit = context.read<PosCubit>();
                          if (discRp > lineSub * 0.15 && !posCubit.state.managerDiscountApproved) {
                            final pin = pinCtrl.text.trim();
                            final verified = pin.isNotEmpty
                                ? await posCubit.verifyManagerPin(pin, action: 'discount')
                                : false;
                            if (!verified) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text('Diskon item > 15% butuh PIN Manajer yang sah!'),
                                  ),
                                );
                              }
                              return;
                            }
                          }

                          posCubit.updateCartItemDetails(
                            idx,
                            quantity: parsedQty,
                            discountAmount: discRp.clamp(0, lineSub),
                            notes: noteCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: const Text('Simpan Item'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomerSelectorSheet(BuildContext context, PosState state) {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final q = searchCtrl.text.trim().toLowerCase();
          final filtered = state.customers.where((c) {
            if (q.isEmpty) return true;
            final name = (c['name'] ?? '').toString().toLowerCase();
            final phone = (c['phone'] ?? '').toString().toLowerCase();
            final code = (c['code'] ?? '').toString().toLowerCase();
            return name.contains(q) || phone.contains(q) || code.contains(q);
          }).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.9,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pilih Pelanggan / Member',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showQuickAddCustomerModal(context);
                        },
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                        label: const Text('Tambah Baru'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setModalState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama, nomor HP/WA, atau kode member...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(Icons.person_outline_rounded, color: AppColors.slate600),
                    ),
                    title: const Text('Pelanggan Umum (Guest)', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Tanpa diskon member / kasbon', style: TextStyle(fontSize: 12)),
                    trailing: state.selectedCustomer == null
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                        : null,
                    onTap: () {
                      context.read<PosCubit>().selectCustomer(null);
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Belum ada pelanggan cocok. Tekan "Tambah Baru" untuk mendaftarkan member.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.slate500),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 10),
                            itemBuilder: (_, idx) {
                              final c = filtered[idx];
                              final groupName = c['group_name']?.toString();
                              final discPct = (c['default_discount_percent'] as num?)?.toDouble() ?? 0;
                              final pts = (c['loyalty_points'] as num?)?.toInt() ?? 0;
                              final limit = (c['credit_limit'] as num?)?.toDouble() ?? 0;
                              final used = (c['outstanding_balance'] as num?)?.toDouble() ?? 0;
                              final remaining = (limit - used).clamp(0, double.infinity);

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                onTap: () {
                                  context.read<PosCubit>().selectCustomer(c);
                                  Navigator.pop(ctx);
                                },
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primarySoft,
                                  child: Text(
                                    (c['name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c['name'].toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                    ),
                                    if (groupName != null && groupName.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primarySoft,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          discPct > 0 ? '$groupName • ${discPct.toInt()}%' : groupName,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${c['phone'] ?? '-'} • $pts Poin'
                                  '${limit > 0 ? ' • Sisa Limit: ${IdrCurrencyFormatter.format(remaining)}' : ''}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
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
      ),
    );
  }

  void _showQuickAddCustomerModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final bizCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '0');

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
            const Text('Tambah Pelanggan Baru', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama Lengkap *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Nomor HP / WhatsApp *'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: bizCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Toko / Bisnis'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: limitCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Batas Limit Kasbon (Rp)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) return;
                  final res = await context.read<PosCubit>().saveCustomer(
                    {
                      'name': nameCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'business_name': bizCtrl.text.trim(),
                      'credit_limit': IdrCurrencyFormatter.parse(limitCtrl.text),
                    },
                    selectAfterSave: true,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: res['success'] == true ? AppColors.successDark : AppColors.danger,
                        content: Text(
                          res['success'] == true
                              ? 'Pelanggan ${nameCtrl.text.trim()} disimpan & dipilih.'
                              : (res['message']?.toString() ?? 'Gagal menambah pelanggan.'),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Simpan & Pilih Pelanggan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRedeemPointsDialog(BuildContext context, PosState state) {
    final cust = state.selectedCustomer;
    if (cust == null) return;
    final availablePts = (cust['loyalty_points'] as num?)?.toInt() ?? 0;
    final ctrl = TextEditingController(
      text: state.redeemedLoyaltyPoints > 0 ? state.redeemedLoyaltyPoints.toString() : availablePts.toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tukar Poin Loyalitas', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo poin ${cust['name']}: $availablePts Poin (1 Poin = Rp 100)'),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jumlah Poin Ditukar'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<PosCubit>().setRedeemedLoyaltyPoints(0);
              Navigator.pop(ctx);
            },
            child: const Text('Reset 0'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = int.tryParse(ctrl.text.trim()) ?? 0;
              final clamped = raw.clamp(0, availablePts);
              context.read<PosCubit>().setRedeemedLoyaltyPoints(clamped);
              Navigator.pop(ctx);
            },
            child: const Text('Pakai Poin'),
          ),
        ],
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
        final activeStore = context.watch<AuthCubit>().state.session.activeStore;
        final capabilities = state.capabilities;
        final screenWidth = MediaQuery.of(context).size.width;
        final gridColumns = screenWidth >= 960
            ? 4
            : (screenWidth >= 600 ? 3 : 2);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
            ),
            titleSpacing: 4,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capabilities.posDisplayName,
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                ),
                Text(
                  capabilities.hasTableManagement && state.selectedTable != null
                      ? 'Meja: ${state.selectedTable!['name']} (${state.selectedTable!['section']})'
                      : activeStore.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: (capabilities.hasTableManagement && state.selectedTable != null)
                        ? AppColors.primary
                        : AppColors.slate500,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              // Quick Shift Status Pill
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  onTap: () => context.push('/shifts'),
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.success.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 7, color: AppColors.success),
                            SizedBox(width: 4),
                            Text(
                              'Shift',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.successDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Held Carts Badge -> opens Held Carts Picker Sheet
              if (state.heldCarts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => _showHeldCartsSheet(context, state),
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.warningSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.pause_circle_outline_rounded, size: 14, color: AppColors.warningDark),
                              const SizedBox(width: 4),
                              Text(
                                '${state.heldCarts.length}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.warningDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Restaurant Mode Switcher Button (Capabilities-Driven)
              if (capabilities.hasTableManagement)
                IconButton(
                  tooltip: 'Denah Meja Restoran (F&B)',
                  onPressed: () => context.push('/restaurant'),
                  icon: const Icon(Icons.table_restaurant_outlined, color: AppColors.slate700),
                ),
              // Sync with Cloud Button
              IconButton(
                tooltip: 'Sinkronkan Data Cloud',
                onPressed: () async {
                  await context.read<PosCubit>().syncWithCloud(force: false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Katalog berhasil disinkronkan dengan server Cloud.')),
                    );
                  }
                },
                icon: Icon(
                  state.isLoading ? Icons.sync_rounded : Icons.cloud_done_outlined,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. Compact Operational Bar (Customer + Sync), Fixed Search/Scan & Category Chips
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildCustomerStatusBar(context, state)),
                        const SizedBox(width: 8),
                        NusaSyncStatusPill(
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Contextual Vertical Metadata Bar (Apotek: Resep/Dokter, Bengkel: Nopol/Mekanik, Laundry: Timbangan/Rak)
                    if (capabilities.hasPrescriptionWorkflow ||
                        capabilities.hasVehicleWorkOrder ||
                        capabilities.hasLaundryOrderMetadata) ...[
                      _buildVerticalMetadataBar(context, state),
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
                                  selectedColor: AppColors.navyDark,
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
                              onChanged: (val) {
                                setState(() {});
                                context.read<PosCubit>().updateSearchQuery(val);
                              },
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: 'Cari nama, barcode, atau SKU...',
                                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.slate400),
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
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _openCameraBarcodeScanner(context),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                                ),
                                child: const Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: AppColors.primary,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: _isListView ? 'Tampilan Grid' : 'Tampilan Daftar',
                          child: Material(
                            color: AppColors.slate100,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => setState(() => _isListView = !_isListView),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Icon(
                                  _isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
                                  color: AppColors.navyDark,
                                  size: 21,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Dynamic Database Category Chips (Compact & Zero Clipping)
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: state.categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, idx) {
                          final cat = state.categories[idx];
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
                  ],
                ),
              ),

              if (state.isExchangeMode)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    border: Border(
                      bottom: BorderSide(color: AppColors.warning.withOpacity(0.45)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.warningDark),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Mode Tukar Barang • Nota ${state.exchangeSourceSale?['number'] ?? '-'}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.warningDark,
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
                                border: Border.all(color: AppColors.warning.withOpacity(0.5)),
                              ),
                              child: const Text(
                                'Batal Tukar',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.dangerDark,
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
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navyDark,
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. Product Catalog Area (Grid or List View)
              Expanded(
                child: state.filteredProducts.isEmpty
                    ? NusaEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'Produk Tidak Ditemukan',
                        subtitle: 'Tidak ada produk yang cocok dengan filter atau kata kunci pencarian.',
                        actionLabel: 'Reset Filter',
                        onAction: () {
                          _searchController.clear();
                          setState(() {});
                          context.read<PosCubit>().updateSearchQuery('');
                          context.read<PosCubit>().selectCategory(0);
                        },
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
                              mainAxisExtent: screenWidth >= 600 ? 242 : 234,
                            ),
                            itemCount: state.filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = state.filteredProducts[index];
                              return _buildPosProductCard(context, state, product);
                            },
                          ),
              ),

              // 3. Thumb-Zone Sticky Expandable Cart Panel
              _buildBottomCartPanel(context, state),
            ],
          ),
        );
      },
    );
  }

  double _productQtyInCart(PosState state, int productId) {
    return state.cart
        .where((item) => item.product.id == productId)
        .fold(0.0, (sum, item) => sum + item.quantity);
  }

  Widget _buildPosProductCard(BuildContext context, PosState state, ProductModel product) {
    final inCartQty = _productQtyInCart(state, product.id);
    final hasInCart = inCartQty > 0;
    final outOfStock = product.stock <= 0;
    final cartIdx = hasInCart ? state.cart.lastIndexWhere((c) => c.product.id == product.id) : -1;

    final String stockMeta = product.sku.isNotEmpty
        ? '${product.sku} • Stok ${IdrCurrencyFormatter.formatQty(product.stock)}'
        : 'Stok ${IdrCurrencyFormatter.formatQty(product.stock)} ${product.unitCode}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onProductTapped(context, product),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasInCart ? AppColors.primary : AppColors.border,
              width: hasInCart ? 1.6 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Full-Width High-Clarity Product Showcase Frame (118dp)
              SizedBox(
                height: 118,
                width: double.infinity,
                child: Stack(
                  children: [
                    ProductIllustrationWidget(
                      iconType: product.iconType,
                      imageUrl: product.imageUrl,
                      width: double.infinity,
                      height: 118,
                      showBorder: false,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                      fit: BoxFit.contain,
                    ),
                    // Top-Left Active Cart Counter Pill
                    if (hasInCart)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '×${IdrCurrencyFormatter.formatQty(inCartQty)}',
                            style: AppTheme.moneyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // Top-Right Quick Undo (-1) when in cart OR Variant / Weight Pill
                    if (hasInCart && cartIdx >= 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: Colors.white.withOpacity(0.95),
                          shape: const CircleBorder(
                            side: BorderSide(color: AppColors.border),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => context.read<PosCubit>().decrementCartItem(cartIdx),
                            child: const SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(
                                Icons.remove_rounded,
                                size: 16,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (product.type == 'variable' || product.soldByWeight)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: Text(
                            product.soldByWeight ? 'KG' : '${product.variants.length} Varian',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
              // 2. Structured Typography & Action Footer (Zero Dead Space)
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: hasInCart ? AppColors.primarySoft.withOpacity(0.28) : Colors.white,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navyDark,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stockMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: outOfStock
                              ? AppColors.dangerDark.withOpacity(0.85)
                              : (product.isLowStock ? AppColors.warningDark : AppColors.slate500),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: NusaPriceTag(
                              amount: product.sellingPrice,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: hasInCart ? AppColors.successDark : AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(9),
                              border: hasInCart
                                  ? null
                                  : Border.all(color: AppColors.primary.withOpacity(0.25)),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              color: hasInCart ? Colors.white : AppColors.primary,
                              size: 19,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosProductListTile(BuildContext context, PosState state, ProductModel product) {
    final inCartQty = _productQtyInCart(state, product.id);
    final hasInCart = inCartQty > 0;
    final outOfStock = product.stock <= 0;

    return NusaCard(
      padding: const EdgeInsets.all(10),
      borderColor: hasInCart ? AppColors.primary : AppColors.border,
      borderWidth: hasInCart ? 1.5 : 1.0,
      backgroundColor: hasInCart ? AppColors.primarySoft.withOpacity(0.2) : Colors.white,
      onTap: () => _onProductTapped(context, product),
      child: Row(
        children: [
          ProductIllustrationWidget(
            iconType: product.iconType,
            imageUrl: product.imageUrl,
            size: 64,
            fit: BoxFit.contain,
            padding: const EdgeInsets.all(4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navyDark,
                        ),
                      ),
                    ),
                    if (hasInCart) ...[
                      const SizedBox(width: 6),
                      NusaBadge(
                        label: '×${IdrCurrencyFormatter.formatQty(inCartQty)}',
                        variant: NusaBadgeVariant.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'SKU: ${product.sku} • Stok: ${IdrCurrencyFormatter.formatQty(product.stock)} ${product.unitCode}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? AppColors.dangerDark.withOpacity(0.85)
                        : (product.isLowStock ? AppColors.warningDark : AppColors.slate500),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    NusaPriceTag(
                      amount: product.sellingPrice,
                      fontSize: 15,
                      color: AppColors.navyDark,
                    ),
                    if (product.type == 'variable') ...[
                      const SizedBox(width: 8),
                      NusaBadge(
                        label: '${product.variants.length} Varian',
                        variant: NusaBadgeVariant.neutral,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: hasInCart ? AppColors.successDark : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(11),
              border: hasInCart ? null : Border.all(color: AppColors.primary.withOpacity(0.25)),
            ),
            child: Icon(
              Icons.add_rounded,
              color: hasInCart ? Colors.white : AppColors.primary,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  void _showVerticalMetadataSheet(BuildContext context, PosState state) {
    final caps = state.capabilities;
    final String title;
    final String primaryLabel;
    final String primaryHint;
    final String secondaryLabel;
    final String secondaryHint;
    final IconData icon;

    if (caps.hasPrescriptionWorkflow) {
      title = 'Data Resep & Farmasi (Apotek)';
      primaryLabel = 'Nomor Resep / RM';
      primaryHint = 'Contoh: RX-2026-0142';
      secondaryLabel = 'Nama Dokter / Pasien';
      secondaryHint = 'Contoh: dr. Andi (Pasien Tn. Budi)';
      icon = Icons.medication_outlined;
    } else if (caps.hasVehicleWorkOrder) {
      title = 'Data Kendaraan & PKB (Bengkel)';
      primaryLabel = 'Nomor Polisi / Plat';
      primaryHint = 'Contoh: B 1234 XYZ';
      secondaryLabel = 'Mekanik & Keluhan / Servis';
      secondaryHint = 'Contoh: Mekanik Agung • Ganti Oli & Tune Up';
      icon = Icons.build_circle_outlined;
    } else {
      title = 'Detail Order & Rak (Laundry)';
      primaryLabel = 'Berat (Kg) / Jenis Layanan';
      primaryHint = 'Contoh: 4.5 Kg • Cuci Setrika Ekspres';
      secondaryLabel = 'Nomor Rak / Estimasi Selesai';
      secondaryHint = 'Contoh: Rak B-04 • Selesai Besok 17:00';
      icon = Icons.local_laundry_service_outlined;
    }

    final existing = state.orderNotes ?? '';
    final parts = existing.split(' • ');
    final field1Ctrl = TextEditingController(text: parts.isNotEmpty ? parts[0] : '');
    final field2Ctrl = TextEditingController(
      text: parts.length > 1 ? parts.sublist(1).join(' • ') : '',
    );

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
            Row(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: field1Ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: primaryLabel,
                hintText: primaryHint,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: field2Ctrl,
              decoration: InputDecoration(
                labelText: secondaryLabel,
                hintText: secondaryHint,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (existing.isNotEmpty)
                  OutlinedButton(
                    onPressed: () {
                      context.read<PosCubit>().setOrderNotes(null);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Hapus'),
                  ),
                if (existing.isNotEmpty) const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () {
                        final p1 = field1Ctrl.text.trim();
                        final p2 = field2Ctrl.text.trim();
                        final combined = [p1, p2].where((s) => s.isNotEmpty).join(' • ');
                        context.read<PosCubit>().setOrderNotes(combined);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Simpan Info Order'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalMetadataBar(BuildContext context, PosState state) {
    final caps = state.capabilities;
    final hasNotes = state.orderNotes != null && state.orderNotes!.trim().isNotEmpty;
    final IconData icon;
    final String emptyLabel;
    if (caps.hasPrescriptionWorkflow) {
      icon = Icons.medication_outlined;
      emptyLabel = 'Tambah No. Resep & Nama Dokter (Apotek)';
    } else if (caps.hasVehicleWorkOrder) {
      icon = Icons.directions_car_outlined;
      emptyLabel = 'Input No. Polisi Kendaraan & Mekanik (PKB)';
    } else {
      icon = Icons.local_laundry_service_outlined;
      emptyLabel = 'Input Berat Cucian (Kg) & Nomor Rak (Laundry)';
    }

    return InkWell(
      onTap: () => _showVerticalMetadataSheet(context, state),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hasNotes ? AppColors.primarySoft : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasNotes ? AppColors.primary.withOpacity(0.35) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: hasNotes ? AppColors.primary : AppColors.slate600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasNotes ? state.orderNotes! : emptyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasNotes ? FontWeight.w700 : FontWeight.w600,
                  color: hasNotes ? AppColors.navyDark : AppColors.slate600,
                ),
              ),
            ),
            Icon(
              hasNotes ? Icons.edit_outlined : Icons.add_circle_outline_rounded,
              size: 16,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerStatusBar(BuildContext context, PosState state) {
    final cust = state.selectedCustomer;
    if (cust == null) {
      return Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _showCustomerSelectorSheet(context, state),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.slate600),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Pelanggan Umum',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.slate500),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: AppColors.border,
                ),
                Tooltip(
                  message: 'Member Baru',
                  child: InkWell(
                    onTap: () => _showQuickAddCustomerModal(context),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.person_add_alt_1_outlined, size: 16, color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final groupName = cust['group_name']?.toString() ?? 'Member';
    final discPct = (cust['default_discount_percent'] as num?)?.toDouble() ?? 0;
    final pts = (cust['loyalty_points'] as num?)?.toInt() ?? 0;

    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _showCustomerSelectorSheet(context, state),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withOpacity(0.28)),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  discPct > 0
                      ? '${cust['name']} (-${discPct.toInt()}%)'
                      : '${cust['name']} ($groupName)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                ),
              ),
              if (pts > 0) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _showRedeemPointsDialog(context, state),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: state.redeemedLoyaltyPoints > 0 ? AppColors.success : AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      state.redeemedLoyaltyPoints > 0
                          ? '-${state.redeemedLoyaltyPoints}p'
                          : '${pts}p',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: state.redeemedLoyaltyPoints > 0 ? Colors.white : AppColors.warningDark,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              InkWell(
                onTap: () => context.read<PosCubit>().selectCustomer(null),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 15, color: AppColors.slate600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCartPanel(BuildContext context, PosState state) {
    final hasItems = state.cart.isNotEmpty;
    final String summaryPreview = !hasItems
        ? 'Pilih produk untuk mulai transaksi'
        : state.cart.length == 1
            ? state.cart.first.displayName
            : '${state.cart.first.displayName} (+${state.cart.length - 1} lainnya)';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppColors.floatingCartShadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row: Interactive Expandable Cart Summary | Diskon | Hapus
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: hasItems ? () => setState(() => _isCartExpanded = !_isCartExpanded) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasItems ? AppColors.primary : AppColors.slate200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              IdrCurrencyFormatter.formatQty(state.totalItemsCount),
                              style: AppTheme.moneyStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: hasItems ? Colors.white : AppColors.slate600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isCartExpanded ? 'Rincian Keranjang' : summaryPreview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: hasItems ? AppColors.navyDark : AppColors.slate400,
                              ),
                            ),
                          ),
                          if (hasItems)
                            Icon(
                              _isCartExpanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_up_rounded,
                              size: 20,
                              color: AppColors.slate600,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasItems) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _showDiscountAndHoldModal(context, state),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: state.totalDiscount > 0 ? AppColors.successSoft : AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        state.totalDiscount > 0
                            ? 'Disc -${IdrCurrencyFormatter.formatCompact(state.totalDiscount)}'
                            : '+ Diskon',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: state.totalDiscount > 0 ? AppColors.successDark : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      context.read<PosCubit>().clearCart();
                      setState(() => _isCartExpanded = false);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      child: Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                    ),
                  ),
                ],
              ],
            ),

            // Animated Expandable Cart Items List (Hidden cleanly until expanded)
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: (!hasItems || !_isCartExpanded)
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 168),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: state.cart.length,
                          separatorBuilder: (_, __) => const Divider(height: 8, color: AppColors.divider),
                          itemBuilder: (context, idx) {
                            final item = state.cart[idx];
                            return Row(
                              children: [
                                ProductIllustrationWidget(
                                  iconType: item.product.iconType,
                                  imageUrl: item.product.imageUrl,
                                  size: 36,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: item.isExchangeReturn
                                        ? null
                                        : () => _showEditCartItemModal(context, idx, item),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.navyDark,
                                                ),
                                              ),
                                            ),
                                            if (item.isExchangeReturn) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warningSoft,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: AppColors.warning.withOpacity(0.45),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'RETUR / TUKAR',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.warningDark,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (!item.isExchangeReturn &&
                                                state.capabilities.hasWholesaleMultiUnit &&
                                                item.product.unitConversions.length > 1) ...[
                                              const SizedBox(width: 6),
                                              InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: () {
                                                  showModalBottomSheet<void>(
                                                    context: context,
                                                    shape: const RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                                    ),
                                                    builder: (sheetCtx) => SafeArea(
                                                      child: Padding(
                                                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              'Pilih Satuan • ${item.displayName}',
                                                              style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.w800,
                                                                color: AppColors.navyDark,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 4),
                                                            const Text(
                                                              'Harga & pengurangan stok otomatis mengikuti konversi satuan.',
                                                              style: TextStyle(fontSize: 12, color: AppColors.slate500),
                                                            ),
                                                            const SizedBox(height: 12),
                                                            ...item.product.unitConversions.map((u) {
                                                              final selected = u.unitCode.toUpperCase() ==
                                                                  item.effectiveUnitCode.toUpperCase();
                                                              return Padding(
                                                                padding: const EdgeInsets.only(bottom: 8),
                                                                child: InkWell(
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  onTap: () {
                                                                    context.read<PosCubit>().changeCartItemUnit(idx, u);
                                                                    Navigator.of(sheetCtx).pop();
                                                                  },
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal: 14,
                                                                      vertical: 12,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: selected
                                                                          ? AppColors.primary.withOpacity(0.08)
                                                                          : Colors.white,
                                                                      borderRadius: BorderRadius.circular(12),
                                                                      border: Border.all(
                                                                        color: selected
                                                                            ? AppColors.primary
                                                                            : AppColors.border,
                                                                        width: selected ? 1.5 : 1,
                                                                      ),
                                                                    ),
                                                                    child: Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child: Column(
                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                            children: [
                                                                              Text(
                                                                                '${u.unitName} (${u.unitCode.toUpperCase()})',
                                                                                style: TextStyle(
                                                                                  fontSize: 13.5,
                                                                                  fontWeight: FontWeight.w800,
                                                                                  color: selected
                                                                                      ? AppColors.primary
                                                                                      : AppColors.navyDark,
                                                                                ),
                                                                              ),
                                                                              Text(
                                                                                '1 ${u.unitCode.toUpperCase()} = ${IdrCurrencyFormatter.formatQty(u.multiplier)} ${item.product.unitCode.toUpperCase()}',
                                                                                style: const TextStyle(
                                                                                  fontSize: 11.5,
                                                                                  color: AppColors.slate500,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        Text(
                                                                          IdrCurrencyFormatter.format(u.price),
                                                                          style: TextStyle(
                                                                            fontSize: 13.5,
                                                                            fontWeight: FontWeight.w800,
                                                                            color: selected
                                                                                ? AppColors.primary
                                                                                : AppColors.navyDark,
                                                                          ),
                                                                        ),
                                                                        if (selected) ...[
                                                                          const SizedBox(width: 8),
                                                                          const Icon(
                                                                            Icons.check_circle_rounded,
                                                                            color: AppColors.primary,
                                                                            size: 18,
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            }),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: AppColors.primary.withOpacity(0.3),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        item.effectiveUnitCode.toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w800,
                                                          color: AppColors.primary,
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons.arrow_drop_down_rounded,
                                                        size: 14,
                                                        color: AppColors.primary,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          '${IdrCurrencyFormatter.format(item.unitPrice)} × ${IdrCurrencyFormatter.formatQty(item.quantity)} ${item.effectiveUnitCode}'
                                          '${item.discountAmount > 0 ? ' • Disc -${IdrCurrencyFormatter.format(item.discountAmount)}' : ''}'
                                          '${item.notes != null && item.notes!.isNotEmpty ? ' • ${item.notes}' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.slate500,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (item.isExchangeReturn)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.warning.withOpacity(0.45)),
                                    ),
                                    child: Text(
                                      '-${IdrCurrencyFormatter.format(item.lineTotal.abs())}',
                                      style: AppTheme.moneyStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.warningDark,
                                      ),
                                    ),
                                  )
                                else
                                  // Compact Ergonomic Stepper
                                  Container(
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: AppColors.slate100,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => context.read<PosCubit>().decrementCartItem(idx),
                                          borderRadius: BorderRadius.circular(10),
                                          child: const SizedBox(
                                            width: 34,
                                            height: 34,
                                            child: Icon(Icons.remove_rounded, size: 16, color: AppColors.slate700),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Text(
                                            IdrCurrencyFormatter.formatQty(item.quantity),
                                            style: AppTheme.moneyStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.navyDark,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => context.read<PosCubit>().incrementCartItem(idx),
                                          borderRadius: BorderRadius.circular(10),
                                          child: const SizedBox(
                                            width: 34,
                                            height: 34,
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
                    ),
            ),

            const Divider(height: 12, color: AppColors.divider),
            // Sticky Thumb-Zone Action Row: Total Tagihan + [Hold] + [Bayar ->] (>= 48dp)
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isExchangeMode && state.exchangeSurplusCredit > 0
                            ? 'Kelebihan Retur'
                            : 'Total Tagihan',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: state.isExchangeMode && state.exchangeSurplusCredit > 0
                              ? AppColors.primary
                              : AppColors.slate500,
                        ),
                      ),
                      NusaPriceTag(
                        amount: state.isExchangeMode && state.exchangeSurplusCredit > 0
                            ? state.exchangeSurplusCredit
                            : state.grandTotal,
                        fontSize: 18,
                        color: state.isExchangeMode && state.exchangeSurplusCredit > 0
                            ? AppColors.primary
                            : AppColors.navyDark,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: hasItems ? () => _showDiscountAndHoldModal(context, state) : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    icon: const Icon(Icons.pause_rounded, size: 18),
                    label: const Text('Hold', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: NusaButton(
                    label: 'Bayar',
                    trailingIcon: Icons.arrow_forward_rounded,
                    minHeight: 48,
                    onPressed: hasItems ? () => context.push('/pos/payment') : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
