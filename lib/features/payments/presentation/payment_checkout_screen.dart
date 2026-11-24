import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/utils/pos_financial_calculator.dart';

class _MultiTenderLine {
  String methodCode;
  String methodLabel;
  final TextEditingController amountController;
  final TextEditingController referenceController;
  String subType;

  _MultiTenderLine({
    required this.methodCode,
    required this.methodLabel,
    required double initialAmount,
    String initialSubType = '',
  })  : amountController = TextEditingController(
          text: IdrCurrencyFormatter.format(initialAmount),
        ),
        referenceController = TextEditingController(),
        subType = initialSubType;

  double get amount => IdrCurrencyFormatter.parse(amountController.text);

  void dispose() {
    amountController.dispose();
    referenceController.dispose();
  }
}

/// LAYAR 4 — PEMBAYARAN / CHECKOUT SCREEN
/// OXORA Mobile Enterprise Payment Checkout Screen
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
  final TextEditingController _storeCreditController = TextEditingController(text: 'Rp 0');
  final TextEditingController _kasbonDpController = TextEditingController(text: 'Rp 0');
  bool _isSplitPayment = false;
  bool _isKasbonMode = false;
  bool _useStoreCredit = false;
  bool _refundSurplusToStoreCredit = true;
  bool _isCartSummaryExpanded = false;
  DateTime _kasbonDueDate = DateTime.now().add(const Duration(days: 7));
  Map<String, dynamic>? _selectedCustomer;
  bool _isSubmitting = false;
  String? _pendingIdempotencyKey;
  String? _checkoutError;
  String? _checkoutErrorCode;

  // Additional payment sub-options
  String _qrisType = 'Dinamis'; // 'Dinamis' | 'Statis'
  String _selectedBank = 'BCA'; // 'BCA' | 'Mandiri' | 'BRI' | 'BNI'
  String _edcCardType = 'Debit'; // 'Debit' | 'Kredit'
  String _kasbonDpMethod = 'cash'; // 'cash' | 'qris' | 'transfer'
  final List<_MultiTenderLine> _splitLines = [];

  // Split Bill state (Bagi Rata / Pisah Per-Item)
  List<int>? _splitItemIndices;
  int _splitEqualPeople = 0;
  int? _splitChildHeldSaleId;
  double? _splitOverrideGrandTotal;
  double _splitServiceCharge = 0.0;
  double _splitTaxTotal = 0.0;

  @override
  void initState() {
    super.initState();
    final state = context.read<PosCubit>().state;
    _amountPaidController = TextEditingController(
      text: IdrCurrencyFormatter.format(state.grandTotal),
    );
    _selectedCustomer = state.selectedCustomer;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && state.isOnline && state.cart.isNotEmpty) {
        final cubit = context.read<PosCubit>();
        final initialGrand = _activeCheckoutTotal(cubit.state);
        final serverData = await cubit.verifyServerCartPrice(
          customerId: (state.selectedCustomer?['id'] as num?)?.toInt(),
          redeemPoints: state.redeemedLoyaltyPoints,
        );
        if (mounted && serverData != null) {
          cubit.reconcileCartWithLatestCatalog(serverPriceData: serverData);
          final nextGrand = _activeCheckoutTotal(cubit.state);
          if ((nextGrand - initialGrand).abs() > 0.005) {
            setState(() {
              _syncAmountToTotal(nextGrand);
              if (_selectedMethodCode == 'cash' && !_isSplitPayment && !_useStoreCredit) {
                _amountPaidController.text = IdrCurrencyFormatter.format(
                  _netTotalAfterStoreCredit(nextGrand),
                );
              }
            });
          }
        }
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
    if (_splitOverrideGrandTotal != null) {
      return _splitOverrideGrandTotal!;
    }
    if (_splitItemIndices != null && _splitItemIndices!.isNotEmpty) {
      double total = 0.0;
      for (final idx in _splitItemIndices!) {
        if (idx >= 0 && idx < posState.cart.length) {
          final item = posState.cart[idx];
          total += item.lineTotal;
          if (!item.isExchangeReturn &&
              !item.product.taxInclusive &&
              item.product.taxRate > 0) {
            final lineTax =
                ((item.lineTotal * (item.product.taxRate / 100.0)) * 10000.0)
                        .roundToDouble() /
                    10000.0;
            total += lineTax;
          }
        }
      }
      return (total * 10000.0).roundToDouble() / 10000.0;
    }
    return posState.grandTotal;
  }

  double _availableStoreCredit(Map<String, dynamic>? customer) {
    return ((customer?['store_credit_balance'] as num?)?.toDouble() ?? 0.0)
        .clamp(0.0, double.infinity);
  }

  double _appliedStoreCredit(double grandTotal) {
    if (!_useStoreCredit || _selectedCustomer == null || grandTotal <= 0) {
      return 0.0;
    }
    final avail = _availableStoreCredit(_selectedCustomer);
    if (avail <= 0) return 0.0;
    final parsed = IdrCurrencyFormatter.parse(_storeCreditController.text);
    return parsed.clamp(0.0, math.min(avail, grandTotal)).roundToDouble();
  }

  double _netTotalAfterStoreCredit(double grandTotal) {
    return (grandTotal - _appliedStoreCredit(grandTotal)).clamp(0.0, double.infinity);
  }

  String _defaultSubTypeFor(String code) {
    switch (code) {
      case 'qris':
        return 'Dinamis';
      case 'transfer':
        return 'BCA';
      case 'card':
        return 'Debit';
      default:
        return '';
    }
  }

  String _labelForCode(String code) {
    switch (code) {
      case 'cash':
        return 'Tunai';
      case 'qris':
        return 'QRIS';
      case 'transfer':
        return 'Transfer Bank';
      case 'card':
        return 'Kartu EDC';
      default:
        return 'Tunai';
    }
  }

  void _initSplitLines(double netTarget) {
    for (final line in _splitLines) {
      line.dispose();
    }
    _splitLines.clear();
    final half = netTarget >= 2000
        ? (((netTarget / 2) / 1000).round() * 1000.0)
        : (netTarget / 2).roundToDouble();
    final rem = math.max(0.0, netTarget - half);
    _splitLines.addAll([
      _MultiTenderLine(
        methodCode: 'cash',
        methodLabel: 'Tunai',
        initialAmount: half,
      ),
      _MultiTenderLine(
        methodCode: 'qris',
        methodLabel: 'QRIS',
        initialAmount: rem,
        initialSubType: 'Dinamis',
      ),
    ]);
  }

  void _addSplitTenderLine(double remainingDue) {
    final usedCodes = _splitLines.map((e) => e.methodCode).toSet();
    final nextCode = !usedCodes.contains('transfer')
        ? 'transfer'
        : (!usedCodes.contains('card')
            ? 'card'
            : (!usedCodes.contains('qris') ? 'qris' : 'cash'));
    setState(() {
      _splitLines.add(
        _MultiTenderLine(
          methodCode: nextCode,
          methodLabel: _labelForCode(nextCode),
          initialAmount: math.max(0.0, remainingDue),
          initialSubType: _defaultSubTypeFor(nextCode),
        ),
      );
    });
  }

  void _removeSplitTenderLine(int idx) {
    if (_splitLines.length <= 2 || idx < 0 || idx >= _splitLines.length) return;
    setState(() {
      _splitLines[idx].dispose();
      _splitLines.removeAt(idx);
    });
  }

  KasbonDpComputation _buildKasbonCalculation(double grandTotal) {
    final c = _selectedCustomer;
    final limit = (c?['credit_limit'] as num?)?.toDouble() ?? 0.0;
    final used = (c?['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
    final availOverride = (c?['available_credit'] as num?)?.toDouble();
    return PosFinancialCalculator.computeKasbonDp(
      grandTotal: grandTotal,
      downPayment: IdrCurrencyFormatter.parse(_kasbonDpController.text),
      creditLimit: limit,
      outstandingBalance: used,
      availableCreditOverride: availOverride,
      storeCreditUsed: _appliedStoreCredit(grandTotal),
    );
  }

  MultiTenderValidation _buildMultiTenderValidation(double grandTotal) {
    return PosFinancialCalculator.validateMultiTenderPayments(
      grandTotal: grandTotal,
      tenderAmounts: _splitLines.map((l) => l.amount).toList(),
      tenderMethodCodes: _splitLines.map((l) => l.methodCode).toList(),
      storeCreditAmount: _appliedStoreCredit(grandTotal),
    );
  }

  void _toggleUseStoreCredit(bool enabled, double grandTotal) {
    final avail = _availableStoreCredit(_selectedCustomer);
    final defaultUse = enabled ? math.min(avail, grandTotal) : 0.0;
    setState(() {
      _useStoreCredit = enabled;
      _storeCreditController.text = IdrCurrencyFormatter.format(defaultUse);
      _syncAmountToTotal(grandTotal);
    });
  }

  void _syncAmountToTotal(double total) {
    final net = _netTotalAfterStoreCredit(total);
    if (_selectedMethodCode != 'cash' || _isSplitPayment) {
      _amountPaidController.text = IdrCurrencyFormatter.format(net);
    } else if (_useStoreCredit) {
      _amountPaidController.text = IdrCurrencyFormatter.format(net);
    }
    if (_isSplitPayment) {
      _initSplitLines(net);
    }
  }

  @override
  void dispose() {
    _amountPaidController.dispose();
    _referenceController.dispose();
    _storeCreditController.dispose();
    _kasbonDpController.dispose();
    for (final line in _splitLines) {
      line.dispose();
    }
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
      final customers =
          cubitCustomers.isNotEmpty ? cubitCustomers : widget.offlineDb.getCachedCustomers();
      _showCustomerKasbonPicker(customers, grandTotal);
      return;
    }
    final netTarget = _netTotalAfterStoreCredit(grandTotal);
    if (code == 'split') {
      setState(() {
        _selectedMethodCode = 'split';
        _selectedMethodName = 'Split Payment';
        _isSplitPayment = true;
        _isKasbonMode = false;
        _initSplitLines(netTarget);
        _amountPaidController.text = IdrCurrencyFormatter.format(netTarget);
      });
      return;
    }
    setState(() {
      _selectedMethodCode = code;
      _selectedMethodName = label;
      _isKasbonMode = false;
      _isSplitPayment = false;
      if (code != 'cash') {
        _amountPaidController.text = IdrCurrencyFormatter.format(netTarget);
      } else {
        _amountPaidController.text = IdrCurrencyFormatter.format(netTarget);
      }
    });
  }

  void _showCustomerKasbonPicker(List<Map<String, dynamic>> customers, double grandTotal) {
    final storeCreditApplied = _appliedStoreCredit(grandTotal);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                'Pilih Pelanggan Kasbon (Guard Plafon Kredit + DP Parsial)',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Jika sisa plafon kredit kurang dari total tagihan, sistem otomatis menghitung minimal Uang Muka (DP).',
                style: TextStyle(fontSize: 12, color: AppColors.slate600),
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
                final avail = (c['available_credit'] as num?)?.toDouble();
                final preview = PosFinancialCalculator.computeKasbonDp(
                  grandTotal: grandTotal,
                  downPayment: 0,
                  creditLimit: limit,
                  outstandingBalance: used,
                  availableCreditOverride: avail,
                  storeCreditUsed: storeCreditApplied,
                );
                final requiresDp = !preview.isWithinCreditLimit;
                final availDisplay = preview.availableCredit.isFinite
                    ? IdrCurrencyFormatter.format(preview.availableCredit)
                    : 'Tanpa Limit';
                final depositBal = _availableStoreCredit(c);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          c['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (depositBal > 0) ...[
                        const SizedBox(width: 6),
                        NusaBadge(
                          label: 'Deposit ${IdrCurrencyFormatter.format(depositBal)}',
                          variant: NusaBadgeVariant.primary,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    requiresDp
                        ? 'Sisa Plafon: $availDisplay • Min. DP: ${IdrCurrencyFormatter.format(preview.minimumRequiredDp)}'
                        : 'Sisa Plafon: $availDisplay • Hutang: ${IdrCurrencyFormatter.format(used)}',
                    style: TextStyle(
                      color: requiresDp ? AppColors.warningDark : AppColors.slate600,
                      fontSize: 12,
                      fontWeight: requiresDp ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: requiresDp ? AppColors.primary : AppColors.warningDark,
                    ),
                    onPressed: () {
                      context.read<PosCubit>().selectCustomer(c);
                      final initialDp = preview.minimumRequiredDp;
                      setState(() {
                        _selectedCustomer = c;
                        if (_availableStoreCredit(c) <= 0) {
                          _useStoreCredit = false;
                          _storeCreditController.text = 'Rp 0';
                        }
                        _selectedMethodCode = 'kasbon';
                        _selectedMethodName = 'Kasbon (Buku Bon)';
                        _isKasbonMode = true;
                        _isSplitPayment = false;
                        _kasbonDpController.text = IdrCurrencyFormatter.format(initialDp);
                        _amountPaidController.text = IdrCurrencyFormatter.format(initialDp);
                      });
                      Navigator.pop(ctx);
                      if (requiresDp && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.warningDark,
                            content: Text(
                              'Plafon sisa $availDisplay — Minimal DP diisi otomatis Rp ${initialDp.toStringAsFixed(0)}.',
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(requiresDp ? 'Pilih + DP' : 'Pilih'),
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
    bool isSyncingSplit = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
                        onPressed: isSyncingSplit
                            ? null
                            : () {
                                setState(() {
                                  _splitItemIndices = null;
                                  _splitEqualPeople = 0;
                                  _splitChildHeldSaleId = null;
                                  _splitOverrideGrandTotal = null;
                                  _splitServiceCharge = 0.0;
                                  _splitTaxTotal = 0.0;
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
                                  for (final n in [2, 3, 4, 5, 6])
                                    NusaPillFilter(
                                      label: '$n Orang',
                                      selected: equalPeople == n,
                                      onTap: () => setModalState(() => equalPeople = n),
                                    ),
                                  ActionChip(
                                    label: const Text('+1 Orang', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                    onPressed: () => setModalState(() => equalPeople = (equalPeople + 1).clamp(2, 20)),
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
                      onPressed: isSyncingSplit
                          ? null
                          : () async {
                              if (mode == 'item') {
                                if (selectedSet.isEmpty) return;
                                final sorted = selectedSet.toList()..sort();
                                final posCubit = context.read<PosCubit>();
                                final messenger = ScaffoldMessenger.of(context);
                                final modalNav = Navigator.of(ctx);
                                setModalState(() => isSyncingSplit = true);
                                final splitResult =
                                    await posCubit.splitRestaurantTableBill(sorted);
                                final resolvedGrand =
                                    (splitResult['grand_total'] as num?)?.toDouble() ??
                                        selectedItemsTotal;
                                final resolvedChildId =
                                    splitResult['child_held_sale_id'] as int?;
                                final resolvedSvc =
                                    (splitResult['service_charge_amount'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                final resolvedTax =
                                    (splitResult['tax_total'] as num?)?.toDouble() ??
                                        0.0;
                                final synced = splitResult['synced'] == true;
                                if (!mounted) return;
                                setState(() {
                                  _splitItemIndices = sorted;
                                  _splitEqualPeople = 0;
                                  _splitChildHeldSaleId = resolvedChildId;
                                  _splitOverrideGrandTotal = resolvedGrand;
                                  _splitServiceCharge = resolvedSvc;
                                  _splitTaxTotal = resolvedTax;
                                  _syncAmountToTotal(resolvedGrand);
                                });
                                if (modalNav.mounted) {
                                  modalNav.pop();
                                }
                                if (synced) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.successDark,
                                      content: Text(
                                        'Tagihan meja dipisah ke server (${IdrCurrencyFormatter.format(resolvedGrand)}).',
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                setState(() {
                                  _splitItemIndices = null;
                                  _splitEqualPeople = equalPeople;
                                  _splitChildHeldSaleId = null;
                                  _splitOverrideGrandTotal = null;
                                  _splitServiceCharge = 0.0;
                                  _splitTaxTotal = 0.0;
                                  _syncAmountToTotal(fullTotal);
                                });
                                Navigator.pop(ctx);
                              }
                            },
                      child: Text(
                        isSyncingSplit
                            ? 'Menyinkronkan Split Bill...'
                            : (mode == 'item'
                                ? 'Bayar Item Terpilih (${IdrCurrencyFormatter.format(selectedItemsTotal)})'
                                : 'Gunakan Info Split $equalPeople Orang'),
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
    final posCubit = context.read<PosCubit>();
    if (_isSubmitting || posCubit.isCheckoutInProgress) return;
    setState(() {
      _isSubmitting = true;
      _checkoutError = null;
      _checkoutErrorCode = null;
    });

    try {
      final rxWarning = posCubit.validatePrescriptionRequirements();
      if (rxWarning != null) {
        PosFeedback.onGuardBlocked();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text(rxWarning),
          ),
        );
        return;
      }

      final posState = posCubit.state;
      final availableMethods = posState.paymentMethods;
      final appliedStoreCredit = _appliedStoreCredit(grandTotal);
      final netDue = _netTotalAfterStoreCredit(grandTotal);

      final paymentsList = <Map<String, dynamic>>[];
      final methodNames = <String>[];
      double paidTotal = 0.0;
      double changeReturned = 0.0;
      double balanceDue = 0.0;
      String? dueDateStr;

      if (appliedStoreCredit > 0) {
        methodNames.add('Saldo Deposit (${IdrCurrencyFormatter.format(appliedStoreCredit)})');
      }

      if (_isKasbonMode) {
        if (_selectedCustomer == null) {
          PosFeedback.onGuardBlocked();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.danger,
              content: Text('Pilih pelanggan terlebih dahulu untuk transaksi Kasbon.'),
            ),
          );
          return;
        }
        final kasbonCalc = _buildKasbonCalculation(grandTotal);
        if (kasbonCalc.validationError != null || !kasbonCalc.isWithinCreditLimit) {
          PosFeedback.onGuardBlocked();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(kasbonCalc.validationError ?? 'Melebihi plafon kredit pelanggan!'),
            ),
          );
          return;
        }

        paidTotal = kasbonCalc.downPayment;
        balanceDue = kasbonCalc.balanceDue;
        dueDateStr = DateFormat('yyyy-MM-dd').format(_kasbonDueDate);

        if (kasbonCalc.downPayment > 0) {
          final dpLabel = _labelForCode(_kasbonDpMethod);
          paymentsList.add({
            'payment_method_id': _resolvePaymentMethodId(availableMethods, _kasbonDpMethod),
            'amount': kasbonCalc.downPayment,
            'tendered_amount': kasbonCalc.downPayment,
            'reference': 'DP-$dpLabel',
          });
          methodNames.add('DP $dpLabel (${IdrCurrencyFormatter.format(kasbonCalc.downPayment)})');
        }
        methodNames.add('Kasbon (${IdrCurrencyFormatter.format(balanceDue)})');
      } else if (_isSplitPayment) {
        final validation = _buildMultiTenderValidation(grandTotal);
        if (!validation.isValidCheckout) {
          PosFeedback.onGuardBlocked();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(
                validation.remainingDue > 0
                    ? 'Multi-Tender masih kurang ${IdrCurrencyFormatter.format(validation.remainingDue)}!'
                    : 'Kelebihan bayar non-tunai tidak diperbolehkan!',
              ),
            ),
          );
          return;
        }

        paidTotal = validation.tendersTotal;
        changeReturned = validation.cashChangeReturned;
        for (int i = 0; i < _splitLines.length; i++) {
          final line = _splitLines[i];
          if (line.amount <= 0) continue;
          final recordedAmount = i < validation.effectiveRecordedAmounts.length
              ? validation.effectiveRecordedAmounts[i]
              : line.amount;
          final label = line.subType.isNotEmpty
              ? '${line.methodLabel} (${line.subType})'
              : line.methodLabel;
          final ref = line.referenceController.text.trim().isNotEmpty
              ? line.referenceController.text.trim()
              : '$label-SPLIT';
          paymentsList.add({
            'payment_method_id': _resolvePaymentMethodId(availableMethods, line.methodCode),
            'amount': recordedAmount,
            'tendered_amount': line.amount,
            if (line.methodCode != 'cash') 'reference': ref,
          });
          methodNames.add('$label (${IdrCurrencyFormatter.format(recordedAmount)})');
        }
      } else {
        if (netDue <= 0.5) {
          paidTotal = 0.0;
          changeReturned = 0.0;
          if (posState.isExchangeMode && posState.exchangeSurplusCredit > 0) {
            methodNames.add(
              _refundSurplusToStoreCredit && (_selectedCustomer?['id'] as num?) != null
                  ? 'Tukar Barang (Simpan Deposit)'
                  : 'Tukar Barang (Kembali Tunai)',
            );
          } else if (posState.isExchangeMode) {
            methodNames.add('Tukar Barang (Impas)');
          }
        } else {
          final rawPaid = _paidAmount;
          if (rawPaid < netDue - 0.5) {
            PosFeedback.onGuardBlocked();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.danger,
                content: Text('Jumlah bayar kurang dari Sisa Tagihan!'),
              ),
            );
            return;
          }
          paidTotal = rawPaid;
          changeReturned = (rawPaid - netDue).clamp(0.0, double.infinity);

          String resolvedName = _selectedMethodName;
          if (_selectedMethodCode == 'qris') resolvedName = 'QRIS $_qrisType';
          if (_selectedMethodCode == 'transfer') resolvedName = 'Transfer $_selectedBank';
          if (_selectedMethodCode == 'card') resolvedName = 'EDC $_edcCardType';

          paymentsList.add({
            'payment_method_id': _resolvePaymentMethodId(availableMethods, _selectedMethodCode),
            'amount': netDue,
            'tendered_amount': rawPaid,
            'reference': _referenceController.text.trim().isNotEmpty
                ? _referenceController.text.trim()
                : resolvedName,
          });
          methodNames.add(resolvedName);
        }
      }

      _pendingIdempotencyKey ??= const Uuid().v4();

      final receipt = await posCubit.completeCheckout(
        payments: paymentsList,
        paymentMethodNames: methodNames.isEmpty ? ['Tunai'] : methodNames,
        paidTotal: paidTotal,
        changeReturned: changeReturned,
        balanceDue: balanceDue,
        storeCreditAmount: appliedStoreCredit,
        grandTotalOverride: _splitOverrideGrandTotal,
        overrideHeldSaleId: _splitChildHeldSaleId,
        refundSurplusToStoreCredit: _refundSurplusToStoreCredit,
        splitItemIndices: _splitItemIndices,
        dueDate: dueDateStr,
        idempotencyKey: _pendingIdempotencyKey,
      );

      _pendingIdempotencyKey = null;

      final enrichedReceipt = Map<String, dynamic>.from(receipt);
      if (_splitServiceCharge > 0) {
        enrichedReceipt['service_charge_amount'] = _splitServiceCharge;
      }
      if (_splitTaxTotal > 0) {
        enrichedReceipt['tax_total'] = _splitTaxTotal;
      }

      final hasCashComponent = PrinterService.shouldKickCashDrawer(
        payments: paymentsList,
        paymentMethods: methodNames,
        isKasbonZeroDp: _isKasbonMode && paidTotal <= 0,
        isReprint: false,
      );
      enrichedReceipt['has_cash_payment'] = hasCashComponent;

      // Phase 3.1: Non-blocking multi-printer KOT & Bar routing when configured
      if (GetIt.instance.isRegistered<PrinterService>()) {
        final printer = GetIt.instance<PrinterService>();
        final hasStationPrinters =
            (printer.printerDapurMac != null && printer.printerDapurMac!.isNotEmpty) ||
                (printer.printerBarMac != null && printer.printerBarMac!.isNotEmpty);
        if (hasStationPrinters || posState.capabilities.hasKitchenOrderTicket) {
          unawaited(
            printer.routeOrderTicketsAndReceipt(
              sale: enrichedReceipt,
              store: widget.offlineDb.getStoreProfile(),
              openCashDrawer: hasCashComponent && printer.autoOpenCashDrawer,
              printReceipt: false,
            ),
          );
        }
      }

      if (mounted) {
        context.pushReplacement('/pos/receipt', extra: enrichedReceipt);
      }
    } on CheckoutServerException catch (e) {
      if (mounted) {
        PosFeedback.onGuardBlocked();
        setState(() {
          _checkoutError = e.message;
          _checkoutErrorCode = e.errorCode;
        });
      }
    } catch (e) {
      if (mounted) {
        PosFeedback.onGuardBlocked();
        setState(() {
          _checkoutError = 'Gagal memproses transaksi: $e';
          _checkoutErrorCode = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Phase 3.3: Dynamic QRIS In-App Polling Timer (5-minute countdown + 3s status polling)
  void _showDynamicQrisPollingModal(
    BuildContext rootContext, {
    required double netDue,
    required double grandTotal,
  }) {
    int remainingSeconds = 300; // 5 menit
    int pollCount = 0;
    String statusText = 'Menunggu pembayaran pelanggan...';
    Timer? countdownTimer;
    Timer? pollTimer;
    bool timersStarted = false;

    showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: NusaThemeTokens.of(rootContext).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final tokens = NusaThemeTokens.of(modalCtx);
          if (!timersStarted) {
            timersStarted = true;
            countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!modalCtx.mounted) return;
              if (remainingSeconds <= 1) {
                countdownTimer?.cancel();
                pollTimer?.cancel();
                setModalState(() {
                  remainingSeconds = 0;
                  statusText = 'QRIS kedaluwarsa (5 menit). Generate ulang QRIS atau verifikasi manual.';
                });
              } else {
                setModalState(() => remainingSeconds--);
              }
            });
            pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
              if (!modalCtx.mounted || remainingSeconds <= 0) return;
              setModalState(() {
                pollCount++;
                statusText = 'Memeriksa status gateway QRIS (Pengecekan ke-$pollCount)...';
              });
            });
          }

          final mm = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
          final ss = (remainingSeconds % 60).toString().padLeft(2, '0');

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'QRIS Dinamis OXORA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      NusaBadge(
                        label: 'Sisa Waktu $mm:$ss',
                        variant: remainingSeconds > 60
                            ? NusaBadgeVariant.primary
                            : NusaBadgeVariant.danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NusaPriceTag(amount: netDue, fontSize: 22, color: tokens.accent),
                  const SizedBox(height: 12),
                  // QR Code itself stays on crisp white scan canvas for camera readability
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tokens.borderDefault, width: 1.5),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 148, color: Color(0xFF1C1917)),
                        SizedBox(height: 6),
                        Text(
                          'QRIS STANDAR PEMBAYARAN NASIONAL (GPN / BI)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            statusText,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  NusaButton(
                    label: 'Verifikasi Manual (Pelanggan Sudah Sukses)',
                    icon: Icons.verified_rounded,
                    variant: NusaButtonVariant.success,
                    minHeight: 50,
                    onPressed: () {
                      countdownTimer?.cancel();
                      pollTimer?.cancel();
                      Navigator.pop(modalCtx);
                      setState(() {
                        _selectedMethodCode = 'qris';
                        _selectedMethodName = 'QRIS $_qrisType';
                        _qrisType = 'Dinamis';
                        _amountPaidController.text = IdrCurrencyFormatter.format(netDue);
                      });
                      _submitPayment(grandTotal);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      countdownTimer?.cancel();
      pollTimer?.cancel();
    });
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
    final tokens = NusaThemeTokens.of(context);
    final posState = context.watch<PosCubit>().state;
    final grandTotal = _activeCheckoutTotal(posState);
    final availStoreCredit = _availableStoreCredit(_selectedCustomer);
    final appliedStoreCredit = _appliedStoreCredit(grandTotal);
    final netDue = _netTotalAfterStoreCredit(grandTotal);
    final kasbonCalc = _buildKasbonCalculation(grandTotal);
    final multiValidation = _buildMultiTenderValidation(grandTotal);
    final changeAmount = (_isKasbonMode || _isSplitPayment || netDue <= 0.5)
        ? 0.0
        : (_paidAmount - netDue).clamp(0.0, double.infinity);
    final isCashInsufficient =
        !_isKasbonMode && !_isSplitPayment && netDue > 0.5 && _paidAmount < netDue - 0.5;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
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
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(44, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.receipt_long_rounded, size: 17, color: tokens.accent),
                label: Text(
                  _splitItemIndices != null
                      ? 'Split (${_splitItemIndices!.length})'
                      : (_splitEqualPeople > 1 ? '÷$_splitEqualPeople' : 'Split Bill'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: tokens.accent),
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
                borderColor: tokens.borderSubtle,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: tokens.heroGradientColors,
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
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
                          if (posState.exclusiveTaxTotal > 0 && _splitOverrideGrandTotal == null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Subtotal ${IdrCurrencyFormatter.format((posState.subtotal - posState.totalDiscount).clamp(0, double.infinity))} + Pajak ${IdrCurrencyFormatter.format(posState.exclusiveTaxTotal)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                          ],
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
                            Icon(Icons.shopping_bag_outlined, size: 17, color: tokens.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rincian Belanja (${IdrCurrencyFormatter.formatQty(posState.totalItemsCount)} item)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              _isCartSummaryExpanded ? 'Tutup' : 'Edit / Lihat',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: tokens.accent,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isCartSummaryExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: tokens.accent,
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
                                if (item.isExchangeReturn)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: AppColors.warning.withOpacity(0.45)),
                                    ),
                                    child: Text(
                                      'RETUR ${IdrCurrencyFormatter.formatQty(item.quantity.abs())}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.warningDark,
                                      ),
                                    ),
                                  )
                                else
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

              // 1B. Surplus Exchange Return Mode (Kelebihan Retur Tukar Barang)
              if (posState.isExchangeMode && posState.exchangeSurplusCredit > 0) ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: AppColors.primarySoft,
                  borderColor: AppColors.primary.withOpacity(0.35),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Kelebihan Retur Tukar Barang',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.navyDark),
                            ),
                          ),
                          NusaPriceTag(
                            amount: posState.exchangeSurplusCredit,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Retur: ${IdrCurrencyFormatter.format(posState.exchangeReturnCreditTotal)} • Pengganti: ${IdrCurrencyFormatter.format(posState.replacementItemsSubtotal)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                      ),
                      const SizedBox(height: 10),
                      if (_selectedCustomer != null && ((_selectedCustomer!['id'] as num?)?.toInt() ?? 0) > 0)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            NusaPillFilter(
                              label: 'Simpan ke Saldo Deposit',
                              selected: _refundSurplusToStoreCredit,
                              onTap: () => setState(() => _refundSurplusToStoreCredit = true),
                            ),
                            NusaPillFilter(
                              label: 'Kembalikan Tunai',
                              selected: !_refundSurplusToStoreCredit,
                              onTap: () => setState(() => _refundSurplusToStoreCredit = false),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'Pelanggan Umum: kelebihan dana dikembalikan tunai kepada pelanggan.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                        ),
                    ],
                  ),
                ),
              ],

              // 1C. Customer Store Credit (Saldo Deposit Pelanggan)
              if (_selectedCustomer != null && availStoreCredit > 0 && grandTotal > 0) ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: _useStoreCredit ? const Color(0xFFECFDF5) : Colors.white,
                  borderColor: _useStoreCredit
                      ? AppColors.success.withOpacity(0.45)
                      : AppColors.border,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            color: _useStoreCredit ? AppColors.successDark : AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gunakan Saldo Deposit (${IdrCurrencyFormatter.format(availStoreCredit)})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: AppColors.navyDark,
                                  ),
                                ),
                                Text(
                                  'Tersedia untuk ${_selectedCustomer!['name'] ?? 'Pelanggan'}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _useStoreCredit,
                            onChanged: (val) => _toggleUseStoreCredit(val, grandTotal),
                          ),
                        ],
                      ),
                      if (_useStoreCredit) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _storeCreditController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {
                                  final updatedNet = _netTotalAfterStoreCredit(grandTotal);
                                  if (_selectedMethodCode != 'cash') {
                                    _amountPaidController.text = IdrCurrencyFormatter.format(updatedNet);
                                  }
                                }),
                                style: AppTheme.moneyStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                decoration: const InputDecoration(
                                  labelText: 'Nominal Deposit Dipakai (Rp)',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () {
                                final maxApply = math.min(availStoreCredit, grandTotal);
                                setState(() {
                                  _storeCreditController.text = IdrCurrencyFormatter.format(maxApply);
                                  _syncAmountToTotal(grandTotal);
                                });
                              },
                              child: const Text('Pakai Maks'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Potong Deposit: ${IdrCurrencyFormatter.format(appliedStoreCredit)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.successDark),
                            ),
                            Text(
                              'Sisa Tagihan: ${IdrCurrencyFormatter.format(netDue)}',
                              style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // 2. Explicit 6 Payment Methods Grid
              Text(
                'Pilih Metode Pembayaran',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
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
                                  'QRIS $_qrisType OXORA',
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
                      if (_qrisType == 'Dinamis') ...[
                        const SizedBox(height: 10),
                        NusaButton(
                          label: 'Tampilkan QRIS & Cek Status Otomatis (5 Menit)',
                          icon: Icons.qr_code_scanner_rounded,
                          variant: NusaButtonVariant.primary,
                          minHeight: 44,
                          onPressed: () => _showDynamicQrisPollingModal(
                            context,
                            netDue: netDue > 0 ? netDue : grandTotal,
                            grandTotal: grandTotal,
                          ),
                        ),
                      ],
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
                        children: ['BCA', 'Mandiri', 'BRI', 'BNI', 'BSI', 'CIMB Niaga'].map((bank) {
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
                  borderColor: multiValidation.isValidCheckout
                      ? AppColors.success.withOpacity(0.45)
                      : AppColors.primary.withOpacity(0.3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Multi-Tender Split Payment',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                          NusaBadge(
                            label: '${_splitLines.length} Metode',
                            variant: multiValidation.isValidCheckout
                                ? NusaBadgeVariant.success
                                : NusaBadgeVariant.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: multiValidation.isValidCheckout
                                ? AppColors.success.withOpacity(0.45)
                                : AppColors.warning.withOpacity(0.45),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Tagihan', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                                Text(
                                  IdrCurrencyFormatter.format(multiValidation.grandTotal),
                                  style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Terbayar', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                                Text(
                                  IdrCurrencyFormatter.format(multiValidation.paidTotal),
                                  style: AppTheme.moneyStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  multiValidation.isValidWithCashChange
                                      ? 'Kembalian Tunai'
                                      : (multiValidation.overpayment > 0
                                          ? 'Kelebihan Non-Tunai'
                                          : 'Sisa Kurang'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: multiValidation.isValidCheckout
                                        ? AppColors.successDark
                                        : AppColors.danger,
                                  ),
                                ),
                                Text(
                                  multiValidation.isValidWithCashChange
                                      ? IdrCurrencyFormatter.format(multiValidation.cashChangeReturned)
                                      : (multiValidation.overpayment > 0
                                          ? IdrCurrencyFormatter.format(multiValidation.overpayment)
                                          : IdrCurrencyFormatter.format(multiValidation.remainingDue)),
                                  style: AppTheme.moneyStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: multiValidation.isValidCheckout
                                        ? AppColors.successDark
                                        : AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < _splitLines.length; i++) ...[
                        _buildSplitTenderLineCard(i, _splitLines[i], multiValidation.remainingDue),
                        if (i < _splitLines.length - 1) const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _addSplitTenderLine(multiValidation.remainingDue),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                          label: const Text('+ Tambah Metode Pembayaran'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: tokens.bgSurface,
                            foregroundColor: tokens.accent,
                            side: BorderSide(color: tokens.accent.withOpacity(0.5)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_isKasbonMode && _selectedCustomer != null) ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: kasbonCalc.isWithinCreditLimit
                      ? AppColors.warningSoft
                      : AppColors.dangerSoft,
                  borderColor: kasbonCalc.isWithinCreditLimit
                      ? AppColors.warning.withOpacity(0.45)
                      : AppColors.danger.withOpacity(0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            color: kasbonCalc.isWithinCreditLimit
                                ? AppColors.warningDark
                                : AppColors.danger,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Piutang Buku Bon: ${_selectedCustomer!['name']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: kasbonCalc.isWithinCreditLimit
                                    ? AppColors.warningDark
                                    : AppColors.danger,
                              ),
                            ),
                          ),
                          NusaBadge(
                            label: kasbonCalc.isWithinCreditLimit ? 'Plafon Aman' : 'Melebihi Plafon',
                            variant: kasbonCalc.isWithinCreditLimit
                                ? NusaBadgeVariant.success
                                : NusaBadgeVariant.danger,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sisa Plafon: ${kasbonCalc.availableCredit.isFinite ? IdrCurrencyFormatter.format(kasbonCalc.availableCredit) : 'Tanpa Limit'} • Hutang Lama: ${IdrCurrencyFormatter.format((_selectedCustomer!['outstanding_balance'] as num?)?.toDouble() ?? 0)}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate700),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _kasbonDpController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: AppTheme.moneyStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Uang Muka / DP Parsial (Rp)',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          NusaPillFilter(
                            label: 'Tanpa DP (Rp 0)',
                            selected: kasbonCalc.downPayment == 0,
                            onTap: () => setState(() {
                              _kasbonDpController.text = IdrCurrencyFormatter.format(0);
                            }),
                          ),
                          NusaPillFilter(
                            label: 'DP 25%',
                            selected: false,
                            onTap: () => setState(() {
                              final dp25 = (netDue * 0.25).roundToDouble();
                              _kasbonDpController.text = IdrCurrencyFormatter.format(dp25);
                            }),
                          ),
                          NusaPillFilter(
                            label: 'DP 50%',
                            selected: false,
                            onTap: () => setState(() {
                              final dp50 = (netDue * 0.50).roundToDouble();
                              _kasbonDpController.text = IdrCurrencyFormatter.format(dp50);
                            }),
                          ),
                          if (kasbonCalc.minimumRequiredDp > 0)
                            NusaPillFilter(
                              label: 'Min. DP Plafon (${IdrCurrencyFormatter.format(kasbonCalc.minimumRequiredDp)})',
                              selected: (kasbonCalc.downPayment - kasbonCalc.minimumRequiredDp).abs() < 1,
                              onTap: () => setState(() {
                                _kasbonDpController.text =
                                    IdrCurrencyFormatter.format(kasbonCalc.minimumRequiredDp);
                              }),
                            ),
                        ],
                      ),
                      if (kasbonCalc.downPayment > 0) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Metode Pembayaran DP:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in ['cash', 'qris', 'transfer'])
                              NusaPillFilter(
                                label: _labelForCode(m),
                                selected: _kasbonDpMethod == m,
                                onTap: () => setState(() => _kasbonDpMethod = m),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Tagihan', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                                Text(IdrCurrencyFormatter.format(grandTotal), style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            if (kasbonCalc.storeCreditUsed > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Potong Saldo Deposit', style: TextStyle(fontSize: 12, color: AppColors.successDark)),
                                  Text('- ${IdrCurrencyFormatter.format(kasbonCalc.storeCreditUsed)}', style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.successDark)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Uang Muka (DP)', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                                Text(IdrCurrencyFormatter.format(kasbonCalc.downPayment), style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                              ],
                            ),
                            const Divider(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sisa Tagihan (Buku Bon)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.warningDark)),
                                Text(IdrCurrencyFormatter.format(kasbonCalc.balanceDue), style: AppTheme.moneyStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.warningDark)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (kasbonCalc.validationError != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.danger.withOpacity(0.45)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  kasbonCalc.validationError!,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

              // 3. Jumlah Bayar Input Box + 5 Quick Cash Buttons (Single-Tender Only)
              if (!_isKasbonMode && !_isSplitPayment && netDue > 0.5) ...[
                NusaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nominal Diterima (Rp)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountPaidController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: AppTheme.moneyStyle(fontSize: 22, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: tokens.bgElevated,
                          suffixIcon: IconButton(
                            icon: Icon(Icons.cancel_rounded, color: tokens.textTertiary),
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
                            selected: (_paidAmount - netDue).abs() < 0.5,
                            onTap: () => _setQuickCashAmount(netDue),
                          ),
                          for (final denom in _smartCashDenominations(netDue))
                            NusaPillFilter(
                              label: IdrCurrencyFormatter.format(denom),
                              selected: (_paidAmount - denom).abs() < 0.5,
                              onTap: () => _setQuickCashAmount(denom),
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
          color: tokens.bgSurface,
          border: Border(top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
          boxShadow: tokens.isDark || tokens.isHighContrast ? null : AppColors.floatingCartShadow,
        ),
        child: SafeArea(
          top: false,
          child: Builder(
            builder: (_) {
              final isKasbonBlocked = _isKasbonMode &&
                  (_selectedCustomer == null ||
                      !kasbonCalc.isWithinCreditLimit ||
                      kasbonCalc.validationError != null);
              final isSplitBlocked = _isSplitPayment && !multiValidation.isValidCheckout;
              final canSubmit = !_isSubmitting && !isKasbonBlocked && !isSplitBlocked;

              String bannerLabel;
              double bannerAmount;
              Color bannerBg;
              Color bannerBorder;
              Color bannerTextColor;

              if (posState.isExchangeMode && posState.exchangeSurplusCredit > 0) {
                bannerLabel = _refundSurplusToStoreCredit && ((_selectedCustomer?['id'] as num?)?.toInt() ?? 0) > 0
                    ? 'Kelebihan Retur -> Deposit'
                    : 'Kelebihan Retur -> Tunai';
                bannerAmount = posState.exchangeSurplusCredit;
                bannerBg = AppColors.primarySoft;
                bannerBorder = AppColors.primary.withOpacity(0.35);
                bannerTextColor = AppColors.primary;
              } else if (_isKasbonMode) {
                bannerLabel = isKasbonBlocked
                    ? 'Melebihi Plafon Kredit'
                    : 'Masuk Buku Bon (DP ${IdrCurrencyFormatter.format(kasbonCalc.downPayment)})';
                bannerAmount = kasbonCalc.balanceDue;
                bannerBg = isKasbonBlocked ? AppColors.dangerSoft : AppColors.warningSoft;
                bannerBorder = isKasbonBlocked
                    ? AppColors.danger.withOpacity(0.35)
                    : AppColors.warning.withOpacity(0.35);
                bannerTextColor = isKasbonBlocked ? AppColors.danger : AppColors.warningDark;
              } else if (_isSplitPayment) {
                if (multiValidation.isValidWithCashChange) {
                  bannerLabel = 'Kembalian Tunai (Split Valid)';
                  bannerAmount = multiValidation.cashChangeReturned;
                  bannerBg = AppColors.successSoft;
                  bannerBorder = AppColors.success.withOpacity(0.35);
                  bannerTextColor = AppColors.successDark;
                } else if (multiValidation.isExactMatch) {
                  bannerLabel = 'Multi-Tender Pas & Valid (${_splitLines.length} Metode)';
                  bannerAmount = multiValidation.grandTotal;
                  bannerBg = AppColors.successSoft;
                  bannerBorder = AppColors.success.withOpacity(0.35);
                  bannerTextColor = AppColors.successDark;
                } else if (multiValidation.overpayment > 0) {
                  bannerLabel = 'Kelebihan Non-Tunai Split';
                  bannerAmount = multiValidation.overpayment;
                  bannerBg = AppColors.dangerSoft;
                  bannerBorder = AppColors.danger.withOpacity(0.35);
                  bannerTextColor = AppColors.danger;
                } else {
                  bannerLabel = 'Sisa Kurang Split Payment';
                  bannerAmount = multiValidation.remainingDue;
                  bannerBg = AppColors.dangerSoft;
                  bannerBorder = AppColors.danger.withOpacity(0.35);
                  bannerTextColor = AppColors.danger;
                }
              } else if (isCashInsufficient) {
                bannerLabel = 'Kurang Bayar';
                bannerAmount = (netDue - _paidAmount).clamp(0.0, double.infinity);
                bannerBg = AppColors.dangerSoft;
                bannerBorder = AppColors.danger.withOpacity(0.35);
                bannerTextColor = AppColors.danger;
              } else {
                bannerLabel = appliedStoreCredit > 0 && netDue <= 0.5
                    ? 'Lunas via Saldo Deposit'
                    : 'Uang Kembalian';
                bannerAmount = changeAmount;
                bannerBg = AppColors.successSoft;
                bannerBorder = AppColors.success.withOpacity(0.35);
                bannerTextColor = AppColors.successDark;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bannerBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: bannerBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            bannerLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: bannerTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NusaPriceTag(
                          amount: bannerAmount,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: bannerTextColor,
                        ),
                      ],
                    ),
                  ),
                  if (_checkoutError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withOpacity(0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _checkoutError!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.dangerDark,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => setState(() {
                                  _checkoutError = null;
                                  _checkoutErrorCode = null;
                                }),
                                child: const Icon(Icons.close_rounded, size: 17, color: AppColors.dangerDark),
                              ),
                            ],
                          ),
                          if (_checkoutErrorCode == 'ShiftRequired' ||
                              _checkoutError!.toLowerCase().contains('shift')) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await context.push('/shifts');
                                  if (mounted) {
                                    setState(() {
                                      _checkoutError = null;
                                      _checkoutErrorCode = null;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.lock_open_rounded, size: 16),
                                label: const Text(
                                  'Buka Shift Kasir Sekarang',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryDark,
                                  backgroundColor: Colors.white,
                                  side: const BorderSide(color: AppColors.primary),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  NusaButton(
                    label: _isSubmitting ? 'Memproses...' : 'Selesaikan Pembayaran',
                    trailingIcon: Icons.check_circle_rounded,
                    minHeight: 52,
                    isLoading: _isSubmitting,
                    onPressed: canSubmit ? () => _submitPayment(grandTotal) : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSplitTenderLineCard(
    int index,
    _MultiTenderLine line,
    double remainingDue,
  ) {
    final subOptions = line.methodCode == 'qris'
        ? const ['Dinamis', 'Statis']
        : (line.methodCode == 'transfer'
            ? const ['BCA', 'Mandiri', 'BRI', 'BNI', 'BSI', 'CIMB Niaga']
            : (line.methodCode == 'card' ? const ['Debit', 'Kredit'] : const <String>[]));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Metode #${index + 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
              const Spacer(),
              if (remainingDue > 0)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  onPressed: () {
                    setState(() {
                      final nextAmount = line.amount + remainingDue;
                      line.amountController.text = IdrCurrencyFormatter.format(nextAmount);
                    });
                  },
                  child: const Text('Isi Sisa', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
              if (_splitLines.length > 2)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Hapus Metode',
                  onPressed: () => _removeSplitTenderLine(index),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in ['cash', 'qris', 'transfer', 'card'])
                NusaPillFilter(
                  label: _labelForCode(m),
                  selected: line.methodCode == m,
                  onTap: () {
                    setState(() {
                      line.methodCode = m;
                      line.methodLabel = _labelForCode(m);
                      line.subType = _defaultSubTypeFor(m);
                    });
                  },
                ),
            ],
          ),
          if (subOptions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: subOptions.map((opt) {
                return NusaPillFilter(
                  label: opt,
                  selected: line.subType == opt,
                  onTap: () => setState(() => line.subType = opt),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: line.amountController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            style: AppTheme.moneyStyle(fontSize: 15, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Nominal ${line.methodLabel} (Rp)',
              prefixIcon: const Icon(Icons.payments_outlined, size: 18),
            ),
          ),
          if (line.methodCode != 'cash') ...[
            const SizedBox(height: 8),
            TextField(
              controller: line.referenceController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Ref / Approval / Catatan (Opsional)',
                hintText: 'Misal: TRF-0012 / APPR-882',
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<double> _smartCashDenominations(double netDue) {
    final set = <double>{50000, 100000, 200000};
    if (netDue > 0) {
      final rounded10k = ((netDue / 10000).ceil() * 10000).toDouble();
      final rounded50k = ((netDue / 50000).ceil() * 50000).toDouble();
      final rounded100k = ((netDue / 100000).ceil() * 100000).toDouble();
      if (rounded10k > netDue) set.add(rounded10k);
      if (rounded50k > netDue) set.add(rounded50k);
      if (rounded100k > netDue) set.add(rounded100k);
    } else {
      set.add(20000);
    }
    final sorted = set.toList()..sort();
    return sorted.take(5).toList();
  }

  Widget _buildPaymentMethodCard({
    required String code,
    required String label,
    required IconData icon,
    required double grandTotal,
    Color? accentColor,
  }) {
    final tokens = NusaThemeTokens.of(context);
    final isSelected = _selectedMethodCode == code;
    final activeColor = accentColor ?? tokens.accent;

    return InkWell(
      onTap: () => _selectPaymentMethod(code, label, grandTotal),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(tokens.isDark ? 0.2 : 0.1) : tokens.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : tokens.borderSubtle,
            width: isSelected ? (tokens.isHighContrast ? 2.2 : 1.8) : tokens.borderWidth,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? activeColor : tokens.textPrimary,
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
                  color: isSelected ? activeColor : tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
