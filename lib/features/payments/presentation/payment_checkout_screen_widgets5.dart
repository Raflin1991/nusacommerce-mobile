// ignore_for_file: invalid_use_of_protected_member
part of 'payment_checkout_screen.dart';

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
                      Divider(height: 1, color: NusaThemeTokens.of(context).borderSubtle),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: posState.cart.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: NusaThemeTokens.of(context).borderSubtle),
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
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: NusaThemeTokens.of(context).textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '${IdrCurrencyFormatter.format(item.unitPrice)} × ${IdrCurrencyFormatter.formatQty(item.quantity)}',
                                        style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.isExchangeReturn)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: NusaThemeTokens.of(context).warningSoft,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.45)),
                                    ),
                                    child: Text(
                                      'RETUR ${IdrCurrencyFormatter.formatQty(item.quantity.abs())}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: NusaThemeTokens.of(context).warning,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: NusaThemeTokens.of(context).bgElevated,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
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
                                          child: SizedBox(
                                            width: 32,
                                            height: 34,
                                            child: Icon(Icons.add_rounded, size: 16, color: NusaThemeTokens.of(context).accent),
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
                  backgroundColor: NusaThemeTokens.of(context).accentSoft,
                  borderColor: NusaThemeTokens.of(context).accent.withOpacity(0.35),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: NusaThemeTokens.of(context).accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Kelebihan Retur Tukar Barang',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: NusaThemeTokens.of(context).textPrimary),
                            ),
                          ),
                          NusaPriceTag(
                            amount: posState.exchangeSurplusCredit,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: NusaThemeTokens.of(context).accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Retur: ${IdrCurrencyFormatter.format(posState.exchangeReturnCreditTotal)} • Pengganti: ${IdrCurrencyFormatter.format(posState.replacementItemsSubtotal)}',
                        style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
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
                        Text(
                          'Pelanggan Umum: kelebihan dana dikembalikan tunai kepada pelanggan.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: NusaThemeTokens.of(context).accent),
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
                      ? NusaThemeTokens.of(context).positive.withOpacity(0.45)
                      : NusaThemeTokens.of(context).borderSubtle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            color: _useStoreCredit ? NusaThemeTokens.of(context).positive : NusaThemeTokens.of(context).accent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gunakan Saldo Deposit (${IdrCurrencyFormatter.format(availStoreCredit)})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: NusaThemeTokens.of(context).textPrimary,
                                  ),
                                ),
                                Text(
                                  'Tersedia untuk ${_selectedCustomer!['name'] ?? 'Pelanggan'}',
                                  style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
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
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).positive),
                            ),
                            Text(
                              'Sisa Tagihan: ${IdrCurrencyFormatter.format(netDue)}',
                              style: AppTheme.moneyStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).textPrimary),
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
                    accentColor: NusaThemeTokens.of(context).warning,
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
                  backgroundColor: NusaThemeTokens.of(context).accentSoft,
                  borderColor: NusaThemeTokens.of(context).accent.withOpacity(0.25),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.group_rounded, color: NusaThemeTokens.of(context).accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Split Bill $_splitEqualPeople Orang • Patungan ${IdrCurrencyFormatter.format((grandTotal / _splitEqualPeople).ceilToDouble())} / orang',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              ..._buildMethodSpecificPanels(
                context,
                tokens: tokens,
                grandTotal: grandTotal,
                netDue: netDue,
                kasbonCalc: kasbonCalc,
                multiValidation: multiValidation,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildCheckoutBottomBar(
        context,
        tokens: tokens,
        posState: posState,
        grandTotal: grandTotal,
        appliedStoreCredit: appliedStoreCredit,
        netDue: netDue,
        changeAmount: changeAmount,
        isCashInsufficient: isCashInsufficient,
        kasbonCalc: kasbonCalc,
        multiValidation: multiValidation,
      ),
    );
  }
}
