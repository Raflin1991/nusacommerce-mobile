import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 4 — PEMBAYARAN / CHECKOUT SCREEN
/// NusaCommerce Mobile Enterprise Payment Checkout Screen
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
  bool _isCartSummaryExpanded = false;
  DateTime _kasbonDueDate = DateTime.now().add(const Duration(days: 7));
  Map<String, dynamic>? _selectedCustomer;
  bool _isSubmitting = false;

  // Additional payment sub-options
  String _qrisType = 'Dinamis'; // 'Dinamis' | 'Statis'
  String _selectedBank = 'BCA'; // 'BCA' | 'Mandiri' | 'BRI' | 'BNI'
  String _edcCardType = 'Debit'; // 'Debit' | 'Kredit'
  String _splitSecondMethod = 'QRIS'; // 'QRIS' | 'Transfer Bank' | 'Kartu EDC'

  // Split Bill state (Bagi Rata / Pisah Per-Item)
  List<int>? _splitItemIndices;
  int _splitEqualPeople = 0;

  @override
  void initState() {
    super.initState();
    final state = context.read<PosCubit>().state;
    _amountPaidController = TextEditingController(
      text: IdrCurrencyFormatter.format(state.grandTotal),
    );
    _selectedCustomer = state.selectedCustomer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.isOnline && state.cart.isNotEmpty) {
        context.read<PosCubit>().verifyServerCartPrice(
              customerId: (state.selectedCustomer?['id'] as num?)?.toInt(),
              redeemPoints: state.redeemedLoyaltyPoints,
            );
      }
    });
  }

  int _resolvePaymentMethodId(List<Map<String, dynamic>> methods, String targetCode) {
    if (methods.isEmpty) {
      return targetCode == 'cash' ? 1 : 2;
    }
    final normalized = targetCode.toLowerCase();
    for (final m in methods) {
      final code = (m['code'] ?? '').toString().toLowerCase();
      final type = (m['type'] ?? '').toString().toLowerCase();
      final name = (m['name'] ?? '').toString().toLowerCase();
      if (normalized == 'cash' &&
          (code == 'cash' || type == 'cash' || name.contains('tunai'))) {
        return (m['id'] as num?)?.toInt() ?? 1;
      }
      if (normalized != 'cash' &&
          (code.contains(normalized) || type.contains(normalized) || name.contains(normalized))) {
        return (m['id'] as num?)?.toInt() ?? 2;
      }
    }
    if (normalized != 'cash') {
      for (final m in methods) {
        final code = (m['code'] ?? '').toString().toLowerCase();
        if (code != 'cash' && (m['id'] as num?) != null) {
          return (m['id'] as num).toInt();
        }
      }
    }
    return (methods.first['id'] as num?)?.toInt() ?? (targetCode == 'cash' ? 1 : 2);
  }

  double _activeCheckoutTotal(PosState posState) {
    if (_splitItemIndices != null && _splitItemIndices!.isNotEmpty) {
      double total = 0.0;
      for (final idx in _splitItemIndices!) {
        if (idx >= 0 && idx < posState.cart.length) {
          total += posState.cart[idx].lineTotal;
        }
      }
      return total;
    }
    return posState.grandTotal;
  }

  void _syncAmountToTotal(double total) {
    if (_selectedMethodCode != 'cash' || _isSplitPayment) {
      _amountPaidController.text = IdrCurrencyFormatter.format(total);
    }
    if (_isSplitPayment) {
      _splitCashController.text = IdrCurrencyFormatter.format((total / 2).round());
    }
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
    if (code == 'kasbon') {
      final cubitCustomers = context.read<PosCubit>().state.customers;
      final customers = cubitCustomers.isNotEmpty ? cubitCustomers : widget.offlineDb.getCachedCustomers();
      _showCustomerKasbonPicker(customers, grandTotal);
      return;
    }
    if (code == 'split') {
      setState(() {
        _selectedMethodCode = 'split';
        _selectedMethodName = 'Split Payment';
        _isSplitPayment = true;
        _isKasbonMode = false;
        _splitCashController.text = IdrCurrencyFormatter.format((grandTotal / 2).round());
        _amountPaidController.text = IdrCurrencyFormatter.format(grandTotal);
      });
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

  void _showCustomerKasbonPicker(List<Map<String, dynamic>> customers, double grandTotal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih Pelanggan Kasbon (Guard Plafon Kredit)',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              if (customers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Belum ada pelanggan terdaftar. Tambahkan pelanggan di menu Kasir / Pelanggan terlebih dahulu.',
                    style: TextStyle(color: AppColors.slate500),
                  ),
                ),
              ...customers.map((c) {
                final limit = (c['credit_limit'] as num?)?.toDouble() ?? 0.0;
                final used = (c['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
                final avail = (c['available_credit'] as num?)?.toDouble() ??
                    (limit > 0 ? (limit - used).clamp(0.0, double.infinity) : 0.0);
                final exceeds = grandTotal > avail;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'Sisa Plafon: ${IdrCurrencyFormatter.format(avail)} • Hutang: ${IdrCurrencyFormatter.format(used)}',
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
                            content: Text('Plafon kredit ${c['name']} tidak mencukupi (Sisa: ${IdrCurrencyFormatter.format(avail)})!'),
                          ),
                        );
                        return;
                      }
                      context.read<PosCubit>().selectCustomer(c);
                      setState(() {
                        _selectedCustomer = c;
                        _selectedMethodCode = 'kasbon';
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
      ),
    );
  }

  void _showSplitBillModal(PosState posState) {
    String mode = _splitItemIndices != null ? 'item' : 'equal';
    int equalPeople = _splitEqualPeople > 1 ? _splitEqualPeople : 2;
    final selectedSet = <int>{...(_splitItemIndices ?? [])};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final fullTotal = posState.grandTotal;
          final perPerson = equalPeople > 0 ? (fullTotal / equalPeople).ceilToDouble() : fullTotal;
          double selectedItemsTotal = 0.0;
          for (final idx in selectedSet) {
            if (idx >= 0 && idx < posState.cart.length) {
              selectedItemsTotal += posState.cart[idx].lineTotal;
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.65,
            maxChildSize: 0.9,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Split Bill / Pisah Nota', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _splitItemIndices = null;
                            _splitEqualPeople = 0;
                            _syncAmountToTotal(posState.grandTotal);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Reset Penuh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      NusaPillFilter(
                        label: 'Bagi Rata Nominal',
                        selected: mode == 'equal',
                        onTap: () => setModalState(() => mode = 'equal'),
                      ),
                      const SizedBox(width: 8),
                      NusaPillFilter(
                        label: 'Pisah Bayar Per-Item',
                        selected: mode == 'item',
                        onTap: () => setModalState(() => mode = 'item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: mode == 'equal'
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Jumlah Orang / Pembagi:', style: TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final n in [2, 3, 4, 5])
                                    NusaPillFilter(
                                      label: '$n Orang',
                                      selected: equalPeople == n,
                                      onTap: () => setModalState(() => equalPeople = n),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    Text('Estimasi Bayar per Orang ($equalPeople Orang)', style: const TextStyle(fontSize: 12.5)),
                                    const SizedBox(height: 4),
                                    Text(
                                      IdrCurrencyFormatter.format(perPerson),
                                      style: AppTheme.moneyStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            itemCount: posState.cart.length,
                            itemBuilder: (_, idx) {
                              final item = posState.cart[idx];
                              final checked = selectedSet.contains(idx);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: (val) {
                                  setModalState(() {
                                    if (val == true) {
                                      selectedSet.add(idx);
                                    } else {
                                      selectedSet.remove(idx);
                                    }
                                  });
                                },
                                title: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${IdrCurrencyFormatter.formatQty(item.quantity)} × ${IdrCurrencyFormatter.format(item.unitPrice)}'),
                                secondary: Text(
                                  IdrCurrencyFormatter.format(item.lineTotal),
                                  style: AppTheme.moneyStyle(fontWeight: FontWeight.w800),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        if (mode == 'item') {
                          if (selectedSet.isEmpty) return;
                          setState(() {
                            _splitItemIndices = selectedSet.toList()..sort();
                            _splitEqualPeople = 0;
                            _syncAmountToTotal(selectedItemsTotal);
                          });
                        } else {
                          setState(() {
                            _splitItemIndices = null;
                            _splitEqualPeople = equalPeople;
                            _syncAmountToTotal(fullTotal);
                          });
                        }
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        mode == 'item'
                            ? 'Bayar Item Terpilih (${IdrCurrencyFormatter.format(selectedItemsTotal)})'
                            : 'Gunakan Info Split $equalPeople Orang',
                      ),
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
    final availableMethods = context.read<PosCubit>().state.paymentMethods;

    if (_isSplitPayment) {
      final cashPart = IdrCurrencyFormatter.parse(_splitCashController.text).clamp(0.0, grandTotal);
      final secondPart = (grandTotal - cashPart).clamp(0.0, grandTotal);
      final cashId = _resolvePaymentMethodId(availableMethods, 'cash');
      final secondCode = _splitSecondMethod.toLowerCase().contains('qris')
          ? 'qris'
          : (_splitSecondMethod.toLowerCase().contains('transfer') ? 'transfer' : 'card');
      final secondId = _resolvePaymentMethodId(availableMethods, secondCode);
      paymentsList.add({'payment_method_id': cashId, 'amount': cashPart, 'tendered_amount': cashPart});
      paymentsList.add({
        'payment_method_id': secondId,
        'amount': secondPart,
        'reference': '${_splitSecondMethod.toUpperCase()}-SPLIT',
      });
      methodNames.addAll([
        'Tunai (${IdrCurrencyFormatter.format(cashPart)})',
        '$_splitSecondMethod (${IdrCurrencyFormatter.format(secondPart)})',
      ]);
    } else {
      String resolvedName = _selectedMethodName;
      if (_selectedMethodCode == 'qris') resolvedName = 'QRIS $_qrisType';
      if (_selectedMethodCode == 'transfer') resolvedName = 'Transfer $_selectedBank';
      if (_selectedMethodCode == 'card') resolvedName = 'EDC $_edcCardType';

      paymentsList.add({
        'payment_method_id': _resolvePaymentMethodId(availableMethods, _selectedMethodCode),
        'amount': _isKasbonMode ? 0.0 : grandTotal,
        'tendered_amount': paid,
        'reference': _referenceController.text.trim().isNotEmpty
            ? _referenceController.text.trim()
            : resolvedName,
      });
      methodNames.add(resolvedName);
    }

    final receipt = await context.read<PosCubit>().completeCheckout(
          payments: paymentsList,
          paymentMethodNames: methodNames,
          paidTotal: paid,
          changeReturned: change,
          balanceDue: balanceDue,
          splitItemIndices: _splitItemIndices,
          dueDate: _isKasbonMode ? DateFormat('yyyy-MM-dd').format(_kasbonDueDate) : null,
        );

    if (mounted) {
      setState(() => _isSubmitting = false);
      context.pushReplacement('/pos/receipt', extra: receipt);
    }
  }

  Future<void> _pickKasbonDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _kasbonDueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _kasbonDueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posState = context.watch<PosCubit>().state;
    final grandTotal = _activeCheckoutTotal(posState);
    final changeAmount = _isKasbonMode ? 0.0 : (_paidAmount - grandTotal).clamp(0.0, double.infinity);
    final isCashInsufficient = !_isKasbonMode && _paidAmount < grandTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Pembayaran'),
        actions: [
          if (posState.cart.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _showSplitBillModal(posState),
                icon: const Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.primary),
                label: Text(
                  _splitItemIndices != null
                      ? 'Split (${_splitItemIndices!.length})'
                      : (_splitEqualPeople > 1 ? '÷$_splitEqualPeople' : 'Split Bill'),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Executive Total Tagihan + Collapsible Rincian Item Card
              NusaCard(
                padding: EdgeInsets.zero,
                borderColor: AppColors.navyDark.withOpacity(0.15),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      decoration: const BoxDecoration(
                        gradient: AppColors.heroNavyGradient,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Total Tagihan',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              if (posState.totalDiscount > 0) ...[
                                const SizedBox(width: 8),
                                NusaBadge(
                                  label: 'Hemat ${IdrCurrencyFormatter.format(posState.totalDiscount)}',
                                  variant: NusaBadgeVariant.success,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          NusaPriceTag(
                            amount: grandTotal,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    // Expandable Item Summary Toggle
                    InkWell(
                      onTap: posState.cart.isNotEmpty
                          ? () => setState(() => _isCartSummaryExpanded = !_isCartSummaryExpanded)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.shopping_bag_outlined, size: 17, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rincian Belanja (${IdrCurrencyFormatter.formatQty(posState.totalItemsCount)} item)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                            Text(
                              _isCartSummaryExpanded ? 'Tutup' : 'Edit / Lihat',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isCartSummaryExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isCartSummaryExpanded && posState.cart.isNotEmpty) ...[
                      const Divider(height: 1, color: AppColors.border),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: posState.cart.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, idx) {
                          final item = posState.cart[idx];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.navyDark,
                                        ),
                                      ),
                                      Text(
                                        '${IdrCurrencyFormatter.format(item.unitPrice)} × ${IdrCurrencyFormatter.formatQty(item.quantity)}',
                                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppColors.slate100,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          context.read<PosCubit>().decrementCartItem(idx);
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted) {
                                              _syncAmountToTotal(_activeCheckoutTotal(context.read<PosCubit>().state));
                                            }
                                          });
                                        },
                                        child: const SizedBox(
                                          width: 32,
                                          height: 34,
                                          child: Icon(Icons.remove_rounded, size: 16),
                                        ),
                                      ),
                                      Text(
                                        IdrCurrencyFormatter.formatQty(item.quantity),
                                        style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          context.read<PosCubit>().incrementCartItem(idx);
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted) {
                                              _syncAmountToTotal(_activeCheckoutTotal(context.read<PosCubit>().state));
                                            }
                                          });
                                        },
                                        child: const SizedBox(
                                          width: 32,
                                          height: 34,
                                          child: Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                NusaPriceTag(
                                  amount: item.lineTotal,
                                  fontSize: 12.5,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Explicit 6 Payment Methods Grid
              const Text(
                'Pilih Metode Pembayaran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.15,
                children: [
                  _buildPaymentMethodCard(
                    code: 'cash',
                    label: 'Tunai',
                    icon: Icons.payments_outlined,
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
                    code: 'card',
                    label: 'Kartu EDC',
                    icon: Icons.credit_card_rounded,
                    grandTotal: grandTotal,
                  ),
                  _buildPaymentMethodCard(
                    code: 'kasbon',
                    label: 'Kasbon (Buku Bon)',
                    icon: Icons.menu_book_rounded,
                    grandTotal: grandTotal,
                    accentColor: AppColors.warningDark,
                  ),
                  _buildPaymentMethodCard(
                    code: 'split',
                    label: 'Split Payment',
                    icon: Icons.call_split_rounded,
                    grandTotal: grandTotal,
                  ),
                ],
              ),

              if (_splitEqualPeople > 1 && _splitItemIndices == null) ...[
                const SizedBox(height: 12),
                NusaCard(
                  backgroundColor: AppColors.primarySoft,
                  borderColor: AppColors.primary.withOpacity(0.25),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.group_rounded, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Split Bill $_splitEqualPeople Orang • Patungan ${IdrCurrencyFormatter.format((grandTotal / _splitEqualPeople).ceilToDouble())} / orang',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Conditional QRIS / Transfer Bank / EDC / Split / Kasbon Info Box
              if (_selectedMethodCode == 'qris') ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: AppColors.primarySoft,
                  borderColor: AppColors.primary.withOpacity(0.28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          NusaPillFilter(
                            label: 'QRIS Dinamis',
                            selected: _qrisType == 'Dinamis',
                            onTap: () => setState(() => _qrisType = 'Dinamis'),
                          ),
                          const SizedBox(width: 8),
                          NusaPillFilter(
                            label: 'QRIS Statis',
                            selected: _qrisType == 'Statis',
                            onTap: () => setState(() => _qrisType = 'Statis'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.qr_code_2_rounded, size: 52, color: AppColors.navyDark),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'QRIS $_qrisType NusaCommerce',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                                ),
                                Text(
                                  'Pelanggan scan QR sebesar ${IdrCurrencyFormatter.format(grandTotal)} via BCA / Mandiri / GoPay / OVO / Dana.',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              if (_selectedMethodCode == 'transfer') ...[
                const SizedBox(height: 14),
                NusaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pilih Bank Tujuan:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['BCA', 'Mandiri', 'BRI', 'BNI'].map((bank) {
                          return NusaPillFilter(
                            label: bank,
                            selected: _selectedBank == bank,
                            onTap: () => setState(() => _selectedBank = bank),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Nomor Referensi / Catatan Transfer',
                          hintText: 'Misal: TRF-00192',
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_selectedMethodCode == 'card') ...[
                const SizedBox(height: 14),
                NusaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          NusaPillFilter(
                            label: 'Kartu Debit',
                            selected: _edcCardType == 'Debit',
                            onTap: () => setState(() => _edcCardType = 'Debit'),
                          ),
                          const SizedBox(width: 8),
                          NusaPillFilter(
                            label: 'Kartu Kredit',
                            selected: _edcCardType == 'Kredit',
                            onTap: () => setState(() => _edcCardType = 'Kredit'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Kode Approval / Trace No EDC',
                          hintText: 'Misal: APPR-8821',
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_isSplitPayment) ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: AppColors.primarySoft,
                  borderColor: AppColors.primary.withOpacity(0.25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kombinasi Split Payment',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.navyDark),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _splitCashController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Nominal Bayar Tunai (Rp)',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['QRIS', 'Transfer Bank', 'Kartu EDC'].map((m) {
                          return NusaPillFilter(
                            label: m,
                            selected: _splitSecondMethod == m,
                            onTap: () => setState(() => _splitSecondMethod = m),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Builder(builder: (_) {
                        final cashPart = IdrCurrencyFormatter.parse(_splitCashController.text).clamp(0.0, grandTotal);
                        final rem = (grandTotal - cashPart).clamp(0.0, grandTotal);
                        return Text(
                          'Sisa dibayar via $_splitSecondMethod: ${IdrCurrencyFormatter.format(rem)}',
                          style: AppTheme.moneyStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              if (_isKasbonMode && _selectedCustomer != null) ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: AppColors.warningSoft,
                  borderColor: AppColors.warning.withOpacity(0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu_book_rounded, color: AppColors.warningDark),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Piutang Buku Bon: ${_selectedCustomer!['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: AppColors.warningDark,
                              ),
                            ),
                          ),
                          const NusaBadge(label: 'Plafon Aman', variant: NusaBadgeVariant.success),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: _pickKasbonDueDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_available_rounded, size: 18, color: AppColors.warningDark),
                              const SizedBox(width: 8),
                              const Text(
                                'Jatuh Tempo:',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.slate700),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  DateFormat('dd MMM yyyy').format(_kasbonDueDate),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyDark,
                                  ),
                                ),
                              ),
                              const Text(
                                'Ubah',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 3. Jumlah Bayar Input Box + 5 Quick Cash Buttons
              if (!_isKasbonMode) ...[
                NusaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Nominal Diterima (Rp)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountPaidController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: AppTheme.moneyStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.background,
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
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          NusaPillFilter(
                            label: 'Uang Pas',
                            selected: _paidAmount == grandTotal,
                            onTap: () => _setQuickCashAmount(grandTotal),
                          ),
                          NusaPillFilter(
                            label: 'Rp 20.000',
                            selected: _paidAmount == 20000,
                            onTap: () => _setQuickCashAmount(20000),
                          ),
                          NusaPillFilter(
                            label: 'Rp 50.000',
                            selected: _paidAmount == 50000,
                            onTap: () => _setQuickCashAmount(50000),
                          ),
                          NusaPillFilter(
                            label: 'Rp 100.000',
                            selected: _paidAmount == 100000,
                            onTap: () => _setQuickCashAmount(100000),
                          ),
                          NusaPillFilter(
                            label: 'Rp 200.000',
                            selected: _paidAmount == 200000,
                            onTap: () => _setQuickCashAmount(200000),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: AppColors.floatingCartShadow,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Prominent Kembalian / Kasbon Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isKasbonMode
                      ? AppColors.warningSoft
                      : (isCashInsufficient ? AppColors.dangerSoft : AppColors.successSoft),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isKasbonMode
                        ? AppColors.warning.withOpacity(0.35)
                        : (isCashInsufficient
                            ? AppColors.danger.withOpacity(0.35)
                            : AppColors.success.withOpacity(0.35)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isKasbonMode
                          ? 'Masuk Buku Bon'
                          : (isCashInsufficient ? 'Kurang Bayar' : 'Uang Kembalian'),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _isKasbonMode
                            ? AppColors.warningDark
                            : (isCashInsufficient ? AppColors.danger : AppColors.successDark),
                      ),
                    ),
                    NusaPriceTag(
                      amount: _isKasbonMode
                          ? grandTotal
                          : (isCashInsufficient ? (grandTotal - _paidAmount) : changeAmount),
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _isKasbonMode
                          ? AppColors.warningDark
                          : (isCashInsufficient ? AppColors.danger : AppColors.successDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              NusaButton(
                label: _isSubmitting ? 'Memproses...' : 'Selesaikan Pembayaran',
                trailingIcon: Icons.check_circle_rounded,
                minHeight: 52,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : () => _submitPayment(grandTotal),
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
    Color? accentColor,
  }) {
    final isSelected = _selectedMethodCode == code;
    final activeColor = accentColor ?? AppColors.primary;

    return InkWell(
      onTap: () => _selectPaymentMethod(code, label, grandTotal),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? activeColor : AppColors.navyMid,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  color: isSelected ? activeColor : AppColors.navyDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
