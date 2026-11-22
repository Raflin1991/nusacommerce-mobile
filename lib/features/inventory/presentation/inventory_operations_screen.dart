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

/// PUSAT OPERASI INVENTARIS & GUDANG
/// Monitor Stok (Tersedia/Menipis/Minus), Penyesuaian & Stock Opname Multi-Item,
/// Kartu Mutasi Stok, Batch FEFO & Transfer Antar Cabang.
class InventoryOperationsScreen extends StatefulWidget {
  final int initialTab;

  const InventoryOperationsScreen({super.key, this.initialTab = 0});

  @override
  State<InventoryOperationsScreen> createState() => _InventoryOperationsScreenState();
}

class _InventoryOperationsScreenState extends State<InventoryOperationsScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  late TabController _tabController;

  bool _loading = false;
  String _monitorFilter = 'Semua'; // Semua, Tersedia, Menipis, Minus
  int? _movementProductFilter;
  List<Map<String, dynamic>> _movements = [];
  List<Map<String, dynamic>> _batches = [];
  List<Map<String, dynamic>> _transfers = [];
  List<Map<String, dynamic>> _adjustmentReasons = [
    {'id': 1, 'name': 'Hasil Stock Opname Fisik'},
    {'id': 2, 'name': 'Barang Rusak / Pecah / Expired'},
    {'id': 3, 'name': 'Bonus / Sampel / Hilang'},
  ];

  // Multi-item Stock Adjustment Cart
  final List<Map<String, dynamic>> _opnameDraftItems = [];
  String _opnameReason = 'Hasil Stock Opname Fisik';
  final TextEditingController _opnameNotesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _loadInventoryOps();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _opnameNotesCtrl.dispose();
    super.dispose();
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  Future<void> _loadInventoryOps() async {
    setState(() => _loading = true);
    final localMovements = _offlineDb.getLocalStockMovements(productId: _movementProductFilter);
    final products = context.read<PosCubit>().state.allProducts;
    final localBatches = <Map<String, dynamic>>[];
    for (final p in products) {
      for (final b in p.batches) {
        localBatches.add({
          'product_id': p.id,
          'product_name': p.name,
          'sku': p.sku,
          'batch_number': b.batchNumber,
          'expiry_date': b.expiryDate,
          'quantity': b.quantity,
        });
      }
    }

    if (_isLocalStandalone) {
      setState(() {
        _movements = localMovements;
        _batches = localBatches;
        _loading = false;
      });
      return;
    }

    Future<List<Map<String, dynamic>>?> safeFetchList(String path, [Map<String, dynamic>? query]) async {
      try {
        final res = await _api.dio.get(path, queryParameters: query);
        return (res.data?['data'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        return null;
      }
    }

    try {
      final results = await Future.wait([
        safeFetchList(ApiEndpoints.stockMovements, {
          if (_movementProductFilter != null) 'product_id': _movementProductFilter,
        }),
        safeFetchList(ApiEndpoints.inventoryBatches),
        safeFetchList(ApiEndpoints.stockTransfers),
        safeFetchList(ApiEndpoints.adjustmentReasons),
      ]);

      final movData = results[0];
      final batchData = results[1];
      final transferData = results[2];
      final reasonData = results[3];

      if (!mounted) return;
      setState(() {
        _movements = (movData != null && movData.isNotEmpty) ? movData : localMovements;
        _batches = (batchData != null && batchData.isNotEmpty) ? batchData : localBatches;
        _transfers = transferData ?? _transfers;
        if (reasonData != null && reasonData.isNotEmpty) {
          _adjustmentReasons = reasonData;
          _opnameReason = reasonData.first['name'].toString();
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _movements = localMovements;
        _batches = localBatches;
        _loading = false;
      });
    }
  }

  void _openAddOpnameProductModal(List<ProductModel> allProducts) {
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final filtered = allProducts.where((p) {
            if (p.isServiceOrNonStockItem) return false;
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q.toLowerCase()) ||
                p.sku.toLowerCase().contains(q.toLowerCase());
          }).toList();

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.72,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih Produk untuk Opname / Penyesuaian',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setModal(() => q = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama barang atau SKU...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final p = filtered[idx];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Stok Sistem: ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}'),
                          trailing: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                          onTap: () {
                            Navigator.pop(ctx);
                            _promptOpnameQty(p);
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

  void _promptOpnameQty(ProductModel p) {
    final qtyCtrl = TextEditingController(text: IdrCurrencyFormatter.formatQty(p.stock));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stok Tercatat: ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                style: const TextStyle(fontSize: 13, color: AppColors.slate600)),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stok Fisik Baru'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final physical = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? p.stock;
              Navigator.pop(ctx);
              setState(() {
                _opnameDraftItems.removeWhere((e) => e['product_id'] == p.id);
                _opnameDraftItems.add({
                  'product': p,
                  'product_id': p.id,
                  'product_name': p.name,
                  'sku': p.sku,
                  'unit_code': p.unitCode,
                  'system_qty': p.stock,
                  'physical_qty': physical,
                  'delta': physical - p.stock,
                });
              });
            },
            child: const Text('Tambahkan'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBatchOpname() async {
    if (_opnameDraftItems.isEmpty) return;
    setState(() => _loading = true);
    final cubit = context.read<PosCubit>();
    bool syncedCloud = false;

    if (!_isLocalStandalone) {
      try {
        await _api.dio.post(ApiEndpoints.stockTakes, data: {
          'notes': '$_opnameReason${_opnameNotesCtrl.text.trim().isNotEmpty ? ' • ${_opnameNotesCtrl.text.trim()}' : ''}',
          'post_now': true,
          'counts': _opnameDraftItems.map((e) => {
                'product_id': e['product_id'],
                'counted_qty': e['physical_qty'],
              }).toList(),
        });
        syncedCloud = true;
      } catch (e) {
        if (!ApiClient.isNetworkOfflineError(e)) {
          if (mounted) {
            setState(() => _loading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.danger,
                content: Text(ApiClient.extractErrorMessage(e)),
              ),
            );
          }
          return;
        }
      }
    }

    for (final item in _opnameDraftItems) {
      final ProductModel prod = item['product'] as ProductModel;
      final newQty = (item['physical_qty'] as num).toDouble();
      final delta = newQty - prod.stock;
      if (!syncedCloud) {
        await _offlineDb.updateLocalProductStock(prod.id, newQty);
        await _offlineDb.recordLocalStockMovement(
          productId: prod.id,
          productName: prod.name,
          sku: prod.sku,
          unitCode: prod.unitCode,
          type: 'stock_opname',
          quantityDelta: delta,
          quantityAfter: newQty,
          unitCost: prod.costPrice,
          notes: '$_opnameReason ${_opnameNotesCtrl.text.trim()}'.trim(),
        );
      }
    }

    await cubit.syncWithCloud(force: syncedCloud, preserveActiveCart: true);
    if (!mounted) return;
    setState(() {
      _opnameDraftItems.clear();
      _opnameNotesCtrl.clear();
    });
    await _loadInventoryOps();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(syncedCloud
            ? 'Stock Opname multi-item berhasil disimpan ke Cloud!'
            : 'Stock Opname tersimpan di perangkat.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final products = context.watch<PosCubit>().state.allProducts;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Inventaris & Gudang'),
        actions: [
          IconButton(
            onPressed: _loadInventoryOps,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          indicatorColor: tokens.accent,
          tabs: const [
            Tab(text: 'Monitor Stok'),
            Tab(text: 'Opname Multi-Item'),
            Tab(text: 'Kartu Mutasi'),
            Tab(text: 'FEFO & Transfer'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStockMonitorTab(products),
                _buildOpnameTab(products),
                _buildMovementsTab(products),
                _buildFefoAndTransferTab(),
              ],
            ),
    );
  }

  Widget _buildStockMonitorTab(List<ProductModel> products) {
    final availableCount = products.where((p) => !p.isServiceOrNonStockItem && p.stock > p.reorderLevel).length;
    final lowCount = products.where((p) => !p.isServiceOrNonStockItem && p.stock >= 0 && p.stock <= p.reorderLevel).length;
    final minusCount = products.where((p) => !p.isServiceOrNonStockItem && p.stock < 0).length;

    final filtered = products.where((p) {
      if (_monitorFilter == 'Tersedia') return !p.isServiceOrNonStockItem && p.stock > p.reorderLevel;
      if (_monitorFilter == 'Menipis') return !p.isServiceOrNonStockItem && p.stock >= 0 && p.stock <= p.reorderLevel;
      if (_monitorFilter == 'Minus') return !p.isServiceOrNonStockItem && p.stock < 0;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              _kpiChip('Tersedia', '$availableCount', AppColors.successDark, AppColors.successSoft),
              const SizedBox(width: 8),
              _kpiChip('Menipis', '$lowCount', AppColors.warningDark, AppColors.warningSoft),
              const SizedBox(width: 8),
              _kpiChip('Minus/Oversold', '$minusCount', AppColors.dangerDark, AppColors.dangerSoft),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: ['Semua', 'Tersedia', 'Menipis', 'Minus'].map((f) {
              final active = _monitorFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f),
                  selected: active,
                  onSelected: (_) => setState(() => _monitorFilter = f),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, idx) {
              final p = filtered[idx];
              final isLow = !p.isServiceOrNonStockItem && p.stock <= p.reorderLevel;
              return NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          Text(
                            'SKU: ${p.sku} • Rak: ${(p.shelfLocation ?? '').isNotEmpty ? p.shelfLocation : "-"}',
                            style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        NusaBadge(
                          label: p.isServiceOrNonStockItem
                              ? 'JASA'
                              : '${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                          variant: p.stock < 0
                              ? NusaBadgeVariant.danger
                              : (isLow ? NusaBadgeVariant.warning : NusaBadgeVariant.success),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Min: ${IdrCurrencyFormatter.formatQty(p.reorderLevel)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.slate500),
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
    );
  }

  Widget _kpiChip(String label, String val, Color fg, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
            Text(val, style: AppTheme.moneyStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _buildOpnameTab(List<ProductModel> products) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NusaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Alasan Penyesuaian / Opname', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _adjustmentReasons.any((r) => r['name'] == _opnameReason)
                    ? _opnameReason
                    : null,
                items: _adjustmentReasons
                    .map((r) => DropdownMenuItem(
                          value: r['name'].toString(),
                          child: Text(r['name'].toString()),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _opnameReason = v);
                },
                decoration: const InputDecoration(prefixIcon: Icon(Icons.fact_check_outlined)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _opnameNotesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Catatan Tambahan (Opsional)',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
              const SizedBox(height: 12),
              NusaButton(
                label: 'Tambah Produk ke Daftar Opname',
                variant: NusaButtonVariant.outline,
                icon: Icons.add_box_outlined,
                onPressed: () => _openAddOpnameProductModal(products),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_opnameDraftItems.isEmpty)
          const NusaEmptyState(
            icon: Icons.inventory_outlined,
            title: 'Daftar Opname Kosong',
            subtitle: 'Klik "Tambah Produk" di atas untuk menghitung selisih stok fisik beberapa barang sekaligus.',
          )
        else ...[
          ..._opnameDraftItems.map((item) {
            final delta = (item['delta'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['product_name'].toString(),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            'Sistem: ${IdrCurrencyFormatter.formatQty((item['system_qty'] as num).toDouble())}  ➔  Fisik: ${IdrCurrencyFormatter.formatQty((item['physical_qty'] as num).toDouble())} ${item['unit_code']}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
                          ),
                        ],
                      ),
                    ),
                    NusaBadge(
                      label: '${delta >= 0 ? "+" : ""}${IdrCurrencyFormatter.formatQty(delta)}',
                      variant: delta < 0
                          ? NusaBadgeVariant.danger
                          : (delta > 0 ? NusaBadgeVariant.success : NusaBadgeVariant.neutral),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      onPressed: () => setState(() => _opnameDraftItems.remove(item)),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          NusaButton(
            label: 'Simpan Semua Penyesuaian (${_opnameDraftItems.length} Produk)',
            variant: NusaButtonVariant.success,
            icon: Icons.check_circle_outline,
            onPressed: _submitBatchOpname,
          ),
        ],
      ],
    );
  }

  Widget _buildMovementsTab(List<ProductModel> products) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<int?>(
            value: _movementProductFilter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Filter Produk Kartu Stok',
              prefixIcon: Icon(Icons.filter_list_rounded),
            ),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Semua Produk')),
              ...products.map((p) => DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) {
              setState(() => _movementProductFilter = v);
              _loadInventoryOps();
            },
          ),
        ),
        Expanded(
          child: _movements.isEmpty
              ? const NusaEmptyState(
                  icon: Icons.history_rounded,
                  title: 'Belum Ada Mutasi Stok',
                  subtitle: 'Setiap transaksi POS, retur, pembelian, dan stock opname akan terekam otomatis di kartu stok.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _movements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final m = _movements[idx];
                    final delta = (m['quantity_delta'] as num?)?.toDouble() ?? 0.0;
                    final isPositive = delta >= 0;
                    return NusaCard(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: isPositive ? AppColors.successSoft : AppColors.dangerSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isPositive ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                              color: isPositive ? AppColors.successDark : AppColors.dangerDark,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (m['product_name'] ?? 'Produk').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                Text(
                                  '${m['type'] ?? 'mutasi'} • ${m['notes'] ?? '-'}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                                ),
                                Text(
                                  (m['created_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first,
                                  style: const TextStyle(fontSize: 11, color: AppColors.slate400),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${isPositive ? "+" : ""}${IdrCurrencyFormatter.formatQty(delta)} ${m['unit_code'] ?? 'pcs'}',
                                style: AppTheme.moneyStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isPositive ? AppColors.successDark : AppColors.dangerDark,
                                ),
                              ),
                              if (m['quantity_after'] != null)
                                Text(
                                  'Saldo: ${IdrCurrencyFormatter.formatQty((m['quantity_after'] as num).toDouble())}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
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
    );
  }

  Widget _buildFefoAndTransferTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Batch & Kedaluwarsa (FEFO)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_batches.isEmpty)
          const NusaCard(
            child: Text(
              'Belum ada data batch tanggal kedaluwarsa. Batch akan muncul dari stok masuk pembelian atau data apotek/F&B.',
              style: TextStyle(fontSize: 13, color: AppColors.slate600),
            ),
          )
        else
          ..._batches.take(25).map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NusaCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((b['product_name'] ?? 'Produk').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              'Batch: ${b['batch_number'] ?? '-'} • Exp: ${(b['expiry_date'] ?? '-').toString().split('T').first}',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                            ),
                          ],
                        ),
                      ),
                      NusaBadge(
                        label: IdrCurrencyFormatter.formatQty((b['quantity'] as num?)?.toDouble() ?? 0),
                        variant: NusaBadgeVariant.warning,
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Transfer Stok Antar Cabang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            if (!_isLocalStandalone)
              FilledButton.icon(
                onPressed: _openCreateTransferModal,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Kirim Transfer'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_transfers.isEmpty)
          NusaCard(
            child: Text(
              _isLocalStandalone
                  ? 'Transfer antar cabang tersedia saat beralih ke OXO Cloud Multi-Cabang.'
                  : 'Belum ada dokumen transfer antar gudang/cabang.',
              style: const TextStyle(fontSize: 13, color: AppColors.slate600),
            ),
          )
        else
          ..._transfers.map((t) {
            final id = (t['id'] as num?)?.toInt() ?? 0;
            final status = (t['status'] ?? 'pending').toString();
            final activeStoreId = context.read<AuthCubit>().state.session.activeStore.id;
            final toStoreId = (t['to_store_id'] as num?)?.toInt() ?? 0;
            final canReceive = (status == 'in_transit' || status == 'pending') &&
                (toStoreId == 0 || toStoreId == activeStoreId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (t['number'] ?? t['transfer_number'] ?? 'TRF-$id').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${t['from_store_name'] ?? t['from_warehouse'] ?? 'Asal'} ➔ ${t['to_store_name'] ?? t['to_warehouse'] ?? 'Tujuan'}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
                          ),
                        ],
                      ),
                    ),
                    if (canReceive)
                      FilledButton(
                        onPressed: () async {
                          try {
                            await _api.dio.post(ApiEndpoints.receiveStockTransfer(id));
                            if (mounted) {
                              await context.read<PosCubit>().syncWithCloud(force: true, preserveActiveCart: true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: AppColors.successDark,
                                  content: Text('Transfer stok berhasil diterima di cabang ini.'),
                                ),
                              );
                            }
                            await _loadInventoryOps();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppColors.danger,
                                  content: Text(ApiClient.extractErrorMessage(e)),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Terima'),
                      )
                    else
                      NusaBadge(
                        label: status.toUpperCase(),
                        variant: status == 'received' ? NusaBadgeVariant.success : NusaBadgeVariant.warning,
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _openCreateTransferModal() {
    final session = context.read<AuthCubit>().state.session;
    final destStores = session.availableStores
        .where((s) => s.id != session.activeStore.id)
        .toList();
    if (destStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cabang tujuan transfer belum tersedia (akun Anda hanya terhubung ke 1 cabang).'),
        ),
      );
      return;
    }

    final products = context
        .read<PosCubit>()
        .state
        .allProducts
        .where((p) => !p.isServiceOrNonStockItem)
        .toList();
    if (products.isEmpty) return;

    int toStoreId = destStores.first.id;
    ProductModel selectedProduct = products.first;
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    final List<Map<String, dynamic>> lines = [];
    bool submitting = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.85,
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
                    const Text(
                      'Kirim Transfer Stok Cabang',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  'Asal: ${session.activeStore.name}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: toStoreId,
                  decoration: const InputDecoration(labelText: 'Cabang Tujuan *'),
                  items: destStores
                      .map((s) => DropdownMenuItem<int>(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setModal(() => toStoreId = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        value: selectedProduct.id,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Pilih Produk'),
                        items: products
                            .take(100)
                            .map((p) => DropdownMenuItem<int>(
                                  value: p.id,
                                  child: Text('${p.name} (Stok: ${IdrCurrencyFormatter.formatQty(p.stock)})'),
                                ))
                            .toList(),
                        onChanged: (pid) {
                          final match = products.where((p) => p.id == pid).firstOrNull;
                          if (match != null) setModal(() => selectedProduct = match);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () {
                        final q = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                        if (q <= 0) return;
                        setModal(() {
                          lines.removeWhere((l) => l['product_id'] == selectedProduct.id);
                          lines.add({
                            'product_id': selectedProduct.id,
                            'product_name': selectedProduct.name,
                            'unit_code': selectedProduct.unitCode,
                            'quantity': q,
                          });
                        });
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan Pengiriman (Opsional)'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: lines.isEmpty
                      ? const Center(
                          child: Text(
                            'Tambahkan barang yang akan dikirim ke cabang tujuan.',
                            style: TextStyle(color: AppColors.slate500),
                          ),
                        )
                      : ListView.separated(
                          itemCount: lines.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, idx) {
                            final line = lines[idx];
                            return NusaCard(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      line['product_name'].toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    '${IdrCurrencyFormatter.formatQty((line['quantity'] as num).toDouble())} ${line['unit_code']}',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                                    onPressed: () => setModal(() => lines.removeAt(idx)),
                                  ),
                                ],
                              ),
                            );
                          },
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
                NusaButton(
                  label: 'Kirim Transfer Stok Sekarang',
                  isLoading: submitting,
                  icon: Icons.send_rounded,
                  onPressed: (submitting || lines.isEmpty)
                      ? null
                      : () async {
                          setModal(() {
                            submitting = true;
                            modalError = null;
                          });
                          try {
                            await _api.dio.post(ApiEndpoints.stockTransfers, data: {
                              'to_store_id': toStoreId,
                              'notes': notesCtrl.text.trim(),
                              'dispatch_now': true,
                              'items': lines
                                  .map((l) => {
                                        'product_id': l['product_id'],
                                        'quantity': l['quantity'],
                                      })
                                  .toList(),
                            });
                            if (mounted) {
                              await context.read<PosCubit>().syncWithCloud(force: true, preserveActiveCart: true);
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadInventoryOps();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: AppColors.successDark,
                                  content: Text('Transfer stok antar cabang berhasil dikirim!'),
                                ),
                              );
                            }
                          } catch (e) {
                            final errMsg = ApiClient.extractErrorMessage(e);
                            setModal(() {
                              submitting = false;
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
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
