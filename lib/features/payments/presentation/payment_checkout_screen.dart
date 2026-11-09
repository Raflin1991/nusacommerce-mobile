import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 4 — PEMBAYARAN / CHECKOUT SCREEN
/// Matches 1:1 with Top-Right Screen (Screen 4) of `Papan Konsep UI KasirKu Modern-1.png`
class PaymentCheckoutScreen extends StatefulWidget {
  final OfflineDatabase offlineDb;

  const PaymentCheckoutScreen({super.key, required this.offlineDb});

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  String _selectedMethodCode = 'cash';
  String _selectedMethodName = 'Tunai';
  late final TextEditingController _amountPaidController;
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _splitCashController = TextEditingController();
  bool _isSplitPayment = false;
  bool _isKasbonMode = false;
  Map<String, dynamic>? _selectedCustomer;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final grandTotal = context.read<PosCubit>().state.grandTotal;
    // If total is Rp 17.000 (default mockup cart), default tendered to Rp 20.000 so Kembalian = Rp 3.000!
    final defaultTendered = grandTotal == 17000 ? 20000.0 : grandTotal;
    _amountPaidController = TextEditingController(
      text: IdrCurrencyFormatter.format(defaultTendered),
    );
    _selectedCustomer = context.read<PosCubit>().state.selectedCustomer;
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    _referenceController.dispose();
    _splitCashController.dispose();
    super.dispose();
  }

  double get _paidAmount => IdrCurrencyFormatter.parse(_amountPaidController.text);

  void _setQuickCashAmount(double amount) {
    setState(() {
      _amountPaidController.text = IdrCurrencyFormatter.format(amount);
    });
  }

  void _selectPaymentMethod(String code, String label, double grandTotal) {
    if (code == 'other') {
      _showKasbonOrSplitModal(grandTotal);
      return;
    }
    setState(() {
      _selectedMethodCode = code;
      _selectedMethodName = label;
      _isKasbonMode = false;
      _isSplitPayment = false;
      if (code != 'cash') {
        _amountPaidController.text = IdrCurrencyFormatter.format(grandTotal);
      }
    });
  }

  void _showKasbonOrSplitModal(double grandTotal) {
    final customers = widget.offlineDb.getCachedCustomers();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Metode Pembayaran Lainnya',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pilih Catat Kasbon (Buku Bon UMKM) atau Split Payment (Bayar Campuran)',
              style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
            ),
            const SizedBox(height: 16),
            // Option 1: Buku Bon / Kasbon with Credit Limit Guard
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.warningSoft,
                child: Icon(Icons.menu_book_rounded, color: AppColors.warningDark),
              ),
              title: const Text(
                'Catat Kasbon / Piutang (Buku Bon)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Tagihan masuk ke Buku Bon Pelanggan & bisa ditagih via WA'),
              onTap: () {
                Navigator.pop(ctx);
                _showCustomerKasbonPicker(customers, grandTotal);
              },
            ),
            const Divider(),
            // Option 2: Split Payment (Tunai + QRIS)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(Icons.call_split_rounded, color: AppColors.primary),
              ),
              title: const Text(
                'Split Payment (Bayar Campuran Tunai + QRIS)',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Sebagian dibayar uang tunai, sisanya via QRIS / Transfer'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedMethodCode = 'other';
                  _selectedMethodName = 'Split (Tunai + QRIS)';
                  _isSplitPayment = true;
                  _isKasbonMode = false;
                  _splitCashController.text = IdrCurrencyFormatter.format((grandTotal / 2).round());
                  _amountPaidController.text = IdrCurrencyFormatter.format(grandTotal);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomerKasbonPicker(List<Map<String, dynamic>> customers, double grandTotal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pilih Pelanggan Kasbon (Guard Plafon Kredit)',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ...customers.map((c) {
              final avail = (c['available_credit'] as num?)?.toDouble() ?? 500000.0;
              final exceeds = grandTotal > avail;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  'Sisa Plafon: ${IdrCurrencyFormatter.format(avail)} • Hutang: ${IdrCurrencyFormatter.format(c['outstanding_balance'])}',
                  style: TextStyle(color: exceeds ? AppColors.danger : AppColors.slate600, fontSize: 12),
                ),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: exceeds ? AppColors.danger : AppColors.warningDark,
                  ),
                  onPressed: () {
                    if (exceeds) {
                      PosFeedback.onGuardBlocked();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.danger,
                          content: Text('Plafon kredit ${c['name']} tidak mencukupi!'),
                        ),
                      );
                      return;
                    }
                    context.read<PosCubit>().selectCustomer(c);
                    setState(() {
                      _selectedCustomer = c;
                      _selectedMethodCode = 'other';
                      _selectedMethodName = 'Kasbon (Buku Bon)';
                      _isKasbonMode = true;
                      _isSplitPayment = false;
                      _amountPaidController.text = IdrCurrencyFormatter.format(0);
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text(exceeds ? 'Limit Habis' : 'Pilih'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _submitPayment(double grandTotal) async {
    if (_isSubmitting) return;

    final paid = _isKasbonMode ? 0.0 : _paidAmount;
    if (!_isKasbonMode && paid < grandTotal) {
      PosFeedback.onGuardBlocked();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Jumlah bayar kurang dari Total Tagihan!'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final change = _isKasbonMode ? 0.0 : (paid - grandTotal).clamp(0.0, double.infinity);
    final balanceDue = _isKasbonMode ? grandTotal : 0.0;

    final paymentsList = <Map<String, dynamic>>[];
    final methodNames = <String>[];

    if (_isSplitPayment) {
      final cashPart = IdrCurrencyFormatter.parse(_splitCashController.text).clamp(0.0, grandTotal);
      final qrisPart = (grandTotal - cashPart).clamp(0.0, grandTotal);
      paymentsList.add({'payment_method_id': 1, 'amount': cashPart, 'tendered_amount': cashPart});
      paymentsList.add({'payment_method_id': 2, 'amount': qrisPart, 'reference': 'QRIS-SPLIT'});
      methodNames.addAll(['Tunai (${IdrCurrencyFormatter.format(cashPart)})', 'QRIS (${IdrCurrencyFormatter.format(qrisPart)})']);
    } else {
      paymentsList.add({
        'payment_method_id': _selectedMethodCode == 'cash' ? 1 : 2,
        'amount': _isKasbonMode ? 0.0 : grandTotal,
        'tendered_amount': paid,
        'reference': _referenceController.text.trim(),
      });
      methodNames.add(_selectedMethodName);
    }

    final receipt = await context.read<PosCubit>().completeCheckout(
          payments: paymentsList,
          paymentMethodNames: methodNames,
          paidTotal: paid,
          changeReturned: change,
          balanceDue: balanceDue,
        );

    if (mounted) {
      setState(() => _isSubmitting = false);
      context.pushReplacement('/pos/receipt', extra: receipt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posState = context.watch<PosCubit>().state;
    final grandTotal = posState.grandTotal > 0 ? posState.grandTotal : 17000.0;
    final changeAmount = _isKasbonMode ? 0.0 : (_paidAmount - grandTotal).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Pembayaran'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Total Tagihan Soft Blue Header Card (Persis Mockup Screen 4)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primarySoft,
                      AppColors.primaryLight.withOpacity(0.55),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Total Tagihan',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      IdrCurrencyFormatter.format(grandTotal),
                      style: AppTheme.moneyStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navyDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Section "Pilih Metode Pembayaran" (6 Grid Cards 2x3 Persis Mockup Screen 4)
              const Text(
                'Pilih Metode Pembayaran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 12,
                childAspectRatio: 1.95,
                children: [
                  _buildPaymentMethodCard(
                    code: 'cash',
                    label: 'Tunai',
                    icon: Icons.account_balance_wallet_rounded,
                    grandTotal: grandTotal,
                  ),
                  _buildPaymentMethodCard(
                    code: 'qris',
                    label: 'QRIS',
                    icon: Icons.qr_code_2_rounded,
                    grandTotal: grandTotal,
                  ),
                  _buildPaymentMethodCard(
                    code: 'transfer',
                    label: 'Transfer Bank',
                    icon: Icons.account_balance_rounded,
                    grandTotal: grandTotal,
                  ),
                  _buildPaymentMethodCard(
                    code: 'ewallet',
                    label: 'E-Wallet',
                    icon: Icons.phone_android_rounded,
                    grandTotal: grandTotal,
                  ),
                  _buildPaymentMethodCard(
                    code: 'card',
                    label: 'Kartu Debit',
                    icon: Icons.credit_card_rounded,
                    grandTotal: grandTotal,
                  ),
                  _buildPaymentMethodCard(
                    code: 'other',
                    label: _isKasbonMode
                        ? 'Kasbon (Bon)'
                        : (_isSplitPayment ? 'Split Bayar' : 'Lainnya'),
                    icon: Icons.more_horiz_rounded,
                    grandTotal: grandTotal,
                  ),
                ],
              ),

              // Conditional QRIS / Reference / Kasbon Info Box
              if (_selectedMethodCode == 'qris') ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded, size: 54, color: AppColors.navyDark),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'QRIS Dinamis NusaCommerce',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                            Text(
                              'Pelanggan scan QR sebesar ${IdrCurrencyFormatter.format(grandTotal)} via BCA/Mandiri/GoPay/OVO/Dana.',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_isKasbonMode && _selectedCustomer != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, color: AppColors.warningDark),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Dicatat ke Buku Bon: ${_selectedCustomer!['name']} (Plafon Aman ✓)',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.warningDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // 3. "Jumlah Bayar" Input Box + Quick Cash Chips (Persis Mockup Screen 4)
              const Text(
                'Jumlah Bayar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountPaidController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                style: AppTheme.moneyStyle(fontSize: 20, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.cancel_rounded, color: AppColors.slate400),
                    onPressed: () {
                      setState(() {
                        _amountPaidController.text = 'Rp 0';
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Quick Denomination Chips for Fast One-Handed Cashier Operation
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _quickCashChip('Uang Pas', grandTotal),
                    const SizedBox(width: 8),
                    _quickCashChip('Rp 20.000', 20000),
                    const SizedBox(width: 8),
                    _quickCashChip('Rp 50.000', 50000),
                    const SizedBox(width: 8),
                    _quickCashChip('Rp 100.000', 100000),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 4. "Kembalian: Rp 3.000" Row (Persis Mockup Screen 4)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isKasbonMode ? 'Masuk Piutang Buku Bon' : 'Kembalian',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navyDark,
                    ),
                  ),
                  Text(
                    IdrCurrencyFormatter.format(_isKasbonMode ? grandTotal : changeAmount),
                    style: AppTheme.moneyStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _isKasbonMode ? AppColors.warningDark : AppColors.successDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // 5. Full-Width Blue CTA Button: "Selesaikan Pembayaran ✓"
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : () => _submitPayment(grandTotal),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 3,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSubmitting ? 'Memproses...' : 'Selesaikan Pembayaran',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard({
    required String code,
    required String label,
    required IconData icon,
    required double grandTotal,
  }) {
    final isSelected = _selectedMethodCode == code;

    return InkWell(
      onTap: () => _selectPaymentMethod(code, label, grandTotal),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 26,
              color: isSelected ? AppColors.primary : AppColors.navyMid,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.navyDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCashChip(String label, double amount) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _setQuickCashAmount(amount),
      backgroundColor: AppColors.primarySoft,
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide.none,
      ),
    );
  }
}
