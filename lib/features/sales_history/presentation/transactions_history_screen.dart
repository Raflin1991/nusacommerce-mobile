import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 6 — RIWAYAT TRANSAKSI (TAB 2 NAVIGASI)
/// Matches 1:1 with Bottom-Left Screen (Screen 5) of `Papan Konsep UI KasirKu Modern-1.png`
class TransactionsHistoryScreen extends StatefulWidget {
  final VoidCallback onOpenDrawer;

  const TransactionsHistoryScreen({super.key, required this.onOpenDrawer});

  @override
  State<TransactionsHistoryScreen> createState() => _TransactionsHistoryScreenState();
}

class _TransactionsHistoryScreenState extends State<TransactionsHistoryScreen> {
  String _searchQuery = '';
  String _periodFilter = 'Hari Ini';
  String _statusFilter = 'Semua';

  void _showTransactionActionSheet(BuildContext context, Map<String, dynamic> sale) {
    final voidReasonCtrl = TextEditingController();
    final isVoided = sale['status'] == 'voided';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detail Nota ${sale['number']}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                Chip(
                  label: Text(
                    isVoided ? 'VOID / BATAL' : 'LUNAS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isVoided ? AppColors.dangerDark : AppColors.successDark,
                    ),
                  ),
                  backgroundColor: isVoided ? AppColors.dangerSoft : AppColors.successSoft,
                ),
              ],
            ),
            Text(
              'Waktu: ${sale['sale_datetime']} • Total: ${IdrCurrencyFormatter.format(sale['grand_total'])}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/pos/receipt', extra: sale);
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Buka Struk (Cetak Thermal / Kirim WA)'),
              ),
            ),
            if (!isVoided) ...[
              const Divider(height: 26),
              const Text(
                'Pembatalan / Void Transaksi (Audit Anti-Fraud)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.dangerDark),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: voidReasonCtrl,
                decoration: const InputDecoration(
                  hintText: 'Wajib isi alasan void (misal: salah input barang)',
                  prefixIcon: Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () {
                    if (voidReasonCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Alasan void wajib diisi!')),
                      );
                      return;
                    }
                    final id = (sale['id'] as num?)?.toInt() ?? 0;
                    context.read<PosCubit>().voidSaleTransaction(id, voidReasonCtrl.text.trim());
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Transaksi ${sale['number']} berhasil di-Void.')),
                    );
                  },
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Batalkan (Void) & Kembalikan Stok'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salesHistory = context.watch<PosCubit>().state.salesHistory;

    final filtered = salesHistory.where((sale) {
      if (_statusFilter == 'Lunas' && sale['status'] != 'completed') return false;
      if (_statusFilter == 'Void' && sale['status'] != 'voided') return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final numStr = (sale['number'] ?? '').toString().toLowerCase();
      final custName = (sale['customer'] is Map ? sale['customer']['name'] : '').toString().toLowerCase();
      return numStr.contains(q) || custName.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('Transaksi'),
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filter Dropdowns ("Hari Ini v" | "Semua v" Persis Mockup Screen 5)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: const InputDecoration(
                    hintText: 'Cari transaksi...',
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.slate400),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildDropdownFilter(
                      value: _periodFilter,
                      items: const ['Hari Ini', '7 Hari Terakhir', 'Bulan Ini'],
                      onChanged: (val) => setState(() => _periodFilter = val!),
                    ),
                    const SizedBox(width: 10),
                    _buildDropdownFilter(
                      value: _statusFilter,
                      items: const ['Semua', 'Lunas', 'Void'],
                      onChanged: (val) => setState(() => _statusFilter = val!),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Transaction Cards List (#INV-1024, #INV-1023, #INV-1022... Persis Mockup Screen 5)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final sale = filtered[idx];
                final isVoid = sale['status'] == 'voided';
                final hasDebt = ((sale['balance_due'] as num?)?.toDouble() ?? 0) > 0;

                return InkWell(
                  onTap: () => _showTransactionActionSheet(context, sale),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.receipt_outlined, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sale['number'].toString(),
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                sale['sale_datetime'].toString(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.slate500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              IdrCurrencyFormatter.format(sale['grand_total']),
                              style: AppTheme.moneyStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Status Pill Badge ("✦ Lunas" green pill matching Mockup)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: isVoid
                                    ? AppColors.dangerSoft
                                    : (hasDebt ? AppColors.warningSoft : AppColors.successSoft),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isVoid
                                        ? Icons.cancel_rounded
                                        : (hasDebt ? Icons.schedule_rounded : Icons.check_circle_rounded),
                                    size: 11,
                                    color: isVoid
                                        ? AppColors.dangerDark
                                        : (hasDebt ? AppColors.warningDark : AppColors.successDark),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isVoid ? 'Void' : (hasDebt ? 'Kasbon' : 'Lunas'),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: isVoid
                                          ? AppColors.dangerDark
                                          : (hasDebt ? AppColors.warningDark : AppColors.successDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.slate600),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.navyDark,
          ),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
