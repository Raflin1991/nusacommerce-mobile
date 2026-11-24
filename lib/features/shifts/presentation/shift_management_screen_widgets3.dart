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
                      if (_lastClosedZReport != null) ...[
                        _buildClosedZReportCard(tokens, _lastClosedZReport!),
                        const SizedBox(height: 14),
                      ],
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
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                        onPressed: _submitting ? null : _showOpenShiftDialog,
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'Buka Shift',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
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
                                fontWeight: FontWeight.w600,
                              ),
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
                                  color: Colors.white,
                                ),
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
                                    child: _shiftStat(
                                      'Modal Awal',
                                      IdrCurrencyFormatter.format(_openingCash),
                                    ),
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
                                      IdrCurrencyFormatter.formatCompact(_payIns - _payOuts),
                                    ),
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
                                onPressed: _submitting ? null : () => _showAddCashEntryModal('pay_in'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: NusaButton(
                                label: 'Kas Keluar',
                                icon: Icons.remove_circle_outline_rounded,
                                variant: NusaButtonVariant.danger,
                                onPressed: _submitting ? null : () => _showAddCashEntryModal('pay_out'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        NusaButton(
                          label: 'Buka Laci Tanpa Transaksi (No-Sale)',
                          icon: Icons.point_of_sale_rounded,
                          variant: NusaButtonVariant.outline,
                          onPressed: _submitting ? null : _recordNoSaleDrawerOpen,
                        ),
                        const SizedBox(height: 16),
                      ],
                      ..._buildCloseShiftAndDrawerWidgets(
                        tokens,
                        counted,
                        canRevealLive,
                        liveVariance,
                      ),
                    ],
                  ),
                ),
    );
  }
}
