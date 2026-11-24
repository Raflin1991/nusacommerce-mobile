// ignore_for_file: invalid_use_of_protected_member
part of 'supplier_list_screen.dart';

extension _SupplierListScreenStatePart1Ext on _SupplierListScreenState {

  void _showAddOrEditSupplierModal({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final codeCtrl = TextEditingController(text: existing?['code']?.toString() ?? '');
    final picCtrl = TextEditingController(text: existing?['contact_person']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone']?.toString() ?? '');
    final bizCtrl = TextEditingController(text: existing?['business_name']?.toString() ?? '');
    final bankNameCtrl = TextEditingController(text: existing?['bank_name']?.toString() ?? 'BCA');
    final bankAccCtrl = TextEditingController(text: existing?['bank_account_number']?.toString() ?? '');
    final bankHolderCtrl = TextEditingController(text: existing?['bank_account_holder']?.toString() ?? '');
    final termsCtrl = TextEditingController(
      text: ((existing?['payment_terms_days'] as num?)?.toInt() ?? 14).toString(),
    );
    bool saving = false;

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
                Text(
                  isEdit ? 'Edit Data Pemasok' : 'Tambah Pemasok (Supplier) Baru',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Pemasok / PT / Distributor *'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(labelText: 'Kode (Opsional)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: picCtrl,
                        decoration: const InputDecoration(labelText: 'Nama PIC / Sales'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'No Telp / WhatsApp'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: termsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Tempo Default (Hari)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bizCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Badan Usaha (Opsional)'),
                ),
                const Divider(height: 24),
                Text(
                  'Informasi Rekening Bank Transfer Pembayaran',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(ctx).accent),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: ['BCA', 'Mandiri', 'BRI', 'BNI', 'BSI', 'CIMB'].map((b) {
                    return ChoiceChip(
                      label: Text(b),
                      selected: bankNameCtrl.text.trim().toUpperCase() == b.toUpperCase(),
                      onSelected: (_) => setModalState(() => bankNameCtrl.text = b),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bankNameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Bank'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankAccCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Nomor Rekening Bank'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bankHolderCtrl,
                  decoration: const InputDecoration(labelText: 'Atas Nama Pemilik Rekening'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(ctx).danger,
                                  content: Text('Nama Pemasok wajib diisi.'),
                                ),
                              );
                              return;
                            }
                            setModalState(() => saving = true);
                            final res = await context.read<PosCubit>().saveSupplier(
                              {
                                'name': nameCtrl.text.trim(),
                                if (codeCtrl.text.trim().isNotEmpty) 'code': codeCtrl.text.trim(),
                                if (picCtrl.text.trim().isNotEmpty) 'contact_person': picCtrl.text.trim(),
                                if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
                                if (bizCtrl.text.trim().isNotEmpty) 'business_name': bizCtrl.text.trim(),
                                if (bankNameCtrl.text.trim().isNotEmpty) 'bank_name': bankNameCtrl.text.trim(),
                                if (bankAccCtrl.text.trim().isNotEmpty)
                                  'bank_account_number': bankAccCtrl.text.trim(),
                                if (bankHolderCtrl.text.trim().isNotEmpty)
                                  'bank_account_holder': bankHolderCtrl.text.trim(),
                                'payment_terms_days': int.tryParse(termsCtrl.text.trim()) ?? 14,
                              },
                              id: (existing?['id'] as num?)?.toInt(),
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor:
                                      res['success'] == true ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).danger,
                                  content: Text(
                                    res['success'] == true
                                        ? (isEdit ? 'Data pemasok diperbarui.' : 'Pemasok berhasil ditambahkan.')
                                        : (res['message']?.toString() ?? 'Gagal menyimpan pemasok.'),
                                  ),
                                ),
                              );
                            }
                          },
                    child: Text(saving ? 'Menyimpan...' : 'Simpan Data Pemasok'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  void _scanProductBarcodeForStockIn(PosState posState) {
    bool scanned = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Scan Barcode Barang Datang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: NusaBarcodeScannerView(
                  onDetect: (raw) {
                    if (scanned) return;
                    final match = posState.allProducts.where(
                      (p) => p.barcode == raw || p.sku.toLowerCase() == raw.toLowerCase(),
                    );
                    scanned = true;
                    Navigator.pop(ctx);
                    if (match.isNotEmpty) {
                      setState(() {
                        _selectedProduct = match.first;
                        _costCtrl.text = match.first.costPrice > 0
                            ? match.first.costPrice.toInt().toString()
                            : '';
                      });
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: NusaThemeTokens.of(ctx).danger,
                          content: Text('Barang dengan barcode "$raw" tidak ditemukan di katalog.'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _submitQuickStockIn() async {
    if (_submittingStockIn) return;
    if (_selectedSupplierId == null || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).danger,
          content: Text('Pilih Pemasok dan Produk terlebih dahulu.'),
        ),
      );
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final cost = IdrCurrencyFormatter.parse(_costCtrl.text);
    if (qty <= 0 || cost < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).danger,
          content: Text('Kuantitas harus > 0 dan harga beli tidak boleh negatif.'),
        ),
      );
      return;
    }

    setState(() => _submittingStockIn = true);
    final res = await context.read<PosCubit>().submitQuickStockIn({
      'supplier_id': _selectedSupplierId,
      'product_id': _selectedProduct!.id,
      'quantity': qty,
      'unit_cost': cost,
      'payment_status': _paymentStatus,
      if (_paymentStatus == 'credit') 'due_date': DateFormat('yyyy-MM-dd').format(_dueDate),
      if (_invoiceCtrl.text.trim().isNotEmpty) 'supplier_invoice_number': _invoiceCtrl.text.trim(),
      if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
    });

    if (!mounted) return;
    setState(() => _submittingStockIn = false);

    if (res['success'] == true) {
      _invoiceCtrl.clear();
      _notesCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).positive,
          content: Text(
            _paymentStatus == 'paid'
                ? 'Stok masuk Lunas berhasil dicatat.'
                : 'Stok masuk & Hutang Supplier tercatat di Buku Bon!',
          ),
          action: _paymentStatus == 'credit'
              ? SnackBarAction(
                  label: 'Buku Bon',
                  textColor: Colors.white,
                  onPressed: () => context.push('/debts?tab=payables'),
                )
              : null,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NusaThemeTokens.of(context).danger,
          content: Text(res['message']?.toString() ?? 'Gagal mencatat stok masuk.'),
        ),
      );
    }
  }
}
