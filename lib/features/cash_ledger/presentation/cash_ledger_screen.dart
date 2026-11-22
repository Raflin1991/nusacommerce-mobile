import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// BUKU KAS & ARUS KAS HARIAN (TUNAI LACI vs REKENING BANK / QRIS)
class CashLedgerScreen extends StatefulWidget {
  const CashLedgerScreen({super.key});

  @override
  State<CashLedgerScreen> createState() => _CashLedgerScreenState();
}

class _CashLedgerScreenState extends State<CashLedgerScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  bool _loading = true;
  String _channel = 'all'; // all, cash, non_cash
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  Future<void> _loadLedger() async {
    setState(() => _loading = true);
    final local = _offlineDb.computeLocalCashLedger(channelFilter: _channel);

    if (!_isLocalStandalone) {
      try {
        final res = await _api.dio.get(
          ApiEndpoints.cashLedger,
          queryParameters: {'channel': _channel},
        );
        final data = res.data['data'];
        if (data is Map) {
          if (!mounted) return;
          setState(() {
            _summary = Map<String, dynamic>.from((data['summary'] as Map?) ?? {});
            _entries = ((data['entries'] as List<dynamic>?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _loading = false;
          });
          return;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _summary = Map<String, dynamic>.from((local['summary'] as Map?) ?? {});
      _entries = ((local['entries'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _loading = false;
    });
  }

  void _openAddCashEntryModal() {
    String direction = 'in'; // in / out
    String channel = 'cash'; // cash / non_cash
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
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
              const Text('Catat Mutasi Buku Kas Manual',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'in', label: Text('Kas Masuk (+)'), icon: Icon(Icons.south_west_rounded)),
                  ButtonSegment(value: 'out', label: Text('Kas Keluar (-)'), icon: Icon(Icons.north_east_rounded)),
                ],
                selected: {direction},
                onSelectionChanged: (s) => setModal(() => direction = s.first),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Kas Tunai (Laci)')),
                  ButtonSegment(value: 'non_cash', label: Text('Bank / QRIS')),
                ],
                selected: {channel},
                onSelectionChanged: (s) => setModal(() => channel = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Keterangan Mutasi (cth: Setoran Modal / Tarik Tunai) *',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal (Rp) *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Catatan Tambahan'),
              ),
              const SizedBox(height: 16),
              if (modalError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.dangerDark, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          modalError!,
                          style: const TextStyle(
                            color: AppColors.dangerDark,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setModal(() => modalError = null),
                        child: const Icon(Icons.close_rounded, color: AppColors.dangerDark, size: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              NusaButton(
                label: 'Simpan ke Buku Kas',
                isLoading: saving,
                icon: Icons.save_rounded,
                onPressed: saving
                    ? null
                    : () async {
                        final title = titleCtrl.text.trim();
                        final amount = IdrCurrencyFormatter.parse(amountCtrl.text);
                        if (title.isEmpty || amount <= 0) {
                          setModal(() => modalError = 'Keterangan mutasi dan nominal (> 0) wajib diisi.');
                          return;
                        }
                        setModal(() {
                          saving = true;
                          modalError = null;
                        });

                        bool cloudOk = false;
                        if (!_isLocalStandalone) {
                          try {
                            await _api.dio.post(ApiEndpoints.cashLedger, data: {
                              'type': direction == 'in' ? 'pay_in' : 'pay_out',
                              'category': channel == 'non_cash' ? 'bank_deposit' : 'other',
                              'reason': notesCtrl.text.trim().isNotEmpty
                                  ? '$title (${notesCtrl.text.trim()})'
                                  : title,
                              'amount': amount,
                            });
                            cloudOk = true;
                          } catch (e) {
                            if (!ApiClient.isNetworkOfflineError(e)) {
                              final errMsg = ApiClient.extractErrorMessage(e);
                              setModal(() {
                                saving = false;
                                modalError = errMsg;
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppColors.danger,
                                    content: Text(errMsg),
                                  ),
                                );
                              }
                              return;
                            }
                          }
                        }
                        if (!cloudOk) {
                          await _offlineDb.addLocalCashEntry(
                            title: title,
                            category: 'Mutasi Manual',
                            direction: direction,
                            channel: channel,
                            methodName: channel == 'cash' ? 'Tunai' : 'Transfer Bank',
                            amount: amount,
                            notes: notesCtrl.text.trim(),
                          );
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _loadLedger();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final totalBalance = (_summary['net_cash_flow'] as num?)?.toDouble() ??
        (_summary['total_balance'] as num?)?.toDouble() ??
        0.0;
    final cashBalance = (_summary['cash_balance'] as num?)?.toDouble() ?? 0.0;
    final bankBalance = (_summary['non_cash_balance'] as num?)?.toDouble() ??
        (_summary['bank_balance'] as num?)?.toDouble() ??
        0.0;
    final totalIn = (_summary['total_in'] as num?)?.toDouble() ?? 0.0;
    final totalOut = (_summary['total_out'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Buku Kas & Arus Kas'),
        actions: [
          IconButton(onPressed: _loadLedger, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddCashEntryModal,
        backgroundColor: tokens.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat Kas'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadLedger,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: tokens.heroGradientColors),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Saldo Kas Bersih Usaha',
                            style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            IdrCurrencyFormatter.format(totalBalance),
                            style: AppTheme.moneyStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Tunai: ${IdrCurrencyFormatter.format(cashBalance)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bank/QRIS: ${IdrCurrencyFormatter.format(bankBalance)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: NusaCard(
                          backgroundColor: tokens.positiveSoft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Uang Masuk',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, color: tokens.positive, fontWeight: FontWeight.w600)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  IdrCurrencyFormatter.format(totalIn),
                                  style: AppTheme.moneyStyle(fontSize: 15, color: tokens.positive),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NusaCard(
                          backgroundColor: tokens.dangerSoft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Uang Keluar',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, color: tokens.danger, fontWeight: FontWeight.w600)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  IdrCurrencyFormatter.format(totalOut),
                                  style: AppTheme.moneyStyle(fontSize: 15, color: tokens.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final c in const [
                        ('all', 'Semua Saluran'),
                        ('cash', 'Tunai'),
                        ('non_cash', 'Bank / QRIS'),
                      ])
                        NusaPillFilter(
                          label: c.$2,
                          selected: _channel == c.$1,
                          onTap: () {
                            setState(() => _channel = c.$1);
                            _loadLedger();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_entries.isEmpty)
                    const NusaEmptyState(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Belum Ada Mutasi Kas',
                      subtitle: 'Penjualan POS, pelunasan bon/hutang, biaya operasional, dan setoran kas akan otomatis tercatat di sini.',
                    )
                  else
                    ..._entries.map((e) {
                      final isIn = e['direction'] == 'in';
                      final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: NusaCard(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  color: isIn ? tokens.positiveSoft : tokens.dangerSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                                  color: isIn ? tokens.positive : tokens.danger,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text((e['title'] ?? '-').toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: tokens.textPrimary)),
                                    Text(
                                      '${e['category'] ?? '-'} • ${e['method_name'] ?? 'Tunai'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                                    ),
                                    Text(
                                      (e['occurred_at'] ?? e['entry_at'] ?? '').toString().replaceFirst('T', ' ').split('.').first,
                                      style: TextStyle(fontSize: 11, color: tokens.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${isIn ? "+" : "-"}${IdrCurrencyFormatter.format(amount)}',
                                style: AppTheme.moneyStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isIn ? tokens.positive : tokens.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
