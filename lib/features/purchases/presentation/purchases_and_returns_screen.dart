import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
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
  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();
  late TabController _tabController;

  List<Map<String, dynamic>> _getPaymentMethods() {
    final cached = _offlineDb.getCachedPaymentMethods();
    if (cached.isNotEmpty) return cached;
    try {
      final posMethods = context.read<PosCubit>().state.paymentMethods;
      if (posMethods.isNotEmpty) return posMethods;
    } catch (_) {}
    return [
      {'id': 1, 'name': 'Tunai'},
      {'id': 2, 'name': 'Transfer Bank'},
    ];
  }

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
    final status = (purchase['status'] ?? '').toString().toLowerCase();
    final isDraft = status == 'draft' || status == 'submitted' || status == 'approved';
    if (isDraft) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('PO ${purchase['number'] ?? '-'} masih berstatus draf/pesanan. Barang belum diterima secara fisik di toko sehingga belum dapat diretur.'),
        ),
      );
      return;
    }

    if (purchase['is_fully_returned'] == true || purchase['is_returnable'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('Seluruh barang pada PO ${purchase['number'] ?? '-'} sudah habis diretur sebelumnya.'),
        ),
      );
      return;
    }

    final items = (purchase['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rincian barang pada PO ini tidak tersedia untuk diretur.')),
      );
      return;
    }

    final Map<int, double> maxReturnableQtys = {};
    final Map<int, double> returnQtys = {};
    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
      final recQty = (it['received_quantity'] as num?)?.toDouble() ?? origQty;
      final retQty = (it['returned_quantity'] as num?)?.toDouble() ?? 0.0;
      final maxRem = (it['returnable_quantity'] as num?)?.toDouble() ?? (recQty - retQty).clamp(0.0, double.infinity);
      maxReturnableQtys[i] = maxRem;
      returnQtys[i] = maxRem > 0 ? maxRem : 0.0;
    }

    if (maxReturnableQtys.values.every((v) => v <= 0.0001)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          content: Text('Seluruh barang pada PO ${purchase['number'] ?? '-'} sudah habis diretur sebelumnya.'),
        ),
      );
      return;
    }

    final notesCtrl = TextEditingController(text: 'Barang rusak / tidak sesuai pesanan');
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
                final maxQty = maxReturnableQtys[i] ?? 0.0;
                final curQty = returnQtys[i] ?? 0.0;
                final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                final alreadyRet = (it['returned_quantity'] as num?)?.toDouble() ?? 0.0;
                final isExhausted = maxQty <= 0.0001;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isExhausted ? AppColors.slate100 : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                it['product_name']?.toString() ?? 'Produk',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isExhausted ? AppColors.slate400 : AppColors.navyDark,
                                ),
                              ),
                            ),
                            if (isExhausted)
                              const NusaBadge(label: 'Habis Diretur', variant: NusaBadgeVariant.neutral)
                            else
                              Text(
                                'Sisa retur: ${IdrCurrencyFormatter.formatQty(maxQty)}',
                                style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Dipesan: ${IdrCurrencyFormatter.formatQty(origQty)} • Sudah Diretur: ${IdrCurrencyFormatter.formatQty(alreadyRet)}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                        ),
                        if (!isExhausted) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: curQty > 0
                                    ? () => setModal(() => returnQtys[i] = (curQty - 1).clamp(0, maxQty))
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text(IdrCurrencyFormatter.formatQty(curQty), style: const TextStyle(fontWeight: FontWeight.w700)),
                              IconButton(
                                onPressed: curQty < maxQty
                                    ? () => setModal(() => returnQtys[i] = (curQty + 1).clamp(0, maxQty))
                                    : null,
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
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
                          final maxAllowed = maxReturnableQtys[i] ?? 0.0;
                          if (q > maxAllowed + 0.0001) {
                            setModal(() => returnModalError = 'Jumlah retur untuk ${items[i]['product_name']} ($q unit) melebihi batas sisa yang dapat diretur ($maxAllowed unit).');
                            return;
                          }
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

  void _openReceivePurchaseModal(Map<String, dynamic> po) {
    final tokens = NusaThemeTokens.of(context);
    final purchaseId = (po['id'] as num?)?.toInt() ?? 0;
    final poNumber = (po['number'] ?? po['purchase_number'] ?? '-').toString();
    final supplierName = (po['supplier_name'] ?? 'Pemasok').toString();
    final items = (po['items'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Rincian barang dalam pesanan pembelian ini tidak ditemukan.'),
        ),
      );
      return;
    }

    final maxReceivableQtys = <int, double>{};
    final receiveQtys = <int, double>{};

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
      final alreadyRec = (it['received_quantity'] as num?)?.toDouble() ?? 0.0;
      final rem = (it['unreceived_quantity'] as num?)?.toDouble() ?? (origQty - alreadyRec).clamp(0.0, double.infinity);
      maxReceivableQtys[i] = rem;
      receiveQtys[i] = rem;
    }

    final suratJalanCtrl = TextEditingController(
      text: (po['delivery_note_number'] ?? po['supplier_invoice_number'] ?? '').toString(),
    );
    final notesCtrl = TextEditingController();
    DateTime receivedDate = DateTime.now();
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final totalReceivingNow = receiveQtys.values.fold<double>(0.0, (sum, q) => sum + q);
          final totalRemainingMax = maxReceivableQtys.values.fold<double>(0.0, (sum, q) => sum + q);
          final isFullReceipt = totalReceivingNow >= totalRemainingMax - 0.0001 && totalRemainingMax > 0.0001;
          final isPartialReceipt = totalReceivingNow > 0.0001 && totalReceivingNow < totalRemainingMax - 0.0001;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: tokens.borderDefault,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.inventory_rounded, color: AppColors.success, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Penerimaan Barang (GRN)',
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '$poNumber • $supplierName',
                              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Surat Jalan & Tanggal Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.bgPage,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: suratJalanCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nomor Surat Jalan / DO Supplier',
                            hintText: 'Contoh: SJ-202611-0982',
                            prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: receivedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 30)),
                            );
                            if (picked != null) {
                              setModal(() => receivedDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            decoration: BoxDecoration(
                              color: tokens.bgSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: tokens.borderDefault),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tanggal Diterima Fisik',
                                        style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                                      ),
                                      Text(
                                        '${receivedDate.day.toString().padLeft(2, '0')}-${receivedDate.month.toString().padLeft(2, '0')}-${receivedDate.year}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, color: AppColors.slate400),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Catatan Penerimaan (Opsional)',
                            hintText: 'Nama supir, kondisi fisik barang, kardus aman, dsb.',
                            prefixIcon: Icon(Icons.notes_rounded, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Rincian Diterima',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setModal(() {
                          for (int i = 0; i < items.length; i++) {
                            receiveQtys[i] = maxReceivableQtys[i] ?? 0.0;
                          }
                        }),
                        child: const Text('Terima Semua', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setModal(() {
                          for (int i = 0; i < items.length; i++) {
                            receiveQtys[i] = 0.0;
                          }
                        }),
                        child: const Text('Reset 0', style: TextStyle(fontSize: 11.5, color: AppColors.slate500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Items list
                  ...List.generate(items.length, (i) {
                    final it = items[i];
                    final maxQty = maxReceivableQtys[i] ?? 0.0;
                    final curQty = receiveQtys[i] ?? 0.0;
                    final origQty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                    final alreadyRec = (it['received_quantity'] as num?)?.toDouble() ?? 0.0;
                    final isExhausted = maxQty <= 0.0001;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isExhausted ? tokens.bgPage : tokens.bgSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isExhausted ? tokens.borderDefault : (curQty > 0 ? AppColors.success.withOpacity(0.5) : tokens.borderDefault),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      it['product_name']?.toString() ?? 'Produk',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: isExhausted ? tokens.textSecondary : null,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'SKU: ${it['sku'] ?? '-'} • Dipesan: ${IdrCurrencyFormatter.formatQty(origQty)}'
                                      '${alreadyRec > 0 ? " • Sudah Diterima: ${IdrCurrencyFormatter.formatQty(alreadyRec)}" : ""}',
                                      style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (isExhausted)
                                const NusaBadge(label: 'Sudah Lengkap', variant: NusaBadgeVariant.success)
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.warningSoft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Sisa: ${IdrCurrencyFormatter.formatQty(maxQty)}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.warningDark, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                          if (!isExhausted) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Diterima:',
                                    style: TextStyle(fontSize: 12, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  iconSize: 22,
                                  onPressed: curQty > 0
                                      ? () => setModal(() => receiveQtys[i] = (curQty - 1).clamp(0.0, maxQty))
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Container(
                                  width: 44,
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: tokens.bgPage,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: tokens.borderDefault),
                                  ),
                                  child: Text(
                                    IdrCurrencyFormatter.formatQty(curQty),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  iconSize: 22,
                                  onPressed: curQty < maxQty
                                      ? () => setModal(() => receiveQtys[i] = (curQty + 1).clamp(0.0, maxQty))
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                const SizedBox(width: 4),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    minimumSize: const Size(36, 28),
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => setModal(() => receiveQtys[i] = maxQty),
                                  child: const Text('Maks', style: TextStyle(fontSize: 10.5)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Summary Status Badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isFullReceipt ? AppColors.successSoft : (isPartialReceipt ? AppColors.warningSoft : tokens.bgPage),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isFullReceipt ? AppColors.success.withOpacity(0.4) : (isPartialReceipt ? AppColors.warning.withOpacity(0.4) : tokens.borderDefault),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isFullReceipt
                                    ? 'Penerimaan Lengkap'
                                    : (isPartialReceipt ? 'Penerimaan Sebagian' : 'Pilih kuantitas barang'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isFullReceipt ? AppColors.successDark : (isPartialReceipt ? AppColors.warningDark : tokens.textSecondary),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (isPartialReceipt)
                                const Text(
                                  'Sisa barang dapat diterima pada GRN berikutnya',
                                  style: TextStyle(fontSize: 10, color: AppColors.warningDark),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${IdrCurrencyFormatter.formatQty(totalReceivingNow)} unit',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: isFullReceipt ? AppColors.successDark : (isPartialReceipt ? AppColors.warningDark : null),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (modalError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        modalError!,
                        style: const TextStyle(fontSize: 12, color: AppColors.dangerDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  NusaButton(
                    label: isFullReceipt
                        ? 'Konfirmasi Terima Lengkap (GRN)'
                        : (isPartialReceipt ? 'Simpan Penerimaan Sebagian (GRN)' : 'Pilih Jumlah Diterima'),
                    variant: NusaButtonVariant.primary,
                    icon: Icons.inventory_rounded,
                    isLoading: saving,
                    onPressed: (saving || totalReceivingNow <= 0.0001)
                        ? null
                        : () async {
                            setModal(() {
                              saving = true;
                              modalError = null;
                            });

                            final receiveLines = <Map<String, dynamic>>[];
                            for (int i = 0; i < items.length; i++) {
                              final q = receiveQtys[i] ?? 0.0;
                              if (q > 0.0001) {
                                final it = items[i];
                                receiveLines.add({
                                  'id': it['id'],
                                  'purchase_item_id': it['id'] ?? it['purchase_item_id'],
                                  'product_id': it['product_id'],
                                  'quantity': q,
                                });
                              }
                            }

                            final sjNumber = suratJalanCtrl.text.trim();
                            final dateStr = '${receivedDate.year}-${receivedDate.month.toString().padLeft(2, '0')}-${receivedDate.day.toString().padLeft(2, '0')}';
                            final noteStr = notesCtrl.text.trim();

                            try {
                              final isOnline = !_isLocalStandalone && (await _connectivity.checkOnline());
                              bool cloudSuccess = false;

                              if (isOnline && purchaseId > 0 && po['is_local'] != true) {
                                try {
                                  await _api.dio.post(
                                    ApiEndpoints.receivePurchase(purchaseId),
                                    data: {
                                      if (sjNumber.isNotEmpty) 'delivery_note_number': sjNumber,
                                      'received_date': dateStr,
                                      if (noteStr.isNotEmpty) 'notes': noteStr,
                                      'items': receiveLines,
                                    },
                                  );
                                  cloudSuccess = true;
                                } catch (e) {
                                  if (!ApiClient.isNetworkOfflineError(e)) {
                                    final errMsg = ApiClient.extractErrorMessage(e);
                                    setModal(() {
                                      saving = false;
                                      modalError = errMsg;
                                    });
                                    return;
                                  }
                                }
                              }

                              if (!cloudSuccess) {
                                await _offlineDb.receiveLocalPurchase(
                                  purchaseId: purchaseId,
                                  poNumber: poNumber,
                                  deliveryNoteNumber: sjNumber.isNotEmpty ? sjNumber : null,
                                  receivedDate: dateStr,
                                  notes: noteStr.isNotEmpty ? noteStr : null,
                                  items: receiveLines,
                                );
                              }

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              await _loadData();

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.success,
                                    content: Text(
                                      isFullReceipt
                                          ? 'Penerimaan fisik barang $poNumber selesai (Lengkap). Stok bertambah!'
                                          : 'Penerimaan sebagian $poNumber (${IdrCurrencyFormatter.formatQty(totalReceivingNow)} unit) berhasil dicatat.',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              setModal(() {
                                saving = false;
                                modalError = e.toString();
                              });
                            }
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

  void _openPurchaseDetailModal(Map<String, dynamic> po) {
    final tokens = NusaThemeTokens.of(context);
    final total = (po['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paid = (po['paid_total'] as num?)?.toDouble() ?? 0.0;
    final balance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
    final isTempo = balance > 0.5;
    final poNumber = (po['number'] ?? po['purchase_number'] ?? '-').toString();
    final supplierName = (po['supplier_name'] ?? 'Pemasok Umum').toString();
    final purchaseDate = (po['purchase_date'] ?? '').toString().split('T').first;
    final dueDate = (po['due_date'] ?? '').toString().split('T').first;
    final invoiceNumber = (po['supplier_invoice_number'] ?? '').toString();
    final notes = (po['notes'] ?? '').toString();
    final status = (po['status'] ?? '').toString().toLowerCase();
    final isDraft = status == 'draft' || status == 'submitted' || status == 'approved';
    final isReceived = status == 'received' || status == 'partially_received' || status == 'partially_paid' || status == 'paid';
    final isFullyReturned = po['is_fully_returned'] == true || (isReceived && ((po['total_returnable_qty'] as num?)?.toDouble() ?? 1.0) <= 0.0001 && po['is_returnable'] == false);

    String detailBadgeLabel;
    NusaBadgeVariant detailBadgeVariant;
    if (isDraft) {
      detailBadgeLabel = status == 'draft' ? 'DRAF PO (BELUM DITERIMA)' : 'DIPESAN (MENUNGGU KIRIM)';
      detailBadgeVariant = NusaBadgeVariant.neutral;
    } else if (status == 'partially_received') {
      detailBadgeLabel = 'DITERIMA SEBAGIAN (PARSIAL)';
      detailBadgeVariant = NusaBadgeVariant.warning;
    } else if (status == 'cancelled') {
      detailBadgeLabel = 'DIBATALKAN';
      detailBadgeVariant = NusaBadgeVariant.danger;
    } else if (isFullyReturned) {
      detailBadgeLabel = 'SEMUA BARANG DIRETUR';
      detailBadgeVariant = NusaBadgeVariant.neutral;
    } else if (isTempo) {
      detailBadgeLabel = 'TEMPO / HUTANG';
      detailBadgeVariant = NusaBadgeVariant.warning;
    } else {
      detailBadgeLabel = 'DITERIMA • LUNAS';
      detailBadgeVariant = NusaBadgeVariant.success;
    }

    final items = (po['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poNumber,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pemasok: $supplierName',
                          style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  NusaBadge(
                    label: detailBadgeLabel,
                    variant: detailBadgeVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Ringkasan Finansial Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDraft
                      ? tokens.bgPage
                      : (isTempo ? AppColors.warningSoft : AppColors.successSoft),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDraft
                        ? tokens.borderDefault
                        : (isTempo
                            ? AppColors.warning.withOpacity(0.3)
                            : AppColors.success.withOpacity(0.3)),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Nilai PO', style: TextStyle(fontSize: 13, color: AppColors.slate700)),
                        Text(
                          IdrCurrencyFormatter.format(total),
                          style: AppTheme.moneyStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Sudah Dibayar', style: TextStyle(fontSize: 13, color: AppColors.slate700)),
                        Text(
                          IdrCurrencyFormatter.format(paid),
                          style: AppTheme.moneyStyle(
                            fontSize: 13.5,
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isDraft
                              ? 'Status Tagihan'
                              : (isTempo ? 'Sisa Hutang Tempo' : 'Status Pelunasan'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isDraft
                                ? tokens.textSecondary
                                : (isTempo ? AppColors.danger : AppColors.success),
                          ),
                        ),
                        Text(
                          isDraft
                              ? 'Belum Ditagihkan (Draft)'
                              : (isTempo ? IdrCurrencyFormatter.format(balance) : 'LUNAS'),
                          style: AppTheme.moneyStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDraft
                                ? tokens.textSecondary
                                : (isTempo ? AppColors.danger : AppColors.success),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Detail Transaksi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.bgPage,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.borderDefault),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      'Status Barang',
                      isDraft
                          ? 'Belum Masuk Toko (Draft / Dipesan)'
                          : 'Barang Fisik Diterima di Toko',
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow('Tanggal Pembelian', purchaseDate.isNotEmpty ? purchaseDate : '-'),
                    if (isTempo && dueDate.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('Jatuh Tempo', dueDate),
                    ],
                    if (invoiceNumber.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('No. Faktur Pemasok', invoiceNumber),
                    ],
                    if ((po['delivery_note_number'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('No. Surat Jalan (DO)', po['delivery_note_number'].toString()),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('Catatan', notes),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Rincian Barang
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Rincian Barang Dipesan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${items.length} Barang',
                    style: TextStyle(fontSize: 12.5, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.bgPage,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Rincian barang per item tidak tersedia dalam cache ringkas.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
                    ),
                  ),
                )
              else
                ...items.map((it) {
                  final name = (it['product_name'] ?? 'Barang').toString();
                  final sku = (it['sku'] ?? '-').toString();
                  final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                  final cost = (it['unit_cost'] as num?)?.toDouble() ?? 0.0;
                  final lineTotal = (it['line_total'] as num?)?.toDouble() ?? (qty * cost);
                  final qtyStr = qty.truncateToDouble() == qty ? qty.toInt().toString() : qty.toStringAsFixed(1);
                  final retQty = (it['returned_quantity'] as num?)?.toDouble() ?? 0.0;
                  final recQty = (it['received_quantity'] as num?)?.toDouble() ?? (isReceived && status != 'partially_received' ? qty : 0.0);
                  final unrecQty = (it['unreceived_quantity'] as num?)?.toDouble() ?? (qty - recQty).clamp(0.0, double.infinity);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.bgPage,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'SKU: $sku • Dipesan: $qtyStr unit x ${IdrCurrencyFormatter.format(cost)}'
                                '${isReceived ? " • Diterima: ${IdrCurrencyFormatter.formatQty(recQty)}" : ""}'
                                '${unrecQty > 0.0001 && isReceived ? " • Sisa Belum: ${IdrCurrencyFormatter.formatQty(unrecQty)}" : ""}'
                                '${retQty > 0 ? " • Diretur: ${IdrCurrencyFormatter.formatQty(retQty)}" : ""}',
                                style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          IdrCurrencyFormatter.format(lineTotal),
                          style: AppTheme.moneyStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 20),
              // Action Buttons di Detail Modal
              if (po['can_receive'] == true || isDraft || status == 'partially_received') ...[
                NusaButton(
                  label: status == 'partially_received'
                      ? 'Terima Sisa Barang (GRN)'
                      : 'Konfirmasi Penerimaan Barang (GRN)',
                  icon: Icons.inventory_rounded,
                  variant: NusaButtonVariant.primary,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openReceivePurchaseModal(po);
                  },
                ),
                const SizedBox(height: 10),
              ],
              if (isReceived && isTempo) ...[
                NusaButton(
                  label: 'Bayar Tagihan PO (${IdrCurrencyFormatter.format(balance)})',
                  icon: Icons.payment_rounded,
                  variant: NusaButtonVariant.primary,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openPayPurchaseModal(po);
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  if (isReceived && !isFullyReturned) ...[
                    Expanded(
                      child: NusaButton(
                        label: 'Retur PO',
                        icon: Icons.assignment_return_outlined,
                        variant: NusaButtonVariant.outline,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openReturnPurchaseModal(po);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: NusaButton(
                      label: 'Tutup',
                      variant: NusaButtonVariant.ghost,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _openPayPurchaseModal(Map<String, dynamic> po) {
    final tokens = NusaThemeTokens.of(context);
    final purchaseId = (po['id'] as num?)?.toInt() ?? 0;
    final poNumber = (po['number'] ?? po['purchase_number'] ?? 'PO-$purchaseId').toString();
    final supplierName = (po['supplier_name'] ?? 'Pemasok Umum').toString();
    final currentBalance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
    final isLocalItem = _isLocalStandalone || po['is_local'] == true;

    final methods = _getPaymentMethods();
    int? selectedMethodId = methods.isNotEmpty ? (methods.first['id'] as num?)?.toInt() : 1;
    String selectedMethodName = methods.isNotEmpty ? (methods.first['name'] ?? 'Tunai').toString() : 'Tunai';

    final amountCtrl = TextEditingController(text: currentBalance.toInt().toString());
    final notesCtrl = TextEditingController();
    bool paying = false;
    String? payError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
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
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.payment_rounded, color: tokens.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bayar Tagihan PO',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '$poNumber • $supplierName',
                          style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Card Sisa Tagihan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sisa Hutang Tagihan:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate700),
                    ),
                    Text(
                      IdrCurrencyFormatter.format(currentBalance),
                      style: AppTheme.moneyStyle(fontSize: 15, color: AppColors.danger, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Input Nominal
              const Text(
                'Nominal Pembayaran (Rp)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  hintText: '0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              // Quick Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPayQuickChip('25%', currentBalance * 0.25, amountCtrl, setModalState),
                    const SizedBox(width: 6),
                    _buildPayQuickChip('50%', currentBalance * 0.50, amountCtrl, setModalState),
                    const SizedBox(width: 6),
                    _buildPayQuickChip('75%', currentBalance * 0.75, amountCtrl, setModalState),
                    const SizedBox(width: 6),
                    _buildPayQuickChip('Lunas (100%)', currentBalance, amountCtrl, setModalState),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Metode Pembayaran
              const Text(
                'Sumber Dana / Metode Pembayaran',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: selectedMethodId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: methods.map((m) {
                  final id = (m['id'] as num).toInt();
                  final name = (m['name'] ?? 'Metode').toString();
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() {
                      selectedMethodId = val;
                      final match = methods.firstWhere(
                        (e) => (e['id'] as num).toInt() == val,
                        orElse: () => {'name': 'Tunai'},
                      );
                      selectedMethodName = (match['name'] ?? 'Tunai').toString();
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // Catatan / Referensi
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Catatan / Referensi Transfer (Opsional)',
                  hintText: 'Misal: Transfer via BCA / Mandiri',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              if (payError != null) ...[
                const SizedBox(height: 10),
                Text(
                  payError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 18),
              NusaButton(
                label: 'Konfirmasi Pembayaran PO',
                isLoading: paying,
                variant: NusaButtonVariant.success,
                icon: Icons.check_circle_rounded,
                onPressed: paying
                    ? null
                    : () async {
                        final paidAmount = IdrCurrencyFormatter.parse(amountCtrl.text);
                        if (paidAmount <= 0) {
                          setModalState(() => payError = 'Masukkan nominal pembayaran yang valid (> 0).');
                          return;
                        }
                        if (paidAmount > currentBalance + 1.0) {
                          setModalState(() => payError = 'Nominal bayar tidak boleh melebihi sisa hutang.');
                          return;
                        }

                        setModalState(() {
                          paying = true;
                          payError = null;
                        });

                        try {
                          final isOnline = !_isLocalStandalone && (await _connectivity.checkOnline());
                          bool cloudSuccess = false;

                          if (isOnline && !isLocalItem && purchaseId > 0) {
                            try {
                              await _api.dio.post(
                                ApiEndpoints.payPayable(purchaseId),
                                data: {
                                  'payment_method_id': selectedMethodId ?? 1,
                                  'amount': paidAmount,
                                  'reference': notesCtrl.text.trim().isNotEmpty
                                      ? notesCtrl.text.trim()
                                      : 'Bayar PO $poNumber',
                                  'notes': notesCtrl.text.trim(),
                                },
                              );
                              cloudSuccess = true;
                            } catch (e) {
                              if (!ApiClient.isNetworkOfflineError(e)) {
                                final errMsg = ApiClient.extractErrorMessage(e);
                                setModalState(() {
                                  paying = false;
                                  payError = errMsg;
                                });
                                return;
                              }
                            }
                          }

                          if (!cloudSuccess) {
                            await _offlineDb.payLocalPayable(
                              payableId: purchaseId,
                              amount: paidAmount,
                              paymentMethod: selectedMethodName,
                              invoiceNumber: poNumber,
                            );
                          }

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          await _loadData();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppColors.success,
                                content: Text(
                                  'Pembayaran $poNumber sebesar ${IdrCurrencyFormatter.format(paidAmount)} berhasil dicatat!',
                                ),
                              ),
                            );
                          }
                        } catch (err) {
                          setModalState(() {
                            paying = false;
                            payError = err.toString();
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.slate600)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPayQuickChip(
    String label,
    double amount,
    TextEditingController ctrl,
    void Function(void Function()) setModalState,
  ) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      padding: EdgeInsets.zero,
      onPressed: () {
        setModalState(() {
          ctrl.text = amount.toInt().toString();
        });
      },
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
                          final status = (po['status'] ?? '').toString().toLowerCase();
                          final isDraft = status == 'draft' || status == 'submitted' || status == 'approved';
                          final isReceived = status == 'received' || status == 'partially_received' || status == 'partially_paid' || status == 'paid';
                          final isFullyReturned = po['is_fully_returned'] == true || (isReceived && ((po['total_returnable_qty'] as num?)?.toDouble() ?? 1.0) <= 0.0001 && po['is_returnable'] == false);
                          final canReceive = po['can_receive'] == true || isDraft || status == 'partially_received';

                          String badgeLabel;
                          NusaBadgeVariant badgeVariant;
                          if (isDraft) {
                            badgeLabel = status == 'draft' ? 'DRAF (BELUM TERIMA)' : 'DIPESAN';
                            badgeVariant = NusaBadgeVariant.neutral;
                          } else if (status == 'partially_received') {
                            badgeLabel = 'DITERIMA SEBAGIAN';
                            badgeVariant = NusaBadgeVariant.warning;
                          } else if (status == 'cancelled') {
                            badgeLabel = 'BATAL';
                            badgeVariant = NusaBadgeVariant.danger;
                          } else if (isFullyReturned) {
                            badgeLabel = 'SEMUA DIRETUR';
                            badgeVariant = NusaBadgeVariant.neutral;
                          } else if (balance > 0.5) {
                            badgeLabel = 'TEMPO / HUTANG';
                            badgeVariant = NusaBadgeVariant.warning;
                          } else {
                            badgeLabel = 'LUNAS';
                            badgeVariant = NusaBadgeVariant.success;
                          }

                          return NusaCard(
                            onTap: () => _openPurchaseDetailModal(po),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              (po['number'] ?? po['purchase_number'] ?? '-').toString(),
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.visibility_outlined,
                                            size: 15,
                                            color: AppColors.slate400,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    NusaBadge(
                                      label: badgeLabel,
                                      variant: badgeVariant,
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
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Total: ${IdrCurrencyFormatter.format(total)}',
                                          style: AppTheme.moneyStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                                        ),
                                        if (balance > 0.5 && !isDraft)
                                          Text(
                                            'Sisa: ${IdrCurrencyFormatter.format(balance)}',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.danger,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (canReceive) ...[
                                          ElevatedButton.icon(
                                            onPressed: () => _openReceivePurchaseModal(po),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.success,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.inventory_rounded, size: 14),
                                            label: Text(
                                              status == 'partially_received' ? 'Terima Sisa' : 'Terima Barang',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (balance > 0.5 && !isDraft) ...[
                                          ElevatedButton.icon(
                                            onPressed: () => _openPayPurchaseModal(po),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: tokens.accent,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.payment_rounded, size: 15),
                                            label: const Text(
                                              'Bayar PO',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                          if (isReceived && !isFullyReturned)
                                            TextButton.icon(
                                              onPressed: () => _openReturnPurchaseModal(po),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                minimumSize: const Size(0, 32),
                                              ),
                                              icon: const Icon(Icons.assignment_return_outlined, size: 16),
                                              label: const Text('Retur PO', style: TextStyle(fontSize: 12)),
                                            ),
                                          if (isFullyReturned)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: tokens.bgPage,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: tokens.borderDefault),
                                              ),
                                              child: const Text(
                                                'Habis Diretur',
                                                style: TextStyle(fontSize: 11, color: AppColors.slate500, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                        ],
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
