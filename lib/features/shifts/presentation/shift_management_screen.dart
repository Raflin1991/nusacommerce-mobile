import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// MODUL SHIFT KASIR, STRICT BLIND DROP & REKONSILIASI Z-REPORT (`PRD-07` / Gelombang 5)
/// - Strict Blind Drop: server menyembunyikan `expected_cash` bagi kasir non-supervisor
///   selama shift aktif; perhitungan selisih & Z-Report dilakukan 100% di sisi server.
/// - Inline Modal Error Guard pada seluruh dialog/sheet shift & kas laci.
/// - Shimmer Skeleton Loading + CDO Warm Linen (Light / Dark / Outdoor High-Contrast).
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

  void _updateDenom(int denom, int delta) {
    if (_isBlindCountLocked) return;
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
    if (_isBlindCountLocked) return;
    setState(() {
      for (final key in _denomCounts.keys) {
        _denomCounts[key] = 0;
      }
      _countedCashCtrl.clear();
    });
  }

  List<Map<String, String>> _parseVarianceReasons(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      final parsed = <Map<String, String>>[];
      for (final item in raw) {
        if (item is Map) {
          final code = (item['code'] ?? '').toString().trim();
          final name = (item['name'] ?? code).toString().trim();
          if (code.isNotEmpty) {
            parsed.add({'code': code, 'name': name});
          }
        }
      }
      if (parsed.isNotEmpty) return parsed;
    }
    return _varianceReasons;
  }

  void _applyLocalShiftState(Map<String, dynamic>? localShift) {
    if (!mounted) return;
    if (localShift != null) {
      final rawEntries = (localShift['entries'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _hasOpenShift = true;
        _blindDropEnforced = false;
        _canViewExpectedCash = true;
        _shiftId = (localShift['id'] as num?)?.toInt();
        _terminalLabel = 'Kasir Mandiri Lokal';
        _openingCash = (localShift['opening_cash'] as num?)?.toDouble() ?? 0.0;
        _cashSales = (localShift['cash_sales'] as num?)?.toDouble() ?? 0.0;
        _expectedCash = (localShift['expected_cash'] as num?)?.toDouble() ?? 0.0;
        _payIns = (localShift['cash_in'] as num?)?.toDouble() ?? 0.0;
        _payOuts = (localShift['cash_out'] as num?)?.toDouble() ?? 0.0;
        _salesCount = (localShift['sales_count'] as num?)?.toInt() ?? 0;
        _drawerEntries = rawEntries;
        _terminals = [];
        _isBlindCountLocked = false;
        _requiresVarianceReason = false;
        _closeError = null;
        _error = null;
        _loading = false;
      });
    } else {
      setState(() {
        _hasOpenShift = false;
        _shiftId = null;
        _terminalLabel = 'Kasir Mandiri Lokal';
        _openingCash = 0;
        _cashSales = null;
        _expectedCash = null;
        _payIns = 0;
        _payOuts = 0;
        _salesCount = 0;
        _drawerEntries = [];
        _terminals = [];
        _isBlindCountLocked = false;
        _requiresVarianceReason = false;
        _closeError = null;
        _error = null;
        _loading = false;
      });
    }
  }

  Future<void> _loadCurrentShift() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isLocalStandalone) {
      _applyLocalShiftState(_offlineDb.getCurrentLocalShift());
      return;
    }

    try {
      final res = await _api.dio.get(ApiEndpoints.currentShift);
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final hasShift = data['has_open_shift'] == true && data['shift'] != null;
      final terms = (data['terminals'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final reasons = _parseVarianceReasons(data['variance_reasons']);
      final topBlind = data['blind_drop_enforced'] == true;
      final topCanView = data['can_view_expected_cash'] == true;

      if (hasShift) {
        final s = Map<String, dynamic>.from(data['shift'] as Map);
        final term = s['terminal'] as Map?;
        final entries = (s['entries'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final rawExpected = s['expected_cash'];
        final rawCashSales = s['cash_sales'] ?? s['sales_total'];
        final blindDrop = s['blind_drop_enforced'] == true ||
            (topBlind && rawExpected == null);
        final canView = s['can_view_expected_cash'] == true ||
            (topCanView && rawExpected != null);

        if (!mounted) return;
        setState(() {
          _hasOpenShift = true;
          _blindDropEnforced = blindDrop;
          _canViewExpectedCash = canView && rawExpected != null;
          _shiftId = (s['id'] as num?)?.toInt();
          _terminalLabel = (term?['name'] ?? 'POS').toString();
          _openingCash = (s['opening_cash'] as num?)?.toDouble() ?? 0;
          _cashSales =
              canView && rawCashSales is num ? rawCashSales.toDouble() : null;
          _expectedCash =
              canView && rawExpected is num ? rawExpected.toDouble() : null;
          _payIns = (s['pay_ins'] as num?)?.toDouble() ?? 0;
          _payOuts = (s['pay_outs'] as num?)?.toDouble() ?? 0;
          _salesCount = (s['sales_count'] as num?)?.toInt() ?? 0;
          _drawerEntries = entries;
          _terminals = terms;
          _varianceReasons = reasons;
          _isBlindCountLocked = false;
          _requiresVarianceReason = false;
          _closeError = null;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasOpenShift = false;
          _blindDropEnforced = topBlind;
          _canViewExpectedCash = topCanView;
          _shiftId = null;
          _terminals = terms;
          _varianceReasons = reasons;
          _drawerEntries = [];
          _openingCash = 0;
          _cashSales = null;
          _expectedCash = null;
          _payIns = 0;
          _payOuts = 0;
          _salesCount = 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (!ApiClient.isNetworkOfflineError(e)) {
        if (!mounted) return;
        setState(() {
          _error = ApiClient.extractErrorMessage(e);
          _loading = false;
        });
        return;
      }
      _applyLocalShiftState(_offlineDb.getCurrentLocalShift());
    }
  }

  Future<void> _showOpenShiftDialog() async {
    final openCtrl = TextEditingController(text: '500000');
    int? selectedTerminalId = _terminals.isNotEmpty
        ? (_terminals.first['id'] as num?)?.toInt()
        : null;
    String? modalError;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setModalState) {
          final tokens = NusaThemeTokens.of(dCtx);
          return AlertDialog(
            title: const Text('Buka Shift Kasir',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_terminals.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedTerminalId,
                      decoration:
                          const InputDecoration(labelText: 'Terminal Kasir'),
                      items: _terminals
                          .map((t) => DropdownMenuItem<int>(
                                value: (t['id'] as num).toInt(),
                                child: Text((t['name'] ?? 'Terminal').toString()),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => setModalState(() => selectedTerminalId = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: openCtrl,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setModalState(() => modalError = null),
                    decoration: const InputDecoration(
                        labelText: 'Modal Awal Kasir (Rp)'),
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
                          selected: IdrCurrencyFormatter.parse(openCtrl.text) ==
                              double.parse(preset.$2),
                          onTap: () => setModalState(() {
                            openCtrl.text = preset.$2;
                            modalError = null;
                          }),
                        ),
                    ],
                  ),
                  if (modalError != null) ...[
                    const SizedBox(height: 12),
                    _inlineModalErrorBox(tokens, modalError!),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final opening =
                            IdrCurrencyFormatter.parse(openCtrl.text);
                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });
                        try {
                          if (_isLocalStandalone) {
                            await _offlineDb.openLocalShift(
                              openingCash: opening,
                              cashierName:
                                  context.read<AuthCubit>().state.session.userName,
                            );
                          } else {
                            await _api.dio.post(
                              ApiEndpoints.openShift,
                              data: {
                                'opening_cash': opening,
                                if (selectedTerminalId != null)
                                  'terminal_id': selectedTerminalId,
                              },
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadCurrentShift();
                        } catch (e) {
                          if (!ApiClient.isNetworkOfflineError(e)) {
                            setModalState(() {
                              saving = false;
                              modalError = ApiClient.extractErrorMessage(e);
                            });
                            return;
                          }
                          await _offlineDb.openLocalShift(
                            openingCash: opening,
                            cashierName:
                                context.read<AuthCubit>().state.session.userName,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadCurrentShift();
                        }
                      },
                child: Text(saving ? 'Membuka...' : 'Buka Shift'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddCashEntryModal(String type) {
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isIn = type == 'pay_in';
    String? modalError;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) {
          final tokens = NusaThemeTokens.of(mCtx);
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(mCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIn
                      ? 'Catat Kas Masuk Laci (Pay-In)'
                      : 'Catat Kas Keluar Laci (Pay-Out)',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Nominal Uang Tunai (Rp)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: isIn
                        ? 'Keterangan (misal: Tambah receh modal)'
                        : 'Alasan (misal: Beli es batu / galon)',
                  ),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  _inlineModalErrorBox(tokens, modalError!),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isIn ? tokens.positive : tokens.danger,
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                            if (amt <= 0 || reasonCtrl.text.trim().isEmpty) {
                              setModalState(() => modalError =
                                  'Isi nominal (> Rp 0) dan alasan mutasi kas.');
                              return;
                            }
                            setModalState(() {
                              saving = true;
                              modalError = null;
                            });
                            try {
                              if (_isLocalStandalone) {
                                await _offlineDb.addLocalShiftCashEntry(
                                  type: type,
                                  amount: amt,
                                  reason: reasonCtrl.text.trim(),
                                );
                              } else {
                                await _api.dio.post(
                                  ApiEndpoints.cashEntry,
                                  data: {
                                    'shift_id': _shiftId,
                                    'type': type,
                                    'amount': amt,
                                    'reason': reasonCtrl.text.trim(),
                                  },
                                );
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadCurrentShift();
                            } catch (e) {
                              if (!ApiClient.isNetworkOfflineError(e)) {
                                setModalState(() {
                                  saving = false;
                                  modalError = ApiClient.extractErrorMessage(e);
                                });
                                return;
                              }
                              await _offlineDb.addLocalShiftCashEntry(
                                type: type,
                                amount: amt,
                                reason: reasonCtrl.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadCurrentShift();
                            }
                          },
                    child: Text(saving
                        ? 'Menyimpan...'
                        : (isIn ? 'Simpan Kas Masuk' : 'Simpan Kas Keluar')),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _recordNoSaleDrawerOpen() async {
    if (!_hasOpenShift || _submitting) return;
    final reasonCtrl =
        TextEditingController(text: 'Tukar uang kembalian / cek fisik laci');
    String? modalError;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (mCtx, setModalState) {
          final tokens = NusaThemeTokens.of(mCtx);
          return AlertDialog(
            title: const Text('Buka Laci Tanpa Transaksi (No-Sale)',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: reasonCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Alasan Buka Laci (Audit Anti-Fraud)',
                  ),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  _inlineModalErrorBox(tokens, modalError!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dCtx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final reasonText = reasonCtrl.text.trim().isEmpty
                            ? 'Buka laci manual (No-Sale)'
                            : reasonCtrl.text.trim();
                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });
                        try {
                          if (_isLocalStandalone) {
                            await _offlineDb.addLocalShiftCashEntry(
                              type: 'drawer_open_no_sale',
                              amount: 0,
                              reason: reasonText,
                            );
                          } else {
                            await _api.dio.post(
                              ApiEndpoints.cashEntry,
                              data: {
                                'shift_id': _shiftId,
                                'type': 'drawer_open_no_sale',
                                'amount': 0,
                                'reason': reasonText,
                              },
                            );
                          }
                        } catch (e) {
                          if (!ApiClient.isNetworkOfflineError(e)) {
                            setModalState(() {
                              saving = false;
                              modalError = ApiClient.extractErrorMessage(e);
                            });
                            return;
                          }
                          await _offlineDb.addLocalShiftCashEntry(
                            type: 'drawer_open_no_sale',
                            amount: 0,
                            reason: reasonText,
                          );
                        }
                        if (dCtx.mounted) Navigator.pop(dCtx);
                        final kicked = await _printer.kickCashDrawer();
                        await _loadCurrentShift();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor:
                                  kicked ? NusaThemeTokens.of(context).positive : null,
                              content: Text(
                                kicked
                                    ? 'Laci kasir RJ-11 dibuka via Bluetooth & kejadian No-Sale dicatat untuk audit.'
                                    : 'Kejadian No-Sale dicatat untuk audit.',
                              ),
                            ),
                          );
                        }
                      },
                child: Text(saving ? 'Memproses...' : 'Kirim Pulse & Buka'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showThermalZReportDialog(Map<String, dynamic> zReport) {
    final session = context.read<AuthCubit>().state.session;
    final storeProfile = _offlineDb.getStoreProfile();
    String selectedWidth = _printer.paperWidth;

    final openCash = (zReport['opening_cash'] as num?)?.toDouble() ?? _openingCash;
    final cashSales = (zReport['cash_sales'] as num?)?.toDouble() ??
        (zReport['sales_total'] as num?)?.toDouble() ??
        0;
    final payIns = (zReport['pay_ins'] as num?)?.toDouble() ?? _payIns;
    final payOuts = (zReport['pay_outs'] as num?)?.toDouble() ?? _payOuts;
    final expected = (zReport['expected_cash'] as num?)?.toDouble() ?? 0;
    final counted = (zReport['counted_cash'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final tokens = NusaThemeTokens.of(ctx);
          final text = _printer.formatShiftZReportText(
            storeProfile: storeProfile,
            cashierName: session.userName,
            openingCash: openCash,
            cashSalesTotal: cashSales,
            payInTotal: payIns,
            payOutTotal: payOuts,
            expectedCash: expected,
            countedCash: counted,
            paperWidthOverride: selectedWidth,
          );
          return AlertDialog(
            title: Text('Struk Z-Report Thermal ($selectedWidth)',
                style: const TextStyle(fontWeight: FontWeight.w800)),
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
                      color: tokens.bgElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: tokens.borderSubtle, width: tokens.borderWidth),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final ok =
                      await _printer.printReceiptText(text, openCashDrawer: false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: ok ? tokens.positive : tokens.warning,
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
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _closeShiftAndSendZReport() async {
    if (!_hasOpenShift) return;
    if (_countedCashCtrl.text.trim().isEmpty || !_isBlindCountLocked) {
      setState(() {
        _closeError =
            'Masukkan uang fisik di laci dan tekan "Kunci Hitungan Fisik" terlebih dahulu (Strict Blind Drop).';
      });
      return;
    }
    if (_requiresVarianceReason &&
        (_selectedVarianceReason == null || _selectedVarianceReason!.isEmpty)) {
      setState(() {
        _closeError =
            'Server mendeteksi selisih kas di luar toleransi. Pilih alasan selisih untuk menyelesaikan tutup shift.';
      });
      return;
    }

    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    final session = context.read<AuthCubit>().state.session;

    setState(() {
      _submitting = true;
      _closeError = null;
    });

    Map<String, dynamic>? closedZReport;

    try {
      if (_isLocalStandalone) {
        await _offlineDb.closeLocalShift(actualClosingCash: counted);
        final exp = _expectedCash ?? 0;
        final diff = counted - exp;
        closedZReport = {
          'shift_id': _shiftId ?? 0,
          'status': diff.abs() > 0 ? 'closed_with_variance' : 'closed',
          'variance_status':
              diff == 0 ? 'balanced' : (diff > 0 ? 'overage' : 'shortage'),
          'opening_cash': _openingCash,
          'cash_sales': _cashSales ?? 0,
          'sales_total': _cashSales ?? 0,
          'pay_ins': _payIns,
          'pay_outs': _payOuts,
          'expected_cash': exp,
          'counted_cash': counted,
          'cash_variance': diff,
          'cash_shortage': diff < 0 ? diff.abs() : 0.0,
          'cash_overage': diff > 0 ? diff : 0.0,
        };
      } else {
        try {
          // Strict Blind Drop: send ONLY counted physical cash & denominations;
          // server computes authoritative expected_cash & variance.
          final res = await _api.dio.post(
            ApiEndpoints.closeShift,
            data: {
              'shift_id': _shiftId,
              'closing_cash_counted': counted,
              'closing_denominations':
                  _denomCounts.map((k, v) => MapEntry(k.toString(), v)),
              if (_selectedVarianceReason != null &&
                  _selectedVarianceReason!.isNotEmpty)
                'variance_reason': _selectedVarianceReason,
              if (_varianceNotesCtrl.text.trim().isNotEmpty)
                'variance_notes': _varianceNotesCtrl.text.trim(),
            },
          );
          final body = res.data is Map
              ? Map<String, dynamic>.from(res.data as Map)
              : <String, dynamic>{};
          final shiftData = Map<String, dynamic>.from((body['data'] as Map?) ?? {});
          final serverZ = shiftData['z_report'];
          if (serverZ is Map) {
            closedZReport = Map<String, dynamic>.from(serverZ);
          } else {
            final exp = (shiftData['expected_cash'] as num?)?.toDouble() ?? 0.0;
            final v = (shiftData['cash_variance'] as num?)?.toDouble() ?? (counted - exp);
            closedZReport = {
              'shift_id': shiftData['id'] ?? _shiftId,
              'status': shiftData['status'] ?? 'closed',
              'variance_status':
                  v == 0 ? 'balanced' : (v > 0 ? 'overage' : 'shortage'),
              'opening_cash': (shiftData['opening_cash'] as num?)?.toDouble() ?? _openingCash,
              'cash_sales': (shiftData['cash_sales'] as num?)?.toDouble() ??
                  (shiftData['sales_total'] as num?)?.toDouble() ??
                  0.0,
              'sales_total': (shiftData['sales_total'] as num?)?.toDouble() ?? 0.0,
              'pay_ins': (shiftData['pay_ins'] as num?)?.toDouble() ?? _payIns,
              'pay_outs': (shiftData['pay_outs'] as num?)?.toDouble() ?? _payOuts,
              'expected_cash': exp,
              'counted_cash': (shiftData['closing_cash_counted'] as num?)?.toDouble() ?? counted,
              'cash_variance': v,
              'cash_shortage': (shiftData['cash_shortage'] as num?)?.toDouble() ??
                  (v < 0 ? v.abs() : 0.0),
              'cash_overage': (shiftData['cash_overage'] as num?)?.toDouble() ??
                  (v > 0 ? v : 0.0),
            };
          }
        } catch (e) {
          if (!ApiClient.isNetworkOfflineError(e)) {
            if (e is DioException && e.response?.data is Map) {
              final errData = Map<String, dynamic>.from(e.response!.data as Map);
              final needsReason = errData['requires_variance_reason'] == true ||
                  errData['error_code'] == 'VarianceReasonRequired';
              if (needsReason && mounted) {
                setState(() {
                  _requiresVarianceReason = true;
                  _varianceReasons = _parseVarianceReasons(errData['variance_reasons']);
                  _selectedVarianceReason ??= _varianceReasons.first['code'];
                  _closeError = (errData['message'] ??
                          'Terjadi selisih kas di luar toleransi. Pilih alasan selisih untuk menutup shift.')
                      .toString();
                  _submitting = false;
                });
                return;
              }
            }
            if (mounted) {
              setState(() {
                _closeError = ApiClient.extractErrorMessage(e);
                _submitting = false;
              });
            }
            return;
          }
          await _offlineDb.closeLocalShift(actualClosingCash: counted);
        }
      }

      if (closedZReport != null) {
        final ownerPhone = session.activeStore.phone?.trim() ?? '';
        if (ownerPhone.isNotEmpty && ownerPhone != '-') {
          await WhatsAppService.sendShiftZReportToOwner(
            ownerPhone: ownerPhone,
            storeName: session.activeStore.name,
            cashierName: session.userName,
            openingCash: (closedZReport['opening_cash'] as num?)?.toDouble() ?? _openingCash,
            salesTotal: (closedZReport['cash_sales'] as num?)?.toDouble() ?? 0,
            expectedCash: (closedZReport['expected_cash'] as num?)?.toDouble() ?? 0,
            countedCash: (closedZReport['counted_cash'] as num?)?.toDouble() ?? counted,
          );
        }
      }

      if (mounted) {
        _countedCashCtrl.clear();
        _varianceNotesCtrl.clear();
        setState(() {
          _lastClosedZReport = closedZReport;
          _isBlindCountLocked = false;
          _requiresVarianceReason = false;
          _selectedVarianceReason = null;
          _closeError = null;
        });
      }
      await _loadCurrentShift();
    } catch (e) {
      if (!mounted) return;
      setState(() => _closeError = ApiClient.extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _inlineModalErrorBox(NusaThemeTokens tokens, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.dangerSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.danger, width: tokens.borderWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: tokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _buildClosedZReportCard(
    NusaThemeTokens tokens,
    Map<String, dynamic> z,
  ) {
    final expected = (z['expected_cash'] as num?)?.toDouble() ?? 0;
    final counted = (z['counted_cash'] as num?)?.toDouble() ?? 0;
    final variance = (z['cash_variance'] as num?)?.toDouble() ?? (counted - expected);
    final isBalanced = variance.abs() < 0.01;

    return NusaCard(
      key: const Key('shift_z_report_card'),
      borderColor: isBalanced ? tokens.positive : tokens.danger,
      borderWidth: tokens.isHighContrast ? 2.0 : 1.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Ringkasan Z-Report Terverifikasi Server',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              NusaBadge(
                label: isBalanced
                    ? 'BALANCE'
                    : (variance > 0 ? 'OVERAGE' : 'SHORTAGE'),
                variant: isBalanced
                    ? NusaBadgeVariant.success
                    : NusaBadgeVariant.danger,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _zRow(tokens, 'Kas Fisik Dihitung Kasir', counted),
          _zRow(tokens, 'Kas Sistem (Server Expected)', expected),
          Divider(height: 14, color: tokens.borderSubtle),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isBalanced
                      ? 'Selisih Kas (Sesuai):'
                      : (variance > 0 ? 'Selisih Lebih:' : 'Selisih Kurang:'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              NusaPriceTag(
                amount: variance.abs(),
                prefix: variance > 0 ? '+' : (variance < 0 ? '-' : ''),
                fontSize: 15,
                color: isBalanced ? tokens.positive : tokens.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          NusaButton(
            label: 'Cetak Struk Z-Report (58mm / 80mm)',
            icon: Icons.receipt_long_rounded,
            variant: NusaButtonVariant.outline,
            minHeight: 44,
            onPressed: () => _showThermalZReportDialog(z),
          ),
        ],
      ),
    );
  }

  Widget _zRow(NusaThemeTokens tokens, String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          NusaPriceTag(amount: amount, fontSize: 13.5, color: tokens.textPrimary),
        ],
      ),
    );
  }

  Widget _shiftStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
