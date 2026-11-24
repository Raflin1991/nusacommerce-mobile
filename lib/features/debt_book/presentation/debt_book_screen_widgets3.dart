// ignore_for_file: invalid_use_of_protected_member
part of 'debt_book_screen.dart';

class _DebtBookScreenState extends State<DebtBookScreen> with SingleTickerProviderStateMixin {
  final ApiClient _api = GetIt.instance<ApiClient>();

  late final BackofficeRepository _repo = BackofficeRepository.resolve(_api);

  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();

  final PrinterService _printer = GetIt.instance<PrinterService>();

  late TabController _tabController;


  bool _loading = true;

  String? _error;


  double _totalReceivables = 0;

  List<Map<String, dynamic>> _receivables = [];

  double _totalPayables = 0;

  List<Map<String, dynamic>> _payables = [];

  List<Map<String, dynamic>> _expenses = [];

  List<Map<String, dynamic>> _expenseCategories = [];

  List<Map<String, dynamic>> _paymentMethods = [];

  String _receivableAgingFilter = 'Semua'; // 'Semua', 'Belum Jatuh Tempo', '1-30 Hari', '>30 Hari'

  String _expenseCategoryFilter = 'Semua';


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _loadData();
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;


  List<Map<String, dynamic>> get _defaultOfflinePaymentMethods => const [
        {'id': 1, 'name': 'Tunai', 'type': 'cash'},
        {'id': 2, 'name': 'QRIS / E-Wallet', 'type': 'qris'},
        {'id': 3, 'name': 'Transfer Bank', 'type': 'bank_transfer'},
      ];


