import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// PUSAT PEMBELIAN (PO MULTI-ITEM + AI REORDER) & RETUR PEMBELIAN KE PEMASOK
class PurchasesAndReturnsScreen extends StatefulWidget {
  final int initialTab;

  const PurchasesAndReturnsScreen({super.key, this.initialTab = 0});

  @override
  State<PurchasesAndReturnsScreen> createState() => _PurchasesAndReturnsScreenState();
}

class _PurchasesAndReturnsScreenState extends State<PurchasesAndReturnsScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  late TabController _tabController;

  bool _loading = true;
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _reorderSuggestions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    if (_isLocalStandalone) {
      _loading = false;
      _purchases = _offlineDb.getLocalPurchases();
      _returns = _offlineDb.getLocalPurchaseReturns();
      _reorderSuggestions = context
          .read<PosCubit>()
          .state
          .allProducts
          .where((p) => !p.isServiceOrNonStockItem && p.stock <= p.reorderLevel)
          .map((p) => {
                'product_id': p.id,
                'name': p.name,
                'sku': p.sku,
                'unit_code': p.unitCode,
                'current_stock': p.stock,
                'reorder_level': p.reorderLevel,
                'suggested_qty': ((p.reorderLevel * 2) - p.stock).clamp(5.0, 50.0),
                'cost_price': p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7,
                'supplier_name': null,
              })
          .toList();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  Future<void> _loadData() async {
    setState(() => _loading = true);
    var localPurchases = _offlineDb.getLocalPurchases();
    var localReturns = _offlineDb.getLocalPurchaseReturns();
    List<Map<String, dynamic>> suggestions = context
        .read<PosCubit>()
        .state
        .allProducts
        .where((p) => !p.isServiceOrNonStockItem && p.stock <= p.reorderLevel)
        .map((p) => {
              'product_id': p.id,
              'name': p.name,
              'sku': p.sku,
              'unit_code': p.unitCode,
              'current_stock': p.stock,
              'reorder_level': p.reorderLevel,
              'suggested_qty': ((p.reorderLevel * 2) - p.stock).clamp(5.0, 50.0),
              'cost_price': p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7,
              'supplier_name': null,
            })
        .toList();

    if (!_isLocalStandalone) {
      try {
        final pRes = await _api.dio.get(ApiEndpoints.purchases);
        final rawP = pRes.data['data'] as List<dynamic>?;
        if (rawP != null) {
          localPurchases = rawP.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      try {
        final rRes = await _api.dio.get(ApiEndpoints.purchaseReturns);
        final rawR = rRes.data['data'] as List<dynamic>?;
        if (rawR != null) {
          localReturns = rawR.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}

      try {
        final aiRes = await _api.dio.get(ApiEndpoints.purchaseAiReorder);
        final rawAi = aiRes.data['data'] as List<dynamic>?;
        if (rawAi != null) {
          suggestions = rawAi.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _purchases = localPurchases;
      _returns = localReturns;
      _reorderSuggestions = suggestions;
      _loading = false;
    });
  }

  void _openCreatePurchaseModal({
    List<Map<String, dynamic>>? initialLines,
    int? initialSupplierId,
  }) {
    final posState = context.read<PosCubit>().state;
    final suppliers = posState.suppliers;
    final products = posState.allProducts.where((p) => !p.isServiceOrNonStockItem).toList();

    Map<String, dynamic>? selectedSupplier = (initialSupplierId != null
            ? suppliers.where((s) => (s['id'] as num?)?.toInt() == initialSupplierId).firstOrNull
            : null) ??
        (suppliers.isNotEmpty ? suppliers.first : null);
    final invoiceCtrl = TextEditingController();
    final paidCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String paymentMode = 'paid'; // paid, partial, credit
    final List<Map<String, dynamic>> lines = initialLines != null
        ? initialLines.map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
    bool saving = false;
    String? modalError;

    double computeTotal() =>
        lines.fold(0.0, (s, e) => s + ((e['quantity'] as num).toDouble() * (e['unit_cost'] as num).toDouble()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final total = computeTotal();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.88,
            child: Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Buat Pembelian Stok (PO)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (suppliers.isEmpty)
                          const NusaCard(
                            backgroundColor: AppColors.warningSoft,
                            child: Text(
                              'Belum ada data Pemasok. Anda tetap bisa mencatat stok dengan pemasok umum atau tambahkan pemasok terlebih dahulu.',
                              style: TextStyle(fontSize: 12.5, color: AppColors.warningDark),
                            ),
                          )
                        else
                          DropdownButtonFormField<int>(
                            value: (selectedSupplier?['id'] as num?)?.toInt(),
                            decoration: const InputDecoration(
                              labelText: 'Pilih Pemasok / Supplier',
                              prefixIcon: Icon(Icons.local_shipping_outlined),
                            ),
                            items: suppliers
                                .map((s) => DropdownMenuItem<int>(
                                      value: (s['id'] as num).toInt(),
                                      child: Text(s['name'].toString()),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              setModal(() {
                                selectedSupplier = suppliers.where((s) => (s['id'] as num).toInt() == v).firstOrNull;
                              });
                            },
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: invoiceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'No. Faktur Supplier (Opsional)',
                            prefixIcon: Icon(Icons.receipt_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickProductForPurchase(ctx, products, (line) {
                                  setModal(() {
                                    lines.removeWhere((e) => e['product_id'] == line['product_id']);
                                    lines.add(line);
                                  });
                                }),
                                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                label: const Text('Tambah Barang'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!_isLocalStandalone && _reorderSuggestions.isEmpty) {
                                  try {
                                    final aiRes = await _api.dio.get(ApiEndpoints.purchaseAiReorder);
                                    final rawAi = aiRes.data['data'] as List<dynamic>?;
                                    if (rawAi != null && mounted) {
                                      _reorderSuggestions =
                                          rawAi.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                                    }
                                  } catch (_) {}
                                }
                                setModal(() {
                                  if (_reorderSuggestions.isNotEmpty) {
                                    for (final s in _reorderSuggestions.take(15)) {
                                      final pid = (s['product_id'] as num).toInt();
                                      lines.removeWhere((e) => e['product_id'] == pid);
                                      lines.add({
                                        'product_id': pid,
                                        'product_name': (s['name'] ?? 'Produk').toString(),
                                        'sku': (s['sku'] ?? '-').toString(),
                                        'unit_code': (s['unit_code'] ?? 'pcs').toString(),
                                        'quantity': (s['suggested_qty'] as num?)?.toDouble() ?? 10.0,
                                        'unit_cost': (s['cost_price'] as num?)?.toDouble() ?? 0.0,
                                      });
                                    }
                                  } else {
                                    final lowItems = products
                                        .where((p) => p.stock <= p.reorderLevel)
                                        .take(10)
                                        .toList();
                                    for (final p in lowItems) {
                                      final qty = ((p.reorderLevel * 2) - p.stock).clamp(5.0, 50.0);
                                      lines.removeWhere((e) => e['product_id'] == p.id);
                                      lines.add({
                                        'product_id': p.id,
                                        'product_name': p.name,
                                        'sku': p.sku,
                                        'unit_code': p.unitCode,
                                        'quantity': qty,
                                        'unit_cost': p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7,
                                      });
                                    }
                                  }
                                });
                              },
                              icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.primary),
                              label: const Text('Saran AI'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (lines.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text('Belum ada item barang dipilih.',
                                  style: TextStyle(color: AppColors.slate500)),
                            ),
                          )
                        else
                          ...lines.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: NusaCard(
                                  padding: const EdgeInsets.all(10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['product_name'].toString(),
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                            Text(
                                              '${IdrCurrencyFormatter.formatQty((item['quantity'] as num).toDouble())} ${item['unit_code']} x ${IdrCurrencyFormatter.format((item['unit_cost'] as num).toDouble())}',
                                              style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        IdrCurrencyFormatter.format(
                                            (item['quantity'] as num) * (item['unit_cost'] as num)),
                                        style: AppTheme.moneyStyle(fontSize: 13.5),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                                        onPressed: () => setModal(() => lines.remove(item)),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                        const SizedBox(height: 10),
                        const Text('Metode Pembayaran Pembelian',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'paid', label: Text('Lunas')),
                            ButtonSegment(value: 'partial', label: Text('DP Sebagian')),
                            ButtonSegment(value: 'credit', label: Text('Hutang Tempo')),
                          ],
                          selected: {paymentMode},
                          onSelectionChanged: (s) => setModal(() => paymentMode = s.first),
                        ),
                        if (paymentMode == 'partial') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: paidCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Nominal DP Dibayar (Rp)'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(labelText: 'Catatan Pembelian'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (modalError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.dangerDark, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              modalError!,
                              style: const TextStyle(
                                color: AppColors.dangerDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => setModal(() => modalError = null),
                            child: const Icon(Icons.close_rounded, color: AppColors.dangerDark, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Pembelian', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        IdrCurrencyFormatter.format(total),
                        style: AppTheme.moneyStyle(fontSize: 18, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  NusaButton(
                    label: 'Simpan & Terima Stok',
                    isLoading: saving,
                    variant: NusaButtonVariant.success,
                    icon: Icons.check_circle_rounded,
                    onPressed: (saving || lines.isEmpty)
                        ? null
                        : () async {
                            setModal(() {
                              saving = true;
                              modalError = null;
                            });
                            final paid = paymentMode == 'paid'
                                ? total
                                : (paymentMode == 'partial'
                                    ? IdrCurrencyFormatter.parse(paidCtrl.text)
                                    : 0.0);
                            final supId = (selectedSupplier?['id'] as num?)?.toInt() ?? 0;
                            final supName = (selectedSupplier?['name'] ?? 'Pemasok Umum').toString();

                            bool cloudOk = false;
                            if (!_isLocalStandalone) {
                              try {
                                await _api.dio.post(ApiEndpoints.purchases, data: {
                                  if (supId > 0) 'supplier_id': supId,
                                  'supplier_name': supName,
                                  'supplier_invoice_number': invoiceCtrl.text.trim(),
                                  'payment_mode': paymentMode,
                                  'paid_amount': paid,
                                  'notes': notesCtrl.text.trim(),
                                  'items': lines,
                                });
                                cloudOk = true;
                              } catch (e) {
                                if (!ApiClient.isNetworkOfflineError(e)) {
                                  final errMsg = ApiClient.extractErrorMessage(e);
                                  setModal(() {
                                    saving = false;
                                    modalError = errMsg;
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.danger,
                                        content: Text(errMsg),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }
                            }
                            if (!cloudOk) {
                              await _offlineDb.addLocalPurchase(
                                supplierId: supId,
                                supplierName: supName,
                                supplierPhone: selectedSupplier?['phone']?.toString(),
                                invoiceNumber: invoiceCtrl.text.trim(),
                                items: lines,
                                paymentMode: paymentMode,
                                paidAmount: paid,
                                notes: notesCtrl.text.trim(),
                              );
                            }
                            if (mounted) {
                              await context.read<PosCubit>().syncWithCloud(force: cloudOk, preserveActiveCart: true);
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadData();
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _pickProductForPurchase(
    BuildContext parentCtx,
    List<ProductModel> products,
    void Function(Map<String, dynamic> line) onAdd,
  ) {
    String q = '';
    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final filtered = products.where((p) {
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q.toLowerCase()) ||
                p.sku.toLowerCase().contains(q.toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Pilih Barang Dibeli'),
            content: SizedBox(
              width: 340,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setDlg(() => q = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari barang...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, idx) {
                        final p = filtered[idx];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text('HPP: ${IdrCurrencyFormatter.format(p.costPrice)} • Stok: ${IdrCurrencyFormatter.formatQty(p.stock)}'),
                          onTap: () {
                            Navigator.pop(ctx);
                            final qtyCtrl = TextEditingController(text: '10');
                            final costCtrl = TextEditingController(
                              text: (p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7).toInt().toString(),
                            );
                            final batchCtrl = TextEditingController();
                            showDialog(
                              context: parentCtx,
                              builder: (qCtx) => AlertDialog(
                                title: Text(p.name),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: qtyCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(labelText: 'Jumlah Beli (${p.unitCode})'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: costCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Harga Beli Satuan (Rp)'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: batchCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Nomor Batch / Lot (Opsional)',
                                        hintText: 'Kosongkan untuk auto-batch',
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(qCtx), child: const Text('Batal')),
                                  FilledButton(
                                    onPressed: () {
                                      final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                                      final cost = IdrCurrencyFormatter.parse(costCtrl.text);
                                      final batchNum = batchCtrl.text.trim();
                                      onAdd({
                                        'product_id': p.id,
                                        'product_name': p.name,
                                        'sku': p.sku,
                                        'unit_code': p.unitCode,
                                        'quantity': qty,
                                        'unit_cost': cost,
                                        if (batchNum.isNotEmpty) 'batch_number': batchNum,
                                      });
                                      Navigator.pop(qCtx);
                                    },
                                    child: const Text('Tambahkan'),
                                  ),
                                ],
                              ),
                            );
                          },
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

  void _openReturnPurchaseModal(Map<String, dynamic> purchase) {
    final items = (purchase['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rincian barang pada PO ini tidak tersedia untuk diretur.')),
      );
      return;
    }
    final notesCtrl = TextEditingController(text: 'Barang rusak / tidak sesuai pesanan');
    final Map<int, double> returnQtys = {
      for (int i = 0; i < items.length; i++) i: (items[i]['quantity'] as num?)?.toDouble() ?? 1.0,
    };
    bool returning = false;
    String? returnModalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
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
              Text('Retur Pembelian: ${purchase['number'] ?? purchase['purchase_number'] ?? '-'}',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...List.generate(items.length, (i) {
                final it = items[i];
                final maxQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                final curQty = returnQtys[i] ?? 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(it['product_name']?.toString() ?? 'Produk')),
                      IconButton(
                        onPressed: curQty > 0
                            ? () => setModal(() => returnQtys[i] = (curQty - 1).clamp(0, maxQty))
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(IdrCurrencyFormatter.formatQty(curQty)),
                      IconButton(
                        onPressed: curQty < maxQty
                            ? () => setModal(() => returnQtys[i] = (curQty + 1).clamp(0, maxQty))
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                );
              }),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Alasan Retur ke Supplier'),
              ),
              if (returnModalError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.dangerDark, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          returnModalError!,
                          style: const TextStyle(
                            color: AppColors.dangerDark,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setModal(() => returnModalError = null),
                        child: const Icon(Icons.close_rounded, color: AppColors.dangerDark, size: 16),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              NusaButton(
                label: 'Proses Retur Pembelian',
                isLoading: returning,
                variant: NusaButtonVariant.danger,
                icon: Icons.assignment_return_outlined,
                onPressed: returning
                    ? null
                    : () async {
                        final selectedLines = <Map<String, dynamic>>[];
                        for (int i = 0; i < items.length; i++) {
                          final q = returnQtys[i] ?? 0.0;
                          if (q > 0) {
                            selectedLines.add({
                              ...items[i],
                              'quantity': q,
                            });
                          }
                        }
                        if (selectedLines.isEmpty) {
                          setModal(() => returnModalError = 'Pilih minimal 1 barang dengan jumlah retur > 0.');
                          return;
                        }
                        setModal(() {
                          returning = true;
                          returnModalError = null;
                        });

                        bool cloudOk = false;
                        if (!_isLocalStandalone) {
                          try {
                            await _api.dio.post(ApiEndpoints.purchaseReturns, data: {
                              'purchase_id': purchase['id'],
                              'notes': notesCtrl.text.trim(),
                              'items': selectedLines,
                            });
                            cloudOk = true;
                          } catch (e) {
                            if (!ApiClient.isNetworkOfflineError(e)) {
                              final errMsg = ApiClient.extractErrorMessage(e);
                              setModal(() {
                                returning = false;
                                returnModalError = errMsg;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text(errMsg),
                                  ),
                                );
                              }
                              return;
                            }
                          }
                        }
                        if (!cloudOk) {
                          await _offlineDb.addLocalPurchaseReturn(
                            purchaseId: (purchase['id'] as num?)?.toInt() ?? 0,
                            purchaseNumber: (purchase['number'] ?? purchase['purchase_number'] ?? '-').toString(),
                            supplierName: (purchase['supplier_name'] ?? 'Pemasok').toString(),
                            items: selectedLines,
                            notes: notesCtrl.text.trim(),
                          );
                        }
                        if (mounted) {
                          await context.read<PosCubit>().syncWithCloud(force: cloudOk, preserveActiveCart: true);
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _loadData();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Pembelian & Retur Supplier'),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          indicatorColor: tokens.accent,
          tabs: const [
            Tab(text: 'Pesanan Beli (PO)'),
            Tab(text: 'Retur Pembelian'),
            Tab(text: 'Saran Kulakan AI'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreatePurchaseModal(),
        backgroundColor: tokens.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Buat Pembelian Baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _purchases.isEmpty
                    ? const NusaEmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: 'Belum Ada Transaksi Pembelian',
                        subtitle: 'Catat kulakan / restok barang dari supplier agar HPP, stok, dan hutang tempo terkelola rapi.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        itemCount: _purchases.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final po = _purchases[idx];
                          final total = (po['grand_total'] as num?)?.toDouble() ?? 0.0;
                          final balance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
                          return NusaCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      (po['number'] ?? po['purchase_number'] ?? '-').toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                    ),
                                    NusaBadge(
                                      label: balance > 0 ? 'TEMPO / HUTANG' : 'LUNAS',
                                      variant: balance > 0 ? NusaBadgeVariant.warning : NusaBadgeVariant.success,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pemasok: ${po['supplier_name'] ?? 'Umum'} • ${(po['purchase_date'] ?? '').toString().split('T').first}',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total: ${IdrCurrencyFormatter.format(total)}',
                                      style: AppTheme.moneyStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _openReturnPurchaseModal(po),
                                      icon: const Icon(Icons.assignment_return_outlined, size: 17),
                                      label: const Text('Retur PO'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                _returns.isEmpty
                    ? const NusaEmptyState(
                        icon: Icons.assignment_return_outlined,
                        title: 'Belum Ada Retur Pembelian',
                        subtitle: 'Pilih tombol "Retur PO" pada tab Pesanan Beli jika ada barang rusak/tidak sesuai saat penerimaan.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _returns.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final ret = _returns[idx];
                          return NusaCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (ret['return_number'] ?? ret['number'] ?? '-').toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      Text(
                                        'Ref: ${ret['purchase_number'] ?? '-'} • ${ret['supplier_name'] ?? '-'}',
                                        style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
                                      ),
                                      if ((ret['notes'] ?? '').toString().isNotEmpty)
                                        Text(
                                          ret['notes'].toString(),
                                          style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  IdrCurrencyFormatter.format(
                                      ((ret['total_amount'] ?? ret['grand_total']) as num?)?.toDouble() ?? 0),
                                  style: AppTheme.moneyStyle(fontSize: 14, color: AppColors.danger),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                _buildAiReorderTab(),
              ],
            ),
    );
  }

  Widget _buildAiReorderTab() {
    if (_reorderSuggestions.isEmpty) {
      return const NusaEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Semua Stok dalam Batas Aman',
        subtitle: 'Tidak ada SKU dengan stok di bawah reorder level saat ini.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        NusaCard(
          backgroundColor: AppColors.primarySoft,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_reorderSuggestions.length} SKU perlu kulakan ulang.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navyDark),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final initial = _reorderSuggestions
                      .take(20)
                      .map((s) => {
                            'product_id': (s['product_id'] as num).toInt(),
                            'product_name': (s['name'] ?? 'Produk').toString(),
                            'sku': (s['sku'] ?? '-').toString(),
                            'unit_code': (s['unit_code'] ?? 'pcs').toString(),
                            'quantity': (s['suggested_qty'] as num?)?.toDouble() ?? 10.0,
                            'unit_cost': (s['cost_price'] as num?)?.toDouble() ?? 0.0,
                          })
                      .toList();
                  _openCreatePurchaseModal(initialLines: initial);
                },
                child: const Text('Buat PO Semua'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._reorderSuggestions.map((s) {
          final currentStock = (s['current_stock'] as num?)?.toDouble() ?? 0.0;
          final reorderLevel = (s['reorder_level'] as num?)?.toDouble() ?? 5.0;
          final suggestedQty = (s['suggested_qty'] as num?)?.toDouble() ?? 10.0;
          final costPrice = (s['cost_price'] as num?)?.toDouble() ?? 0.0;
          final unitCode = (s['unit_code'] ?? 'pcs').toString();
          final supId = (s['supplier_id'] as num?)?.toInt();
          final supName = s['supplier_name']?.toString();

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NusaCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((s['name'] ?? 'Produk').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(
                          'SKU: ${s['sku'] ?? '-'} • Sisa: ${IdrCurrencyFormatter.formatQty(currentStock)} $unitCode (Min ${IdrCurrencyFormatter.formatQty(reorderLevel)})',
                          style: const TextStyle(fontSize: 12, color: AppColors.dangerDark),
                        ),
                        if (supName != null && supName.isNotEmpty)
                          Text('Pemasok terakhir: $supName',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.slate500)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${IdrCurrencyFormatter.formatQty(suggestedQty)} $unitCode',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton(
                        onPressed: () {
                          _openCreatePurchaseModal(
                            initialSupplierId: supId,
                            initialLines: [
                              {
                                'product_id': (s['product_id'] as num).toInt(),
                                'product_name': (s['name'] ?? 'Produk').toString(),
                                'sku': (s['sku'] ?? '-').toString(),
                                'unit_code': unitCode,
                                'quantity': suggestedQty,
                                'unit_cost': costPrice,
                              }
                            ],
                          );
                        },
                        child: const Text('Pesan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
