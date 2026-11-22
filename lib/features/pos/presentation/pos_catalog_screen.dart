import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/barcode_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_barcode_scanner_view.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/pos_cubit.dart';
import '../models/pos_models.dart';

/// LAYAR 3 — PENJUALAN BARU (POS CATALOG & FLOATING CART)
/// OXO.ID Mobile Enterprise POS Catalog Screen
class PosCatalogScreen extends StatefulWidget {
  const PosCatalogScreen({super.key});

  @override
  State<PosCatalogScreen> createState() => _PosCatalogScreenState();
}

class _PosCatalogScreenState extends State<PosCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _hardwareScannerFocusNode = FocusNode(skipTraversal: true);
  final HardwareBarcodeWedgeBuffer _wedgeBuffer = HardwareBarcodeWedgeBuffer();
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
    _hardwareScannerFocusNode.dispose();
    super.dispose();
  }

  void _handleHardwareScannerKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText) return;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    final scanned = _wedgeBuffer.onKeyCharacter(
      character: event.character,
      isEnter: isEnter,
    );
    if (scanned != null && scanned.isNotEmpty) {
      final ok = context.read<PosCubit>().handleBarcodeScanned(scanned);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('Scanner HID: $scanned ditambahkan ke keranjang.'),
          ),
        );
      }
    }
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in const ['0.25', '0.5', '1.0', '1.5', '2.0'])
                  ActionChip(
                    label: Text(
                      '$preset ${product.unitCode}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      ctrl.text = preset;
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                child: NusaBarcodeScannerView(
                  onDetect: (code) {
                    final ok = context.read<PosCubit>().handleBarcodeScanned(code);
                    Navigator.pop(ctx);
                    if (ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Barcode $code berhasil ditambahkan!')),
                      );
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
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                        modalError = null;
                        discountCtrl.clear();
                      }),
                    ),
                    const SizedBox(width: 8),
                    NusaPillFilter(
                      label: 'Persen (%)',
                      selected: discMode == 'pct',
                      onTap: () => setModalState(() {
                        discMode = 'pct';
                        modalError = null;
                        discountCtrl.clear();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final pct in const [5, 10, 15, 20])
                      NusaPillFilter(
                        label: '$pct%',
                        selected: discMode == 'pct' && discountCtrl.text.trim() == '$pct',
                        onTap: () => setModalState(() {
                          discMode = 'pct';
                          modalError = null;
                          discountCtrl.text = '$pct';
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: discountCtrl,
                  onChanged: (_) {
                    if (modalError != null) setModalState(() => modalError = null);
                  },
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
                  onChanged: (_) {
                    if (modalError != null) setModalState(() => modalError = null);
                  },
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
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modalError!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dangerDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                            setModalState(() {
                              modalError = 'Diskon > 15% memerlukan PIN / Sandi Manajer yang sah!';
                            });
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
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final posCubit = context.read<PosCubit>();
          final filteredHeld = posCubit.searchHeldCarts(searchCtrl.text);
          return Padding(
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
                Text(
                  'Antrean Keranjang Diparkir (${state.heldCarts.length})',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
                if (state.cart.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                    ),
                    child: Text(
                      'Keranjang aktif (${state.cart.length} item) akan otomatis diparkir agar tidak hilang saat membuka antrean.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ),
                ],
                if (state.heldCarts.length > 1) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setModalState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama pelanggan, label, atau meja...',
                      prefixIcon: Icon(Icons.search_rounded, size: 19),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (filteredHeld.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      state.heldCarts.isEmpty
                          ? 'Belum ada keranjang ditahan.'
                          : 'Antrean tidak ditemukan untuk pencarian "${searchCtrl.text}".',
                      style: const TextStyle(color: AppColors.slate500),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredHeld.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (_, idx) {
                        final held = filteredHeld[idx];
                        final originalIndex = state.heldCarts.indexOf(held);
                        final items = (held['cart_items'] as List?) ?? [];
                        final custName = (held['customer_name'] ?? '').toString();
                        final tableName = (held['table_name'] ?? '').toString();
                        final metaParts = [
                          if (custName.isNotEmpty && custName != 'Pelanggan Umum') custName,
                          if (tableName.isNotEmpty) 'Meja $tableName',
                          if ((held['held_at'] ?? '').toString().isNotEmpty) '${held['held_at']}',
                          '${items.length} item',
                          IdrCurrencyFormatter.format((held['subtotal'] as num?) ?? 0),
                        ];
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
                            metaParts.join(' • '),
                            style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Hapus Antrean',
                                onPressed: () {
                                  if (originalIndex >= 0) {
                                    posCubit.deleteHeldCart(originalIndex);
                                    setModalState(() {});
                                  }
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.danger,
                                  size: 20,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  if (originalIndex >= 0) {
                                    posCubit.resumeHeldCart(originalIndex);
                                  }
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Buka'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditCartItemModal(BuildContext context, int idx, CartItemModel item) {
    final qtyCtrl = TextEditingController(text: IdrCurrencyFormatter.formatQty(item.quantity));
    final discCtrl = TextEditingController(
      text: item.discountAmount > 0 ? item.discountAmount.toInt().toString() : '',
    );
    final noteCtrl = TextEditingController(text: item.notes ?? '');
    final stylistCtrl = TextEditingController(text: item.stylistName ?? '');
    final pinCtrl = TextEditingController();
    final posState = context.read<PosCubit>().state;
    final isSalonMode = posState.capabilities.hasSalonStylistWorkflow;
    final isLaundryMode = posState.capabilities.hasLaundryOrderMetadata;
    bool isExpressLaundry = (item.notes ?? '').toLowerCase().contains('express');
    double effectiveUnitPrice = item.unitPrice;
    String discMode = 'rp';
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                  'Harga Satuan: ${IdrCurrencyFormatter.format(effectiveUnitPrice)} / ${item.product.unitCode}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: isLaundryMode
                        ? 'Berat / Kuantitas Desimal (misal 2.4 kg)'
                        : 'Kuantitas (Mendukung desimal misal 0.5)',
                    prefixIcon: const Icon(Icons.scale_outlined),
                  ),
                ),
                if (isLaundryMode) ...[
                  const SizedBox(height: 10),
                  NusaPillFilter(
                    label: 'Layanan Express (+Rp 5.000 / ${item.effectiveUnitCode})',
                    icon: Icons.bolt_rounded,
                    selected: isExpressLaundry,
                    selectedColor: AppColors.warningDark,
                    onTap: () {
                      setModalState(() {
                        isExpressLaundry = !isExpressLaundry;
                        if (isExpressLaundry) {
                          effectiveUnitPrice += 5000.0;
                          if (!noteCtrl.text.contains('[Express]')) {
                            noteCtrl.text = ('[Express] ${noteCtrl.text}').trim();
                          }
                        } else {
                          effectiveUnitPrice = (effectiveUnitPrice - 5000.0).clamp(0.0, double.infinity);
                          noteCtrl.text = noteCtrl.text.replaceAll('[Express]', '').trim();
                        }
                      });
                    },
                  ),
                ],
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final chip in const [
                      'Tanpa Gula',
                      'Es Sedikit',
                      'Bungkus Pisah',
                      'Pedas',
                      'Tanpa Es',
                    ])
                      ActionChip(
                        label: Text(chip, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        onPressed: () {
                          setModalState(() {
                            final cur = noteCtrl.text.trim();
                            if (cur.isEmpty) {
                              noteCtrl.text = chip;
                            } else if (!cur.toLowerCase().contains(chip.toLowerCase())) {
                              noteCtrl.text = '$cur, $chip';
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan Item (Opsional)',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                if (isSalonMode) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Kapster / Stylist / Terapis',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in const ['Rina (Senior)', 'Andi (Barber)', 'Siska (Terapis)', 'Budi (Kapster)'])
                        NusaPillFilter(
                          label: name,
                          selected: stylistCtrl.text.trim() == name,
                          onTap: () => setModalState(() => stylistCtrl.text = name),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stylistCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Kapster / Stylist',
                      hintText: 'Pilih chip di atas atau ketik nama kapster...',
                      prefixIcon: Icon(Icons.content_cut_rounded),
                    ),
                  ),
                ],
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modalError!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dangerDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                          final lineSub = (parsedQty * effectiveUnitPrice).roundToDouble();
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
                              setModalState(() {
                                modalError = 'Diskon item > 15% butuh PIN Manajer yang sah!';
                              });
                              return;
                            }
                          }

                          posCubit.updateCartItemDetails(
                            idx,
                            quantity: parsedQty,
                            unitPrice: isLaundryMode ? effectiveUnitPrice : null,
                            discountAmount: discRp.clamp(0, lineSub),
                            notes: noteCtrl.text.trim(),
                            stylistName: isSalonMode ? stylistCtrl.text.trim() : null,
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
        final tokens = NusaThemeTokens.of(context);
        final activeStore = context.watch<AuthCubit>().state.session.activeStore;
        final capabilities = state.capabilities;
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 600;
        final sideCartWidth = screenWidth >= 960 ? 380.0 : (screenWidth >= 760 ? 340.0 : 300.0);
        final catalogWidth = isTablet ? (screenWidth - sideCartWidth) : screenWidth;
        final gridColumns = catalogWidth >= 780
            ? 4
            : (catalogWidth >= 450 ? 3 : 2);

        return Scaffold(
          backgroundColor: tokens.bgPage,
          appBar: AppBar(
            backgroundColor: tokens.bgSurface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
            ),
            titleSpacing: 4,
            title: InkWell(
              onTap: (capabilities.hasTableManagement && state.selectedTable != null)
                  ? null
                  : () => _showStoreWarehouseSwitcherSheet(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capabilities.posDisplayName,
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (capabilities.hasTableManagement && state.selectedTable != null)
                              ? Icons.table_restaurant_rounded
                              : (activeStore.isWarehouse
                                  ? Icons.warehouse_rounded
                                  : Icons.storefront_rounded),
                          size: 12,
                          color: (capabilities.hasTableManagement && state.selectedTable != null)
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            capabilities.hasTableManagement && state.selectedTable != null
                                ? 'Meja: ${state.selectedTable!['name']} (${state.selectedTable!['section']})'
                                : activeStore.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: (capabilities.hasTableManagement && state.selectedTable != null)
                                  ? tokens.accent
                                  : tokens.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!(capabilities.hasTableManagement && state.selectedTable != null)) ...[
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 15,
                            color: tokens.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
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
              // Quick Price & Stock Checker Button
              IconButton(
                tooltip: 'Cek Harga Cepat',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                onPressed: () => _showQuickPriceCheckerSheet(context),
                icon: Icon(Icons.price_check_rounded, color: tokens.textSecondary, size: 21),
              ),
              // Restaurant Mode Switcher Button (Capabilities-Driven)
              if (capabilities.hasTableManagement)
                IconButton(
                  tooltip: 'Denah Meja Restoran (F&B)',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                  onPressed: () => context.push('/restaurant'),
                  icon: Icon(Icons.table_restaurant_outlined, color: tokens.textSecondary, size: 20),
                ),
              // Sync with Cloud Button
              IconButton(
                tooltip: 'Sinkronkan Data Cloud',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
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
                  color: tokens.accent,
                  size: 20,
                ),
              ),
            ],
          ),
          body: KeyboardListener(
            focusNode: _hardwareScannerFocusNode,
            onKeyEvent: _handleHardwareScannerKeyEvent,
            child: isTablet
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildCatalogColumn(
                          context,
                          state,
                          gridColumns,
                          screenWidth,
                          isTablet: true,
                        ),
                      ),
                      _buildTabletSideCartPanel(context, state, sideCartWidth),
                    ],
                  )
                : _buildCatalogColumn(
                    context,
                    state,
                    gridColumns,
                    screenWidth,
                    isTablet: false,
                  ),
          ),
        );
      },
    );
  }

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
                              color: AppColors.dangerSoft,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.medical_information_rounded,
                                  color: AppColors.danger,
                                  size: 17,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${state.prescriptionRequiredCartProducts.length} obat resep belum dilengkapi Nama Dokter & Pasien. Ketuk untuk isi.',
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppColors.danger,
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
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Cek Stok Multi-Gudang',
                          child: Material(
                            color: AppColors.warningSoft,
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
                                  border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                                ),
                                child: const Icon(
                                  Icons.warehouse_outlined,
                                  color: AppColors.warningDark,
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

  Widget _buildPosProductCard(BuildContext context, PosState state, ProductModel product) {
    final tokens = NusaThemeTokens.of(context);
    final inCartQty = _productQtyInCart(state, product.id);
    final hasInCart = inCartQty > 0;
    final outOfStock = product.stock <= 0;
    final cartIdx = hasInCart ? state.cart.lastIndexWhere((c) => c.product.id == product.id) : -1;

    final String stockLabel = product.isServiceOrNonStockItem || !product.trackStock
        ? 'Jasa / Non-Stok'
        : 'Stok ${IdrCurrencyFormatter.formatQty(product.stock)}';
    final String stockMeta = product.sku.isNotEmpty
        ? '${product.sku} • $stockLabel'
        : '$stockLabel ${product.unitCode}';

    return Material(
      color: tokens.bgSurface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onProductTapped(context, product),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasInCart ? tokens.accent : tokens.borderSubtle,
              width: hasInCart ? (tokens.isHighContrast ? 2.2 : 1.6) : tokens.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. High-Clarity Product Showcase Frame (108dp gives generous typography room)
              SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  children: [
                    ProductIllustrationWidget(
                      iconType: product.iconType,
                      imageUrl: product.imageUrl,
                      width: double.infinity,
                      height: 108,
                      showBorder: false,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      backgroundColor: tokens.bgSurface,
                      padding: const EdgeInsets.all(6),
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
                            color: tokens.accent,
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
                          color: tokens.bgSurface.withOpacity(0.95),
                          shape: CircleBorder(
                            side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => context.read<PosCubit>().decrementCartItem(cartIdx),
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(
                                Icons.remove_rounded,
                                size: 16,
                                color: tokens.textPrimary,
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
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tokens.accent.withOpacity(0.25)),
                          ),
                          child: Text(
                            product.soldByWeight ? 'KG' : '${product.variants.length} Varian',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ),
                    // Bottom-Left Wholesale Tier Badge (Grosir Bertingkat)
                    if (product.volumeTiers.isNotEmpty)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.successSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.success.withOpacity(0.35)),
                          ),
                          child: const Text(
                            'Grosir',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.successDark,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
              // 2. Structured Typography & Action Footer (Zero Vertical Clipping, Zero Price Ellipsis)
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: hasInCart ? tokens.accentSoft.withOpacity(tokens.isDark ? 0.45 : 0.35) : tokens.bgSurface,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                          height: 1.22,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stockMeta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: outOfStock && product.trackStock && !product.isServiceOrNonStockItem
                                    ? tokens.danger
                                    : (product.isLowStock && product.trackStock ? tokens.warning : tokens.textSecondary),
                              ),
                            ),
                          ),
                          if (product.otherWarehousesStock > 0) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _showWarehouseStockSheet(context, initialProduct: product),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.warningSoft,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                                ),
                                child: Text(
                                  '+Gdg ${IdrCurrencyFormatter.formatQty(product.otherWarehousesStock)}',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warningDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: NusaPriceTag(
                              amount: product.sellingPrice,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                              fitWidth: true,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: hasInCart ? tokens.positive : tokens.accentSoft,
                              borderRadius: BorderRadius.circular(9),
                              border: hasInCart
                                  ? null
                                  : Border.all(color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.3)),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              color: hasInCart ? Colors.white : tokens.accent,
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
    final tokens = NusaThemeTokens.of(context);
    final inCartQty = _productQtyInCart(state, product.id);
    final hasInCart = inCartQty > 0;
    final outOfStock = product.stock <= 0;

    return NusaCard(
      padding: const EdgeInsets.all(10),
      borderColor: hasInCart ? tokens.accent : tokens.borderSubtle,
      borderWidth: hasInCart ? (tokens.isHighContrast ? 2.2 : 1.5) : tokens.borderWidth,
      backgroundColor: hasInCart ? tokens.accentSoft.withOpacity(tokens.isDark ? 0.35 : 0.25) : tokens.bgSurface,
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (product.volumeTiers.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const NusaBadge(
                        label: 'Grosir',
                        variant: NusaBadgeVariant.success,
                      ),
                    ],
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
                        ? tokens.danger
                        : (product.isLowStock ? tokens.warning : tokens.textSecondary),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: NusaPriceTag(
                        amount: product.sellingPrice,
                        fontSize: 15,
                        color: tokens.textPrimary,
                        fitWidth: true,
                      ),
                    ),
                    if (product.otherWarehousesStock > 0) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _showWarehouseStockSheet(context, initialProduct: product),
                        borderRadius: BorderRadius.circular(6),
                        child: NusaBadge(
                          label: '+Gudang ${IdrCurrencyFormatter.formatQty(product.otherWarehousesStock)}',
                          variant: NusaBadgeVariant.warning,
                        ),
                      ),
                    ],
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
              color: hasInCart ? tokens.positive : tokens.accentSoft,
              borderRadius: BorderRadius.circular(11),
              border: hasInCart ? null : Border.all(color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.3)),
            ),
            child: Icon(
              Icons.add_rounded,
              color: hasInCart ? Colors.white : tokens.accent,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  void _showVerticalMetadataSheet(BuildContext context, PosState state) {
    final caps = state.capabilities;
    final meta = state.verticalMetadata;

    final String title;
    final IconData icon;
    if (caps.hasPrescriptionWorkflow) {
      title = 'Data Resep & Farmasi (Apotek)';
      icon = Icons.medication_outlined;
    } else if (caps.hasVehicleWorkOrder) {
      title = 'Data Kendaraan & PKB (Bengkel)';
      icon = Icons.build_circle_outlined;
    } else if (caps.hasSalonStylistWorkflow) {
      title = 'Penugasan Kapster / Stylist (Salon)';
      icon = Icons.content_cut_rounded;
    } else {
      title = 'Detail Rak & Estimasi Selesai (Laundry)';
      icon = Icons.local_laundry_service_outlined;
    }

    // Workshop controllers
    final nopolCtrl = TextEditingController(text: (meta['nopol'] ?? '').toString());
    final vehicleCtrl = TextEditingController(text: (meta['kendaraan'] ?? meta['vehicle_model'] ?? '').toString());
    final kmCtrl = TextEditingController(text: (meta['kilometer'] ?? meta['km'] ?? '').toString());
    final mechanicCtrl = TextEditingController(text: (meta['mechanic_name'] ?? '').toString());

    // Pharmacy controllers
    final doctorCtrl = TextEditingController(text: (meta['doctor_name'] ?? '').toString());
    final sipCtrl = TextEditingController(text: (meta['doctor_sip'] ?? '').toString());
    final patientCtrl = TextEditingController(text: (meta['patient_name'] ?? '').toString());
    final rxNoCtrl = TextEditingController(text: (meta['prescription_number'] ?? '').toString());

    // Laundry controllers
    final rackCtrl = TextEditingController(text: (meta['rack_number'] ?? '').toString());
    final estReadyCtrl = TextEditingController(text: (meta['estimated_ready_at'] ?? '').toString());

    // Salon controller
    final stylistCtrl = TextEditingController(text: (meta['stylist_name'] ?? '').toString());
    final hasAnyExisting = meta.isNotEmpty || (state.orderNotes?.trim().isNotEmpty ?? false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
        child: SingleChildScrollView(
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
              if (caps.hasVehicleWorkOrder) ...[
                TextField(
                  controller: nopolCtrl,
                  textCapitalization: TextCapitalization.characters,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Polisi (Plat Motor / Mobil) *',
                    hintText: 'Contoh: B 1234 XYZ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: vehicleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Merk / Tipe Kendaraan *',
                    hintText: 'Contoh: Honda PCX 160 / Toyota Avanza',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kilometer (KM) Kendaraan',
                    hintText: 'Contoh: 24500',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mechanicCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Mekanik & Keluhan (Opsional)',
                    hintText: 'Contoh: Mekanik Agung • Ganti Oli & Tune Up',
                  ),
                ),
              ] else if (caps.hasPrescriptionWorkflow) ...[
                TextField(
                  controller: doctorCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama Dokter Penulis Resep *',
                    hintText: 'Contoh: dr. Andi Wijaya, Sp.PD',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nomor SIP Dokter *',
                    hintText: 'Contoh: 503/0142/SIP.D/2026',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: patientCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Pasien *',
                    hintText: 'Contoh: Tn. Budi Santoso',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rxNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Resep / RM (Opsional)',
                    hintText: 'Contoh: RX-2026-0142',
                  ),
                ),
              ] else if (caps.hasSalonStylistWorkflow) ...[
                TextField(
                  controller: stylistCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama Kapster / Stylist / Terapis',
                    hintText: 'Contoh: Rina (Senior Stylist)',
                  ),
                ),
              ] else ...[
                TextField(
                  controller: rackCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Rak Penyimpanan Cucian *',
                    hintText: 'Contoh: Rak B-04',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: estReadyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Estimasi Selesai Cuci (Tanggal & Jam) *',
                    hintText: 'Contoh: 17 Nov 2026 • 17:00 WIB',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (hasAnyExisting)
                    OutlinedButton(
                      onPressed: () {
                        context.read<PosCubit>().setVerticalMetadata({});
                        Navigator.pop(ctx);
                      },
                      child: const Text('Hapus'),
                    ),
                  if (hasAnyExisting) const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          final cubit = context.read<PosCubit>();
                          if (caps.hasVehicleWorkOrder) {
                            cubit.setVerticalMetadata({
                              'nopol': nopolCtrl.text.trim(),
                              'kendaraan': vehicleCtrl.text.trim(),
                              'kilometer': kmCtrl.text.trim(),
                              'mechanic_name': mechanicCtrl.text.trim(),
                            });
                          } else if (caps.hasPrescriptionWorkflow) {
                            cubit.setVerticalMetadata({
                              'doctor_name': doctorCtrl.text.trim(),
                              'doctor_sip': sipCtrl.text.trim(),
                              'patient_name': patientCtrl.text.trim(),
                              'prescription_number': rxNoCtrl.text.trim(),
                            });
                          } else if (caps.hasSalonStylistWorkflow) {
                            cubit.setVerticalMetadata({
                              'stylist_name': stylistCtrl.text.trim(),
                            });
                          } else {
                            cubit.setVerticalMetadata({
                              'rack_number': rackCtrl.text.trim(),
                              'estimated_ready_at': estReadyCtrl.text.trim(),
                            });
                          }
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
      emptyLabel = 'Input Dokter, No. SIP & Pasien (Resep Apotek)';
    } else if (caps.hasVehicleWorkOrder) {
      icon = Icons.directions_car_outlined;
      emptyLabel = 'Input No. Polisi, Kendaraan & KM (Bengkel)';
    } else if (caps.hasSalonStylistWorkflow) {
      icon = Icons.content_cut_rounded;
      emptyLabel = 'Pilih Kapster / Stylist (Tap item utk per-layanan)';
    } else {
      icon = Icons.local_laundry_service_outlined;
      emptyLabel = 'Input Nomor Rak & Estimasi Selesai (Laundry)';
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
    final tokens = NusaThemeTokens.of(context);
    final cust = state.selectedCustomer;
    if (cust == null) {
      return Material(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _showCustomerSelectorSheet(context, state),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 16, color: tokens.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pelanggan Umum',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textPrimary),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: tokens.textSecondary),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: tokens.borderSubtle,
                ),
                Tooltip(
                  message: 'Member Baru',
                  child: InkWell(
                    onTap: () => _showQuickAddCustomerModal(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.person_add_alt_1_outlined, size: 16, color: tokens.accent),
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
      color: tokens.accentSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _showCustomerSelectorSheet(context, state),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35), width: tokens.borderWidth),
          ),
          child: Row(
            children: [
              Icon(Icons.workspace_premium_rounded, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  discPct > 0
                      ? '${cust['name']} (-${discPct.toInt()}%)'
                      : '${cust['name']} ($groupName)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tokens.textPrimary),
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
                      color: state.redeemedLoyaltyPoints > 0 ? tokens.positive : tokens.warningSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      state.redeemedLoyaltyPoints > 0
                          ? '-${state.redeemedLoyaltyPoints}p'
                          : '${pts}p',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: state.redeemedLoyaltyPoints > 0 ? Colors.white : tokens.warning,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              InkWell(
                onTap: () => context.read<PosCubit>().selectCustomer(null),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 15, color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCartPanel(BuildContext context, PosState state) {
    final tokens = NusaThemeTokens.of(context);
    final hasItems = state.cart.isNotEmpty;
    final String summaryPreview = !hasItems
        ? 'Pilih produk untuk mulai transaksi'
        : state.cart.length == 1
            ? state.cart.first.displayName
            : '${state.cart.first.displayName} (+${state.cart.length - 1} lainnya)';

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
        boxShadow: tokens.isDark || tokens.isHighContrast ? null : AppColors.floatingCartShadow,
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
                              color: hasItems ? tokens.accent : tokens.bgElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              IdrCurrencyFormatter.formatQty(state.totalItemsCount),
                              style: AppTheme.moneyStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: hasItems ? Colors.white : tokens.textSecondary,
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
                                color: hasItems ? tokens.textPrimary : tokens.textTertiary,
                              ),
                            ),
                          ),
                          if (hasItems)
                            Icon(
                              _isCartExpanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_up_rounded,
                              size: 20,
                              color: tokens.textSecondary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasItems) ..._buildCartActionToolbar(context, state, hasItems),
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
                        child: _buildCartItemsListView(context, state, shrinkWrap: true),
                      ),
                    ),
            ),

            ..._buildCartCheckoutFooter(context, state, hasItems),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCartActionToolbar(BuildContext context, PosState state, bool hasItems) {
    final tokens = NusaThemeTokens.of(context);
    return [
      const SizedBox(width: 6),
      InkWell(
        onTap: hasItems ? () => _showDiscountAndHoldModal(context, state) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: state.totalDiscount > 0 ? tokens.positiveSoft : tokens.accentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            state.totalDiscount > 0
                ? 'Disc -${IdrCurrencyFormatter.formatCompact(state.totalDiscount)}'
                : '+ Diskon',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: state.totalDiscount > 0 ? tokens.positive : tokens.accent,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      InkWell(
        onTap: hasItems
            ? () {
                context.read<PosCubit>().clearCart();
                setState(() => _isCartExpanded = false);
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Icon(Icons.delete_outline_rounded, size: 18, color: tokens.danger),
        ),
      ),
    ];
  }

  List<Widget> _buildCartCheckoutFooter(BuildContext context, PosState state, bool hasItems) {
    final tokens = NusaThemeTokens.of(context);
    final hasSurplusCredit = state.isExchangeMode && state.exchangeSurplusCredit > 0;
    return [
      Divider(height: 12, color: tokens.borderSubtle),
      Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSurplusCredit ? 'Kelebihan Retur' : 'Total Tagihan',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasSurplusCredit ? tokens.accent : tokens.textSecondary,
                  ),
                ),
                NusaPriceTag(
                  amount: hasSurplusCredit ? state.exchangeSurplusCredit : state.grandTotal,
                  fontSize: 18,
                  color: hasSurplusCredit ? tokens.accent : tokens.textPrimary,
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
                side: BorderSide(color: tokens.borderDefault, width: tokens.borderWidth),
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
    ];
  }

  Widget _buildTabletSideCartPanel(BuildContext context, PosState state, double width) {
    final tokens = NusaThemeTokens.of(context);
    final hasItems = state.cart.isNotEmpty;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        border: Border(left: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
      ),
      child: SafeArea(
        top: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasItems ? tokens.accent : tokens.bgElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      IdrCurrencyFormatter.formatQty(state.totalItemsCount),
                      style: AppTheme.moneyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: hasItems ? Colors.white : tokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Keranjang Kasir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  if (hasItems) ..._buildCartActionToolbar(context, state, hasItems),
                ],
              ),
              Divider(height: 16, color: tokens.borderSubtle),
              Expanded(
                child: !hasItems
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_cart_outlined, size: 42, color: tokens.textTertiary),
                            const SizedBox(height: 10),
                            Text(
                              'Keranjang Masih Kosong',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ketuk produk di katalog kiri\nuntuk menambah ke nota.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: tokens.textTertiary),
                            ),
                          ],
                        ),
                      )
                    : _buildCartItemsListView(context, state, shrinkWrap: false),
              ),
              ..._buildCartCheckoutFooter(context, state, hasItems),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartItemsListView(
    BuildContext context,
    PosState state, {
    required bool shrinkWrap,
  }) {
    return ListView.separated(
      shrinkWrap: shrinkWrap,
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
                                          '${item.stylistName != null && item.stylistName!.isNotEmpty ? ' • Kapster: ${item.stylistName}' : ''}'
                                          '${(item.batch ?? item.product.fefoBatch) != null ? ' • Batch: ${(item.batch ?? item.product.fefoBatch)!.batchNumber}' : ''}'
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
                        );
  }

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
                    const Icon(Icons.warehouse_rounded, color: AppColors.primary, size: 22),
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
                        const Icon(Icons.warehouse_rounded, color: AppColors.warningDark, size: 22),
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
                          color: AppColors.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                        ),
                        child: Text(
                          inlineError!,
                          style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w700),
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
                                                  ? AppColors.success.withOpacity(0.35)
                                                  : tokens.borderSubtle,
                                            ),
                                          ),
                                          child: Text(
                                            '${isWh ? 'Gudang' : 'Cabang'} ${wh['store_name']}: ${IdrCurrencyFormatter.formatQty(avail)} $unit',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: avail > 0 ? AppColors.successDark : tokens.textSecondary,
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
                                        ? AppColors.successDark
                                        : AppColors.danger,
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
                                          color: AppColors.successDark,
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

  bool ctxMountedCheck(BuildContext ctx) => ctx.mounted;
}