  List<Map<String, dynamic>> get _defaultOfflineExpenseCategories => const [
        {'id': 1, 'name': 'Operasional Toko'},
        {'id': 2, 'name': 'Listrik & Air'},
        {'id': 3, 'name': 'Gaji Harian Kasir'},
        {'id': 4, 'name': 'Perlengkapan & Kemasan'},
        {'id': 5, 'name': 'Transport & Pengiriman'},
        {'id': 6, 'name': 'Perawatan Toko'},
      ];


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final storeName = context.watch<AuthCubit>().state.session.activeStore.name;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Buku Bon & Biaya Toko'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/cash-ledger'),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Buku Kas'),
          ),
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _loadData,
            icon: Icon(Icons.refresh_rounded, color: tokens.accent),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          indicatorColor: tokens.accent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(text: 'Piutang Bon'),
            Tab(text: 'Hutang Supplier'),
            Tab(text: 'Biaya Toko'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? NusaEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Gagal Memuat Buku Bon',
                  subtitle: _error!,
                  actionLabel: 'Coba Lagi',
                  onAction: _loadData,
                )
              : Column(
                  children: [
                    // Executive Summary Comparison Banner: Piutang vs Hutang
                    Container(
                      decoration: BoxDecoration(
                        color: tokens.bgSurface,
                        border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _tabController.animateTo(0),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: tokens.warningSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: tokens.warning.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                                    width: tokens.borderWidth,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Piutang Bon',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: tokens.warning,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        NusaBadge(
                                          label: '${_receivables.length}',
                                          variant: NusaBadgeVariant.warning,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: NusaPriceTag(
                                        amount: _totalReceivables,
                                        fontSize: 15.5,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => _tabController.animateTo(1),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: tokens.dangerSoft,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: tokens.danger.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                                    width: tokens.borderWidth,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Hutang Tempo',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: tokens.danger,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        NusaBadge(
                                          label: '${_payables.length}',
                                          variant: NusaBadgeVariant.danger,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: NusaPriceTag(
                                        amount: _totalPayables,
                                        fontSize: 15.5,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // TAB 1: PIUTANG BON PELANGGAN
                          ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              SizedBox(
                                height: 36,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: ['Semua', 'Belum Jatuh Tempo', '1-30 Hari', '>30 Hari']
                                      .map((ageFilter) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: NusaPillFilter(
                                        label: ageFilter,
                                        selected: _receivableAgingFilter == ageFilter,
                                        onTap: () => setState(() => _receivableAgingFilter = ageFilter),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_receivables.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showBatchSettlementModal(isReceivable: true),
                                        icon: const Icon(Icons.done_all_rounded, size: 18),
                                        label: const Text('Pelunasan Gabungan (Multi-Nota)'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],
                              Builder(builder: (context) {
                                final filteredRecs = _receivables.where((r) {
                                  final age = (r['age_days'] as num?)?.toInt() ?? 0;
                                  if (_receivableAgingFilter == 'Belum Jatuh Tempo') return age <= 0;
                                  if (_receivableAgingFilter == '1-30 Hari') return age >= 1 && age <= 30;
                                  if (_receivableAgingFilter == '>30 Hari') return age > 30;
                                  return true;
                                }).toList();

                                if (filteredRecs.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 24),
                                    child: NusaEmptyState(
                                      icon: Icons.menu_book_outlined,
                                      title: 'Tidak Ada Piutang',
                                      subtitle: 'Tidak ada tagihan piutang pelanggan pada kategori jatuh tempo ini.',
                                    ),
                                  );
                                }

                                return Column(
                                  children: filteredRecs.map((r) {
                                    final originalIdx = _receivables.indexOf(r);
                                    final cust = Map<String, dynamic>.from((r['customer'] as Map?) ?? {});
                                    final custName = (cust['name'] ?? 'Pelanggan').toString();
                                    final phone = (cust['phone'] ?? '').toString();
                                    final ageDays = (r['age_days'] as num?)?.toInt() ?? 0;
                                    final agingLabel = ageDays <= 0
                                        ? 'Belum Jatuh Tempo'
                                        : (ageDays <= 30 ? '1-30 Hari ($ageDays hr)' : '>30 Hari ($ageDays hr)');
                                    final agingVariant = ageDays <= 0
                                        ? NusaBadgeVariant.primary
                                        : (ageDays <= 30 ? NusaBadgeVariant.warning : NusaBadgeVariant.danger);

                                    return NusaCard(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  custName,
                                                  style: TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: NusaThemeTokens.of(context).textPrimary,
                                                  ),
                                                ),
                                              ),
                                              NusaPriceTag(
                                                amount: (r['balance_due'] as num?)?.toDouble() ?? 0,
                                                fontSize: 15,
                                                color: NusaThemeTokens.of(context).danger,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              NusaBadge(label: agingLabel, variant: agingVariant),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Nota ${r['number']} • WA: ${phone.isEmpty ? '-' : phone}',
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              if (phone.isNotEmpty) ...[
                                                Expanded(
                                                  child: NusaButton(
                                                    label: 'Tagih WA',
                                                    icon: Icons.chat_rounded,
                                                    variant: NusaButtonVariant.outline,
                                                    minHeight: 44,
                                                    onPressed: () {
                                                      WhatsAppService.sendDebtReminder(
                                                        customerName: custName,
                                                        customerPhone: phone,
                                                        invoiceNumber: r['number'].toString(),
                                                        balanceDue: (r['balance_due'] as num?)?.toDouble() ?? 0,
                                                        storeName: storeName,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              IconButton(
                                                tooltip: 'Riwayat Cicilan',
                                                onPressed: () => _showInstallmentHistoryModal(
                                                  isReceivable: true,
                                                  invoice: r,
                                                  partyName: custName,
                                                ),
                                                icon: Icon(Icons.history_rounded, color: NusaThemeTokens.of(context).accent),
                                              ),
                                              Expanded(
                                                child: NusaButton(
                                                  label: 'Terima Cicilan',
                                                  icon: Icons.check_circle_outline_rounded,
                                                  minHeight: 44,
                                                  onPressed: () => _showPayInstallmentModal(originalIdx),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              }),
                            ],
                          ),

                          // TAB 2: HUTANG USAHA SUPPLIER (PAYABLES)
                          ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: NusaButton(
                                      label: 'Data Pemasok',
                                      icon: Icons.local_shipping_outlined,
                                      variant: NusaButtonVariant.outline,
                                      minHeight: 44,
                                      onPressed: () => context.push('/suppliers'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: NusaButton(
                                      label: 'Stok Masuk Beli',
                                      icon: Icons.add_shopping_cart_rounded,
                                      minHeight: 44,
                                      onPressed: () => context.push('/suppliers?tab=stock-in'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_payables.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 24),
                                  child: NusaEmptyState(
                                    icon: Icons.local_shipping_outlined,
                                    title: 'Hutang Supplier Lunas',
                                    subtitle: 'Tidak ada tagihan pembelian tempo supplier yang belum lunas.',
                                  ),
                                )
                              else
                                ...List.generate(_payables.length, (idx) {
                                  final p = _payables[idx];
                                  final supp = Map<String, dynamic>.from((p['supplier'] as Map?) ?? {});
                                  final suppName = (supp['name'] ?? supp['business_name'] ?? 'Supplier').toString();
                                  final phone = (supp['phone'] ?? '').toString();
                                  final bankName = (supp['bank_name'] ?? '').toString();
                                  final bankAcc = (supp['bank_account_number'] ?? '').toString();
                                  final bankHolder = (supp['bank_account_holder'] ?? '').toString();
                                  final isOverdue = p['is_overdue'] == true;

                                  return NusaCard(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                suppName,
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: NusaThemeTokens.of(context).textPrimary,
                                                ),
                                              ),
                                            ),
                                            NusaPriceTag(
                                              amount: (p['balance_due'] as num?)?.toDouble() ?? 0,
                                              fontSize: 15,
                                              color: NusaThemeTokens.of(context).danger,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            NusaBadge(
                                              label: isOverdue ? 'Jatuh Tempo Lewat' : 'Tempo',
                                              variant: isOverdue ? NusaBadgeVariant.danger : NusaBadgeVariant.warning,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Faktur: ${p['number']} • Tempo: ${p['due_date'] ?? '-'}',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (bankName.isNotEmpty || bankAcc.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: NusaThemeTokens.of(context).bgPage,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.account_balance_outlined, size: 17, color: NusaThemeTokens.of(context).accent),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '$bankName $bankAcc ${bankHolder.isNotEmpty ? "($bankHolder)" : ""}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: NusaThemeTokens.of(context).textPrimary,
                                                    ),
                                                  ),
                                                ),
                                                if (bankAcc.isNotEmpty)
                                                  InkWell(
                                                    onTap: () {
                                                      Clipboard.setData(ClipboardData(text: bankAcc));
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('No. Rekening $bankAcc disalin!')),
                                                      );
                                                    },
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      constraints: const BoxConstraints(minHeight: 36),
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: NusaThemeTokens.of(context).accentSoft,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.copy_rounded, size: 14, color: NusaThemeTokens.of(context).accent),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Salin',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w800,
                                                              color: NusaThemeTokens.of(context).accent,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            if (phone.isNotEmpty) ...[
                                              Expanded(
                                                child: NusaButton(
                                                  label: 'Hubungi WA',
                                                  icon: Icons.chat_rounded,
                                                  variant: NusaButtonVariant.outline,
                                                  minHeight: 44,
                                                  onPressed: () {
                                                    WhatsAppService.sendDebtReminder(
                                                      customerName: suppName,
                                                      customerPhone: phone,
                                                      invoiceNumber: p['number'].toString(),
                                                      balanceDue: (p['balance_due'] as num?)?.toDouble() ?? 0,
                                                      storeName: storeName,
                                                    );
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                            IconButton(
                                              tooltip: 'Riwayat Bayar Hutang',
                                              onPressed: () => _showInstallmentHistoryModal(
                                                isReceivable: false,
                                                invoice: p,
                                                partyName: suppName,
                                              ),
                                              icon: Icon(Icons.history_rounded, color: NusaThemeTokens.of(context).accent),
                                            ),
                                            Expanded(
                                              child: NusaButton(
                                                label: 'Bayar Hutang',
                                                icon: Icons.payment_rounded,
                                                minHeight: 44,
                                                onPressed: () => _showPaySupplierModal(idx),
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

                          // TAB 3: BIAYA OPERASIONAL TOKO
                          ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: NusaButton(
                                      label: 'Catat Biaya Baru',
                                      icon: Icons.add_rounded,
                                      onPressed: _showAddExpenseModal,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: NusaButton(
                                      label: 'Kategori',
                                      icon: Icons.folder_outlined,
                                      variant: NusaButtonVariant.outline,
                                      onPressed: _showExpenseCategoriesManager,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (final cat in [
                                      'Semua',
                                      ..._expenseCategories.map((c) => (c['name'] ?? '').toString()).where((n) => n.isNotEmpty),
                                    ])
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: NusaPillFilter(
                                          label: cat,
                                          selected: _expenseCategoryFilter == cat,
                                          onTap: () => setState(() => _expenseCategoryFilter = cat),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Builder(builder: (context) {
                                final filteredExps = _expenses.where((exp) {
                                  if (_expenseCategoryFilter == 'Semua') return true;
                                  final cName = (exp['category']?['name'] ?? exp['category_name'] ?? 'Operasional').toString();
                                  return cName == _expenseCategoryFilter;
                                }).toList();
                                if (filteredExps.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.only(top: 24),
                                    child: NusaEmptyState(
                                      icon: Icons.receipt_long_outlined,
                                      title: 'Belum Ada Biaya Operasional',
                                      subtitle: 'Catat pengeluaran operasional seperti listrik, plastik, atau transportasi toko.',
                                    ),
                                  );
                                }
                                return Column(
                                  children: filteredExps.map((exp) {
                                    final catName = (exp['category']?['name'] ?? exp['category_name'] ?? 'Operasional').toString();
                                    final dateStr = (exp['expense_date'] ?? exp['created_at'] ?? '').toString();
                                    return NusaCard(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: NusaThemeTokens.of(context).dangerSoft,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(Icons.receipt_long_rounded, color: NusaThemeTokens.of(context).danger, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  (exp['description'] ?? '-').toString(),
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: NusaThemeTokens.of(context).textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$catName • $dateStr',
                                                  style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              NusaPriceTag(
                                                amount: (exp['amount'] as num?)?.toDouble() ?? 0,
                                                fontSize: 13.5,
                                                color: NusaThemeTokens.of(context).danger,
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  InkWell(
                                                    onTap: () => _showEditExpenseModal(exp),
                                                    child: Padding(
                                                      padding: EdgeInsets.all(4),
                                                      child: Icon(Icons.edit_outlined, size: 17, color: NusaThemeTokens.of(context).accent),
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () => _confirmDeleteExpense(exp),
                                                    child: Padding(
                                                      padding: EdgeInsets.all(4),
                                                      child: Icon(Icons.delete_outline, size: 17, color: NusaThemeTokens.of(context).danger),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
