import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// FITUR 5 — PUSAT RADAR OPERASIONAL TOKO
/// Menampilkan deteksi proaktif: Approval Manajer, Tugas Toko, Order Online, Konflik Offline,
/// Void & Diskon Besar (> Rp 50.000), Selisih Kasir (Shift Variance),
/// Stok Menipis & FEFO < 30 Hari, serta Piutang Jatuh Tempo dengan tombol WA.
Future<void> showAlertNotificationsModal(
  BuildContext context, {
  required int voidCountFromServer,
  required int varianceShiftsCount,
  required List<Map<String, dynamic>> overdueReceivables,
  required String storeName,
  List<Map<String, dynamic>> approvals = const [],
  List<Map<String, dynamic>> tasks = const [],
  List<Map<String, dynamic>> offlineConflicts = const [],
  int pendingOnlineOrdersCount = 0,
  Future<bool> Function(int approvalId, String decision, {String? notes})? onDecideApproval,
  VoidCallback? onOpenOnlineOrders,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return _OperationalRadarSheet(
        voidCountFromServer: voidCountFromServer,
        varianceShiftsCount: varianceShiftsCount,
        overdueReceivables: overdueReceivables,
        storeName: storeName,
        approvals: approvals,
        tasks: tasks,
        offlineConflicts: offlineConflicts,
        pendingOnlineOrdersCount: pendingOnlineOrdersCount,
        onDecideApproval: onDecideApproval,
        onOpenOnlineOrders: onOpenOnlineOrders,
      );
    },
  );
}

class _OperationalRadarSheet extends StatefulWidget {
  final int voidCountFromServer;
  final int varianceShiftsCount;
  final List<Map<String, dynamic>> overdueReceivables;
  final String storeName;
  final List<Map<String, dynamic>> approvals;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> offlineConflicts;
  final int pendingOnlineOrdersCount;
  final Future<bool> Function(int approvalId, String decision, {String? notes})? onDecideApproval;
  final VoidCallback? onOpenOnlineOrders;

  const _OperationalRadarSheet({
    required this.voidCountFromServer,
    required this.varianceShiftsCount,
    required this.overdueReceivables,
    required this.storeName,
    this.approvals = const [],
    this.tasks = const [],
    this.offlineConflicts = const [],
    this.pendingOnlineOrdersCount = 0,
    this.onDecideApproval,
    this.onOpenOnlineOrders,
  });

  @override
  State<_OperationalRadarSheet> createState() => _OperationalRadarSheetState();
}

class _OperationalRadarSheetState extends State<_OperationalRadarSheet> {
  late List<Map<String, dynamic>> _approvals;
  late List<Map<String, dynamic>> _cloudConflicts;
  final Set<int> _processingApprovalIds = <int>{};
  final Set<String> _processingConflictUuids = <String>{};
  String? _conflictInlineError;
  String? _conflictInlineSuccess;

