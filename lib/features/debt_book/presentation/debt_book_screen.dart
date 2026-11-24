import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';

part 'debt_book_parity_modals.dart';

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
  final PrinterService _printer = GetIt.instance<PrinterService>();
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
  String _expenseCategoryFilter = 'Semua';

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

  void _refreshPosPendingBadge() {
    if (!mounted) return;
    try {
      context.read<PosCubit>().refreshOfflinePendingState();
    } catch (_) {}
  }

  void _applyLocalDebtBookData() {
    final localRec = _offlineDb.getLocalReceivables();
    final cachedCloudRec = _offlineDb
        .getCachedCloudReceivables()
        .where((r) => ((r['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .toList();
    final mergedRec = <Map<String, dynamic>>[...localRec];
    final existingKeys = mergedRec
        .map((r) => '${r['sale_id'] ?? r['id'] ?? ''}|${r['number'] ?? ''}')
        .toSet();
    for (final cloudItem in cachedCloudRec) {
      final key = '${cloudItem['sale_id'] ?? cloudItem['id'] ?? ''}|${cloudItem['number'] ?? ''}';
      if (!existingKeys.contains(key)) {
        mergedRec.add(cloudItem);
        existingKeys.add(key);
      }
    }

    final localPay = _offlineDb
        .getLocalPayables()
        .where((p) => ((p['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .toList();
    final localExp = _offlineDb.getLocalExpenses();

    final recTotal = mergedRec.fold<double>(
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
      _receivables = mergedRec;
      _totalPayables = payTotal;
      _payables = localPay;
      _expenses = localExp;
      final cachedExpCats = _offlineDb.getCachedExpenseCategories();
      _expenseCategories = cachedExpCats.isNotEmpty
          ? cachedExpCats
          : List<Map<String, dynamic>>.from(_defaultOfflineExpenseCategories);
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

      // Cache authoritative Cloud receivables locally so offline installment payments stay available
      await _offlineDb.cacheCloudReceivables(invoices);

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
      if (cats.isNotEmpty) {
        await _offlineDb.cacheExpenseCategories(cats);
      }

      // Include any unsynced local expenses at the top until Cloud sync completes
      final unsyncedLocalExps = _offlineDb.getUnsyncedLocalExpenses();
      final mergedExps = <Map<String, dynamic>>[
        ...unsyncedLocalExps,
        ...exps,
      ];

      final methods = (results[3].data['data'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _totalReceivables = (recSummary['total_receivables'] as num?)?.toDouble() ?? 0;
        _receivables = invoices;
        _totalPayables = (paySummary['total_payables'] as num?)?.toDouble() ?? 0;
        _payables = payInvoices;
        _expenses = mergedExps;
        _expenseCategories = cats;
        _paymentMethods = methods;
        _loading = false;
      });
    } catch (e) {
      if (_isLocalStandalone ||
          _offlineDb.getLocalSalesHistory().isNotEmpty ||
          _offlineDb.getCachedCloudReceivables().isNotEmpty ||
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
    final customerId = ((item['customer'] is Map ? item['customer']['id'] : null) ??
            item['customer_id']) as num?;
    final saleId = (item['sale_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0;
    final saleLocalUuid = item['local_uuid']?.toString();
    final isLocalOnlySale = _isLocalStandalone || item['is_local'] == true || saleId > 1000000000;
    final amountCtrl = TextEditingController(text: currentDue.toStringAsFixed(0));
    int? selectedMethodId = _paymentMethods.isNotEmpty ? (_paymentMethods.first['id'] as num?)?.toInt() : 1;
    bool isSaving = false;
    String? modalError;
    final idempotencyKey = const Uuid().v4();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                style: TextStyle(color: NusaThemeTokens.of(mCtx).textSecondary, fontSize: 13),
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
                  onChanged: isSaving ? null : (v) => setModalState(() => selectedMethodId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nominal Dibayar (Rp)',
                  prefixIcon: Icon(Icons.payments_rounded, color: NusaThemeTokens.of(mCtx).positive),
                ),
              ),
              if (modalError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(mCtx).dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NusaThemeTokens.of(mCtx).danger.withOpacity(0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: NusaThemeTokens.of(mCtx).danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          modalError!,
                          style: TextStyle(
                            color: NusaThemeTokens.of(mCtx).danger,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: NusaThemeTokens.of(mCtx).positive),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final paid = IdrCurrencyFormatter.parse(amountCtrl.text);
                          if (paid <= 0 || selectedMethodId == null) {
                            setModalState(() => modalError = 'Masukkan nominal pembayaran yang valid (> 0).');
                            return;
                          }
                          setModalState(() {
                            isSaving = true;
                            modalError = null;
                          });

                          final methodName = _methodNameById(selectedMethodId);
                          final invNo = (item['number'] ?? 'BON-$saleId').toString();
                          final custPhone =
                              (item['customer']?['phone'] ?? item['customer_phone'] ?? '').toString();
                          final remain = (currentDue - paid).clamp(0.0, double.infinity);

                          Future<void> saveOfflineAndFinish() async {
                            await _offlineDb.payLocalReceivable(
                              saleId: saleId,
                              saleLocalUuid: saleLocalUuid,
                              amount: paid,
                              paymentMethod: methodName,
                              paymentMethodId: selectedMethodId ?? 1,
                              invoiceNumber: invNo,
                              customerName: customerName,
                              customerId: customerId?.toInt(),
                              enqueueForCloudSync: !_isLocalStandalone,
                              idempotencyKey: idempotencyKey,
                            );
                            _refreshPosPendingBadge();
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadData();
                            if (!mounted) return;
                            if (!_isLocalStandalone) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(mCtx).warning,
                                  content: Text(
                                    'Pelunasan piutang disimpan offline & masuk antrean sinkronisasi Cloud.',
                                  ),
                                ),
                              );
                            }
                            _showSettlementReceiptDialog(
                              isReceivable: true,
                              partyName: customerName,
                              phone: custPhone,
                              invoiceNumber: invNo,
                              paidAmount: paid,
                              remainingBalance: remain,
                              paymentMethod: methodName,
                            );
                          }

                          try {
                            if (isLocalOnlySale || !(await _connectivity.checkOnline())) {
                              await saveOfflineAndFinish();
                              return;
                            }
                            await _api.dio.post(
                              ApiEndpoints.payReceivable(saleId),
                              data: {
                                'payment_method_id': selectedMethodId,
                                'amount': paid,
                              },
                              options: Options(
                                headers: {
                                  'X-Idempotency-Key': idempotencyKey,
                                },
                              ),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadData();
                            if (!mounted) return;
                            _showSettlementReceiptDialog(
                              isReceivable: true,
                              partyName: customerName,
                              phone: custPhone,
                              invoiceNumber: invNo,
                              paidAmount: paid,
                              remainingBalance: remain,
                              paymentMethod: methodName,
                            );
                          } catch (e) {
                            if (ApiClient.isNetworkOfflineError(e)) {
                              await saveOfflineAndFinish();
                              return;
                            }
                            if (!ctx.mounted) return;
                            setModalState(() {
                              isSaving = false;
                              modalError = ApiClient.extractErrorMessage(e);
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Simpan Pembayaran Piutang'),
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(mCtx).textSecondary),
              ),
              if (bankName != '-' || bankAcc != '-') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(mCtx).accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_rounded, color: NusaThemeTokens.of(mCtx).accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rekening Supplier: $bankName $bankAcc',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: NusaThemeTokens.of(mCtx).textPrimary),
                            ),
                            if (bankHolder != '-')
                              Text(
                                'a.n. $bankHolder',
                                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(mCtx).textSecondary),
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
                decoration: InputDecoration(
                  labelText: 'Nominal Dibayar (Rp)',
                  prefixIcon: Icon(Icons.payments_rounded, color: NusaThemeTokens.of(mCtx).accent),
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
                      final invNo = (item['number'] ?? 'PO-$purchaseId').toString();
                      final suppPhone = (item['supplier']?['phone'] ?? '').toString();
                      final remain = (currentDue - paid).clamp(0.0, double.infinity);
                      if (isLocalItem || !(await _connectivity.checkOnline())) {
                        await _offlineDb.payLocalPayable(
                          payableId: purchaseId,
                          amount: paid,
                          paymentMethod: methodName,
                        );
                        await _loadData();
                        if (!mounted) return;
                        _showSettlementReceiptDialog(
                          isReceivable: false,
                          partyName: supplierName,
                          phone: suppPhone,
                          invoiceNumber: invNo,
                          paidAmount: paid,
                          remainingBalance: remain,
                          paymentMethod: methodName,
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
                      _showSettlementReceiptDialog(
                        isReceivable: false,
                        partyName: supplierName,
                        phone: suppPhone,
                        invoiceNumber: invNo,
                        paidAmount: paid,
                        remainingBalance: remain,
                        paymentMethod: methodName,
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
    bool isSaving = false;
    String? modalError;
    final idempotencyKey = const Uuid().v4();
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
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                Text(
                  'Kategori Cepat:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(mCtx).textSecondary),
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
                        if (isSaving) return;
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
                    onChanged: isSaving ? null : (v) => setModalState(() => selectedCatId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: descCtrl,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan Biaya / Pengeluaran *',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amtCtrl,
                  enabled: !isSaving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nominal Pengeluaran (Rp) *',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: NusaThemeTokens.of(mCtx).dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NusaThemeTokens.of(mCtx).danger.withOpacity(0.35)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, color: NusaThemeTokens.of(mCtx).danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            modalError!,
                            style: TextStyle(
                              color: NusaThemeTokens.of(mCtx).danger,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                            final desc = descCtrl.text.trim();
                            if (amt <= 0 || desc.isEmpty) {
                              setModalState(() => modalError = 'Lengkapi keterangan dan nominal (> 0).');
                              return;
                            }
                            setModalState(() {
                              isSaving = true;
                              modalError = null;
                            });
                            final chosenCatName = _expenseCategories
                                .firstWhere(
                                  (c) => (c['id'] as num?)?.toInt() == selectedCatId,
                                  orElse: () => {'name': 'Operasional Toko'},
                                )['name']
                                .toString();

                            Future<void> saveOfflineExpenseAndFinish() async {
                              await _offlineDb.addLocalExpense(
                                category: chosenCatName,
                                categoryId: selectedCatId,
                                amount: amt,
                                description: desc,
                                paymentMethod: 'Tunai',
                                localUuid: idempotencyKey,
                                isSynced: false,
                              );
                              _refreshPosPendingBadge();
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor:
                                      _isLocalStandalone ? NusaThemeTokens.of(mCtx).positive : NusaThemeTokens.of(mCtx).warning,
                                  content: Text(
                                    _isLocalStandalone
                                        ? 'Biaya operasional dicatat secara lokal!'
                                        : 'Biaya disimpan offline & akan otomatis disinkronkan ke Cloud saat online.',
                                  ),
                                ),
                              );
                            }

                            try {
                              if (_isLocalStandalone || !(await _connectivity.checkOnline())) {
                                await saveOfflineExpenseAndFinish();
                                return;
                              }
                              await _api.dio.post(
                                ApiEndpoints.expenses,
                                data: {
                                  'category_id': selectedCatId,
                                  'amount': amt,
                                  'description': desc,
                                },
                                options: Options(
                                  headers: {
                                    'X-Idempotency-Key': idempotencyKey,
                                  },
                                ),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                            } catch (e) {
                              if (ApiClient.isNetworkOfflineError(e)) {
                                await saveOfflineExpenseAndFinish();
                                return;
                              }
                              if (!ctx.mounted) return;
                              setModalState(() {
                                isSaving = false;
                                modalError = ApiClient.extractErrorMessage(e);
                              });
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Simpan Biaya Operasional'),
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
    final tokens = NusaThemeTokens.of(context);
    final storeName = context.watch<AuthCubit>().state.session.activeStore.name;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Buku Bon & Biaya Toko'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/cash-ledger'),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Buku Kas'),
          ),
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _loadData,
            icon: Icon(Icons.refresh_rounded, color: tokens.accent),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          indicatorColor: tokens.accent,
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
                      decoration: BoxDecoration(
                        color: tokens.bgSurface,
                        border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
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
                                  color: tokens.warningSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: tokens.warning.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                                    width: tokens.borderWidth,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Piutang Bon',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: tokens.warning,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        NusaBadge(
                                          label: '${_receivables.length}',
                                          variant: NusaBadgeVariant.warning,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: NusaPriceTag(
                                        amount: _totalReceivables,
                                        fontSize: 15.5,
                                        color: tokens.textPrimary,
                                      ),
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
                                  color: tokens.dangerSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: tokens.danger.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                                    width: tokens.borderWidth,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Hutang Tempo',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: tokens.danger,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        NusaBadge(
                                          label: '${_payables.length}',
                                          variant: NusaBadgeVariant.danger,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: NusaPriceTag(
                                        amount: _totalPayables,
                                        fontSize: 15.5,
                                        color: tokens.textPrimary,
                                      ),
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
                              if (_receivables.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showBatchSettlementModal(isReceivable: true),
                                        icon: const Icon(Icons.done_all_rounded, size: 18),
                                        label: const Text('Pelunasan Gabungan (Multi-Nota)'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],
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
                                                  style: TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: NusaThemeTokens.of(context).textPrimary,
                                                  ),
                                                ),
                                              ),
                                              NusaPriceTag(
                                                amount: (r['balance_due'] as num?)?.toDouble() ?? 0,
                                                fontSize: 15,
                                                color: NusaThemeTokens.of(context).danger,
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
                                                  style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
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
                                                const SizedBox(width: 8),
                                              ],
                                              IconButton(
                                                tooltip: 'Riwayat Cicilan',
                                                onPressed: () => _showInstallmentHistoryModal(
                                                  isReceivable: true,
                                                  invoice: r,
                                                  partyName: custName,
                                                ),
                                                icon: Icon(Icons.history_rounded, color: NusaThemeTokens.of(context).accent),
                                              ),
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
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: NusaThemeTokens.of(context).textPrimary,
                                                ),
                                              ),
                                            ),
                                            NusaPriceTag(
                                              amount: (p['balance_due'] as num?)?.toDouble() ?? 0,
                                              fontSize: 15,
                                              color: NusaThemeTokens.of(context).danger,
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
                                                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (bankName.isNotEmpty || bankAcc.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: NusaThemeTokens.of(context).bgPage,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.account_balance_outlined, size: 17, color: NusaThemeTokens.of(context).accent),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '$bankName $bankAcc ${bankHolder.isNotEmpty ? "($bankHolder)" : ""}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: NusaThemeTokens.of(context).textPrimary,
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
                                                        color: NusaThemeTokens.of(context).accentSoft,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.copy_rounded, size: 14, color: NusaThemeTokens.of(context).accent),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Salin',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w800,
                                                              color: NusaThemeTokens.of(context).accent,
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
                                            IconButton(
                                              tooltip: 'Riwayat Bayar Hutang',
                                              onPressed: () => _showInstallmentHistoryModal(
                                                isReceivable: false,
                                                invoice: p,
                                                partyName: suppName,
                                              ),
                                              icon: Icon(Icons.history_rounded, color: NusaThemeTokens.of(context).accent),
                                            ),
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
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: NusaButton(
                                      label: 'Catat Biaya Baru',
                                      icon: Icons.add_rounded,
                                      onPressed: _showAddExpenseModal,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: NusaButton(
                                      label: 'Kategori',
                                      icon: Icons.folder_outlined,
                                      variant: NusaButtonVariant.outline,
                                      onPressed: _showExpenseCategoriesManager,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final cat in [
                                      'Semua',
                                      ..._expenseCategories.map((c) => (c['name'] ?? '').toString()).where((n) => n.isNotEmpty),
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: NusaPillFilter(
                                          label: cat,
                                          selected: _expenseCategoryFilter == cat,
                                          onTap: () => setState(() => _expenseCategoryFilter = cat),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Builder(builder: (context) {
                                final filteredExps = _expenses.where((exp) {
                                  if (_expenseCategoryFilter == 'Semua') return true;
                                  final cName = (exp['category']?['name'] ?? exp['category_name'] ?? 'Operasional').toString();
                                  return cName == _expenseCategoryFilter;
                                }).toList();
                                if (filteredExps.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 24),
                                    child: NusaEmptyState(
                                      icon: Icons.receipt_long_outlined,
                                      title: 'Belum Ada Biaya Operasional',
                                      subtitle: 'Catat pengeluaran operasional seperti listrik, plastik, atau transportasi toko.',
                                    ),
                                  );
                                }
                                return Column(
                                  children: filteredExps.map((exp) {
                                    final catName = (exp['category']?['name'] ?? exp['category_name'] ?? 'Operasional').toString();
                                    final dateStr = (exp['expense_date'] ?? exp['created_at'] ?? '').toString();
                                    return NusaCard(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: NusaThemeTokens.of(context).dangerSoft,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(Icons.receipt_long_rounded, color: NusaThemeTokens.of(context).danger, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  (exp['description'] ?? '-').toString(),
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: NusaThemeTokens.of(context).textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$catName • $dateStr',
                                                  style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              NusaPriceTag(
                                                amount: (exp['amount'] as num?)?.toDouble() ?? 0,
                                                fontSize: 13.5,
                                                color: NusaThemeTokens.of(context).danger,
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  InkWell(
                                                    onTap: () => _showEditExpenseModal(exp),
                                                    child: Padding(
                                                      padding: EdgeInsets.all(4),
                                                      child: Icon(Icons.edit_outlined, size: 17, color: NusaThemeTokens.of(context).accent),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () => _confirmDeleteExpense(exp),
                                                    child: Padding(
                                                      padding: EdgeInsets.all(4),
                                                      child: Icon(Icons.delete_outline, size: 17, color: NusaThemeTokens.of(context).danger),
                                                    ),
                                                  ),
                                                ],
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
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
