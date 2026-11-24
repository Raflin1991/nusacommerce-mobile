// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosCartItemAndCustomerSheetsExt on _PosCatalogScreenState {
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
                  style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
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
                    selectedColor: NusaThemeTokens.of(ctx).warning,
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
                  Text(
                    'Kapster / Stylist / Terapis',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(ctx).textPrimary),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        context.read<PosCubit>().removeCartItem(idx);
                        Navigator.pop(ctx);
                      },
                      style: OutlinedButton.styleFrom(foregroundColor: NusaThemeTokens.of(ctx).danger),
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
                    leading: CircleAvatar(
                      backgroundColor: Color(0xFFF1F5F9),
                      child: Icon(Icons.person_outline_rounded, color: NusaThemeTokens.of(ctx).textSecondary),
                    ),
                    title: const Text('Pelanggan Umum (Guest)', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Tanpa diskon member / kasbon', style: TextStyle(fontSize: 12)),
                    trailing: state.selectedCustomer == null
                        ? Icon(Icons.check_circle_rounded, color: NusaThemeTokens.of(ctx).accent)
                        : null,
                    onTap: () {
                      context.read<PosCubit>().selectCustomer(null);
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Belum ada pelanggan cocok. Tekan "Tambah Baru" untuk mendaftarkan member.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: NusaThemeTokens.of(ctx).textSecondary),
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
                                  backgroundColor: NusaThemeTokens.of(ctx).accentSoft,
                                  child: Text(
                                    (c['name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                                    style: TextStyle(fontWeight: FontWeight.w800, color: NusaThemeTokens.of(ctx).accent),
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
                                          color: NusaThemeTokens.of(ctx).accentSoft,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          discPct > 0 ? '$groupName • ${discPct.toInt()}%' : groupName,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: NusaThemeTokens.of(ctx).accent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${c['phone'] ?? '-'} • $pts Poin'
                                  '${limit > 0 ? ' • Sisa Limit: ${IdrCurrencyFormatter.format(remaining)}' : ''}',
                                  style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).textSecondary),
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
                        backgroundColor: res['success'] == true ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).danger,
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
}