  @override
  void initState() {
    super.initState();
    _approvals = widget.approvals.map((e) => Map<String, dynamic>.from(e)).toList();
    _cloudConflicts = widget.offlineConflicts.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> _mergeOfflineConflicts(
    List<Map<String, dynamic>> localConflicts,
  ) {
    final byUuid = <String, Map<String, dynamic>>{};
    for (final c in _cloudConflicts) {
      final uuid = (c['local_uuid'] ?? c['client_uuid'] ?? c['id'] ?? '').toString();
      if (uuid.isNotEmpty) {
        final copy = Map<String, dynamic>.from(c);
        copy['cloud_conflict_id'] = (c['id'] as num?)?.toInt();
        byUuid[uuid] = copy;
      }
    }
    for (final c in localConflicts) {
      final uuid = (c['local_uuid'] ?? c['id'] ?? '').toString();
      if (uuid.isNotEmpty) {
        byUuid[uuid] = {
          ...?byUuid[uuid],
          ...Map<String, dynamic>.from(c),
          'is_local_conflict': true,
        };
      }
    }
    return byUuid.values.toList();
  }

  Future<void> _handleResolveCloudConflict(
    int cloudConflictId,
    String key, {
    required String resolution,
  }) async {
    if (_processingConflictUuids.contains(key)) return;
    setState(() {
      _processingConflictUuids.add(key);
      _conflictInlineError = null;
      _conflictInlineSuccess = null;
    });
    final posCubit = context.read<PosCubit>();
    final result = await posCubit.resolveCloudOfflineConflict(
      cloudConflictId,
      resolution: resolution,
      notes: resolution == 'keep_offline'
          ? 'Disetujui fakta transaksi cabang via OXO Mobile POS'
          : 'Menggunakan snapshot Cloud via OXO Mobile POS',
    );
    if (!mounted) return;
    setState(() {
      _processingConflictUuids.remove(key);
      if (result.success) {
        _cloudConflicts.removeWhere((e) => (e['id'] as num?)?.toInt() == cloudConflictId);
        _conflictInlineSuccess = result.message;
      } else {
        _conflictInlineError = result.message;
      }
    });
  }

  Future<void> _handleResolveConflict(
    String uuid, {
    required bool approveOversell,
    bool retryOnly = false,
  }) async {
    if (_processingConflictUuids.contains(uuid)) return;
    setState(() => _processingConflictUuids.add(uuid));
    final posCubit = context.read<PosCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = retryOnly
        ? await posCubit.retryOfflineSyncConflict(uuid)
        : await posCubit.resolveOfflineStockConflict(
            localUuid: uuid,
            approveOversell: approveOversell,
          );
    if (!mounted) return;
    setState(() => _processingConflictUuids.remove(uuid));
    if (retryOnly) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
          content: Text(
            ok
                ? 'Nota offline berhasil disinkronkan ulang ke Cloud.'
                : 'Sinkronisasi ulang masih ditolak server. Pastikan syarat (seperti Shift Kasir) sudah terpenuhi.',
          ),
        ),
      );
    } else if (approveOversell) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
          content: Text(
            ok
                ? 'Oversell disetujui dan nota offline berhasil disinkronkan.'
                : 'Gagal sinkronisasi oversell. Periksa koneksi jaringan cabang.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.warningDark,
          content: Text(
            'Nota offline dibatalkan dari antrean. Lakukan pengembalian dana manual ke pelanggan.',
          ),
        ),
      );
    }
  }

  bool _isTodayIso(dynamic rawDate) {
    final raw = (rawDate ?? '').toString().trim();
    if (raw.isEmpty) return true;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return true;
    final now = DateTime.now();
    return parsed.year == now.year &&
        parsed.month == now.month &&
        parsed.day == now.day;
  }

  Future<void> _handleApprovalDecision(int id, String decision) async {
    if (widget.onDecideApproval == null || _processingApprovalIds.contains(id)) {
      return;
    }
    setState(() => _processingApprovalIds.add(id));
    final ok = await widget.onDecideApproval!(id, decision);
    if (!mounted) return;
    setState(() {
      _processingApprovalIds.remove(id);
      if (ok) {
        _approvals.removeWhere((a) => (a['id'] as num?)?.toInt() == id);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.successDark : AppColors.danger,
        content: Text(
          ok
              ? (decision == 'approved'
                  ? 'Permintaan otorisasi disetujui.'
                  : 'Permintaan otorisasi ditolak.')
              : 'Gagal memproses keputusan otorisasi.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posState = context.watch<PosCubit>().state;

    final List<Map<String, dynamic>> voidOrLargeDiscounts = posState.salesHistory
        .where((sale) {
          final isVoid =
              (sale['status'] ?? '').toString().toUpperCase() == 'VOID' ||
              (sale['status'] ?? '').toString().toUpperCase() == 'VOIDED';
          final discount = ((sale['discount_total'] ??
                  sale['discount_amount'] ??
                  sale['discount'] ??
                  0) as num)
              .toDouble();
          final dateVal = sale['created_at'] ?? sale['sold_at'] ?? sale['date'];
          return _isTodayIso(dateVal) && (isVoid || discount > 50000);
        })
        .toList();

    final List<ProductModel> inventoryAlerts = posState.allProducts
        .where((p) => p.isLowStock || p.hasExpiringSoonBatch)
        .toList();
    final List<Map<String, dynamic>> mergedOfflineConflicts =
        _mergeOfflineConflicts(posState.localSyncConflicts);

    final int totalAlerts = _approvals.length +
        widget.tasks.length +
        mergedOfflineConflicts.length +
        widget.pendingOnlineOrdersCount +
        voidOrLargeDiscounts.length +
        widget.voidCountFromServer +
        widget.varianceShiftsCount +
        inventoryAlerts.length +
        widget.overdueReceivables.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final tokens = NusaThemeTokens.of(context);
        return Container(
          decoration: BoxDecoration(
            color: tokens.bgPage,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.borderDefault,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: totalAlerts > 0 ? tokens.dangerSoft : tokens.positiveSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.radar_rounded,
                        color: totalAlerts > 0 ? tokens.danger : tokens.positive,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pusat Radar Operasional Toko',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          Text(
                            totalAlerts > 0
                                ? '$totalAlerts item operasional & peringatan perlu perhatian'
                                : 'Seluruh indikator operasional toko terpantau aman',
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: tokens.textPrimary),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    if (_approvals.isNotEmpty) ...[
                      _buildApprovalsSection(),
                      const SizedBox(height: 12),
                    ],
                    if (widget.pendingOnlineOrdersCount > 0 ||
                        widget.onOpenOnlineOrders != null) ...[
                      _buildOnlineOrdersSection(context),
                      const SizedBox(height: 12),
                    ],
                    if (widget.tasks.isNotEmpty) ...[
                      _buildTasksSection(),
                      const SizedBox(height: 12),
                    ],
                    if (mergedOfflineConflicts.isNotEmpty) ...[
                      _buildOfflineConflictsSection(mergedOfflineConflicts),
                      const SizedBox(height: 12),
                    ],
                    _buildVoidAndDiscountSection(voidOrLargeDiscounts),
                    const SizedBox(height: 12),
                    _buildCashVarianceSection(context),
                    const SizedBox(height: 12),
                    _buildInventoryAndFefoSection(inventoryAlerts),
                    const SizedBox(height: 12),
                    _buildReceivablesSection(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildApprovalsSection() {
    return _buildSectionCard(
      title: 'Otorisasi & Approval Manajer (${_approvals.length})',
      subtitle: 'Permintaan persetujuan transaksi, biaya, atau pembelian stok',
      icon: Icons.verified_user_outlined,
      accentColor: AppColors.primary,
      softBgColor: AppColors.primarySoft,
      child: Column(
        children: _approvals.take(10).map((ap) {
          final id = (ap['id'] as num?)?.toInt() ?? 0;
          final actionType = (ap['action_type'] ?? ap['approvable_type'] ?? 'Otorisasi').toString();
          final reason = (ap['reason'] ?? 'Menunggu persetujuan').toString();
          final requester = (ap['requested_by'] ?? 'Staf Toko').toString();
          final amount = (ap['amount'] as num?)?.toDouble();
          final busy = _processingApprovalIds.contains(id);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NusaThemeTokens.of(context).bgElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        actionType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (amount != null)
                      Text(
                        IdrCurrencyFormatter.format(amount),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyDark,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: const TextStyle(fontSize: 12, color: AppColors.navyDark, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Pemohon: $requester',
                  style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                ),
                if (widget.onDecideApproval != null && id > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : () => _handleApprovalDecision(id, 'rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.dangerDark,
                            side: const BorderSide(color: AppColors.danger),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Tolak'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: busy ? null : () => _handleApprovalDecision(id, 'approved'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.successDark,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Setujui'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOnlineOrdersSection(BuildContext context) {
    final hasPending = widget.pendingOnlineOrdersCount > 0;
    return _buildSectionCard(
      title: 'Pesanan Toko Online (Webstore)',
      subtitle: 'Pesanan daring menunggu konfirmasi, proses, atau pengiriman',
      icon: Icons.shopping_bag_outlined,
      accentColor: hasPending ? AppColors.primary : AppColors.successDark,
      softBgColor: hasPending ? AppColors.primarySoft : AppColors.successSoft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasPending
                  ? '${widget.pendingOnlineOrdersCount} pesanan online aktif perlu ditindaklanjuti.'
                  : 'Cek & kelola antrean pesanan toko online cabang.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: hasPending ? AppColors.navyDark : AppColors.slate600,
              ),
            ),
          ),
          if (widget.onOpenOnlineOrders != null) ...[
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenOnlineOrders!();
              },
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Kelola Order'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTasksSection() {
    return _buildSectionCard(
      title: 'Tugas Operasional Toko (${widget.tasks.length})',
      subtitle: 'Daftar pekerjaan harian dan eskalasi tim cabang',
      icon: Icons.task_alt_rounded,
      accentColor: AppColors.warningDark,
      softBgColor: AppColors.warningSoft,
      child: Column(
        children: widget.tasks.take(8).map((t) {
          final title = (t['title'] ?? t['name'] ?? 'Tugas Operasional').toString();
          final desc = (t['description'] ?? t['notes'] ?? '').toString();
          final priority = (t['priority'] ?? 'normal').toString().toUpperCase();
          final priorityColor = priority == 'URGENT' || priority == 'HIGH'
              ? AppColors.danger
              : AppColors.warningDark;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                      ),
                      if (desc.isNotEmpty)
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.slate500),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    priority,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: priorityColor),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOfflineConflictsSection(List<Map<String, dynamic>> conflicts) {
    final hasOnlyStockConflicts = conflicts.every((c) {
      final code = (c['conflict_code'] ?? '').toString();
      return code.isEmpty ||
          code == 'InsufficientStock' ||
          code.toLowerCase().contains('stock');
    });
    return _buildSectionCard(
      title: 'Konflik Sinkronisasi Offline (${conflicts.length})',
      subtitle: hasOnlyStockConflicts
          ? 'Transaksi offline yang terblokir akibat stok fisik server habis (InsufficientStock)'
          : 'Transaksi offline tertahan validasi server (mis. Shift Kasir, stok, atau aturan bisnis)',
      icon: Icons.sync_problem_rounded,
      accentColor: AppColors.danger,
      softBgColor: AppColors.danger.withOpacity(0.1),
      child: Column(
        children: [
          if (_conflictInlineError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withOpacity(0.4)),
              ),
              child: Text(
                _conflictInlineError!,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dangerDark,
                ),
              ),
            ),
          if (_conflictInlineSuccess != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.successDark.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.successDark.withOpacity(0.35)),
              ),
              child: Text(
                _conflictInlineSuccess!,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.successDark,
                ),
              ),
            ),
          ...conflicts.take(10).map((c) {
          final uuid = (c['local_uuid'] ?? c['client_uuid'] ?? c['id'] ?? '-').toString();
          final cloudId = (c['cloud_conflict_id'] ?? (c['is_local_conflict'] == true ? null : c['id'])) as num?;
          final saleNumber = (c['sale_number'] ??
                  (c['server_snapshot'] is Map ? c['server_snapshot']['sale_number'] : null) ??
                  (c['client_payload'] is Map ? c['client_payload']['number'] : null) ??
                  '')
              .toString()
              .trim();
          final reason = (c['conflict_reason'] ??
                  c['reason'] ??
                  (c['server_snapshot'] is Map ? c['server_snapshot']['reason'] : null) ??
                  c['error_message'] ??
                  'Stok fisik di cabang tidak mencukupi saat sinkronisasi')
              .toString();
          final cashier = c['cashier'] is Map
              ? (c['cashier']['name'] ?? 'Kasir').toString()
              : 'Kasir';
          final hasLocalQueueRecord =
              c['is_local_conflict'] == true || c['sync_status'] == 'sync_conflict';
          final conflictCode = (c['conflict_code'] ?? c['conflict_type'] ?? '').toString();
          final isStockConflict = conflictCode.isEmpty ||
              conflictCode == 'InsufficientStock' ||
              conflictCode.toLowerCase().contains('stock') ||
              conflictCode.toLowerCase().contains('oversold');
          final isProcessing = _processingConflictUuids.contains(uuid);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.danger.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        saleNumber.isNotEmpty
                            ? '$saleNumber • $cashier'
                            : 'Nota Offline #$uuid • $cashier',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyDark,
                        ),
                      ),
                    ),
                    if (conflictCode.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          conflictCode.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dangerDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.dangerDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasLocalQueueRecord) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            foregroundColor: AppColors.dangerDark,
                            side: BorderSide(color: AppColors.danger.withOpacity(0.45)),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () => _handleResolveConflict(uuid, approveOversell: false),
                          child: const Text(
                            'Batalkan & Refund Manual',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            backgroundColor: isStockConflict ? AppColors.warningDark : AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: isProcessing
                              ? null
                              : () => _handleResolveConflict(
                                    uuid,
                                    approveOversell: isStockConflict,
                                    retryOnly: !isStockConflict,
                                  ),
                          child: Text(
                            isProcessing
                                ? 'Memproses...'
                                : (isStockConflict
                                    ? 'Setujui Oversell (Override)'
                                    : 'Coba Sinkron Ulang'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (!isStockConflict &&
                          (conflictCode == 'ShiftRequired' ||
                              reason.toLowerCase().contains('shift'))) ...[
                        const SizedBox(width: 6),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            foregroundColor: AppColors.primaryDark,
                            side: const BorderSide(color: AppColors.primary),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  context.push('/shifts');
                                },
                          child: const Text(
                            'Buka Shift',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (cloudId != null && cloudId.toInt() > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            foregroundColor: AppColors.navyDark,
                            side: BorderSide(color: AppColors.slate400.withOpacity(0.6)),
                          ),
                          onPressed: isProcessing
                              ? null
                              : () => _handleResolveCloudConflict(
                                    cloudId.toInt(),
                                    uuid,
                                    resolution: 'use_server',
                                  ),
                          child: const Text(
                            'Gunakan Snapshot Cloud',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: isProcessing
                              ? null
                              : () => _handleResolveCloudConflict(
                                    cloudId.toInt(),
                                    uuid,
                                    resolution: 'keep_offline',
                                  ),
                          child: Text(
                            isProcessing ? 'Memproses...' : 'Terima Fakta Cabang',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color softBgColor,
    required Widget child,
  }) {
    final tokens = NusaThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: softBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSafePill(String label) {
    final tokens = NusaThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.positiveSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: tokens.positive),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.positive,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoidAndDiscountSection(List<Map<String, dynamic>> items) {
    final totalVoids = items.length + widget.voidCountFromServer;
    final hasAlert = totalVoids > 0;
    return _buildSectionCard(
      title: 'Radar Void & Diskon > Rp 50.000',
      subtitle: 'Audit transaksi batal dan potongan harga besar hari ini',
      icon: Icons.gpp_maybe_rounded,
      accentColor: hasAlert ? AppColors.danger : AppColors.successDark,
      softBgColor: hasAlert ? AppColors.danger.withOpacity(0.1) : AppColors.successSoft,
      child: !hasAlert
          ? _buildSafePill('Aman • Tidak ada void atau diskon > Rp 50.000 hari ini')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.voidCountFromServer > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Server Audit Watch mendeteksi ${widget.voidCountFromServer} transaksi void.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ...items.take(5).map((sale) {
                  final inv = (sale['number'] ?? sale['invoice_number'] ?? sale['code'] ?? 'NOTA').toString();
                  final status = (sale['status'] ?? '').toString().toUpperCase();
                  final discount = ((sale['discount_total'] ??
                          sale['discount_amount'] ??
                          sale['discount'] ??
                          0) as num)
                      .toDouble();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            inv,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ),
                        Text(
                          status == 'VOID'
                              ? 'STATUS VOID'
                              : 'Diskon ${IdrCurrencyFormatter.format(discount)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildCashVarianceSection(BuildContext context) {
    final hasVariance = widget.varianceShiftsCount > 0;
    return _buildSectionCard(
      title: 'Radar Selisih Kasir (Shift Variance)',
      subtitle: 'Pantau perbedaan kas fisik laci dengan catatan sistem',
      icon: Icons.point_of_sale_rounded,
      accentColor: hasVariance ? AppColors.warningDark : AppColors.successDark,
      softBgColor: hasVariance ? AppColors.warningSoft : AppColors.successSoft,
      child: !hasVariance
          ? _buildSafePill('Aman • Tidak ditemukan shift dengan selisih kas')
          : Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.varianceShiftsCount} shift ditutup dengan selisih kas laci.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warningDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/shifts');
                  },
                  child: const Text('Buka Shift & Kas'),
                ),
              ],
            ),
    );
  }

  Widget _buildInventoryAndFefoSection(List<ProductModel> items) {
    final hasAlert = items.isNotEmpty;
    return _buildSectionCard(
      title: 'Radar Stok Menipis & FEFO (< 30 Hari)',
      subtitle: 'Barang mendekati stok minimum atau tanggal kedaluwarsa',
      icon: Icons.inventory_2_rounded,
      accentColor: hasAlert ? AppColors.warningDark : AppColors.successDark,
      softBgColor: hasAlert ? AppColors.warningSoft : AppColors.successSoft,
      child: !hasAlert
          ? _buildSafePill('Aman • Stok produk & tanggal kedaluwarsa terkendali')
          : Column(
              children: items.take(8).map((p) {
                final badgeLabel = p.hasExpiringSoonBatch
                    ? 'FEFO < 30 Hari'
                    : 'Stok Menipis';
                final badgeColor =
                    p.hasExpiringSoonBatch ? AppColors.danger : AppColors.warningDark;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.navyDark,
                              ),
                            ),
                            Text(
                              'SKU: ${p.sku.isEmpty ? '-' : p.sku} • Sisa ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.slate500,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildReceivablesSection(BuildContext context) {
    final hasOverdue = widget.overdueReceivables.isNotEmpty;
    return _buildSectionCard(
      title: 'Radar Piutang Jatuh Tempo',
      subtitle: 'Kirim pengingat tagihan WhatsApp langsung ke pelanggan',
      icon: Icons.receipt_long_rounded,
      accentColor: hasOverdue ? AppColors.danger : AppColors.successDark,
      softBgColor: hasOverdue ? AppColors.danger.withOpacity(0.1) : AppColors.successSoft,
      child: !hasOverdue
          ? _buildSafePill('Aman • Tidak ada piutang jatuh tempo tertunggak')
          : Column(
              children: widget.overdueReceivables.take(6).map((item) {
                final customer = (item['customer'] as Map?) ?? const {};
                final customerName = (item['customer_name'] ??
                        customer['name'] ??
                        'Pelanggan')
                    .toString();
                final phone = (item['customer_phone'] ??
                        item['phone'] ??
                        customer['phone'] ??
                        '')
                    .toString();
                final invoiceNumber = (item['invoice_number'] ??
                        item['reference'] ??
                        item['code'] ??
                        'BON')
                    .toString();
                final dueDate =
                    (item['due_date'] ?? item['maturity_date'] ?? '-').toString();
                final balance = ((item['balance_due'] ??
                        item['remaining_amount'] ??
                        item['amount'] ??
                        0) as num)
                    .toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(context).bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customerName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                          Text(
                            IdrCurrencyFormatter.format(balance),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nota: $invoiceNumber • Jatuh Tempo: $dueDate',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.slate500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await WhatsAppService.sendDebtReminder(
                                customerName: customerName,
                                customerPhone: phone,
                                invoiceNumber: invoiceNumber,
                                balanceDue: balance,
                                storeName: widget.storeName,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Membuka WhatsApp tagihan untuk $customerName.',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Gagal membuka WhatsApp: $e',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text('Kirim Tagihan WA'),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
