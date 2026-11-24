import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';

/// MEJA PERSETUJUAN OWNER (APPROVALS DESK — MAKER-CHECKER SOD)
/// Memberikan kendali otorisasi 1-ketuk kepada Owner/Manager untuk permintaan
/// pembatalan nota (void), diskon khusus, transfer gudang, penyesuaian stok, PO, dan biaya.
class OwnerApprovalsScreen extends StatefulWidget {
  const OwnerApprovalsScreen({super.key});

  @override
  State<OwnerApprovalsScreen> createState() => _OwnerApprovalsScreenState();
}

class _OwnerApprovalsScreenState extends State<OwnerApprovalsScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _isOffline = false;
  String? _error;
  String _statusFilter = 'pending';
  String _searchQuery = '';
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadApprovals();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApprovals() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _isOffline = false;
      });
    }

    final session = context.read<AuthCubit>().state.session;
    if (session.isLocalTrial || !(await _connectivity.checkOnline())) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isOffline = true;
        _items = const [];
      });
      return;
    }

    try {
      final params = <String, dynamic>{'status': _statusFilter};
      if (!session.isOwner && session.activeStore.id > 0) {
        params['store_id'] = session.activeStore.id;
      }
      final res = await _api.dio.get(ApiEndpoints.approvals, queryParameters: params);
      final raw = res.data is Map ? res.data['data'] : null;
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) list.add(Map<String, dynamic>.from(item));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isOffline = ApiClient.isNetworkOfflineError(e);
        _error = ApiClient.extractErrorMessage(e);
      });
    }
  }

  String _humanizeActionType(String actionType, String approvableType) {
    final lower = actionType.toLowerCase();
    if (lower.contains('void')) return 'Pembatalan Nota (Void)';
    if (lower.contains('refund') || lower.contains('return')) return 'Retur / Pengembalian Dana';
    if (lower.contains('discount')) return 'Otorisasi Diskon Khusus';
    if (lower.contains('transfer')) return 'Transfer Stok Antar Cabang';
    if (lower.contains('adjust') || lower.contains('opname')) return 'Penyesuaian / Opname Stok';
    if (lower.contains('purchase') || lower.contains('po')) return 'Persetujuan Purchase Order';
    if (lower.contains('expense')) return 'Persetujuan Biaya Operasional';
    if (lower.contains('shift') || lower.contains('variance')) return 'Selisih Tutup Shift Kasir';
    if (lower.contains('payroll')) return 'Otorisasi Payroll (Cloud)';
    if (approvableType.trim().isNotEmpty) return '$approvableType • $actionType';
    return actionType.replaceAll('_', ' ').toUpperCase();
  }

  String _formatTimestamp(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '-';
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return s;
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year} $hh:$min';
  }

  Future<void> _openDecisionSheet(
    BuildContext context,
    Map<String, dynamic> item, {
    required String decision,
  }) async {
    final tokens = NusaThemeTokens.of(context);
    final isApprove = decision == 'approved';
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final title = _humanizeActionType(
      (item['action_type'] ?? '').toString(),
      (item['approvable_type'] ?? '').toString(),
    );
    final amount = (item['amount'] as num?)?.toDouble();
    final notesCtrl = TextEditingController();
    bool submitting = false;
    String? inlineError;

    final decided = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isApprove ? tokens.positiveSoft : tokens.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isApprove ? Icons.verified_rounded : Icons.cancel_outlined,
                        color: isApprove ? tokens.positive : tokens.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isApprove ? 'Setujui Permintaan Otorisasi?' : 'Tolak Permintaan Otorisasi?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                NusaCard(
                  padding: const EdgeInsets.all(12),
                  backgroundColor: tokens.bgElevated,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Pemohon: ${item['requested_by'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: tokens.textPrimary,
                              ),
                            ),
                          ),
                          if (amount != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              IdrCurrencyFormatter.format(amount),
                              style: AppTheme.moneyStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: tokens.accentDark,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if ((item['reason'] ?? '').toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Alasan: ${item['reason']}',
                          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: isApprove ? 'Catatan Persetujuan (Opsional)' : 'Alasan Penolakan (Disarankan)',
                    hintText: isApprove
                        ? 'Contoh: Sudah diverifikasi bersama kepala toko'
                        : 'Contoh: Nominal diskon melebihi batas promo',
                  ),
                ),
                if (inlineError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: tokens.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.danger.withOpacity(0.5)),
                    ),
                    child: Text(
                      inlineError!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.danger,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: submitting
                            ? null
                            : () async {
                                setModalState(() {
                                  submitting = true;
                                  inlineError = null;
                                });
                                try {
                                  final res = await _api.dio.post(
                                    ApiEndpoints.decideApproval(id),
                                    data: {
                                      'decision': decision,
                                      if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
                                    },
                                  );
                                  final body = res.data is Map
                                      ? Map<String, dynamic>.from(res.data as Map)
                                      : <String, dynamic>{};
                                  if (body['success'] == true) {
                                    if (ctx.mounted) Navigator.pop(ctx, true);
                                    return;
                                  }
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      submitting = false;
                                      inlineError = (body['message'] ?? 'Keputusan persetujuan ditolak server.').toString();
                                    });
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      submitting = false;
                                      inlineError = ApiClient.extractErrorMessage(e);
                                    });
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          backgroundColor: isApprove ? tokens.positive : tokens.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(isApprove ? Icons.check_rounded : Icons.close_rounded, size: 18),
                        label: Text(
                          isApprove ? 'Konfirmasi Setujui' : 'Konfirmasi Tolak',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (decided == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isApprove ? tokens.positive : tokens.warning,
          content: Text(
            isApprove
                ? 'Permintaan otorisasi #$id berhasil disetujui.'
                : 'Permintaan otorisasi #$id telah ditolak.',
          ),
        ),
      );
      await _loadApprovals();
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final hay = [
        item['action_type'],
        item['approvable_type'],
        item['requested_by'],
        item['store_name'],
        item['reason'],
        item['status'],
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final session = context.watch<AuthCubit>().state.session;
    final visible = _filteredItems;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        title: const Text('Meja Persetujuan Owner'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang antrean',
            onPressed: _loading ? null : _loadApprovals,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              border: Border(
                bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(fontSize: 13, color: tokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Cari pemohon, cabang, jenis transaksi, atau alasan...',
                    hintStyle: TextStyle(fontSize: 13, color: tokens.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: tokens.textTertiary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18, color: tokens.textSecondary),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: tokens.bgElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final opt in const [
                        ('pending', 'Menunggu'),
                        ('approved', 'Disetujui'),
                        ('rejected', 'Ditolak'),
                        ('all', 'Semua'),
                      ]) ...[
                        NusaPillFilter(
                          label: opt.$2,
                          selected: _statusFilter == opt.$1,
                          onTap: () {
                            if (_statusFilter == opt.$1) return;
                            setState(() => _statusFilter = opt.$1);
                            _loadApprovals();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: tokens.accent,
              onRefresh: _loadApprovals,
              child: _buildBody(context, tokens, session, visible),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    List<Map<String, dynamic>> visible,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: NusaListSkeleton(itemCount: 5),
      );
    }

    if (_isOffline) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NusaCard(
            backgroundColor: tokens.warningSoft,
            borderColor: tokens.warning.withOpacity(0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, color: tokens.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Koneksi Cloud Diperlukan untuk Otorisasi',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Persetujuan Maker-Checker (Void, Diskon, Transfer Stok, PO) membutuhkan verifikasi real-time server OXORA Cloud demi integritas audit SoD.',
                  style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                NusaButton(
                  label: 'Periksa Koneksi & Muat Ulang',
                  icon: Icons.refresh_rounded,
                  minHeight: 44,
                  onPressed: _loadApprovals,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          NusaCard(
            backgroundColor: tokens.dangerSoft,
            borderColor: tokens.danger.withOpacity(0.5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: tokens.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Gagal Memuat Antrean Persetujuan',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: tokens.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12.5, color: tokens.textPrimary),
                ),
                const SizedBox(height: 12),
                NusaButton(
                  label: 'Coba Lagi',
                  icon: Icons.refresh_rounded,
                  minHeight: 44,
                  onPressed: _loadApprovals,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (visible.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          NusaEmptyState(
            icon: Icons.verified_user_outlined,
            title: _statusFilter == 'pending'
                ? 'Tidak Ada Persetujuan Menunggu'
                : 'Belum Ada Riwayat Persetujuan',
            subtitle: _statusFilter == 'pending'
                ? 'Seluruh permintaan otorisasi operasional cabang telah selesai diproses.'
                : 'Ubah filter status atau pencarian untuk melihat catatan otorisasi lainnya.',
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) => _buildApprovalCard(ctx, tokens, session, visible[idx]),
    );
  }

  Widget _buildApprovalCard(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    Map<String, dynamic> item,
  ) {
    final status = (item['status'] ?? 'pending').toString().toLowerCase();
    final isPending = status == 'pending';
    final amount = (item['amount'] as num?)?.toDouble();
    final requestedById = (item['requested_by_id'] as num?)?.toInt();
    final isSelfRequest = requestedById != null && requestedById == session.userId;
    final title = _humanizeActionType(
      (item['action_type'] ?? '').toString(),
      (item['approvable_type'] ?? '').toString(),
    );

    final badgeVariant = status == 'approved'
        ? NusaBadgeVariant.success
        : (status == 'rejected' ? NusaBadgeVariant.danger : NusaBadgeVariant.warning);
    final statusLabel = status == 'approved'
        ? 'DISETUJUI'
        : (status == 'rejected' ? 'DITOLAK' : 'MENUNGGU');

    return NusaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['store_name'] ?? session.activeStore.name} • ${_formatTimestamp(item['created_at'])}',
                      style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NusaBadge(label: statusLabel, variant: badgeVariant),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Pemohon: ${item['requested_by'] ?? 'Staf Cabang'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              if (amount != null)
                Text(
                  IdrCurrencyFormatter.format(amount),
                  style: AppTheme.moneyStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accentDark,
                  ),
                ),
            ],
          ),
          if ((item['reason'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Text(
                (item['reason'] ?? '').toString(),
                style: TextStyle(fontSize: 12, color: tokens.textSecondary),
              ),
            ),
          ],
          if (!isPending && (item['approved_by'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Diputuskan oleh ${item['approved_by']} • ${_formatTimestamp(item['decided_at'])}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 12),
            if (isSelfRequest)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: tokens.warningSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.warning.withOpacity(0.45)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: tokens.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aturan Maker-Checker (SoD): Pemohon tidak dapat menyetujui permintaannya sendiri.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openDecisionSheet(context, item, decision: 'rejected'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        foregroundColor: tokens.danger,
                        side: BorderSide(color: tokens.danger.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Tolak', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => _openDecisionSheet(context, item, decision: 'approved'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        backgroundColor: tokens.positive,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Setujui', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
