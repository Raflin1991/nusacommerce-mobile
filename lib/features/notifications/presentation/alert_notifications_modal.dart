import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

part 'alert_notifications_modal_part1.dart';
part 'alert_notifications_modal_part2.dart';

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
    final List<Map<String, dynamic>> nonSaleDeadLetters = posState.deadLetterItems
        .where((d) => (d['entity_type'] ?? '').toString() != 'sale')
        .toList();

    final int totalAlerts = _approvals.length +
        widget.tasks.length +
        mergedOfflineConflicts.length +
        nonSaleDeadLetters.length +
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
                    if (_conflictInlineError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.dangerSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.danger),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: tokens.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _conflictInlineError!,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_conflictInlineSuccess != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tokens.positiveSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.positive),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, color: tokens.positive, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _conflictInlineSuccess!,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.positive),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                    if (nonSaleDeadLetters.isNotEmpty) ...[
                      _buildDeadLetterSection(nonSaleDeadLetters),
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
}
