import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// MODUL BUKU BON UMKM (PIUTANG PELANGGAN + 1-KLIK TAGIH WA) & BIAYA OPERASIONAL (`PRD-07`)
class DebtBookScreen extends StatefulWidget {
  final int initialTab;

  const DebtBookScreen({super.key, this.initialTab = 0});

  @override
  State<DebtBookScreen> createState() => _DebtBookScreenState();
}

class _DebtBookScreenState extends State<DebtBookScreen> with SingleTickerProviderStateMixin {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();
  late TabController _tabController;

  bool _loading = true;
  String? _error;

  double _totalReceivables = 0;
  List<Map<String, dynamic>> _receivables = [];
  double _totalPayables = 0;
  List<Map<String, dynamic>> _payables = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _expenseCategories = [];
  List<Map<String, dynamic>> _paymentMethods = [];
  String _receivableAgingFilter = 'Semua'; // 'Semua', 'Belum Jatuh Tempo', '1-30 Hari', '>30 Hari'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  List<Map<String, dynamic>> get _defaultOfflinePaymentMethods => const [
        {'id': 1, 'name': 'Tunai', 'type': 'cash'},
        {'id': 2, 'name': 'QRIS / E-Wallet', 'type': 'qris'},
        {'id': 3, 'name': 'Transfer Bank', 'type': 'bank_transfer'},
      ];

  List<Map<String, dynamic>> get _defaultOfflineExpenseCategories => const [
        {'id': 1, 'name': 'Operasional Toko'},
        {'id': 2, 'name': 'Listrik & Air'},
        {'id': 3, 'name': 'Gaji Harian Kasir'},
        {'id': 4, 'name': 'Perlengkapan & Kemasan'},
        {'id': 5, 'name': 'Transport & Pengiriman'},
        {'id': 6, 'name': 'Perawatan Toko'},
      ];

  String _methodNameById(int? id) {
    final found = _paymentMethods.firstWhere(
      (m) => (m['id'] as num?)?.toInt() == id,
      orElse: () => {'name': 'Tunai'},
    );
    return (found['name'] ?? 'Tunai').toString();
  }

  void _applyLocalDebtBookData() {
    final localRec = _offlineDb.getLocalReceivables();
    final localPay = _offlineDb
        .getLocalPayables()
        .where((p) => ((p['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .toList();
    final localExp = _offlineDb.getLocalExpenses();

    final recTotal = localRec.fold<double>(
      0.0,
      (sum, item) => sum + ((item['balance_due'] as num?)?.toDouble() ?? 0.0),
    );
    final payTotal = localPay.fold<double>(
      0.0,
      (sum, item) => sum + ((item['balance_due'] as num?)?.toDouble() ?? 0.0),
    );

    if (!mounted) return;
    setState(() {
      _totalReceivables = recTotal;
      _receivables = localRec;
      _totalPayables = payTotal;
      _payables = localPay;
      _expenses = localExp;
      _expenseCategories = List<Map<String, dynamic>>.from(_defaultOfflineExpenseCategories);
      if (_paymentMethods.isEmpty) {
        _paymentMethods = List<Map<String, dynamic>>.from(_defaultOfflinePaymentMethods);
      }
      _error = null;
      _loading = false;
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isLocalStandalone || !(await _connectivity.checkOnline())) {
      _applyLocalDebtBookData();
      return;
    }

    try {
      final results = await Future.wait([
        _api.dio.get(ApiEndpoints.receivables),
        _api.dio.get(ApiEndpoints.payables),
        _api.dio.get(ApiEndpoints.expenses),
        _api.dio.get(ApiEndpoints.paymentMethods),
      ]);

      final recData = Map<String, dynamic>.from((results[0].data['data'] as Map?) ?? {});
      final recSummary = Map<String, dynamic>.from((recData['summary'] as Map?) ?? {});
      final invoices = (recData['invoices'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final payData = Map<String, dynamic>.from((results[1].data['data'] as Map?) ?? {});
      final paySummary = Map<String, dynamic>.from((payData['summary'] as Map?) ?? {});
      final payInvoices = (payData['invoices'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final expData = Map<String, dynamic>.from((results[2].data['data'] as Map?) ?? {});
      final exps = (expData['expenses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final cats = (expData['categories'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final methods = (results[3].data['data'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _totalReceivables = (recSummary['total_receivables'] as num?)?.toDouble() ?? 0;
        _receivables = invoices;
        _totalPayables = (paySummary['total_payables'] as num?)?.toDouble() ?? 0;
        _payables = payInvoices;
        _expenses = exps;
        _expenseCategories = cats;
        _paymentMethods = methods;
        _loading = false;
      });
    } catch (e) {
      if (_isLocalStandalone ||
          _offlineDb.getLocalSalesHistory().isNotEmpty ||
          _offlineDb.getLocalPayables().isNotEmpty ||
          _offlineDb.getLocalExpenses().isNotEmpty) {
        _applyLocalDebtBookData();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _showPayInstallmentModal(int index) {
    final item = _receivables[index];
    final currentDue = (item['balance_due'] as num?)?.toDouble() ?? 0;
    final customerName = (item['customer']?['name'] ?? item['customer_name'] ?? 'Pelanggan').toString();
    final saleId = (item['sale_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0;
    final isLocalItem = _isLocalStandalone || item['is_local'] == true;
    final amountCtrl = TextEditingController(text: currentDue.toStringAsFixed(0));
    int? selectedMethodId = _paymentMethods.isNotEmpty ? (_paymentMethods.first['id'] as num?)?.toInt() : 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) => Padding(
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
                'Catat Pembayaran Bon — $customerName',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Nota ${item['number']} • Sisa Tagihan: ${IdrCurrencyFormatter.format(currentDue)}',
                style: const TextStyle(color: AppColors.slate600, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (_paymentMethods.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: selectedMethodId,
                  decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                  items: _paymentMethods
                      .map((pm) => DropdownMenuItem<int>(
                            value: (pm['id'] as num).toInt(),
                            child: Text((pm['name'] ?? 'Tunai').toString()),
                          ))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedMethodId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal Dibayar (Rp)',
                  prefixIcon: Icon(Icons.payments_rounded, color: AppColors.success),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  onPressed: () async {
                    final paid = IdrCurrencyFormatter.parse(amountCtrl.text);
                    if (paid <= 0 || selectedMethodId == null) return;
                    final methodName = _methodNameById(selectedMethodId);
                    Navigator.pop(ctx);
                    try {
                      if (isLocalItem || !(await _connectivity.checkOnline())) {
                        await _offlineDb.payLocalReceivable(
                          saleId: saleId,
                          amount: paid,
                          paymentMethod: methodName,
                        );
                        await _loadData();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cicilan / pelunasan kasbon dicatat secara lokal!')),
                        );
                        return;
                      }
                      await _api.dio.post(
                        ApiEndpoints.payReceivable(saleId),
                        data: {
                          'payment_method_id': selectedMethodId,
                          'amount': paid,
                        },
                      );
                      await _loadData();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pembayaran piutang Buku Bon berhasil dicatat!')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                      );
                    }
                  },
                  child: const Text('Simpan Pembayaran Piutang'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaySupplierModal(int index) {
    final item = _payables[index];
    final currentDue = (item['balance_due'] as num?)?.toDouble() ?? 0;
    final supplierName = (item['supplier']?['name'] ?? item['supplier']?['business_name'] ?? 'Supplier').toString();
    final bankName = (item['supplier']?['bank_name'] ?? '-').toString();
    final bankAcc = (item['supplier']?['bank_account_number'] ?? '-').toString();
    final bankHolder = (item['supplier']?['bank_account_holder'] ?? '-').toString();
    final purchaseId = (item['purchase_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0;
    final isLocalItem = _isLocalStandalone || item['is_local'] == true;

    final amountCtrl = TextEditingController(text: currentDue.toInt().toString());
    final notesCtrl = TextEditingController();
    int? selectedMethodId = _paymentMethods.isNotEmpty
        ? (_paymentMethods.first['id'] as num).toInt()
        : 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) => Padding(
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
                'Bayar Faktur Hutang — $supplierName',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Faktur: ${item['number']} • Sisa Hutang: ${IdrCurrencyFormatter.format(currentDue)}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
              ),
              if (bankName != '-' || bankAcc != '-') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rekening Supplier: $bankName $bankAcc',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navyDark),
                            ),
                            if (bankHolder != '-')
                              Text(
                                'a.n. $bankHolder',
                                style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_paymentMethods.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: selectedMethodId,
                  decoration: const InputDecoration(labelText: 'Sumber Rekening / Metode Bayar'),
                  items: _paymentMethods
                      .map((m) => DropdownMenuItem<int>(
                            value: (m['id'] as num).toInt(),
                            child: Text((m['name'] ?? 'Transfer Bank').toString()),
                          ))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedMethodId = v),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nominal Dibayar (Rp)',
                  prefixIcon: Icon(Icons.payments_rounded, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Keterangan / Nomor Referensi Transfer',
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final paid = IdrCurrencyFormatter.parse(amountCtrl.text);
                    if (paid <= 0 || selectedMethodId == null) return;
                    final methodName = _methodNameById(selectedMethodId);
                    Navigator.pop(ctx);
                    try {
                      if (isLocalItem || !(await _connectivity.checkOnline())) {
                        await _offlineDb.payLocalPayable(
                          payableId: purchaseId,
                          amount: paid,
                          paymentMethod: methodName,
                        );
                        await _loadData();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pembayaran hutang supplier berhasil dicatat secara lokal!')),
                        );
                        return;
                      }
                      await _api.dio.post(
                        ApiEndpoints.payPayable(purchaseId),
                        data: {
                          'payment_method_id': selectedMethodId,
                          'amount': paid,
                          'reference': notesCtrl.text.trim(),
                        },
                      );
                      await _loadData();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pembayaran hutang supplier berhasil dicatat!')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                      );
                    }
                  },
                  child: const Text('Simpan Pembayaran Hutang'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddExpenseModal() {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    int? selectedCatId = _expenseCategories.isNotEmpty ? (_expenseCategories.first['id'] as num?)?.toInt() : null;
    const presetLabels = [
      'Listrik',
      'Air',
      'Gaji Harian Kasir',
      'Kantong Kresek',
      'Konsumsi',
      'Transport',
      'Perawatan Toko',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) => Padding(
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
                  'Catat Biaya Operasional Toko',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Kategori Cepat:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presetLabels.map((preset) {
                    return NusaPillFilter(
                      label: preset,
                      selected: descCtrl.text.trim() == preset,
                      onTap: () {
                        descCtrl.text = preset;
                        setModalState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (_expenseCategories.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: selectedCatId,
                    decoration: const InputDecoration(labelText: 'Pos Biaya Akuntansi'),
                    items: _expenseCategories
                        .map((c) => DropdownMenuItem<int>(
                              value: (c['id'] as num).toInt(),
                              child: Text((c['name'] ?? 'Operasional').toString()),
                            ))
                        .toList(),
                    onChanged: (v) => setModalState(() => selectedCatId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan Biaya / Pengeluaran *',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nominal Pengeluaran (Rp) *',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                      if (amt <= 0 || descCtrl.text.trim().isEmpty) return;
                      final chosenCatName = _expenseCategories
                          .firstWhere(
                            (c) => (c['id'] as num?)?.toInt() == selectedCatId,
                            orElse: () => {'name': 'Operasional Toko'},
                          )['name']
                          .toString();
                      Navigator.pop(ctx);
                      try {
                        if (_isLocalStandalone || !(await _connectivity.checkOnline())) {
                          await _offlineDb.addLocalExpense(
                            category: chosenCatName,
                            amount: amt,
                            description: descCtrl.text.trim(),
                            paymentMethod: 'Tunai',
                          );
                          await _loadData();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Biaya operasional dicatat secara lokal!')),
                          );
                          return;
                        }
                        await _api.dio.post(
                          ApiEndpoints.expenses,
                          data: {
                            'category_id': selectedCatId,
                            'amount': amt,
                            'description': descCtrl.text.trim(),
                          },
                        );
                        await _loadData();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                        );
                      }
                    },
                    child: const Text('Simpan Biaya Operasional'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeName = context.watch<AuthCubit>().state.session.activeStore.name;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Buku Bon & Biaya Toko'),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.slate500,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(text: 'Piutang Bon'),
            Tab(text: 'Hutang Supplier'),
            Tab(text: 'Biaya Toko'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? NusaEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Gagal Memuat Buku Bon',
                  subtitle: _error!,
                  actionLabel: 'Coba Lagi',
                  onAction: _loadData,
                )
              : Column(
                  children: [
                    // Executive Summary Comparison Banner: Piutang vs Hutang
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _tabController.animateTo(0),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.warningSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Piutang Bon',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.warningDark,
                                          ),
                                        ),
                                        NusaBadge(
                                          label: '${_receivables.length}',
                                          variant: NusaBadgeVariant.warning,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    NusaPriceTag(
                                      amount: _totalReceivables,
                                      fontSize: 15.5,
                                      color: AppColors.navyDark,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => _tabController.animateTo(1),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Hutang Tempo',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.dangerDark,
                                          ),
                                        ),
                                        NusaBadge(
                                          label: '${_payables.length}',
                                          variant: NusaBadgeVariant.danger,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    NusaPriceTag(
                                      amount: _totalPayables,
                                      fontSize: 15.5,
                                      color: AppColors.navyDark,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // TAB 1: PIUTANG BON PELANGGAN
                          ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              SizedBox(
                                height: 36,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: ['Semua', 'Belum Jatuh Tempo', '1-30 Hari', '>30 Hari']
                                      .map((ageFilter) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: NusaPillFilter(
                                        label: ageFilter,
                                        selected: _receivableAgingFilter == ageFilter,
                                        onTap: () => setState(() => _receivableAgingFilter = ageFilter),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Builder(builder: (context) {
                                final filteredRecs = _receivables.where((r) {
                                  final age = (r['age_days'] as num?)?.toInt() ?? 0;
                                  if (_receivableAgingFilter == 'Belum Jatuh Tempo') return age <= 0;
                                  if (_receivableAgingFilter == '1-30 Hari') return age >= 1 && age <= 30;
                                  if (_receivableAgingFilter == '>30 Hari') return age > 30;
                                  return true;
                                }).toList();

                                if (filteredRecs.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 24),
                                    child: NusaEmptyState(
                                      icon: Icons.menu_book_outlined,
                                      title: 'Tidak Ada Piutang',
                                      subtitle: 'Tidak ada tagihan piutang pelanggan pada kategori jatuh tempo ini.',
                                    ),
                                  );
                                }

                                return Column(
                                  children: filteredRecs.map((r) {
                                    final originalIdx = _receivables.indexOf(r);
                                    final cust = Map<String, dynamic>.from((r['customer'] as Map?) ?? {});
                                    final custName = (cust['name'] ?? 'Pelanggan').toString();
                                    final phone = (cust['phone'] ?? '').toString();
                                    final ageDays = (r['age_days'] as num?)?.toInt() ?? 0;
                                    final agingLabel = ageDays <= 0
                                        ? 'Belum Jatuh Tempo'
                                        : (ageDays <= 30 ? '1-30 Hari ($ageDays hr)' : '>30 Hari ($ageDays hr)');
                                    final agingVariant = ageDays <= 0
                                        ? NusaBadgeVariant.primary
                                        : (ageDays <= 30 ? NusaBadgeVariant.warning : NusaBadgeVariant.danger);

                                    return NusaCard(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  custName,
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.navyDark,
                                                  ),
                                                ),
                                              ),
                                              NusaPriceTag(
                                                amount: (r['balance_due'] as num?)?.toDouble() ?? 0,
                                                fontSize: 15,
                                                color: AppColors.danger,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              NusaBadge(label: agingLabel, variant: agingVariant),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Nota ${r['number']} • WA: ${phone.isEmpty ? '-' : phone}',
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              if (phone.isNotEmpty) ...[
                                                Expanded(
                                                  child: NusaButton(
                                                    label: 'Tagih WA',
                                                    icon: Icons.chat_rounded,
                                                    variant: NusaButtonVariant.outline,
                                                    minHeight: 44,
                                                    onPressed: () {
                                                      WhatsAppService.sendDebtReminder(
                                                        customerName: custName,
                                                        customerPhone: phone,
                                                        invoiceNumber: r['number'].toString(),
                                                        balanceDue: (r['balance_due'] as num?)?.toDouble() ?? 0,
                                                        storeName: storeName,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                              ],
                                              Expanded(
                                                child: NusaButton(
                                                  label: 'Terima Cicilan',
                                                  icon: Icons.check_circle_outline_rounded,
                                                  minHeight: 44,
                                                  onPressed: () => _showPayInstallmentModal(originalIdx),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              }),
                            ],
                          ),

                          // TAB 2: HUTANG USAHA SUPPLIER (PAYABLES)
                          ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: NusaButton(
                                      label: 'Data Pemasok',
                                      icon: Icons.local_shipping_outlined,
                                      variant: NusaButtonVariant.outline,
                                      minHeight: 44,
                                      onPressed: () => context.push('/suppliers'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: NusaButton(
                                      label: 'Stok Masuk Beli',
                                      icon: Icons.add_shopping_cart_rounded,
                                      minHeight: 44,
                                      onPressed: () => context.push('/suppliers?tab=stock-in'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_payables.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 24),
                                  child: NusaEmptyState(
                                    icon: Icons.local_shipping_outlined,
                                    title: 'Hutang Supplier Lunas',
                                    subtitle: 'Tidak ada tagihan pembelian tempo supplier yang belum lunas.',
                                  ),
                                )
                              else
                                ...List.generate(_payables.length, (idx) {
                                  final p = _payables[idx];
                                  final supp = Map<String, dynamic>.from((p['supplier'] as Map?) ?? {});
                                  final suppName = (supp['name'] ?? supp['business_name'] ?? 'Supplier').toString();
                                  final phone = (supp['phone'] ?? '').toString();
                                  final bankName = (supp['bank_name'] ?? '').toString();
                                  final bankAcc = (supp['bank_account_number'] ?? '').toString();
                                  final bankHolder = (supp['bank_account_holder'] ?? '').toString();
                                  final isOverdue = p['is_overdue'] == true;

                                  return NusaCard(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                suppName,
                                                style: const TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.navyDark,
                                                ),
                                              ),
                                            ),
                                            NusaPriceTag(
                                              amount: (p['balance_due'] as num?)?.toDouble() ?? 0,
                                              fontSize: 15,
                                              color: AppColors.danger,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            NusaBadge(
                                              label: isOverdue ? 'Jatuh Tempo Lewat' : 'Tempo',
                                              variant: isOverdue ? NusaBadgeVariant.danger : NusaBadgeVariant.warning,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Faktur: ${p['number']} • Tempo: ${p['due_date'] ?? '-'}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (bankName.isNotEmpty || bankAcc.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.background,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: AppColors.border),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.account_balance_outlined, size: 17, color: AppColors.primary),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '$bankName $bankAcc ${bankHolder.isNotEmpty ? "($bankHolder)" : ""}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.navyDark,
                                                    ),
                                                  ),
                                                ),
                                                if (bankAcc.isNotEmpty)
                                                  InkWell(
                                                    onTap: () {
                                                      Clipboard.setData(ClipboardData(text: bankAcc));
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('No. Rekening $bankAcc disalin!')),
                                                      );
                                                    },
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      constraints: const BoxConstraints(minHeight: 36),
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.primarySoft,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Row(
                                                        children: [
                                                          Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Salin',
                                                            style: TextStyle(
                                                              fontSize: 11,
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
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            if (phone.isNotEmpty) ...[
                                              Expanded(
                                                child: NusaButton(
                                                  label: 'Hubungi WA',
                                                  icon: Icons.chat_rounded,
                                                  variant: NusaButtonVariant.outline,
                                                  minHeight: 44,
                                                  onPressed: () {
                                                    WhatsAppService.sendDebtReminder(
                                                      customerName: suppName,
                                                      customerPhone: phone,
                                                      invoiceNumber: p['number'].toString(),
                                                      balanceDue: (p['balance_due'] as num?)?.toDouble() ?? 0,
                                                      storeName: storeName,
                                                    );
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                            Expanded(
                                              child: NusaButton(
                                                label: 'Bayar Hutang',
                                                icon: Icons.payment_rounded,
                                                minHeight: 44,
                                                onPressed: () => _showPaySupplierModal(idx),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),

                          // TAB 3: BIAYA OPERASIONAL TOKO
                          ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              NusaButton(
                                label: 'Tambah Biaya Operasional / Pembelian',
                                icon: Icons.add_rounded,
                                onPressed: _showAddExpenseModal,
                              ),
                              const SizedBox(height: 14),
                              if (_expenses.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 24),
                                  child: NusaEmptyState(
                                    icon: Icons.receipt_long_outlined,
                                    title: 'Belum Ada Biaya Operasional',
                                    subtitle: 'Catat pengeluaran operasional seperti listrik, plastik, atau transportasi toko.',
                                  ),
                                )
                              else
                                ..._expenses.map((exp) {
                                  final catName = (exp['category']?['name'] ?? exp['category_name'] ?? 'Operasional').toString();
                                  final dateStr = (exp['expense_date'] ?? exp['created_at'] ?? '').toString();
                                  return NusaCard(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: AppColors.dangerSoft,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.receipt_long_rounded, color: AppColors.danger, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (exp['description'] ?? '-').toString(),
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.navyDark,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$catName • $dateStr',
                                                style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                              ),
                                            ],
                                          ),
                                        ),
                                        NusaPriceTag(
                                          amount: (exp['amount'] as num?)?.toDouble() ?? 0,
                                          fontSize: 13.5,
                                          color: AppColors.dangerDark,
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
