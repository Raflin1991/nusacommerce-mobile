import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../models/mobile_report_catalog.dart';
import '../services/mobile_report_repository.dart';

/// Mobile-First Report Detail & Drill-Down Viewer supporting all 50 Cloud-parity
/// reports (plus `oversold` audit) with stacked cards, bottom-sheet drill-down,
/// 1-click WhatsApp share, PDF/CSV export, and explicit offline resilience.
class MobileReportDetailScreen extends StatefulWidget {
  final MobileReportDefinition definition;
  final String initialPeriodKey;
  final DateTime? initialCustomStart;
  final DateTime? initialCustomEnd;
  final String initialStoreScope;
  final String initialStoreLabel;
  final List<Map<String, dynamic>> availableStores;

  const MobileReportDetailScreen({
    super.key,
    required this.definition,
    this.initialPeriodKey = '7d',
    this.initialCustomStart,
    this.initialCustomEnd,
    this.initialStoreScope = 'all',
    this.initialStoreLabel = 'Semua Cabang',
    this.availableStores = const [],
  });

  @override
  State<MobileReportDetailScreen> createState() =>
      _MobileReportDetailScreenState();
}

class _MobileReportDetailScreenState extends State<MobileReportDetailScreen> {
  late final MobileReportRepository _repo;
  final TextEditingController _searchCtrl = TextEditingController();

  late String _periodKey;
  DateTime? _customStart;
  DateTime? _customEnd;
  late String _storeScope;
  late String _storeLabel;
  String _searchQuery = '';

  bool _loading = true;
  String? _error;
  MobileReportPayload? _payload;

