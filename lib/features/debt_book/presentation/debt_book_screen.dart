import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';

/// MODUL BUKU BON UMKM (PIUTANG PELANGGAN + 1-KLIK TAGIH WA) & BIAYA OPERASIONAL
/// Connected to `/api/v1/debts/receivables` & `/api/v1/expenses`
class DebtBookScreen extends StatefulWidget {
  final int initialTab;

  const DebtBookScreen({super.key, this.initialTab = 0});

  @override
  State<DebtBookScreen> createState() => _DebtBookScreenState();
}

class _DebtBookScreenState extends State<DebtBookScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> _receivables = [
    {
      'sale_id': 901,
      'number': '#INV-0988',
      'customer_name': 'Budi Santoso (Warung Berkah)',
      'phone': '081234567890',
      'age_days': 14,
      'balance_due': 200000.0,
    },
    {
      'sale_id': 902,
      'number': '#INV-1002',
      'customer_name': 'Siti Rahmawati',
      'phone': '081398765432',
      'age_days': 3,
      'balance_due': 120000.0,
    },
  ];

  final List<Map<String, dynamic>> _expenses = [
    {
      'number': 'EXP-202611-01',
      'category': 'Listrik & Air Toko',
      'description': 'Token Listrik Toko Kemang',
      'amount': 250000.0,
      'date': 'Hari Ini',
    },
    {
      'number': 'EXP-202611-02',
      'category': 'Kemasan & Plastik',
      'description': 'Kantong kresek & kertas thermal 10 roll',
      'amount': 95000.0,
      'date': 'Kemarin',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double get _totalReceivables =>
      _receivables.fold(0.0, (sum, r) => sum + ((r['balance_due'] as num?)?.toDouble() ?? 0.0));

  void _showPayInstallmentModal(int index) {
    final item = _receivables[index];
    final currentDue = (item['balance_due'] as num).toDouble();
    final amountCtrl = TextEditingController(text: currentDue.toInt().toString());

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
              'Catat Pelunasan / Cicilan — ${item['customer_name']}',
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
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
                onPressed: () {
                  final paid = IdrCurrencyFormatter.parse(amountCtrl.text);
                  setState(() {
                    if (paid >= currentDue) {
                      _receivables.removeAt(index);
                    } else {
                      _receivables[index]['balance_due'] = currentDue - paid;
                    }
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pembayaran piutang Buku Bon berhasil dicatat!')),
                  );
                },
                child: const Text('Simpan Pembayaran Piutang'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddExpenseModal() {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();

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
            const Text(
              'Catat Biaya Operasional / Pembelian',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Keterangan Biaya / Pembelian',
                prefixIcon: Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nominal Pengeluaran (Rp)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                  if (amt <= 0) return;
                  setState(() {
                    _expenses.insert(0, {
                      'number': 'EXP-${DateTime.now().millisecond}',
                      'category': 'Operasional Toko',
                      'description': descCtrl.text.trim().isEmpty ? 'Biaya Harian' : descCtrl.text.trim(),
                      'amount': amt,
                      'date': 'Baru saja',
                    });
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Simpan Biaya Operasional'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Buku Bon & Biaya Toko'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          tabs: const [
            Tab(text: 'Piutang Pelanggan (Bon)'),
            Tab(text: 'Biaya & Pembelian'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: BUKU BON PIUTANG PELANGGAN
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Piutang Belum Lunas',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.warningDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          IdrCurrencyFormatter.format(_totalReceivables),
                          style: AppTheme.moneyStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.navyDark),
                        ),
                      ],
                    ),
                    Chip(
                      backgroundColor: Colors.white,
                      label: Text(
                        '${_receivables.length} Penunggak',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ...List.generate(_receivables.length, (idx) {
                final r = _receivables[idx];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            r['customer_name'].toString(),
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            IdrCurrencyFormatter.format(r['balance_due']),
                            style: AppTheme.moneyStyle(fontSize: 15, color: AppColors.danger),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nota ${r['number']} • Umur Piutang: ${r['age_days']} Hari • WA: ${r['phone']}',
                        style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                WhatsAppService.sendDebtReminder(
                                  customerName: r['customer_name'].toString(),
                                  customerPhone: r['phone'].toString(),
                                  invoiceNumber: r['number'].toString(),
                                  balanceDue: r['balance_due'] as num,
                                  storeName: 'Toko Berkah Jaya',
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.successDark,
                                side: const BorderSide(color: AppColors.success),
                              ),
                              icon: const Icon(Icons.chat_rounded, size: 17),
                              label: const Text('Tagih WA'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showPayInstallmentModal(idx),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                              label: const Text('Catat Bayar'),
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

          // TAB 2: BIAYA OPERASIONAL & PEMBELIAN
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showAddExpenseModal,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah Biaya Operasional / Pembelian'),
                ),
              ),
              const SizedBox(height: 14),
              ..._expenses.map((exp) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.dangerSoft,
                        child: Icon(Icons.receipt_long_rounded, color: AppColors.danger),
                      ),
                      title: Text(exp['description'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${exp['category']} • ${exp['date']}'),
                      trailing: Text(
                        IdrCurrencyFormatter.format(exp['amount']),
                        style: AppTheme.moneyStyle(fontSize: 14, color: AppColors.dangerDark),
                      ),
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
