import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// PILAR 3 — MANAJEMEN PEMASOK (SUPPLIER), REKENING BANK & PEMBELIAN STOK MASUK (QUICK STOCK IN)
class SupplierListScreen extends StatefulWidget {
  final int initialTab;

  const SupplierListScreen({super.key, this.initialTab = 0});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  // Quick Stock In form state
  int? _selectedSupplierId;
  ProductModel? _selectedProduct;
  final TextEditingController _qtyCtrl = TextEditingController(text: '10');
  final TextEditingController _costCtrl = TextEditingController();
  final TextEditingController _invoiceCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  String _paymentStatus = 'credit'; // 'paid' | 'credit'
  DateTime _dueDate = DateTime.now().add(const Duration(days: 14));
  bool _submittingStockIn = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _tabController.addListener(() => setState(() {}));
    context.read<PosCubit>().syncWithCloud(force: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _invoiceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

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
                const Text(
                  'Informasi Rekening Bank Transfer Pembayaran',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.primary),
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
                                const SnackBar(
                                  backgroundColor: AppColors.danger,
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
                                      res['success'] == true ? AppColors.successDark : AppColors.danger,
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
      backgroundColor: Colors.white,
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
                child: MobileScanner(
                  onDetect: (capture) {
                    if (scanned) return;
                    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
                    if (raw == null || raw.isEmpty) return;
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
                          backgroundColor: AppColors.danger,
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
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Pilih Pemasok dan Produk terlebih dahulu.'),
        ),
      );
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final cost = IdrCurrencyFormatter.parse(_costCtrl.text);
    if (qty <= 0 || cost < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
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
          backgroundColor: AppColors.successDark,
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
          backgroundColor: AppColors.danger,
          content: Text(res['message']?.toString() ?? 'Gagal mencatat stok masuk.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        final q = _searchCtrl.text.trim().toLowerCase();
        final filteredSuppliers = state.suppliers.where((s) {
          if (q.isEmpty) return true;
          final name = (s['name'] ?? '').toString().toLowerCase();
          final code = (s['code'] ?? '').toString().toLowerCase();
          final bank = (s['bank_name'] ?? '').toString().toLowerCase();
          final pic = (s['contact_person'] ?? '').toString().toLowerCase();
          return name.contains(q) || code.contains(q) || bank.contains(q) || pic.contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Pemasok & Pembelian Stok'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => context.read<PosCubit>().syncWithCloud(force: false),
              ),
              IconButton(
                tooltip: 'Buku Bon Hutang Supplier',
                icon: const Icon(Icons.menu_book_rounded, color: AppColors.warningDark),
                onPressed: () => context.push('/debts?tab=payables'),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.slate500,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: 'Data Pemasok (${state.suppliers.length})'),
                const Tab(text: 'Stok Masuk (Quick In)'),
              ],
            ),
          ),
          floatingActionButton: _tabController.index == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddOrEditSupplierModal(),
                  backgroundColor: AppColors.primary,
                  icon: const Icon(Icons.add_business_rounded, color: Colors.white),
                  label: const Text('Tambah Pemasok', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                )
              : null,
          body: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: SUPPLIER LIST WITH FULL BANK DETAILS
              Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Cari nama pemasok, kode, PIC, atau nama bank...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  Expanded(
                    child: filteredSuppliers.isEmpty
                        ? const Center(
                            child: Text(
                              'Belum ada data pemasok terdaftar.',
                              style: TextStyle(color: AppColors.slate500),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 88),
                            itemCount: filteredSuppliers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, idx) {
                              final s = filteredSuppliers[idx];
                              final bankName = (s['bank_name'] ?? '').toString();
                              final bankNo = (s['bank_account_number'] ?? '').toString();
                              final bankHolder = (s['bank_account_holder'] ?? '').toString();
                              final hasBank = bankName.isNotEmpty || bankNo.isNotEmpty;
                              final payable = (s['outstanding_balance'] as num?)?.toDouble() ?? 0.0;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: AppColors.primarySoft,
                                          child: const Icon(Icons.local_shipping_rounded, color: AppColors.primary, size: 20),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${s['code'] ?? 'SUP'} • ${s['name']}',
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                              ),
                                              Text(
                                                'PIC: ${s['contact_person'] ?? '-'} • Telp: ${s['phone'] ?? '-'}',
                                                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.slate600),
                                          onPressed: () => _showAddOrEditSupplierModal(existing: s),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.account_balance_rounded, size: 18, color: AppColors.primary),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: hasBank
                                                ? Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '$bankName • $bankNo',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 12.5,
                                                          color: AppColors.navyDark,
                                                        ),
                                                      ),
                                                      if (bankHolder.isNotEmpty)
                                                        Text(
                                                          'a.n. $bankHolder',
                                                          style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                                                        ),
                                                    ],
                                                  )
                                                : const Text(
                                                    'Rekening bank belum dilengkapi',
                                                    style: TextStyle(fontSize: 12, color: AppColors.slate400),
                                                  ),
                                          ),
                                          if (bankNo.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Salin Nomor Rekening',
                                              icon: const Icon(Icons.copy_rounded, size: 17, color: AppColors.primary),
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(text: bankNo));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('No. Rekening $bankNo disalin!')),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          payable > 0
                                              ? 'Hutang Faktur: ${IdrCurrencyFormatter.format(payable)}'
                                              : 'Tidak ada hutang tempo',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: payable > 0 ? AppColors.dangerDark : AppColors.successDark,
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            setState(() => _selectedSupplierId = (s['id'] as num?)?.toInt());
                                            _tabController.animateTo(1);
                                          },
                                          icon: const Icon(Icons.add_box_outlined, size: 16),
                                          label: const Text('Input Stok Masuk'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),

              // TAB 2: QUICK STOCK IN FORM
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pencatatan Barang Datang (Quick Stock In)',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tambah stok barang langsung dari HP & catat pelunasan atau hutang tempo ke pemasok.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: state.suppliers.any((s) => (s['id'] as num?)?.toInt() == _selectedSupplierId)
                          ? _selectedSupplierId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Pilih Pemasok / Distributor *',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                      items: state.suppliers
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: (s['id'] as num).toInt(),
                              child: Text('${s['name']} (${s['bank_name'] ?? '-'})'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _selectedSupplierId = val),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: _selectedProduct != null &&
                                    state.allProducts.any((p) => p.id == _selectedProduct!.id)
                                ? _selectedProduct!.id
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Pilih Barang Masuk *',
                              prefixIcon: Icon(Icons.inventory_2_outlined),
                            ),
                            items: state.allProducts
                                .map(
                                  (p) => DropdownMenuItem<int>(
                                    value: p.id,
                                    child: Text(
                                      '${p.name} (Stok: ${IdrCurrencyFormatter.formatQty(p.stock)})',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (id) {
                              final picked = state.allProducts.where((p) => p.id == id).firstOrNull;
                              setState(() {
                                _selectedProduct = picked;
                                if (picked != null && picked.costPrice > 0) {
                                  _costCtrl.text = picked.costPrice.toInt().toString();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _scanProductBarcodeForStockIn(state),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Jumlah Masuk (${_selectedProduct?.unitCode ?? 'pcs'}) *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _costCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(labelText: 'Harga Beli / Unit (Rp) *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Nilai Faktur:', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            IdrCurrencyFormatter.format(
                              (double.tryParse(_qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0) *
                                  IdrCurrencyFormatter.parse(_costCtrl.text),
                            ),
                            style: AppTheme.moneyStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Status Pembayaran Faktur:', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Lunas (Kas/Bank)')),
                            selected: _paymentStatus == 'paid',
                            onSelected: (_) => setState(() => _paymentStatus = 'paid'),
                            selectedColor: AppColors.success,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _paymentStatus == 'paid' ? Colors.white : AppColors.slate700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Tempo / Hutang Bon')),
                            selected: _paymentStatus == 'credit',
                            onSelected: (_) => setState(() => _paymentStatus = 'credit'),
                            selectedColor: AppColors.warningDark,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _paymentStatus == 'credit' ? Colors.white : AppColors.slate700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_paymentStatus == 'credit') ...[
                      const SizedBox(height: 10),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        tileColor: Colors.white,
                        leading: const Icon(Icons.event_rounded, color: AppColors.warningDark),
                        title: const Text('Tanggal Jatuh Tempo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(DateFormat('dd MMM yyyy').format(_dueDate)),
                        trailing: const Text('Ubah', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dueDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setState(() => _dueDate = picked);
                        },
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: _invoiceCtrl,
                      decoration: const InputDecoration(labelText: 'No. Faktur Supplier (Opsional)'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Catatan Penerimaan Barang (Opsional)'),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _submittingStockIn ? null : _submitQuickStockIn,
                        icon: const Icon(Icons.inventory_rounded),
                        label: Text(
                          _submittingStockIn ? 'Menyimpan Stok Masuk...' : 'Catat Pembelian Stok Masuk',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