  @override
  void initState() {
    super.initState();
    _repo = MobileReportRepository(
      api: GetIt.instance<ApiClient>(),
      offlineDb: GetIt.instance<OfflineDatabase>(),
      connectivity: GetIt.instance<NetworkConnectivityService>(),
    );
    _periodKey = widget.initialPeriodKey;
    _customStart = widget.initialCustomStart;
    _customEnd = widget.initialCustomEnd;
    _storeScope = widget.initialStoreScope;
    _storeLabel = widget.initialStoreLabel;
    _loadReport();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final authSession = context.read<AuthCubit>().state.session;
    try {
      final result = await _repo.fetchReport(
        definition: widget.definition,
        periodKey: _periodKey,
        customStart: _customStart,
        customEnd: _customEnd,
        storeScope: _storeScope,
        storeLabel: _storeLabel,
        isLocalTrial: authSession.isLocalTrial,
      );
      if (!mounted) return;
      setState(() {
        _payload = result;
        _loading = false;
      });
    } on MobileReportApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _selectPeriod(String key) async {
    if (key == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        initialDateRange: _customStart != null && _customEnd != null
            ? DateTimeRange(start: _customStart!, end: _customEnd!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 6)),
                end: now,
              ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _periodKey = 'custom';
        _customStart = picked.start;
        _customEnd = picked.end;
      });
      await _loadReport();
      return;
    }

    setState(() {
      _periodKey = key;
      _customStart = null;
      _customEnd = null;
    });
    await _loadReport();
  }

  void _openStorePicker() {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih Cakupan Cabang',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: Icon(Icons.domain_rounded, color: tokens.accent),
                title: Text(
                  'Semua Cabang',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                trailing: _storeScope == 'all'
                    ? Icon(Icons.check_circle_rounded, color: tokens.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _storeScope = 'all';
                    _storeLabel = 'Semua Cabang';
                  });
                  _loadReport();
                },
              ),
              for (final s in widget.availableStores)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(
                    Icons.storefront_rounded,
                    color: tokens.textSecondary,
                  ),
                  title: Text(
                    (s['name'] ?? s['store_name'] ?? 'Cabang').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  trailing: _storeScope == (s['id'] ?? s['store_id']).toString()
                      ? Icon(Icons.check_circle_rounded, color: tokens.accent)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _storeScope = (s['id'] ?? s['store_id']).toString();
                      _storeLabel =
                          (s['name'] ?? s['store_name'] ?? 'Cabang').toString();
                    });
                    _loadReport();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareWhatsApp() async {
    final payload = _payload;
    if (payload == null) return;
    final text = payload.whatsappSummary.trim().isNotEmpty
        ? payload.whatsappSummary
        : MobileReportRepository.buildWhatsAppSummary(
            definition: widget.definition,
            storeLabel: payload.storeLabel,
            periodLabel: payload.periodLabel,
            kpis: payload.kpis,
            items: payload.items,
            isOfflineData: payload.isOfflineData,
            lastSyncLabel: payload.lastSyncLabel,
          );

    await Clipboard.setData(ClipboardData(text: text));
    final opened = await WhatsAppService.shareToAnyChat(text: text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Ringkasan laporan siap dikirim ke WhatsApp (juga disalin ke clipboard).'
              : 'Teks laporan WhatsApp telah disalin ke clipboard.',
        ),
        backgroundColor: AppColors.whatsapp,
      ),
    );
  }

  void _openExportSheet() {
    final payload = _payload;
    if (payload == null) return;
    final tokens = NusaThemeTokens.of(context);
    final isLocalTrial = context.read<AuthCubit>().state.session.isLocalTrial;

    String? sheetError;
    String? sheetSuccess;
    bool busy = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: tokens.borderDefault,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Bagikan & Ekspor Laporan',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${payload.title} • ${payload.periodLabel}',
                  style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                ),
                const SizedBox(height: 14),
                if (sheetError != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tokens.danger.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: tokens.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sheetError!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (sheetSuccess != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.positiveSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tokens.positive.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: tokens.positive, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sheetSuccess!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.positive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildExportActionTile(
                  tokens: tokens,
                  icon: Icons.chat_rounded,
                  iconColor: AppColors.whatsapp,
                  title: 'Kirim Ringkasan via WhatsApp (1-Klik)',
                  subtitle: 'Teks rapi berformat emoji & total Rupiah siap kirim ke grup toko',
                  busy: busy,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _shareWhatsApp();
                  },
                ),
                const SizedBox(height: 8),
                _buildExportActionTile(
                  tokens: tokens,
                  icon: Icons.picture_as_pdf_rounded,
                  iconColor: AppColors.danger,
                  title: 'Ekspor PDF Ringkas (A4)',
                  subtitle: payload.isOfflineData || isLocalTrial
                      ? 'Perlu koneksi Cloud untuk render PDF A4 resmi'
                      : 'Unduh PDF resmi berlogo OXO.ID dari server Cloud',
                  busy: busy,
                  onTap: () async {
                    if (payload.isOfflineData || isLocalTrial) {
                      setModalState(() {
                        sheetError =
                            'Ekspor PDF A4 memerlukan koneksi Cloud. Gunakan ekspor CSV atau bagikan via WhatsApp saat offline.';
                        sheetSuccess = null;
                      });
                      return;
                    }
                    setModalState(() {
                      busy = true;
                      sheetError = null;
                      sheetSuccess = null;
                    });
                    try {
                      final res = await _repo.downloadServerPdf(
                        definition: widget.definition,
                        periodKey: _periodKey,
                        customStart: _customStart,
                        customEnd: _customEnd,
                        storeScope: _storeScope,
                      );
                      setModalState(() {
                        busy = false;
                        sheetSuccess = res.filePath != null
                            ? 'PDF berhasil disimpan (${(res.byteLength / 1024).toStringAsFixed(1)} KB): ${res.filePath}'
                            : 'PDF berhasil diunduh (${res.filename}, ${(res.byteLength / 1024).toStringAsFixed(1)} KB).';
                      });
                    } catch (e) {
                      setModalState(() {
                        busy = false;
                        sheetError = ApiClient.extractErrorMessage(e);
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildExportActionTile(
                  tokens: tokens,
                  icon: Icons.table_view_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Ekspor CSV / Excel (Aman Formula)',
                  subtitle: 'Simpan file .csv (UTF-8 BOM) & salin isi ke clipboard',
                  busy: busy,
                  onTap: () async {
                    setModalState(() {
                      busy = true;
                      sheetError = null;
                      sheetSuccess = null;
                    });
                    try {
                      final res = await _repo.exportCsvFile(payload);
                      if (res.textContent != null) {
                        await Clipboard.setData(
                          ClipboardData(text: res.textContent!),
                        );
                      }
                      setModalState(() {
                        busy = false;
                        sheetSuccess = res.filePath != null
                            ? 'CSV tersimpan di ${res.filePath} & disalin ke clipboard.'
                            : 'Data CSV (${res.filename}) berhasil disalin ke clipboard.';
                      });
                    } catch (e) {
                      setModalState(() {
                        busy = false;
                        sheetError = 'Gagal membuat file CSV: $e';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportActionTile({
    required NusaThemeTokens tokens,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tokens.textTertiary),
          ],
        ),
      ),
    );
  }

  void _openItemDrillDown(MobileReportRowItem item) {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: tokens.borderDefault,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.badge != null && item.badge!.isNotEmpty)
                      _buildToneBadge(tokens, item.badge!, item.badgeTone),
                  ],
                ),
                if (item.primaryValue.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.accent.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Nilai Utama',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.textSecondary,
                          ),
                        ),
                        Text(
                          item.primaryValue,
                          style: AppTheme.moneyStyle(
                            fontSize: 16,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in item.details.entries)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: tokens.borderSubtle),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 6,
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.right,
                                  style: AppTheme.moneyStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final summary = [
                            '📌 *${widget.definition.title}*',
                            'Item: ${item.title}',
                            ...item.details.entries
                                .map((e) => '• ${e.key}: ${e.value}'),
                          ].join('\n');
                          await Clipboard.setData(ClipboardData(text: summary));
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Rincian disalin ke clipboard.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text('Salin'),
                      ),
                    ),
                    if (item.phone != null && item.phone!.trim().isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.whatsapp,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await WhatsAppService.sendCustomMessage(
                              phone: item.phone!,
                              text:
                                  'Halo ${item.title}, terkait ${widget.definition.title} (${item.primaryValue}), mohon konfirmasinya. Terima kasih.',
                            );
                          },
                          icon: const Icon(Icons.chat_rounded, size: 17),
                          label: const Text('Hubungi WA'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _toneColor(NusaThemeTokens tokens, String tone) {
    switch (tone) {
      case 'positive':
        return tokens.positive;
      case 'warning':
        return tokens.warning;
      case 'danger':
        return tokens.danger;
      default:
        return tokens.textSecondary;
    }
  }

  Color _toneSoftBg(NusaThemeTokens tokens, String tone) {
    switch (tone) {
      case 'positive':
        return tokens.positiveSoft;
      case 'warning':
        return tokens.warningSoft;
      case 'danger':
        return tokens.dangerSoft;
      default:
        return tokens.bgElevated;
    }
  }

  Widget _buildToneBadge(NusaThemeTokens tokens, String text, String tone) {
    final fg = _toneColor(tokens, tone);
    final bg = _toneSoftBg(tokens, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final payload = _payload;
    final filteredItems = (payload?.items ?? const <MobileReportRowItem>[])
        .where((i) => i.matchesSearch(_searchQuery))
        .toList();

    final dateRangeInfo = MobileReportRepository.resolveDateRange(
      _periodKey,
      customStart: _customStart,
      customEnd: _customEnd,
    );

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.definition.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: tokens.textPrimary,
              ),
            ),
            Text(
              '$_storeLabel • ${dateRangeInfo.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bagikan ke WhatsApp (1-Klik)',
            onPressed: payload == null ? null : _shareWhatsApp,
            icon: const Icon(Icons.share_rounded, color: AppColors.whatsapp),
          ),
          IconButton(
            tooltip: 'Ekspor PDF / CSV',
            onPressed: payload == null ? null : _openExportSheet,
            icon: Icon(Icons.download_rounded, color: tokens.accent),
          ),
          IconButton(
            tooltip: 'Muat Ulang',
            onPressed: _loadReport,
            icon: Icon(Icons.refresh_rounded, color: tokens.textSecondary),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Global Control Bar (Store + Quick Date Range + In-Report Search)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _openStorePicker,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 42),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.bgSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: tokens.borderSubtle,
                                  width: tokens.borderWidth,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.storefront_rounded,
                                    size: 16,
                                    color: tokens.accent,
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      _storeLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: tokens.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: payload == null ? null : _shareWhatsApp,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.whatsapp.withOpacity(0.12),
                            foregroundColor: AppColors.whatsapp,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text(
                            'WA 1-Klik',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 35,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final p in const [
                            ('today', 'Hari Ini'),
                            ('yesterday', 'Kemarin'),
                            ('7d', '7 Hari Terakhir'),
                            ('30d', '30 Hari'),
                            ('month', 'Bulan Ini'),
                            ('last_month', 'Bulan Lalu'),
                            ('custom', 'Kustom Kalender'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: NusaPillFilter(
                                label: p.$1 == 'custom' && _periodKey == 'custom'
                                    ? dateRangeInfo.label
                                    : p.$2,
                                selected: _periodKey == p.$1,
                                onTap: () => _selectPeriod(p.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Cari di dalam ${widget.definition.title}...',
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: tokens.textTertiary,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: tokens.textTertiary,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: tokens.bgSurface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.borderSubtle),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.borderSubtle),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tokens.accent, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Offline Data Banner
            if (payload != null && payload.isOfflineData)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.warningSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.warning.withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 17,
                          color: tokens.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Data Offline (Sinkronisasi Terakhir: ${payload.lastSyncLabel ?? '-'})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 3. Error State (Online 401/403/422/500 — NEVER masked)
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                  child: NusaCard(
                    backgroundColor: tokens.dangerSoft,
                    borderColor: tokens.danger.withOpacity(0.35),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: tokens.danger),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: tokens.danger,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadReport,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 4. Loading State
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
              )
            else if (payload != null) ...[
              // 5. Offline Notice for Cloud-exclusive GL/Tax Reports
              if (payload.offlineNotice != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                    child: NusaCard(
                      backgroundColor: tokens.bgSurface,
                      borderColor: tokens.borderSubtle,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: tokens.accent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              payload.offlineNotice!,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 6. Dynamic KPI Summary Cards
              if (payload.kpis.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        final cols = constraints.maxWidth >= 700 ? 4 : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: payload.kpis.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: cols == 4 ? 2.1 : 1.95,
                          ),
                          itemBuilder: (_, idx) =>
                              _buildKpiCard(tokens, payload.kpis[idx]),
                        );
                      },
                    ),
                  ),
                ),

              // 7. Compact Visual Distribution Bars for Top Contributors
              if (_shouldShowVisualBars(filteredItems))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: _buildTopBarsCard(tokens, filteredItems),
                  ),
                ),

              // 8. Section Header + Row Count
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Rincian Data (${filteredItems.length})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Ketuk baris untuk rincian',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tokens.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 9. Stacked Mobile-First Cards
              if (filteredItems.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                    child: NusaCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 38,
                              color: tokens.textTertiary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Tidak ada data yang cocok dengan "$_searchQuery".'
                                  : 'Belum ada data transaksi pada periode ${payload.periodLabel}.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, idx) =>
                          _buildStackedRowCard(tokens, filteredItems[idx]),
                      childCount: filteredItems.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(NusaThemeTokens tokens, MobileReportKpi kpi) {
    final toneCol = _toneColor(tokens, kpi.tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: toneCol,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              kpi.formatted,
              maxLines: 1,
              style: AppTheme.moneyStyle(
                fontSize: 15.5,
                color: kpi.tone == 'neutral' ? tokens.textPrimary : toneCol,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowVisualBars(List<MobileReportRowItem> items) {
    final numericRows = items
        .where((i) => !i.isSection && !i.isTotal && (i.primaryNumeric ?? 0) > 0)
        .toList();
    return numericRows.length >= 2 && numericRows.length <= 40;
  }

  Widget _buildTopBarsCard(
    NusaThemeTokens tokens,
    List<MobileReportRowItem> items,
  ) {
    final ranked = items
        .where((i) => !i.isSection && !i.isTotal && (i.primaryNumeric ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.primaryNumeric ?? 0).compareTo(a.primaryNumeric ?? 0));
    final top5 = ranked.take(5).toList();
    final maxVal = top5.first.primaryNumeric ?? 1.0;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top ${top5.length} Kontributor Terbesar',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final row in top5) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  row.primaryValue,
                  style: AppTheme.moneyStyle(
                    fontSize: 12,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ((row.primaryNumeric ?? 0) / (maxVal <= 0 ? 1 : maxVal))
                    .clamp(0.03, 1.0),
                minHeight: 6,
                backgroundColor: tokens.bgElevated,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildStackedRowCard(
    NusaThemeTokens tokens,
    MobileReportRowItem item,
  ) {
    if (item.isSection) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Text(
          item.title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: tokens.accent,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openItemDrillDown(item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: item.isTotal ? tokens.accentSoft : tokens.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isTotal
                  ? tokens.accent.withOpacity(0.35)
                  : tokens.borderSubtle,
              width: tokens.borderWidth,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            item.isTotal ? FontWeight.w800 : FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    if (item.badge != null && item.badge!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildToneBadge(tokens, item.badge!, item.badgeTone),
                    ],
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.primaryValue.isNotEmpty)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          item.primaryValue,
                          maxLines: 1,
                          style: AppTheme.moneyStyle(
                            fontSize: 13.5,
                            color: item.isTotal ? tokens.accent : tokens.textPrimary,
                          ),
                        ),
                      ),
                    if (item.secondaryValue != null &&
                        item.secondaryValue!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.secondaryValue!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: tokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
