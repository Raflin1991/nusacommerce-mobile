import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// MODUL SHIFT KASIR, MUTASI LACI UANG & REKONSILIASI Z-REPORT (`PRD-07`, Live API Bound)
class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final PrinterService _printer = GetIt.instance<PrinterService>();
  final _countedCashCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _isBlindCountVerified = false;
  bool _showDenomCalculator = false;
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

  void _updateDenom(int denom, int delta) {
    if (_isBlindCountVerified) return;
    setState(() {
      final current = _denomCounts[denom] ?? 0;
      _denomCounts[denom] = (current + delta).clamp(0, 9999);
      final total = _denomCounts.entries.fold<double>(
        0.0,
        (sum, e) => sum + (e.key * e.value),
      );
      _countedCashCtrl.text = IdrCurrencyFormatter.format(total);
    });
  }

  void _resetDenoms() {
    if (_isBlindCountVerified) return;
    setState(() {
      for (final key in _denomCounts.keys) {
        _denomCounts[key] = 0;
      }
      _countedCashCtrl.clear();
    });
  }

  bool _hasOpenShift = false;
  int? _shiftId;
  String _terminalLabel = '';
  double _openingCash = 0;
  double _cashSales = 0;
  double _expectedCash = 0;
  double _payIns = 0;
  double _payOuts = 0;

  List<Map<String, dynamic>> _drawerEntries = [];
  List<Map<String, dynamic>> _terminals = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentShift();
  }

  @override
  void dispose() {
    _countedCashCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentShift() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.dio.get(ApiEndpoints.currentShift);
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final hasShift = data['has_open_shift'] == true && data['shift'] != null;
      final terms = (data['terminals'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (hasShift) {
        final s = Map<String, dynamic>.from(data['shift'] as Map);
        final term = s['terminal'] as Map?;
        final entries = (s['entries'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final expCash = (s['expected_cash'] as num?)?.toDouble() ?? 0;

        if (!mounted) return;
        setState(() {
          _hasOpenShift = true;
          _shiftId = (s['id'] as num?)?.toInt();
          _terminalLabel = (term?['name'] ?? 'POS').toString();
          _openingCash = (s['opening_cash'] as num?)?.toDouble() ?? 0;
          _cashSales = (s['sales_total'] as num?)?.toDouble() ?? 0;
          _expectedCash = expCash;
          _payIns = (s['pay_ins'] as num?)?.toDouble() ?? 0;
          _payOuts = (s['pay_outs'] as num?)?.toDouble() ?? 0;
          _drawerEntries = entries;
          _terminals = terms;
          _isBlindCountVerified = false;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasOpenShift = false;
          _shiftId = null;
          _terminals = terms;
          _drawerEntries = [];
          _openingCash = 0;
          _cashSales = 0;
          _expectedCash = 0;
          _payIns = 0;
          _payOuts = 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _showOpenShiftDialog() async {
    final openCtrl = TextEditingController(text: '500000');
    int? selectedTerminalId = _terminals.isNotEmpty ? (_terminals.first['id'] as num?)?.toInt() : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setModalState) => AlertDialog(
          title: const Text('Buka Shift Kasir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_terminals.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: selectedTerminalId,
                  decoration: const InputDecoration(labelText: 'Terminal Kasir'),
                  items: _terminals
                      .map((t) => DropdownMenuItem<int>(
                            value: (t['id'] as num).toInt(),
                            child: Text((t['name'] ?? 'Terminal').toString()),
                          ))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedTerminalId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: openCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setModalState(() {}),
                decoration: const InputDecoration(labelText: 'Modal Awal Kasir (Rp)'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in const [
                    ('Rp 200rb', '200000'),
                    ('Rp 300rb', '300000'),
                    ('Rp 500rb', '500000'),
                    ('Rp 1 Jt', '1000000'),
                  ])
                    NusaPillFilter(
                      label: preset.$1,
                      selected: IdrCurrencyFormatter.parse(openCtrl.text) == double.parse(preset.$2),
                      onTap: () => setModalState(() => openCtrl.text = preset.$2),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final opening = IdrCurrencyFormatter.parse(openCtrl.text);
                Navigator.pop(ctx);
                setState(() => _submitting = true);
                try {
                  await _api.dio.post(
                    ApiEndpoints.openShift,
                    data: {
                      'opening_cash': opening,
                      if (selectedTerminalId != null) 'terminal_id': selectedTerminalId,
                    },
                  );
                  await _loadCurrentShift();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                  );
                } finally {
                  if (mounted) setState(() => _submitting = false);
                }
              },
              child: const Text('Buka Shift'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCashEntryModal(String type) {
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isIn = type == 'pay_in';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isIn ? 'Catat Kas Masuk Laci (Pay-In)' : 'Catat Kas Keluar Laci (Pay-Out)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal Uang Tunai (Rp)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: isIn ? 'Keterangan (misal: Tambah receh modal)' : 'Alasan (misal: Beli es batu / galon)',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isIn ? AppColors.success : AppColors.danger),
                onPressed: () async {
                  final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                  if (amt <= 0 || reasonCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  setState(() => _submitting = true);
                  try {
                    await _api.dio.post(
                      ApiEndpoints.cashEntry,
                      data: {
                        'shift_id': _shiftId,
                        'type': type,
                        'amount': amt,
                        'reason': reasonCtrl.text.trim(),
                      },
                    );
                    await _loadCurrentShift();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                    );
                  } finally {
                    if (mounted) setState(() => _submitting = false);
                  }
                },
                child: Text(isIn ? 'Simpan Kas Masuk' : 'Simpan Kas Keluar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordNoSaleDrawerOpen() async {
    if (!_hasOpenShift || _submitting) return;
    final reasonCtrl = TextEditingController(text: 'Tukar uang kembalian / cek fisik laci');
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Buka Laci Tanpa Transaksi (No-Sale)', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Alasan Buka Laci (Audit Anti-Fraud)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              setState(() => _submitting = true);
              try {
                await _api.dio.post(
                  ApiEndpoints.cashEntry,
                  data: {
                    'shift_id': _shiftId,
                    'type': 'drawer_open_no_sale',
                    'amount': 0,
                    'reason': reasonCtrl.text.trim().isEmpty
                        ? 'Buka laci manual (No-Sale)'
                        : reasonCtrl.text.trim(),
                  },
                );
                final kicked = await _printer.kickCashDrawer();
                await _loadCurrentShift();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: kicked ? AppColors.successDark : null,
                      content: Text(
                        kicked
                            ? 'Laci kasir RJ-11 dibuka via Bluetooth & kejadian No-Sale dicatat untuk audit.'
                            : 'Kejadian No-Sale dicatat untuk audit (sambungkan printer Bluetooth untuk membuka laci RJ-11).',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                  );
                }
              } finally {
                if (mounted) setState(() => _submitting = false);
              }
            },
            child: const Text('Kirim Pulse & Buka'),
          ),
        ],
      ),
    );
  }

  void _showThermalZReportDialog(double counted) {
    final session = context.read<AuthCubit>().state.session;
    final storeProfile = _offlineDb.getStoreProfile();
    String selectedWidth = _printer.paperWidth;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final text = _printer.formatShiftZReportText(
            storeProfile: storeProfile,
            cashierName: session.userName,
            openingCash: _openingCash,
            cashSalesTotal: _cashSales,
            payInTotal: _payIns,
            payOutTotal: _payOuts,
            expectedCash: _expectedCash,
            countedCash: counted,
            paperWidthOverride: selectedWidth,
          );
          return AlertDialog(
            title: Text('Struk Z-Report Thermal ($selectedWidth)', style: const TextStyle(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NusaPillFilter(
                        label: '58mm',
                        selected: selectedWidth == '58mm',
                        onTap: () => setModalState(() {
                          selectedWidth = '58mm';
                          _printer.savePreferences(width: '58mm');
                        }),
                      ),
                      const SizedBox(width: 8),
                      NusaPillFilter(
                        label: '80mm',
                        selected: selectedWidth == '80mm',
                        onTap: () => setModalState(() {
                          selectedWidth = '80mm';
                          _printer.savePreferences(width: '80mm');
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final ok = await _printer.printReceiptText(text, openCashDrawer: false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
                      content: Text(
                        ok
                            ? 'Struk Z-Report ($selectedWidth) dikirim ke printer Bluetooth!'
                            : 'Printer Bluetooth tidak terhubung. Cek Pengaturan > Printer.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.print_rounded, size: 17),
                label: const Text('Cetak Bluetooth'),
              ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _closeShiftAndSendZReport() async {
    if (!_hasOpenShift) return;
    if (_countedCashCtrl.text.trim().isEmpty || !_isBlindCountVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Masukkan uang fisik dan tekan "Verifikasi & Kunci Kasir" terlebih dahulu (Blind Count).'),
        ),
      );
      return;
    }
    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    final diff = counted - _expectedCash;
    final cashShortage = diff < 0 ? diff.abs() : 0.0;
    final cashOverage = diff > 0 ? diff : 0.0;
    final session = context.read<AuthCubit>().state.session;

    setState(() => _submitting = true);
    try {
      await _api.dio.post(
        ApiEndpoints.closeShift,
        data: {
          'shift_id': _shiftId,
          'closing_cash_counted': counted,
          'expected_cash': _expectedCash,
          'cash_shortage': cashShortage,
          'cash_overage': cashOverage,
          'denomination_counts': _denomCounts.map((k, v) => MapEntry(k.toString(), v)),
        },
      );

      final ownerPhone = session.activeStore.phone?.trim() ?? '';
      if (ownerPhone.isNotEmpty) {
        await WhatsAppService.sendShiftZReportToOwner(
          ownerPhone: ownerPhone,
          storeName: session.activeStore.name,
          cashierName: session.userName,
          openingCash: _openingCash,
          salesTotal: _cashSales,
          expectedCash: _expectedCash,
          countedCash: counted,
        );
      }

      if (mounted) {
        _countedCashCtrl.clear();
        setState(() => _isBlindCountVerified = false);
      }
      await _loadCurrentShift();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.successDark,
          content: Text('Shift berhasil ditutup & Z-Report dikirim ke Owner.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    final variance = counted - _expectedCash;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Shift Kasir & Laci Uang'),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang Status Shift',
            onPressed: _loadCurrentShift,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                      // 1. Shift Status Executive Hero Card (Blind Count Protected)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: _hasOpenShift ? AppColors.heroBlueGradient : AppColors.executiveNavyGradient,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                NusaBadge(
                                  label: _hasOpenShift ? 'SHIFT AKTIF • $_terminalLabel' : 'SHIFT TUTUP',
                                  variant: _hasOpenShift ? NusaBadgeVariant.success : NusaBadgeVariant.warning,
                                ),
                                if (!_hasOpenShift)
                                  SizedBox(
                                    height: 44,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _submitting ? null : _showOpenShiftDialog,
                                      icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                                      label: const Text(
                                        'Buka Shift',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isBlindCountVerified || !_hasOpenShift
                                  ? 'Saldo Kas Tunai Seharusnya di Laci'
                                  : 'Blind Count Aktif — Hitung Uang Fisik Laci',
                              style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isBlindCountVerified || !_hasOpenShift
                                  ? IdrCurrencyFormatter.format(_expectedCash)
                                  : 'Rp ••••••• (Tersembunyi)',
                              style: AppTheme.moneyStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _shiftStat('Modal Awal', IdrCurrencyFormatter.format(_openingCash)),
                                  _shiftStat(
                                    'Penjualan Tunai',
                                    _isBlindCountVerified ? IdrCurrencyFormatter.format(_cashSales) : '•••••',
                                  ),
                                  _shiftStat('Mutasi Laci', IdrCurrencyFormatter.formatCompact(_payIns - _payOuts)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (_hasOpenShift) ...[
                        // 2. Drawer Operations (>= 48dp hit targets)
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

                        // 3. Blind Count + Expandable Denomination Calculator + Z-Report Card
                        NusaCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Tutup Shift (Blind Count) & Z-Report',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                                    ),
                                  ),
                                  const NusaBadge(label: 'Audit Anti-Fraud', variant: NusaBadgeVariant.navy),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Hitung fisik uang tunai di laci terlebih dahulu sebelum melihat kas sistem.',
                                style: TextStyle(fontSize: 12, color: AppColors.slate500),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _countedCashCtrl,
                                readOnly: _isBlindCountVerified,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                style: AppTheme.moneyStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                decoration: InputDecoration(
                                  labelText: _isBlindCountVerified
                                      ? 'Uang Tunai Fisik Terkunci (Rp)'
                                      : 'Uang Tunai Fisik Dihitung (Rp)',
                                  hintText: 'Contoh: 1250000',
                                  prefixIcon: Icon(
                                    _isBlindCountVerified ? Icons.lock_rounded : Icons.calculate_outlined,
                                    color: _isBlindCountVerified ? AppColors.successDark : AppColors.primary,
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
                                      onTap: () => setState(() => _showDenomCalculator = !_showDenomCalculator),
                                    ),
                                  ),
                                  if (_showDenomCalculator && !_isBlindCountVerified) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: _resetDenoms,
                                      child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
                                    ),
                                  ],
                                ],
                              ),
                              if (_showDenomCalculator) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    children: _denomCounts.entries.map((entry) {
                                      final denom = entry.key;
                                      final count = entry.value;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: Text(
                                                IdrCurrencyFormatter.format(denom),
                                                style: AppTheme.moneyStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () => _updateDenom(denom, -1),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Container(
                                                width: 40,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: AppColors.border),
                                                ),
                                                child: const Icon(Icons.remove_rounded, size: 17),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 40,
                                              child: Text(
                                                '$count',
                                                textAlign: TextAlign.center,
                                                style: AppTheme.moneyStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () => _updateDenom(denom, 1),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Container(
                                                width: 40,
                                                height: 36,
                                                decoration: BoxDecoration(
                                                  color: AppColors.primarySoft,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                                ),
                                                child: const Icon(Icons.add_rounded, size: 17, color: AppColors.primary),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 4,
                                              child: Align(
                                                alignment: Alignment.centerRight,
                                                child: NusaPriceTag(
                                                  amount: denom * count,
                                                  fontSize: 12,
                                                  color: AppColors.slate600,
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
                              if (!_isBlindCountVerified)
                                NusaButton(
                                  label: 'Verifikasi & Kunci Kasir',
                                  icon: Icons.lock_outline_rounded,
                                  variant: NusaButtonVariant.outline,
                                  onPressed: _countedCashCtrl.text.trim().isEmpty
                                      ? null
                                      : () => setState(() => _isBlindCountVerified = true),
                                )
                              else ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: variance == 0 ? AppColors.successSoft : AppColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: (variance == 0 ? AppColors.success : AppColors.danger).withOpacity(0.35),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Kas Fisik Terkunci:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                          NusaPriceTag(amount: counted, fontSize: 13.5),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Kas Sistem (Expected):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                          NusaPriceTag(amount: _expectedCash, fontSize: 13.5),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            variance == 0
                                                ? 'Status Kas (Balance):'
                                                : (variance > 0
                                                    ? 'Selisih Lebih (Cash Overage):'
                                                    : 'Selisih Kurang (Cash Shortage):'),
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                          ),
                                          NusaPriceTag(
                                            amount: variance.abs(),
                                            prefix: variance > 0 ? '+' : (variance < 0 ? '-' : ''),
                                            fontSize: 15,
                                            color: variance == 0 ? AppColors.successDark : AppColors.danger,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                NusaButton(
                                  label: 'Cetak Struk Z-Report (58mm / 80mm)',
                                  icon: Icons.receipt_long_rounded,
                                  variant: NusaButtonVariant.outline,
                                  onPressed: () => _showThermalZReportDialog(counted),
                                ),
                              ],
                              const SizedBox(height: 12),
                              NusaButton(
                                label: _submitting ? 'Memproses...' : 'Tutup Shift & Kirim Z-Report WA Owner',
                                icon: Icons.send_rounded,
                                isLoading: _submitting,
                                onPressed: (_submitting || !_isBlindCountVerified) ? null : _closeShiftAndSendZReport,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      const Text(
                        'Riwayat Mutasi Kas Laci Shift Ini',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                      ),
                      const SizedBox(height: 8),
                      if (_drawerEntries.isEmpty)
                        const NusaEmptyState(
                          icon: Icons.point_of_sale_outlined,
                          title: 'Belum Ada Mutasi Kas',
                          subtitle: 'Mutasi Kas Masuk, Kas Keluar, atau No-Sale laci akan tercatat di sini.',
                        )
                      else
                        ..._drawerEntries.map((e) {
                          final isIn = e['type'] == 'pay_in';
                          return NusaCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isIn ? AppColors.successSoft : AppColors.dangerSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                                    color: isIn ? AppColors.successDark : AppColors.danger,
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: AppColors.navyDark,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (e['created_at'] ?? '').toString(),
                                        style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                      ),
                                    ],
                                  ),
                                ),
                                NusaPriceTag(
                                  amount: (e['amount'] as num?)?.toDouble() ?? 0,
                                  prefix: isIn ? '+' : '-',
                                  fontSize: 13.5,
                                  color: isIn ? AppColors.successDark : AppColors.danger,
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

  Widget _shiftStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
