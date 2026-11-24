// ignore_for_file: invalid_use_of_protected_member
part of 'home_dashboard_screen.dart';

extension _HomeDashboardScreenStatePart3Ext on _HomeDashboardScreenState {

  Widget _buildCopilotBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    MobileWorkspaceRole ws,
  ) {
    return NusaCard(
      onTap: () => _openCopilot(session),
      backgroundColor: tokens.accentSoft,
      borderColor: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: tokens.accentGradientColors),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tanya OXORA Copilot AI (Chat & Suara)',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ws == MobileWorkspaceRole.posFastLane
                      ? 'Cek stok produk, jumlah transaksi Anda & tugas kasir lewat suara/chat.'
                      : 'Ringkas omzet, stok kritis, approval & operasional cabang instan.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.mic_none_rounded, size: 20, color: tokens.accentDark),
        ],
      ),
    );
  }


  List<Map<String, dynamic>> _mergedOfflineConflicts(
    List<Map<String, dynamic>> localConflicts,
  ) {
    final byUuid = <String, Map<String, dynamic>>{};
    for (final c in _offlineConflictsList) {
      final uuid = (c['local_uuid'] ?? c['id'] ?? '').toString();
      if (uuid.isNotEmpty) byUuid[uuid] = Map<String, dynamic>.from(c);
    }
    for (final c in localConflicts) {
      final uuid = (c['local_uuid'] ?? c['id'] ?? '').toString();
      if (uuid.isNotEmpty) {
        byUuid[uuid] = {
          ...?byUuid[uuid],
          ...Map<String, dynamic>.from(c),
        };
      }
    }
    return byUuid.values.toList();
  }


  Widget _buildSyncConflictBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    return GestureDetector(
      onTap: () {
        showAlertNotificationsModal(
          context,
          voidCountFromServer: _voidCount,
          varianceShiftsCount: _varianceShiftsCount,
          overdueReceivables: _overdueReceivables,
          storeName: session.activeStore.name.isEmpty
              ? 'OXORA POS'
              : session.activeStore.name,
          approvals: _approvalsList,
          tasks: _tasksList,
          offlineConflicts: mergedConflicts,
          pendingOnlineOrdersCount: _pendingOnlineOrdersCount,
          onDecideApproval: _decideApproval,
          onOpenOnlineOrders: () => _showOnlineOrdersSheet(context),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.dangerSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tokens.danger.withOpacity(tokens.isHighContrast ? 1.0 : 0.5),
            width: tokens.borderWidth,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.danger.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.sync_problem_rounded, color: tokens.danger, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    posState.localSyncConflicts.every((c) {
                      final code = (c['conflict_code'] ?? '').toString();
                      return code.isEmpty ||
                          code == 'InsufficientStock' ||
                          code.toLowerCase().contains('stock');
                    })
                        ? '${posState.localSyncConflicts.length} Konflik Stok Sinkronisasi Offline'
                        : '${posState.localSyncConflicts.length} Nota Offline Tertahan Validasi',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: tokens.danger,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    posState.localSyncConflicts.every((c) {
                      final code = (c['conflict_code'] ?? '').toString();
                      return code.isEmpty ||
                          code == 'InsufficientStock' ||
                          code.toLowerCase().contains('stock');
                    })
                        ? 'Stok habis di server saat sinkronisasi. Ketuk untuk tindak lanjut.'
                        : 'Transaksi offline ditolak server (mis. Shift Kasir / validasi). Ketuk untuk tindak lanjut.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: tokens.danger),
          ],
        ),
      ),
    );
  }


  Widget _buildErrorBanner(
    BuildContext context,
    NusaThemeTokens tokens,
    int activeStoreId,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.dangerSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.danger, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: tokens.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: tokens.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _loadDashboard(storeId: activeStoreId),
                child: const Text('Muat Ulang', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final posCubit = context.read<PosCubit>();
                  await context.read<AuthCubit>().logout();
                  await posCubit.resetForLogout();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.danger,
                  side: BorderSide(color: tokens.danger),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Login Ulang', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildTopHeader(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    int offlinePendingCount,
    int badgeCount,
    int activeStoreId,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final storeName = session.activeStore.name.isEmpty
        ? 'OXORA POS'
        : session.activeStore.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: widget.onOpenDrawer,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                ),
                child: Icon(Icons.menu_rounded, size: 22, color: tokens.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _showBranchSwitcherModal(context, tokens, session),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront_rounded, size: 15, color: tokens.accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          session.activeStore.name.isEmpty
                              ? 'Cabang Aktif'
                              : session.activeStore.name,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: tokens.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const Key('home_copilot_button'),
              tooltip: 'OXORA Copilot AI',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openCopilot(session),
              icon: Icon(Icons.auto_awesome_rounded, size: 21, color: tokens.accent),
            ),
            IconButton(
              tooltip: 'Muat ulang dasbor',
              visualDensity: VisualDensity.compact,
              onPressed: _loading ? null : () => _loadDashboard(storeId: activeStoreId),
              icon: Icon(Icons.refresh_rounded, size: 21, color: tokens.textSecondary),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Pusat Radar Operasional Toko',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showAlertNotificationsModal(
                      context,
                      voidCountFromServer: _voidCount,
                      varianceShiftsCount: _varianceShiftsCount,
                      overdueReceivables: _overdueReceivables,
                      storeName: storeName,
                      approvals: _approvalsList,
                      tasks: _tasksList,
                      offlineConflicts: mergedConflicts,
                      pendingOnlineOrdersCount: _pendingOnlineOrdersCount,
                      onDecideApproval: _decideApproval,
                      onOpenOnlineOrders: () => _showOnlineOrdersSheet(context),
                    );
                  },
                  icon: Icon(Icons.notifications_none_rounded, size: 23, color: tokens.textPrimary),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: tokens.danger,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        BlocBuilder<PosCubit, PosState>(
          builder: (ctx, posState) {
            final effectivePending = posState.offlinePendingCount > 0
                ? posState.offlinePendingCount
                : offlinePendingCount;
            return NusaSyncStatusPill(
              isOnline: posState.isOnline,
              isSyncing: posState.isSyncingOfflineQueue,
              offlinePendingCount: effectivePending,
              onTap: () async {
                final cubit = ctx.read<PosCubit>();
                final synced = await cubit.syncOfflineTransactions();
                if (!ctx.mounted) return;
                if (synced > 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      backgroundColor: NusaThemeTokens.of(ctx).positive,
                      content: Text('$synced nota offline berhasil disinkronkan ke Cloud.'),
                    ),
                  );
                } else if (cubit.state.localSyncConflicts.isNotEmpty) {
                  showAlertNotificationsModal(
                    ctx,
                    voidCountFromServer: _voidCount,
                    varianceShiftsCount: _varianceShiftsCount,
                    overdueReceivables: _overdueReceivables,
                    storeName: storeName,
                    approvals: _approvalsList,
                    tasks: _tasksList,
                    offlineConflicts: _mergedOfflineConflicts(cubit.state.localSyncConflicts),
                    pendingOnlineOrdersCount: _pendingOnlineOrdersCount,
                    onDecideApproval: _decideApproval,
                    onOpenOnlineOrders: () => _showOnlineOrdersSheet(ctx),
                  );
                }
              },
            );
          },
        ),
      ],
    );
  }


  Widget _buildOperatorStrip(
    NusaThemeTokens tokens,
    AuthSessionModel session,
    String displayName,
    MobileWorkspaceRole workspace,
  ) {
    final storeCode = session.activeStore.code.isEmpty ? '-' : session.activeStore.code;
    final wsSpec = MobileWorkspaceResolver.specFor(workspace);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(wsSpec.icon, size: 20, color: tokens.accentDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selamat bertugas, $displayName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${wsSpec.title} • ${session.userRole.isEmpty ? 'Operator' : session.userRole} • $storeCode',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                width: tokens.borderWidth,
              ),
            ),
            child: Text(
              (session.planName.isEmpty ? 'Starter' : session.planName).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: tokens.accentDark,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPrimaryActionStrip(
    BuildContext context,
    NusaThemeTokens tokens,
    VerticalCapabilities capabilities,
  ) {
    if (!capabilities.hasTableManagement) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => context.push('/pos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.point_of_sale_rounded, size: 20),
                label: const Text(
                  'Buka Kasir POS',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/shifts'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  backgroundColor: tokens.bgSurface,
                  side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(Icons.lock_clock_outlined, size: 18, color: tokens.positive),
                label: const Text(
                  'Shift Kasir',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/pos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.point_of_sale_rounded, size: 20),
              label: const Text(
                'Buka Kasir POS',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/restaurant'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textPrimary,
                backgroundColor: tokens.bgSurface,
                side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.table_restaurant_outlined, size: 18, color: tokens.accent),
              label: const Text('Meja', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/shifts'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.textPrimary,
                backgroundColor: tokens.bgSurface,
                side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(Icons.lock_clock_outlined, size: 18, color: tokens.positive),
              label: const Text('Shift', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}
