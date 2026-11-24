// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosItemInputSheetsExt on _PosCatalogScreenState {
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
                prefixIcon: Icon(Icons.bolt_rounded, color: NusaThemeTokens.of(ctx).accent),
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
              style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(ctx).textSecondary),
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
                prefixIcon: Icon(Icons.scale_rounded, color: NusaThemeTokens.of(ctx).accent),
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
                    prefixIcon: Icon(Icons.discount_outlined, color: NusaThemeTokens.of(ctx).accent),
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
                  decoration: InputDecoration(
                    labelText: 'PIN / Sandi Manajer (Wajib jika diskon > 15%)',
                    prefixIcon: Icon(Icons.verified_user_outlined, color: NusaThemeTokens.of(ctx).warning),
                  ),
                ),
                const Divider(height: 24),
                TextField(
                  controller: holdLabelCtrl,
                  decoration: InputDecoration(
                    labelText: state.capabilities.hasTableManagement
                        ? 'Label Parkir Antrean (Misal: Ibu Sari / Meja 4)'
                        : 'Label Parkir Antrean (Misal: Ibu Sari / Antrean 2)',
                    prefixIcon: Icon(Icons.bookmark_border_rounded, color: NusaThemeTokens.of(ctx).warning),
                  ),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NusaThemeTokens.of(ctx).dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NusaThemeTokens.of(ctx).danger.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: NusaThemeTokens.of(ctx).danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modalError!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: NusaThemeTokens.of(ctx).danger,
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
                      color: NusaThemeTokens.of(ctx).warningSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NusaThemeTokens.of(ctx).warning.withOpacity(0.4)),
                    ),
                    child: Text(
                      'Keranjang aktif (${state.cart.length} item) akan otomatis diparkir agar tidak hilang saat membuka antrean.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: NusaThemeTokens.of(ctx).warning,
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
                      style: TextStyle(color: NusaThemeTokens.of(ctx).textSecondary),
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
                              color: NusaThemeTokens.of(ctx).warningSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.pause_circle_filled_rounded, color: NusaThemeTokens.of(ctx).warning),
                          ),
                          title: Text(
                            (held['held_label'] ?? held['number'] ?? 'Antrean').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            metaParts.join(' • '),
                            style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).textSecondary),
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
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: NusaThemeTokens.of(ctx).danger,
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
}
