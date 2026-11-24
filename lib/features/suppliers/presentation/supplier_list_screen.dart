import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_barcode_scanner_view.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

part 'supplier_list_screen_part1.dart';

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
          backgroundColor: NusaThemeTokens.of(context).bgPage,
          appBar: AppBar(
            title: const Text('Pemasok & Pembelian Stok'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => context.read<PosCubit>().syncWithCloud(force: false),
              ),
              IconButton(
                tooltip: 'Buku Bon Hutang Supplier',
                icon: Icon(Icons.menu_book_rounded, color: NusaThemeTokens.of(context).warning),
                onPressed: () => context.push('/debts?tab=payables'),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: NusaThemeTokens.of(context).accent,
              unselectedLabelColor: NusaThemeTokens.of(context).textSecondary,
              indicatorColor: NusaThemeTokens.of(context).accent,
              tabs: [
                Tab(text: 'Data Pemasok (${state.suppliers.length})'),
                const Tab(text: 'Stok Masuk (Quick In)'),
              ],
            ),
          ),
          floatingActionButton: _tabController.index == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddOrEditSupplierModal(),
                  backgroundColor: NusaThemeTokens.of(context).accent,
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
                        ? Center(
                            child: Text(
                              'Belum ada data pemasok terdaftar.',
                              style: TextStyle(color: NusaThemeTokens.of(context).textSecondary),
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
                                  border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: NusaThemeTokens.of(context).accentSoft,
                                          child: Icon(Icons.local_shipping_rounded, color: NusaThemeTokens.of(context).accent, size: 20),
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
                                                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.edit_outlined, size: 20, color: NusaThemeTokens.of(context).textSecondary),
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
                                        border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.account_balance_rounded, size: 18, color: NusaThemeTokens.of(context).accent),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: hasBank
                                                ? Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        '$bankName • $bankNo',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 12.5,
                                                          color: NusaThemeTokens.of(context).textPrimary,
                                                        ),
                                                      ),
                                                      if (bankHolder.isNotEmpty)
                                                        Text(
                                                          'a.n. $bankHolder',
                                                          style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
                                                        ),
                                                    ],
                                                  )
                                                : Text(
                                                    'Rekening bank belum dilengkapi',
                                                    style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textTertiary),
                                                  ),
                                          ),
                                          if (bankNo.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Salin Nomor Rekening',
                                              icon: Icon(Icons.copy_rounded, size: 17, color: NusaThemeTokens.of(context).accent),
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
                                            color: payable > 0 ? NusaThemeTokens.of(context).danger : NusaThemeTokens.of(context).positive,
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
                    Text(
                      'Tambah stok barang langsung dari HP & catat pelunasan atau hutang tempo ke pemasok.',
                      style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(context).textSecondary),
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
                              color: NusaThemeTokens.of(context).accentSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: NusaThemeTokens.of(context).accent.withOpacity(0.3)),
                            ),
                            child: Icon(Icons.qr_code_scanner_rounded, color: NusaThemeTokens.of(context).accent),
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
                        color: NusaThemeTokens.of(context).accentSoft,
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
                            style: AppTheme.moneyStyle(fontSize: 16, fontWeight: FontWeight.w900, color: NusaThemeTokens.of(context).accent),
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
                            selectedColor: NusaThemeTokens.of(context).positive,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _paymentStatus == 'paid' ? Colors.white : NusaThemeTokens.of(context).textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Tempo / Hutang Bon')),
                            selected: _paymentStatus == 'credit',
                            onSelected: (_) => setState(() => _paymentStatus = 'credit'),
                            selectedColor: NusaThemeTokens.of(context).warning,
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _paymentStatus == 'credit' ? Colors.white : NusaThemeTokens.of(context).textPrimary,
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
                          side: BorderSide(color: NusaThemeTokens.of(context).borderSubtle),
                        ),
                        tileColor: Colors.white,
                        leading: Icon(Icons.event_rounded, color: NusaThemeTokens.of(context).warning),
                        title: const Text('Tanggal Jatuh Tempo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(DateFormat('dd MMM yyyy').format(_dueDate)),
                        trailing: Text('Ubah', style: TextStyle(color: NusaThemeTokens.of(context).accent, fontWeight: FontWeight.w700)),
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
