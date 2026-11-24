// ignore_for_file: invalid_use_of_protected_member
part of 'owner_approvals_screen.dart';

extension _OwnerApprovalsScreenStatePart2Ext on _OwnerApprovalsScreenState {

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
