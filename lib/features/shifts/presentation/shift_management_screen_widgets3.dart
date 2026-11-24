// ignore_for_file: invalid_use_of_protected_member
part of 'shift_management_screen.dart';

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();

  late final BackofficeRepository _repo = BackofficeRepository.resolve(_api);

  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  final PrinterService _printer = GetIt.instance<PrinterService>();

  final _countedCashCtrl = TextEditingController();

  final _varianceNotesCtrl = TextEditingController();


  bool _loading = true;

  bool _submitting = false;

  bool _isBlindCountLocked = false;

  bool _showDenomCalculator = false;

  bool _requiresVarianceReason = false;

  String? _selectedVarianceReason;

  String? _closeError;

  String? _error;


  final Map<int, int> _denomCounts = {
    100000: 0,
    50000: 0,
    20000: 0,
    10000: 0,
    5000: 0,
    2000: 0,
    1000: 0,
  };


  bool _hasOpenShift = false;

  bool _blindDropEnforced = true;

  bool _canViewExpectedCash = false;

  int? _shiftId;

  String _terminalLabel = '';

  double _openingCash = 0;

  double? _cashSales;

  double? _expectedCash;

  double _payIns = 0;

  double _payOuts = 0;

  int _salesCount = 0;


  Map<String, dynamic>? _lastClosedZReport;

  List<Map<String, dynamic>> _drawerEntries = [];

  List<Map<String, dynamic>> _terminals = [];

  List<Map<String, String>> _varianceReasons = const [
    {'code': 'miscount', 'name': 'Salah hitung uang / kembalian'},
    {'code': 'change_dispute', 'name': 'Selisih uang kembalian pelanggan'},
    {'code': 'unaccounted_pay_out', 'name': 'Pengeluaran laci belum tercatat'},
    {'code': 'other', 'name': 'Lainnya (tulis catatan)'},
  ];


  @override
  void initState() {
    super.initState();
    _loadCurrentShift();
  }


  @override
  void dispose() {
    _countedCashCtrl.dispose();
    _varianceNotesCtrl.dispose();
    super.dispose();
  }


  bool get _isLocalStandalone =>
      context.read<AuthCubit>().state.session.isLocalTrial;


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    final canRevealLive = _canViewExpectedCash && _expectedCash != null && !_blindDropEnforced;
    final liveVariance = canRevealLive ? (counted - _expectedCash!) : null;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        title: const Text('Shift Kasir & Strict Blind Drop'),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang Status Shift',
            onPressed: _loadCurrentShift,
            icon: Icon(Icons.refresh_rounded, color: tokens.accent),
          ),
        ],
      ),
      body: _loading
          ? const NusaShiftSkeleton()
          : _error != null
              ? NusaEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Gagal Memuat Shift',
                  subtitle: _error!,
                  actionLabel: 'Coba Lagi',
                  onAction: _loadCurrentShift,
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 0a. Pending Offline Shift Closures Banner (BUG 6)
                      if (!_isLocalStandalone && _offlineDb.pendingShiftClosuresCount > 0) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: tokens.warningSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: tokens.warning, width: tokens.borderWidth),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.cloud_upload_outlined, color: tokens.warning, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${_offlineDb.pendingShiftClosuresCount} penutupan shift offline menunggu sinkronisasi Cloud.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _loadCurrentShift,
                                child: const Text('Sinkronkan'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 0. Authoritative Server-Verified Z-Report Summary (shown after shift close)
                      if (_lastClosedZReport != null) ...[
                        _buildClosedZReportCard(tokens, _lastClosedZReport!),
                        const SizedBox(height: 14),
                      ],

                      // 1. Shift Status Executive Hero Card (Strict Blind Drop Enforced)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _hasOpenShift
                                ? tokens.accentGradientColors
                                : tokens.heroGradientColors,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  NusaBadge(
                                    label: _hasOpenShift
                                        ? 'SHIFT AKTIF • $_terminalLabel'
                                        : 'SHIFT TUTUP',
                                    variant: _hasOpenShift
                                        ? NusaBadgeVariant.success
                                        : NusaBadgeVariant.warning,
                                  ),
                                  if (_hasOpenShift && !canRevealLive)
                                    const NusaBadge(
                                      label: 'STRICT BLIND DROP',
                                      variant: NusaBadgeVariant.navy,
                                      icon: Icons.lock_rounded,
                                    )
                                  else if (!_hasOpenShift)
                                    SizedBox(
                                      height: 44,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: tokens.positive,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: _submitting
                                            ? null
                                            : _showOpenShiftDialog,
                                        icon: const Icon(Icons.play_arrow_rounded,
                                            size: 18, color: Colors.white),
                                        label: const Text(
                                          'Buka Shift',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              !_hasOpenShift
                                  ? 'Tidak Ada Shift Aktif Saat Ini'
                                  : (canRevealLive
                                      ? 'Saldo Kas Tunai Seharusnya (X-Report Supervisor)'
                                      : 'Strict Blind Drop Aktif — Hitung Fisik Uang Laci'),
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                !_hasOpenShift
                                    ? IdrCurrencyFormatter.format(0)
                                    : (canRevealLive
                                        ? IdrCurrencyFormatter.format(_expectedCash!)
                                        : 'Rp ••••••• (Terkunci Server)'),
                                key: const Key('shift_expected_cash_display'),
                                style: AppTheme.moneyStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _shiftStat('Modal Awal',
                                        IdrCurrencyFormatter.format(_openingCash)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _shiftStat(
                                      'Penjualan Tunai',
                                      canRevealLive && _cashSales != null
                                          ? IdrCurrencyFormatter.format(_cashSales!)
                                          : '$_salesCount Trx • Terkunci',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _shiftStat(
                                        'Mutasi Laci',
                                        IdrCurrencyFormatter.formatCompact(
                                            _payIns - _payOuts)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (_hasOpenShift) ...[
                        Row(
                          children: [
                            Expanded(
                              child: NusaButton(
                                label: 'Kas Masuk',
                                icon: Icons.add_circle_outline_rounded,
                                variant: NusaButtonVariant.success,
                                onPressed: _submitting
                                    ? null
                                    : () => _showAddCashEntryModal('pay_in'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: NusaButton(
                                label: 'Kas Keluar',
                                icon: Icons.remove_circle_outline_rounded,
                                variant: NusaButtonVariant.danger,
                                onPressed: _submitting
                                    ? null
                                    : () => _showAddCashEntryModal('pay_out'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        NusaButton(
                          label: 'Buka Laci Tanpa Transaksi (No-Sale)',
                          icon: Icons.point_of_sale_rounded,
                          variant: NusaButtonVariant.outline,
                          onPressed:
                              _submitting ? null : _recordNoSaleDrawerOpen,
                        ),
                        const SizedBox(height: 16),

                        // 3. Strict Blind Drop + Denomination Calculator + Server Z-Report Card
                        NusaCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Tutup Shift (Strict Blind Drop)',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const NusaBadge(
                                    label: 'Anti-Fraud Server',
                                    variant: NusaBadgeVariant.navy,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                canRevealLive
                                    ? 'Hitung fisik uang tunai laci untuk rekonsiliasi Z-Report server.'
                                    : 'Server menyembunyikan total kas sistem hingga shift ditutup. Hitung fisik laci lalu kirim untuk verifikasi Z-Report.',
                                style: TextStyle(
                                    fontSize: 12, color: tokens.textSecondary),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('shift_counted_cash_input'),
                                controller: _countedCashCtrl,
                                readOnly: _isBlindCountLocked,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() => _closeError = null),
                                style: AppTheme.moneyStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.textPrimary,
                                ),
                                decoration: InputDecoration(
                                  labelText: _isBlindCountLocked
                                      ? 'Uang Tunai Fisik Terkunci (Rp)'
                                      : 'Uang Tunai Fisik Dihitung (Rp)',
                                  hintText: 'Contoh: 1250000',
                                  prefixIcon: Icon(
                                    _isBlindCountLocked
                                        ? Icons.lock_rounded
                                        : Icons.calculate_outlined,
                                    color: _isBlindCountLocked
                                        ? tokens.positive
                                        : tokens.accent,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: NusaPillFilter(
                                      label: _showDenomCalculator
                                          ? 'Sembunyikan Kalkulator Pecahan'
                                          : 'Hitung Pecahan Uang (100rb - 1rb)',
                                      icon: Icons.money_rounded,
                                      selected: _showDenomCalculator,
                                      onTap: () => setState(() =>
                                          _showDenomCalculator =
                                              !_showDenomCalculator),
                                    ),
                                  ),
                                  if (_showDenomCalculator &&
                                      !_isBlindCountLocked) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: _resetDenoms,
                                      child: Text('Reset',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: tokens.danger)),
                                    ),
                                  ],
                                ],
                              ),
                              if (_showDenomCalculator) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: tokens.bgElevated,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: tokens.borderSubtle,
                                        width: tokens.borderWidth),
                                  ),
                                  child: Column(
                                    children: _denomCounts.entries.map((entry) {
                                      final denom = entry.key;
                                      final count = entry.value;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  IdrCurrencyFormatter.format(
                                                      denom),
                                                  style: AppTheme.moneyStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: tokens.textPrimary),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () =>
                                                  _updateDenom(denom, -1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: tokens.bgSurface,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: tokens.borderSubtle),
                                                ),
                                                child: Icon(Icons.remove_rounded,
                                                    size: 16,
                                                    color: tokens.textPrimary),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 32,
                                              child: Text(
                                                '$count',
                                                textAlign: TextAlign.center,
                                                style: AppTheme.moneyStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                    color: tokens.textPrimary),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () =>
                                                  _updateDenom(denom, 1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  color: tokens.accentSoft,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: tokens.accent
                                                          .withOpacity(0.35)),
                                                ),
                                                child: Icon(Icons.add_rounded,
                                                    size: 16,
                                                    color: tokens.accent),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              flex: 4,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerRight,
                                                child: NusaPriceTag(
                                                  amount: denom * count,
                                                  fontSize: 12,
                                                  color: tokens.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (!_isBlindCountLocked)
                                NusaButton(
                                  key: const Key('shift_lock_count_btn'),
                                  label: 'Kunci Hitungan Fisik (Blind Drop)',
                                  icon: Icons.lock_outline_rounded,
                                  variant: NusaButtonVariant.outline,
                                  onPressed: _countedCashCtrl.text.trim().isEmpty
                                      ? null
                                      : () => setState(() {
                                            _isBlindCountLocked = true;
                                            _closeError = null;
                                          }),
                                )
                              else ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: liveVariance != null
                                        ? (liveVariance == 0
                                            ? tokens.positiveSoft
                                            : tokens.dangerSoft)
                                        : tokens.accentSoft,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: liveVariance != null
                                          ? (liveVariance == 0
                                              ? tokens.positive
                                              : tokens.danger)
                                          : tokens.accent,
                                      width: tokens.borderWidth,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text('Kas Fisik Terkunci:',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: tokens.textPrimary)),
                                          ),
                                          const SizedBox(width: 8),
                                          NusaPriceTag(
                                            amount: counted,
                                            fontSize: 14,
                                            color: tokens.textPrimary,
                                          ),
                                        ],
                                      ),
                                      if (canRevealLive && liveVariance != null) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text('Kas Sistem (X-Report):',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: tokens.textSecondary)),
                                            ),
                                            const SizedBox(width: 8),
                                            NusaPriceTag(
                                              amount: _expectedCash!,
                                              fontSize: 13.5,
                                              color: tokens.textPrimary,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                liveVariance == 0
                                                    ? 'Status Kas (Balance):'
                                                    : (liveVariance > 0
                                                        ? 'Selisih Lebih:'
                                                        : 'Selisih Kurang:'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                    color: tokens.textPrimary),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            NusaPriceTag(
                                              amount: liveVariance.abs(),
                                              prefix: liveVariance > 0
                                                  ? '+'
                                                  : (liveVariance < 0
                                                      ? '-'
                                                      : ''),
                                              fontSize: 14.5,
                                              color: liveVariance == 0
                                                  ? tokens.positive
                                                  : tokens.danger,
                                            ),
                                          ],
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Strict Blind Drop: Nominal kas sistem & selisih dihitung eksklusif di server saat tutup shift diverifikasi.',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: tokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],

                              if (_requiresVarianceReason) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Alasan Selisih Kas (Wajib untuk Audit Z-Report)',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.danger,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _varianceReasons.map((r) {
                                    final code = r['code'] ?? 'other';
                                    final label = r['name'] ?? code;
                                    return NusaPillFilter(
                                      label: label,
                                      selected: _selectedVarianceReason == code,
                                      selectedColor: tokens.danger,
                                      onTap: () => setState(() {
                                        _selectedVarianceReason = code;
                                        _closeError = null;
                                      }),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _varianceNotesCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Catatan Penjelasan Selisih (Opsional)',
                                    hintText: 'Contoh: Kembalian kurang Rp 5.000 pada transaksi siang',
                                  ),
                                ),
                              ],

                              if (_closeError != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  key: const Key('shift_close_inline_error'),
                                  child: _inlineModalErrorBox(tokens, _closeError!),
                                ),
                              ],

                              const SizedBox(height: 12),
                              NusaButton(
                                key: const Key('shift_close_submit_btn'),
                                label: _submitting
                                    ? 'Memverifikasi di Server...'
                                    : (_requiresVarianceReason
                                        ? 'Konfirmasi Alasan & Tutup Shift'
                                        : 'Tutup Shift & Hitung Z-Report Server'),
                                icon: Icons.verified_user_outlined,
                                isLoading: _submitting,
                                onPressed: (_submitting || !_isBlindCountLocked)
                                    ? null
                                    : _closeShiftAndSendZReport,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Text(
                        'Riwayat Mutasi Kas Laci Shift Ini',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_drawerEntries.isEmpty)
                        const NusaEmptyState(
                          icon: Icons.point_of_sale_outlined,
                          title: 'Belum Ada Mutasi Kas',
                          subtitle:
                              'Mutasi Kas Masuk, Kas Keluar, atau No-Sale laci akan tercatat di sini.',
                        )
                      else
                        ..._drawerEntries.map((e) {
                          final isIn = e['type'] == 'pay_in';
                          return NusaCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isIn
                                        ? tokens.positiveSoft
                                        : tokens.dangerSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isIn
                                        ? Icons.south_west_rounded
                                        : Icons.north_east_rounded,
                                    color: isIn ? tokens.positive : tokens.danger,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (e['reason'] ?? '-').toString(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (e['created_at'] ?? '').toString(),
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: tokens.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                NusaPriceTag(
                                  amount: (e['amount'] as num?)?.toDouble() ?? 0,
                                  prefix: isIn ? '+' : '-',
                                  fontSize: 13.5,
                                  color: isIn ? tokens.positive : tokens.danger,
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
