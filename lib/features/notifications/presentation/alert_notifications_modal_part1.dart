// ignore_for_file: invalid_use_of_protected_member
part of 'alert_notifications_modal.dart';

extension _OperationalRadarSheetStatePart1Ext on _OperationalRadarSheetState {

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
          ? 'Disetujui fakta transaksi cabang via OXORA Mobile POS'
          : 'Menggunakan snapshot Cloud via OXORA Mobile POS',
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
    setState(() {
      _processingConflictUuids.add(uuid);
      _conflictInlineError = null;
      _conflictInlineSuccess = null;
    });
    final posCubit = context.read<PosCubit>();
    final ok = retryOnly
        ? await posCubit.retryOfflineSyncConflict(uuid)
        : await posCubit.resolveOfflineStockConflict(
            localUuid: uuid,
            approveOversell: approveOversell,
          );
    if (!mounted) return;
    setState(() {
      _processingConflictUuids.remove(uuid);
      if (retryOnly) {
        if (ok) {
          _conflictInlineSuccess = 'Nota offline berhasil disinkronkan ulang ke Cloud.';
        } else {
          _conflictInlineError =
              'Sinkronisasi ulang masih ditolak server. Pastikan syarat (seperti Shift Kasir) sudah terpenuhi.';
        }
      } else if (approveOversell) {
        if (ok) {
          _conflictInlineSuccess = 'Oversell disetujui dan nota offline berhasil disinkronkan.';
        } else {
          _conflictInlineError = 'Gagal sinkronisasi oversell. Periksa koneksi jaringan cabang.';
        }
      } else {
        _conflictInlineError =
            'Nota offline dibatalkan dari antrean. Lakukan pengembalian dana manual ke pelanggan.';
      }
    });
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
    setState(() {
      _processingApprovalIds.add(id);
      _conflictInlineError = null;
      _conflictInlineSuccess = null;
    });
    final ok = await widget.onDecideApproval!(id, decision);
    if (!mounted) return;
    setState(() {
      _processingApprovalIds.remove(id);
      if (ok) {
        _approvals.removeWhere((a) => (a['id'] as num?)?.toInt() == id);
        _conflictInlineSuccess = decision == 'approved'
            ? 'Permintaan otorisasi disetujui.'
            : 'Permintaan otorisasi ditolak.';
      } else {
        _conflictInlineError = 'Gagal memproses keputusan otorisasi.';
      }
    });
  }


  Widget _buildApprovalsSection() {
    return _buildSectionCard(
      title: 'Otorisasi & Approval Manajer (${_approvals.length})',
      subtitle: 'Permintaan persetujuan transaksi, biaya, atau pembelian stok',
      icon: Icons.verified_user_outlined,
      accentColor: NusaThemeTokens.of(context).accent,
      softBgColor: NusaThemeTokens.of(context).accentSoft,
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
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: NusaThemeTokens.of(context).accent,
                        ),
                      ),
                    ),
                    if (amount != null)
                      Text(
                        IdrCurrencyFormatter.format(amount),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: NusaThemeTokens.of(context).textPrimary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textPrimary, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Pemohon: $requester',
                  style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(context).textSecondary),
                ),
                if (widget.onDecideApproval != null && id > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : () => _handleApprovalDecision(id, 'rejected'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NusaThemeTokens.of(context).danger,
                            side: BorderSide(color: NusaThemeTokens.of(context).danger),
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
                            backgroundColor: NusaThemeTokens.of(context).positive,
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
      accentColor: hasPending ? NusaThemeTokens.of(context).accent : NusaThemeTokens.of(context).positive,
      softBgColor: hasPending ? NusaThemeTokens.of(context).accentSoft : NusaThemeTokens.of(context).positiveSoft,
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
                color: hasPending ? NusaThemeTokens.of(context).textPrimary : NusaThemeTokens.of(context).textSecondary,
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
      accentColor: NusaThemeTokens.of(context).warning,
      softBgColor: NusaThemeTokens.of(context).warningSoft,
      child: Column(
        children: widget.tasks.take(8).map((t) {
          final title = (t['title'] ?? t['name'] ?? 'Tugas Operasional').toString();
          final desc = (t['description'] ?? t['notes'] ?? '').toString();
          final priority = (t['priority'] ?? 'normal').toString().toUpperCase();
          final priorityColor = priority == 'URGENT' || priority == 'HIGH'
              ? NusaThemeTokens.of(context).danger
              : NusaThemeTokens.of(context).warning;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: NusaThemeTokens.of(context).bgPage,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).textPrimary),
                      ),
                      if (desc.isNotEmpty)
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(context).textSecondary),
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
      accentColor: NusaThemeTokens.of(context).danger,
      softBgColor: NusaThemeTokens.of(context).danger.withOpacity(0.1),
      child: Column(
        children: [
          if (_conflictInlineError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NusaThemeTokens.of(context).danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.4)),
              ),
              child: Text(
                _conflictInlineError!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: NusaThemeTokens.of(context).danger,
                ),
              ),
            ),
          if (_conflictInlineSuccess != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NusaThemeTokens.of(context).positive.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.35)),
              ),
              child: Text(
                _conflictInlineSuccess!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: NusaThemeTokens.of(context).positive,
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
              color: NusaThemeTokens.of(context).bgPage,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.35)),
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
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: NusaThemeTokens.of(context).textPrimary,
                        ),
                      ),
                    ),
                    if (conflictCode.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: NusaThemeTokens.of(context).danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          conflictCode.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: NusaThemeTokens.of(context).danger,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: NusaThemeTokens.of(context).danger,
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
                            foregroundColor: NusaThemeTokens.of(context).danger,
                            side: BorderSide(color: NusaThemeTokens.of(context).danger.withOpacity(0.45)),
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
                            backgroundColor: isStockConflict ? NusaThemeTokens.of(context).warning : NusaThemeTokens.of(context).accent,
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
                            foregroundColor: NusaThemeTokens.of(context).accentDark,
                            side: BorderSide(color: NusaThemeTokens.of(context).accent),
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
                            foregroundColor: NusaThemeTokens.of(context).textPrimary,
                            side: BorderSide(color: NusaThemeTokens.of(context).textTertiary.withOpacity(0.6)),
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
                            backgroundColor: NusaThemeTokens.of(context).accent,
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
}
