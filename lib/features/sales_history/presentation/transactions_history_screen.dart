import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';

part 'transactions_history_screen_part1.dart';
part 'transactions_history_screen_part2.dart';

/// LAYAR 6 — RIWAYAT TRANSAKSI (TAB 2 NAVIGASI)
/// OXORA Mobile Enterprise Sales History Screen
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

  final Map<String, int> _reprintCounts = {};


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


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
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
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('Riwayat Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Surat Penawaran Harga',
            icon: Icon(Icons.request_quote_outlined, color: tokens.accent),
            onPressed: () => context.push('/quotations'),
          ),
          IconButton(
            tooltip: 'Kelola Alasan Retur',
            icon: Icon(Icons.rule_folder_outlined, color: tokens.accent),
            onPressed: () => _showReturnReasonsManager(context),
          ),
          IconButton(
            tooltip: 'Sinkronkan Riwayat Transaksi',
            icon: Icon(Icons.sync_rounded, color: tokens.accent),
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
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
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
                    prefixIcon: Icon(Icons.search_rounded, color: tokens.textTertiary),
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
                            selectedColor: tokens.isDark ? tokens.accent : tokens.textPrimary,
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
                const SizedBox(height: 8),
                _buildTransactionShortcutsStrip(context, tokens),
              ],
            ),
          ),

          // Summary Strip
          if (filtered.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: tokens.bgElevated,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      '${filtered.length} Transaksi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total Valid: ',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.textSecondary),
                          ),
                          NusaPriceTag(amount: validSalesTotal, fontSize: 12.5, color: tokens.accent),
                        ],
                      ),
                    ),
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
                                      ? tokens.dangerSoft
                                      : (hasDebt ? tokens.warningSoft : tokens.accentSoft),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  (isVoid || isRefunded)
                                      ? Icons.cancel_outlined
                                      : (hasDebt ? Icons.menu_book_rounded : Icons.receipt_outlined),
                                  color: (isVoid || isRefunded)
                                      ? tokens.danger
                                      : (hasDebt ? tokens.warning : tokens.accent),
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
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sale['sale_datetime']} • $custName'
                                      '${cashierName.isNotEmpty ? ' • Kasir: $cashierName' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: tokens.textSecondary,
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
                                    color: (isVoid || isRefunded) ? tokens.textTertiary : tokens.textPrimary,
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
