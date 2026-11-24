// ignore_for_file: invalid_use_of_protected_member
part of 'payment_checkout_screen.dart';

extension _PaymentCheckoutScreenStatePart1Ext on _PaymentCheckoutScreenState {

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
              Text(
                'Jika sisa plafon kredit kurang dari total tagihan, sistem otomatis menghitung minimal Uang Muka (DP).',
                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).textSecondary),
              ),
              const SizedBox(height: 12),
              if (customers.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Belum ada pelanggan terdaftar. Tambahkan pelanggan di menu Kasir / Pelanggan terlebih dahulu.',
                    style: TextStyle(color: NusaThemeTokens.of(ctx).textSecondary),
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
                      color: requiresDp ? NusaThemeTokens.of(ctx).warning : NusaThemeTokens.of(ctx).textSecondary,
                      fontSize: 12,
                      fontWeight: requiresDp ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: requiresDp ? NusaThemeTokens.of(ctx).accent : NusaThemeTokens.of(ctx).warning,
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
                            backgroundColor: NusaThemeTokens.of(ctx).warning,
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
                                  color: NusaThemeTokens.of(ctx).accentSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    Text('Estimasi Bayar per Orang ($equalPeople Orang)', style: const TextStyle(fontSize: 12.5)),
                                    const SizedBox(height: 4),
                                    Text(
                                      IdrCurrencyFormatter.format(perPerson),
                                      style: AppTheme.moneyStyle(fontSize: 22, fontWeight: FontWeight.w900, color: NusaThemeTokens.of(ctx).accent),
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
                                      backgroundColor: NusaThemeTokens.of(ctx).positive,
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
}
