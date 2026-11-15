import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 6 — RIWAYAT TRANSAKSI (TAB 2 NAVIGASI)
/// NusaCommerce Mobile Enterprise Sales History Screen
class TransactionsHistoryScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;

  const TransactionsHistoryScreen({super.key, required this.onOpenDrawer});

  @override
  State<TransactionsHistoryScreen> createState() => _TransactionsHistoryScreenState();
}

class _TransactionsHistoryScreenState extends State<TransactionsHistoryScreen> {
  String _searchQuery = '';
  String _periodFilter = 'Semua Waktu';
  String _statusFilter = 'Semua';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cubit = context.read<PosCubit>();
        cubit.syncWithCloud(force: false);
        cubit.fetchReturnReasons();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseSaleDate(Map<String, dynamic> sale) {
    final raw = (sale['created_at'] ?? sale['sale_datetime'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso.toLocal();
    try {
      return DateFormat('dd MMM yyyy • HH:mm').parse(raw);
    } catch (_) {
      return null;
    }
  }

  bool _matchesPeriod(Map<String, dynamic> sale) {
    if (_periodFilter == 'Semua Waktu') return true;
    final dt = _parseSaleDate(sale);
    if (dt == null) return true;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (_periodFilter == 'Hari Ini') {
      return !dt.isBefore(todayStart);
    }
    if (_periodFilter == '7 Hari') {
      return !dt.isBefore(todayStart.subtract(const Duration(days: 6)));
    }
    if (_periodFilter == 'Bulan Ini') {
      return dt.year == now.year && dt.month == now.month;
    }
    return true;
  }

  Future<bool> _promptAndVerifyManagerPin(BuildContext rootContext, String action) async {
    final pinCtrl = TextEditingController();
    final pin = await showDialog<String>(
      context: rootContext,
      builder: (dCtx) => AlertDialog(
        title: const Text('Otorisasi PIN Manajer', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action == 'void'
                  ? 'Pembatalan (Void) nota memerlukan otorisasi PIN Manajer / Supervisor.'
                  : 'Retur barang (Refund) memerlukan otorisasi PIN Manajer / Supervisor.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Masukkan PIN / Sandi Manajer *',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, pinCtrl.text.trim()),
            child: const Text('Verifikasi'),
          ),
        ],
      ),
    );

    if (pin == null || pin.isEmpty || !rootContext.mounted) return false;
    final ok = await rootContext.read<PosCubit>().verifyManagerPin(
          pin,
          action: action,
          setApprovedState: false,
        );
    if (!ok && rootContext.mounted) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('PIN / Sandi Manajer tidak valid atau ditolak server!'),
        ),
      );
    }
    return ok;
  }

  void _showTransactionActionSheet(BuildContext context, Map<String, dynamic> sale) {
    final voidReasonCtrl = TextEditingController();
    final posCubit = context.read<PosCubit>();
    Map<String, dynamic> activeSale = Map<String, dynamic>.from(sale);
    bool loadingDetail = ((activeSale['items'] as List<dynamic>?) ?? []).isEmpty &&
        ((activeSale['id'] as num?)?.toInt() ?? 0) > 0 &&
        ((activeSale['id'] as num?)?.toInt() ?? 0) < 1000000000;
    bool initializedFetch = false;
    int? selectedReasonCodeId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (!initializedFetch) {
            initializedFetch = true;
            if (loadingDetail) {
              final saleId = (activeSale['id'] as num).toInt();
              Future.microtask(() async {
                final detail = await posCubit.fetchSaleDetail(saleId);
                if (!ctx.mounted) return;
                setModalState(() {
                  loadingDetail = false;
                  if (detail != null) {
                    activeSale = detail;
                  }
                });
              });
            }
            if (posCubit.state.returnReasons.isEmpty) {
              Future.microtask(() async {
                await posCubit.fetchReturnReasons();
                if (ctx.mounted) setModalState(() {});
              });
            }
          }

          final status = (activeSale['status'] ?? 'completed').toString().toLowerCase();
          final isVoided = status == 'voided' || status == 'refunded';
          final items = (activeSale['items'] as List<dynamic>? ?? []);
          final methods = (activeSale['payment_methods'] as List<dynamic>? ?? []);
          final customerName = (activeSale['customer'] is Map
                  ? activeSale['customer']['name']
                  : 'Pelanggan Umum')
              .toString();
          final returnReasons = posCubit.state.returnReasons;

          return Padding(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Nota ${activeSale['number']}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                        ),
                      ),
                      NusaBadge(
                        label: status == 'voided'
                            ? 'VOID / BATAL'
                            : (status == 'refunded' ? 'RETUR / REFUND' : 'LUNAS'),
                        variant: isVoided ? NusaBadgeVariant.danger : NusaBadgeVariant.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${activeSale['sale_datetime']} • $customerName'
                    '${methods.isNotEmpty ? ' • ${methods.join(', ')}' : ''}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.slate600, fontWeight: FontWeight.w500),
                  ),
                  if (loadingDetail)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    NusaCard(
                      backgroundColor: AppColors.background,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daftar Item (${items.length})',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.slate500),
                          ),
                          const SizedBox(height: 8),
                          ...items.take(6).map((raw) {
                            final it = raw is Map ? raw : <String, dynamic>{};
                            final name = (it['product_name'] ?? it['name'] ?? 'Produk').toString();
                            final qty = (it['quantity'] as num?) ?? 1;
                            final lineTotal = (it['line_total'] as num?) ?? ((it['unit_price'] as num?) ?? 0) * qty;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${IdrCurrencyFormatter.formatQty(qty)}× $name',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  NusaPriceTag(amount: lineTotal, fontSize: 12.5),
                                ],
                              ),
                            );
                          }),
                          if (items.length > 6)
                            Text(
                              '+${items.length - 6} item lainnya (lihat di struk)',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          const Divider(height: 14, color: AppColors.border),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Nota', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                              NusaPriceTag(amount: activeSale['grand_total'], fontSize: 15, color: AppColors.primary),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  NusaButton(
                    label: 'Buka Struk (Cetak Thermal / Kirim WA)',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/pos/receipt', extra: activeSale);
                    },
                  ),
                  if (!isVoided) ...[
                    const SizedBox(height: 8),
                    NusaButton(
                      label: 'Tukar Barang (Exchange) 1-Klik',
                      icon: Icons.swap_horiz_rounded,
                      variant: NusaButtonVariant.outline,
                      onPressed: () {
                        if (items.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Item nota belum termuat. Tunggu sebentar atau sinkronkan riwayat.'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx);
                        _showExchangeItemSelectorSheet(context, posCubit, activeSale);
                      },
                    ),
                    const Divider(height: 24, color: AppColors.border),
                    const Text(
                      'Retur Barang / Pembatalan (Void) Transaksi',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.dangerDark),
                    ),
                    if (returnReasons.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: returnReasons.map((r) {
                          final rid = (r['id'] as num?)?.toInt();
                          final rName = (r['name'] ?? r['code'] ?? 'Retur').toString();
                          final selected = rid != null && selectedReasonCodeId == rid;
                          return NusaPillFilter(
                            label: rName,
                            selected: selected,
                            onTap: () {
                              setModalState(() {
                                selectedReasonCodeId = rid;
                                voidReasonCtrl.text = rName;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: voidReasonCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Wajib isi alasan retur / void (misal: tukar barang / salah input)',
                        prefixIcon: Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: NusaButton(
                            label: 'Retur (Refund)',
                            icon: Icons.assignment_return_outlined,
                            variant: NusaButtonVariant.warning,
                            onPressed: () async {
                              final ok = await _promptAndVerifyManagerPin(context, 'refund');
                              if (!ok || !context.mounted) return;
                              final id = (activeSale['id'] as num?)?.toInt() ?? 0;
                              final notes = voidReasonCtrl.text.trim().isEmpty
                                  ? 'Retur Pelanggan'
                                  : voidReasonCtrl.text.trim();
                              await context.read<PosCubit>().refundSaleTransaction(
                                    id,
                                    notes: notes,
                                    reasonCodeId: selectedReasonCodeId,
                                  );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Retur nota ${activeSale['number']} berhasil diproses & stok dikembalikan.')),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NusaButton(
                            label: 'Void Nota',
                            icon: Icons.cancel_outlined,
                            variant: NusaButtonVariant.danger,
                            onPressed: () async {
                              if (voidReasonCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Alasan void wajib diisi!')),
                                );
                                return;
                              }
                              final ok = await _promptAndVerifyManagerPin(context, 'void');
                              if (!ok || !context.mounted) return;
                              final id = (activeSale['id'] as num?)?.toInt() ?? 0;
                              await context.read<PosCubit>().voidSaleTransaction(id, voidReasonCtrl.text.trim());
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Transaksi ${activeSale['number']} berhasil di-Void.')),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showExchangeItemSelectorSheet(
    BuildContext rootContext,
    PosCubit posCubit,
    Map<String, dynamic> activeSale,
  ) {
    final rawItems = (activeSale['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (rawItems.isEmpty) return;

    final selectedQtys = <int, double>{
      for (int i = 0; i < rawItems.length; i++)
        i: ((rawItems[i]['quantity'] as num?)?.toDouble() ?? 1.0).abs(),
    };

    showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          double totalCredit = 0.0;
          int selectedCount = 0;
          for (int i = 0; i < rawItems.length; i++) {
            final q = selectedQtys[i] ?? 0.0;
            if (q > 0) {
              selectedCount++;
              final unitPrice = (rawItems[i]['unit_price'] as num?)?.toDouble() ?? 0.0;
              totalCredit += (unitPrice * q);
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.62,
            maxChildSize: 0.88,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tukar Barang • ${activeSale['number'] ?? '-'}',
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pilih item & jumlah yang dikembalikan pelanggan, lalu tambahkan barang pengganti di layar Kasir POS.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate600),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: rawItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (_, idx) {
                        final item = rawItems[idx];
                        final maxQty = ((item['quantity'] as num?)?.toDouble() ?? 1.0).abs();
                        final currentQty = selectedQtys[idx] ?? 0.0;
                        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                        final checked = currentQty > 0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Checkbox(
                                value: checked,
                                onChanged: (val) {
                                  setModalState(() {
                                    selectedQtys[idx] = (val == true) ? maxQty : 0.0;
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (item['product_name'] ?? 'Produk').toString(),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    Text(
                                      'Maks ${IdrCurrencyFormatter.formatQty(maxQty)} × ${IdrCurrencyFormatter.format(unitPrice)}',
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.slate100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.remove_rounded, size: 16),
                                      onPressed: currentQty <= 0
                                          ? null
                                          : () {
                                              setModalState(() {
                                                final next = (currentQty - 1).clamp(0.0, maxQty);
                                                selectedQtys[idx] = next;
                                              });
                                            },
                                    ),
                                    Text(
                                      IdrCurrencyFormatter.formatQty(currentQty),
                                      style: AppTheme.moneyStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                                      onPressed: currentQty >= maxQty
                                          ? null
                                          : () {
                                              setModalState(() {
                                                final next = (currentQty + 1).clamp(0.0, maxQty);
                                                selectedQtys[idx] = next;
                                              });
                                            },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kredit Retur ($selectedCount item)',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                        ),
                        NusaPriceTag(
                          amount: totalCredit,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  NusaButton(
                    label: 'Lanjut ke Kasir POS (Tukar Barang)',
                    trailingIcon: Icons.arrow_forward_rounded,
                    minHeight: 48,
                    onPressed: selectedCount == 0
                        ? null
                        : () {
                            final returnedItems = <Map<String, dynamic>>[];
                            for (int i = 0; i < rawItems.length; i++) {
                              final qty = selectedQtys[i] ?? 0.0;
                              if (qty > 0) {
                                returnedItems.add({
                                  ...rawItems[i],
                                  'return_quantity': qty,
                                });
                              }
                            }
                            posCubit.startItemExchange(
                              originalSale: activeSale,
                              returnedItems: returnedItems,
                            );
                            Navigator.pop(ctx);
                            if (rootContext.mounted) {
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppColors.primary,
                                  content: Text(
                                    'Mode Tukar Barang nota ${activeSale['number']} aktif — pilih barang pengganti di POS.',
                                  ),
                                ),
                              );
                              rootContext.go('/pos');
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

  @override
  Widget build(BuildContext context) {
    final salesHistory = context.watch<PosCubit>().state.salesHistory;

    final filtered = salesHistory.where((sale) {
      if (!_matchesPeriod(sale)) return false;
      final status = (sale['status'] ?? 'completed').toString().toLowerCase();
      final isVoid = status == 'voided' || status == 'refunded';
      final hasDebt = ((sale['balance_due'] as num?)?.toDouble() ?? 0) > 0;
      if (_statusFilter == 'Lunas' && (isVoid || hasDebt)) return false;
      if (_statusFilter == 'Kasbon' && (!hasDebt || isVoid)) return false;
      if (_statusFilter == 'Void / Batal' && !isVoid) return false;

      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final numStr = (sale['number'] ?? '').toString().toLowerCase();
      final custName = (sale['customer'] is Map ? sale['customer']['name'] : '').toString().toLowerCase();
      final cashier = (sale['cashier_name'] ?? '').toString().toLowerCase();
      return numStr.contains(q) || custName.contains(q) || cashier.contains(q);
    }).toList();

    final validSalesTotal = filtered
        .where((s) => s['status'] != 'voided' && s['status'] != 'refunded')
        .fold<double>(0.0, (sum, s) => sum + ((s['grand_total'] as num?)?.toDouble() ?? 0.0));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('Riwayat Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Sinkronkan Riwayat Transaksi',
            icon: const Icon(Icons.sync_rounded, color: AppColors.primary),
            onPressed: () async {
              await context.read<PosCubit>().syncWithCloud(force: false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Riwayat transaksi berhasil disinkronkan.')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Sticky Filter & Search Header
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Cari nomor nota, pelanggan, atau kasir...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate400),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                // Period Pills
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final period in const ['Semua Waktu', 'Hari Ini', '7 Hari', 'Bulan Ini'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: NusaPillFilter(
                            label: period,
                            selected: _periodFilter == period,
                            selectedColor: AppColors.navyDark,
                            onTap: () => setState(() => _periodFilter = period),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Status Pills + Quick Metric
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final st in const ['Semua', 'Lunas', 'Kasbon', 'Void / Batal'])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: NusaPillFilter(
                            label: st,
                            selected: _statusFilter == st,
                            onTap: () => setState(() => _statusFilter = st),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Summary Strip
          if (filtered.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.slate100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${filtered.length} Transaksi',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate600),
                  ),
                  Row(
                    children: [
                      const Text(
                        'Total Valid: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate500),
                      ),
                      NusaPriceTag(amount: validSalesTotal, fontSize: 12.5, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),

          // 2. Transaction Cards List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => context.read<PosCubit>().syncWithCloud(force: false),
              child: filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        NusaEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Belum Ada Transaksi Tercatat',
                          subtitle: 'Buka Penjualan Baru di Kasir untuk mencatat transaksi atau ubah filter pencarian.',
                          actionLabel: (_periodFilter != 'Semua Waktu' || _statusFilter != 'Semua' || _searchQuery.isNotEmpty)
                              ? 'Tampilkan Semua'
                              : null,
                          onAction: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchQuery = '';
                              _periodFilter = 'Semua Waktu';
                              _statusFilter = 'Semua';
                            });
                          },
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(14),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final sale = filtered[idx];
                        final status = (sale['status'] ?? 'completed').toString().toLowerCase();
                        final isVoid = status == 'voided';
                        final isRefunded = status == 'refunded';
                        final hasDebt = ((sale['balance_due'] as num?)?.toDouble() ?? 0) > 0;
                        final custName = (sale['customer'] is Map ? sale['customer']['name'] : 'Pelanggan Umum').toString();
                        final cashierName = (sale['cashier_name'] ?? '').toString().trim();
                        final methods = (sale['payment_methods'] as List<dynamic>? ?? []);
                        final methodLabel = methods.isNotEmpty ? methods.first.toString() : 'Tunai';

                        return NusaCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          onTap: () => _showTransactionActionSheet(context, sale),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: (isVoid || isRefunded)
                                      ? AppColors.dangerSoft
                                      : (hasDebt ? AppColors.warningSoft : AppColors.primarySoft),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  (isVoid || isRefunded)
                                      ? Icons.cancel_outlined
                                      : (hasDebt ? Icons.menu_book_rounded : Icons.receipt_outlined),
                                  color: (isVoid || isRefunded)
                                      ? AppColors.danger
                                      : (hasDebt ? AppColors.warningDark : AppColors.primary),
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sale['number'].toString(),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navyDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sale['sale_datetime']} • $custName'
                                      '${cashierName.isNotEmpty ? ' • Kasir: $cashierName' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.slate500,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    NusaBadge(
                                      label: methodLabel,
                                      variant: NusaBadgeVariant.neutral,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  NusaPriceTag(
                                    amount: sale['grand_total'],
                                    fontSize: 14.5,
                                    strikethrough: isVoid || isRefunded,
                                    color: (isVoid || isRefunded) ? AppColors.slate400 : AppColors.navyDark,
                                  ),
                                  const SizedBox(height: 5),
                                  NusaBadge(
                                    label: isVoid
                                        ? 'Void'
                                        : (isRefunded ? 'Retur' : (hasDebt ? 'Kasbon' : 'Lunas')),
                                    icon: isVoid || isRefunded
                                        ? Icons.cancel_rounded
                                        : (hasDebt ? Icons.schedule_rounded : Icons.check_circle_rounded),
                                    variant: isVoid || isRefunded
                                        ? NusaBadgeVariant.danger
                                        : (hasDebt ? NusaBadgeVariant.warning : NusaBadgeVariant.success),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
