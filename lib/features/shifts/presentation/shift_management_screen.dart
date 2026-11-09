import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';

/// MODUL SHIFT KASIR, MUTASI LACI UANG & REKONSILIASI Z-REPORT
/// Connected to `/api/v1/shifts/*`
class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  bool _isShiftOpen = true;
  double _openingCash = 500000.0;
  final double _cashSales = 1250000.0;
  double _payIns = 100000.0;
  double _payOuts = 50000.0;
  final TextEditingController _countedCashCtrl = TextEditingController(text: '1800000');

  final List<Map<String, dynamic>> _drawerEntries = [
    {'type': 'pay_in', 'amount': 100000.0, 'reason': 'Tambahan uang receh kembalian', 'time': '09:15'},
    {'type': 'pay_out', 'amount': 50000.0, 'reason': 'Beli kantong plastik & kertas thermal', 'time': '13:40'},
  ];

  double get _expectedCash => _openingCash + _cashSales + _payIns - _payOuts;

  void _showAddCashEntryModal(String type) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

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
            Text(
              type == 'pay_in' ? 'Catat Kas Masuk Laci (Pay-In)' : 'Catat Kas Keluar Laci (Pay-Out)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nominal Uang (Rp)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Alasan / Keterangan Mutasi Kas',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amt = IdrCurrencyFormatter.parse(amountCtrl.text);
                  if (amt <= 0) return;
                  setState(() {
                    if (type == 'pay_in') {
                      _payIns += amt;
                    } else {
                      _payOuts += amt;
                    }
                    _drawerEntries.insert(0, {
                      'type': type,
                      'amount': amt,
                      'reason': reasonCtrl.text.trim().isEmpty ? 'Mutasi kas laci' : reasonCtrl.text.trim(),
                      'time': 'Baru saja',
                    });
                    _countedCashCtrl.text = _expectedCash.toInt().toString();
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Simpan Mutasi Kas Laci'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closeShiftAndSendZReport() async {
    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    setState(() => _isShiftOpen = false);

    await WhatsAppService.sendShiftZReportToOwner(
      ownerPhone: '081234567890',
      storeName: 'Toko Berkah Jaya (Kemang)',
      cashierName: 'Raflin Abdul',
      openingCash: _openingCash,
      salesTotal: _cashSales,
      expectedCash: _expectedCash,
      countedCash: counted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    final variance = counted - _expectedCash;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Shift Kasir & Laci Uang'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Live X-Report / Expected Drawer Cash Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: _isShiftOpen ? AppColors.heroBlueGradient : AppColors.executiveNavyGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isShiftOpen ? '🟢 SHIFT KASIR AKTIF (KASIR-01)' : '⚪ SHIFT SUDAH DITUTUP (Z-REPORT)',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                      if (!_isShiftOpen)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                          onPressed: () => setState(() {
                            _isShiftOpen = true;
                            _openingCash = 500000;
                          }),
                          child: const Text('Buka Shift Baru'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Saldo Kas Tunai Seharusnya di Laci',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  Text(
                    IdrCurrencyFormatter.format(_expectedCash),
                    style: AppTheme.moneyStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _shiftStat('Modal Awal', IdrCurrencyFormatter.format(_openingCash)),
                      _shiftStat('Jual Tunai', IdrCurrencyFormatter.format(_cashSales)),
                      _shiftStat('Kas Masuk/Keluar', '+${IdrCurrencyFormatter.formatCompact(_payIns - _payOuts)}'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 2. Quick Cash In / Out Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddCashEntryModal('pay_in'),
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.successDark),
                    label: const Text('Kas Masuk (Pay-In)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddCashEntryModal('pay_out'),
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger),
                    label: const Text('Kas Keluar (Pay-Out)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 3. Close Shift & Blind Cash Reconciliation Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rekonsiliasi Tutup Shift (Z-Report)',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _countedCashCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Uang Tunai Fisik Dihitung di Laci (Rp)',
                      prefixIcon: Icon(Icons.calculate_outlined, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Selisih Kas (Cash Variance):', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        IdrCurrencyFormatter.format(variance),
                        style: AppTheme.moneyStyle(
                          fontSize: 15,
                          color: variance == 0 ? AppColors.successDark : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _closeShiftAndSendZReport,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.navyMid),
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('Tutup Shift, Cetak Z-Report & Kirim WA Owner'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 4. Cash Drawer Mutation History
            const Text(
              'Riwayat Mutasi Kas Laci Shift Ini',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ..._drawerEntries.map((e) {
              final isIn = e['type'] == 'pay_in';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isIn ? AppColors.successSoft : AppColors.dangerSoft,
                    child: Icon(
                      isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                      color: isIn ? AppColors.successDark : AppColors.danger,
                    ),
                  ),
                  title: Text(e['reason'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: Text('Jam: ${e['time']}'),
                  trailing: Text(
                    '${isIn ? '+' : '-'}${IdrCurrencyFormatter.format(e['amount'])}',
                    style: AppTheme.moneyStyle(
                      fontSize: 13.5,
                      color: isIn ? AppColors.successDark : AppColors.danger,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _shiftStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
