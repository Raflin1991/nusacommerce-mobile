// ignore_for_file: invalid_use_of_protected_member
part of 'payment_checkout_screen.dart';

extension _PaymentCheckoutScreenStatePart4Ext on _PaymentCheckoutScreenState {

  Widget _buildCheckoutBottomBar(
    BuildContext context, {
    required NusaThemeTokens tokens,
    required PosState posState,
    required double grandTotal,
    required double appliedStoreCredit,
    required double netDue,
    required double changeAmount,
    required bool isCashInsufficient,
    required KasbonDpComputation kasbonCalc,
    required MultiTenderValidation multiValidation,
  }) {
    return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          border: Border(top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
          boxShadow: tokens.isDark || tokens.isHighContrast ? null : NusaThemeTokens.of(context).floatingCartShadow,
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
                bannerBg = NusaThemeTokens.of(context).accentSoft;
                bannerBorder = NusaThemeTokens.of(context).accent.withOpacity(0.35);
                bannerTextColor = NusaThemeTokens.of(context).accent;
              } else if (_isKasbonMode) {
                bannerLabel = isKasbonBlocked
                    ? 'Melebihi Plafon Kredit'
                    : 'Masuk Buku Bon (DP ${IdrCurrencyFormatter.format(kasbonCalc.downPayment)})';
                bannerAmount = kasbonCalc.balanceDue;
                bannerBg = isKasbonBlocked ? NusaThemeTokens.of(context).dangerSoft : NusaThemeTokens.of(context).warningSoft;
                bannerBorder = isKasbonBlocked
                    ? NusaThemeTokens.of(context).danger.withOpacity(0.35)
                    : NusaThemeTokens.of(context).warning.withOpacity(0.35);
                bannerTextColor = isKasbonBlocked ? NusaThemeTokens.of(context).danger : NusaThemeTokens.of(context).warning;
              } else if (_isSplitPayment) {
                if (multiValidation.isValidWithCashChange) {
                  bannerLabel = 'Kembalian Tunai (Split Valid)';
                  bannerAmount = multiValidation.cashChangeReturned;
                  bannerBg = NusaThemeTokens.of(context).positiveSoft;
                  bannerBorder = NusaThemeTokens.of(context).positive.withOpacity(0.35);
                  bannerTextColor = NusaThemeTokens.of(context).positive;
                } else if (multiValidation.isExactMatch) {
                  bannerLabel = 'Multi-Tender Pas & Valid (${_splitLines.length} Metode)';
                  bannerAmount = multiValidation.grandTotal;
                  bannerBg = NusaThemeTokens.of(context).positiveSoft;
                  bannerBorder = NusaThemeTokens.of(context).positive.withOpacity(0.35);
                  bannerTextColor = NusaThemeTokens.of(context).positive;
                } else if (multiValidation.overpayment > 0) {
                  bannerLabel = 'Kelebihan Non-Tunai Split';
                  bannerAmount = multiValidation.overpayment;
                  bannerBg = NusaThemeTokens.of(context).dangerSoft;
                  bannerBorder = NusaThemeTokens.of(context).danger.withOpacity(0.35);
                  bannerTextColor = NusaThemeTokens.of(context).danger;
                } else {
                  bannerLabel = 'Sisa Kurang Split Payment';
                  bannerAmount = multiValidation.remainingDue;
                  bannerBg = NusaThemeTokens.of(context).dangerSoft;
                  bannerBorder = NusaThemeTokens.of(context).danger.withOpacity(0.35);
                  bannerTextColor = NusaThemeTokens.of(context).danger;
                }
              } else if (isCashInsufficient) {
                bannerLabel = 'Kurang Bayar';
                bannerAmount = (netDue - _paidAmount).clamp(0.0, double.infinity);
                bannerBg = NusaThemeTokens.of(context).dangerSoft;
                bannerBorder = NusaThemeTokens.of(context).danger.withOpacity(0.35);
                bannerTextColor = NusaThemeTokens.of(context).danger;
              } else {
                bannerLabel = appliedStoreCredit > 0 && netDue <= 0.5
                    ? 'Lunas via Saldo Deposit'
                    : 'Uang Kembalian';
                bannerAmount = changeAmount;
                bannerBg = NusaThemeTokens.of(context).positiveSoft;
                bannerBorder = NusaThemeTokens.of(context).positive.withOpacity(0.35);
                bannerTextColor = NusaThemeTokens.of(context).positive;
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
                        color: NusaThemeTokens.of(context).dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.45)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline_rounded, size: 18, color: NusaThemeTokens.of(context).danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _checkoutError!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: NusaThemeTokens.of(context).danger,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => setState(() {
                                  _checkoutError = null;
                                  _checkoutErrorCode = null;
                                }),
                                child: Icon(Icons.close_rounded, size: 17, color: NusaThemeTokens.of(context).danger),
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
                                  foregroundColor: NusaThemeTokens.of(context).accentDark,
                                  backgroundColor: NusaThemeTokens.of(context).bgSurface,
                                  side: BorderSide(color: NusaThemeTokens.of(context).accent),
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
        border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Metode #${index + 1}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).textPrimary),
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
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: NusaThemeTokens.of(context).danger),
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
