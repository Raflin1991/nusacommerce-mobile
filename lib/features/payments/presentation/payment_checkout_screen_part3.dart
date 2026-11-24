// ignore_for_file: invalid_use_of_protected_member
part of 'payment_checkout_screen.dart';

extension _PaymentCheckoutScreenStatePart3Ext on _PaymentCheckoutScreenState {


  List<Widget> _buildMethodSpecificPanels(
    BuildContext context, {
    required NusaThemeTokens tokens,
    required double grandTotal,
    required double netDue,
    required KasbonDpComputation kasbonCalc,
    required MultiTenderValidation multiValidation,
  }) {
    return [
              // Conditional QRIS / Transfer Bank / EDC / Split / Kasbon Info Box
              if (_selectedMethodCode == 'qris') ...[
                const SizedBox(height: 14),
                NusaCard(
                  backgroundColor: NusaThemeTokens.of(context).accentSoft,
                  borderColor: NusaThemeTokens.of(context).accent.withOpacity(0.28),
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
                          Icon(Icons.qr_code_2_rounded, size: 52, color: NusaThemeTokens.of(context).textPrimary),
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
                                  style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
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
                  backgroundColor: NusaThemeTokens.of(context).accentSoft,
                  borderColor: multiValidation.isValidCheckout
                      ? NusaThemeTokens.of(context).positive.withOpacity(0.45)
                      : NusaThemeTokens.of(context).accent.withOpacity(0.3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Multi-Tender Split Payment',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: NusaThemeTokens.of(context).textPrimary,
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
                                ? NusaThemeTokens.of(context).positive.withOpacity(0.45)
                                : NusaThemeTokens.of(context).warning.withOpacity(0.45),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Tagihan', style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary)),
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
                                Text('Total Terbayar', style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary)),
                                Text(
                                  IdrCurrencyFormatter.format(multiValidation.paidTotal),
                                  style: AppTheme.moneyStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: NusaThemeTokens.of(context).accent,
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
                                        ? NusaThemeTokens.of(context).positive
                                        : NusaThemeTokens.of(context).danger,
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
                                        ? NusaThemeTokens.of(context).positive
                                        : NusaThemeTokens.of(context).danger,
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
                      ? NusaThemeTokens.of(context).warningSoft
                      : NusaThemeTokens.of(context).dangerSoft,
                  borderColor: kasbonCalc.isWithinCreditLimit
                      ? NusaThemeTokens.of(context).warning.withOpacity(0.45)
                      : NusaThemeTokens.of(context).danger.withOpacity(0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            color: kasbonCalc.isWithinCreditLimit
                                ? NusaThemeTokens.of(context).warning
                                : NusaThemeTokens.of(context).danger,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Piutang Buku Bon: ${_selectedCustomer!['name']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: kasbonCalc.isWithinCreditLimit
                                    ? NusaThemeTokens.of(context).warning
                                    : NusaThemeTokens.of(context).danger,
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
                        style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textPrimary),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _kasbonDpController,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        style: AppTheme.moneyStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: NusaThemeTokens.of(context).bgSurface,
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
                        Text(
                          'Metode Pembayaran DP:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).textPrimary),
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
                          border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.35)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Tagihan', style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary)),
                                Text(IdrCurrencyFormatter.format(grandTotal), style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            if (kasbonCalc.storeCreditUsed > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Potong Saldo Deposit', style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).positive)),
                                  Text('- ${IdrCurrencyFormatter.format(kasbonCalc.storeCreditUsed)}', style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).positive)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Uang Muka (DP)', style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary)),
                                Text(IdrCurrencyFormatter.format(kasbonCalc.downPayment), style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).accent)),
                              ],
                            ),
                            const Divider(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Sisa Tagihan (Buku Bon)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).warning)),
                                Text(IdrCurrencyFormatter.format(kasbonCalc.balanceDue), style: AppTheme.moneyStyle(fontSize: 14, fontWeight: FontWeight.w900, color: NusaThemeTokens.of(context).warning)),
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
                            color: NusaThemeTokens.of(context).danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.45)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 18, color: NusaThemeTokens.of(context).danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  kasbonCalc.validationError!,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).danger),
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
                            border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.event_available_rounded, size: 18, color: NusaThemeTokens.of(context).warning),
                              const SizedBox(width: 8),
                              Text(
                                'Jatuh Tempo:',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).textPrimary),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  DateFormat('dd MMM yyyy').format(_kasbonDueDate),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: NusaThemeTokens.of(context).textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                'Ubah',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).accent),
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
    ];
  }
}
