// ignore_for_file: invalid_use_of_protected_member
part of 'home_dashboard_screen.dart';

extension _HomeDashboardScreenStatePart2Ext on _HomeDashboardScreenState {

  Widget _buildPosFastLaneWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final themeCubit = _maybeThemeCubit(context);
    final isOutdoor = tokens.isHighContrast;
    final canCustomers = MobileWorkspaceResolver.canViewCustomers(session);
    final storeName = session.activeStore.name.isEmpty
        ? 'OXORA POS'
        : session.activeStore.name;

    return Column(
      key: const Key('workspace_pos_fast_lane'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.posFastLane),
        const SizedBox(height: 12),

        // Giant Thumb-Zone Primary POS Fast-Lane CTA
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton.icon(
            key: const Key('fast_lane_open_pos_btn'),
            onPressed: () => context.push('/pos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.point_of_sale_rounded, size: 24),
            label: Text(
              'Mulai Transaksi Kasir (${posState.capabilities.posDisplayName})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Strict Blind Drop Shift Status Hero (NEVER shows expected_cash)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _hasOpenShift ? tokens.accentGradientColors : tokens.heroGradientColors,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NusaBadge(
                      label: _hasOpenShift
                          ? 'SHIFT AKTIF • ${_shiftTerminalLabel.isEmpty ? 'POS' : _shiftTerminalLabel}'
                          : 'SHIFT BELUM DIBUKA',
                      variant: _hasOpenShift ? NusaBadgeVariant.success : NusaBadgeVariant.warning,
                    ),
                    if (_shiftBlindDropEnforced)
                      const NusaBadge(
                        label: 'Strict Blind Drop',
                        variant: NusaBadgeVariant.navy,
                        icon: Icons.lock_outline_rounded,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _hasOpenShift
                    ? 'Kas Laci Terkunci (Blind Drop Aktif)'
                    : 'Buka Shift Kasir Sebelum Melayani Pembeli',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _hasOpenShift
                    ? 'Total kas sistem disembunyikan server hingga tutup shift diverifikasi.'
                    : 'Catat modal awal laci kas untuk memulai shift operasional cabang.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/shifts'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.lock_clock_rounded, size: 18),
                  label: Text(
                    _hasOpenShift ? 'Kelola & Tutup Shift (Blind Drop)' : 'Buka Shift Sekarang',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Fast-Lane Status Chips (Held Carts, Offline Queue, High-Contrast Outdoor Toggle)
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.pause_circle_outline_rounded,
                accentColor: tokens.accent,
                label: 'Keranjang Ditahan',
                value: '${posState.heldCarts.length} Transaksi',
                onTap: () => context.push('/pos'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.task_alt_rounded,
                accentColor: tokens.positive,
                label: 'Tugas Cabang',
                value: '$_openTasksCount Terbuka',
                onTap: () => showAlertNotificationsModal(
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
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (themeCubit != null) ...[
          NusaCard(
            onTap: () => themeCubit.toggleOutdoorHighContrast(),
            child: Row(
              children: [
                Icon(
                  Icons.contrast_rounded,
                  color: isOutdoor ? tokens.accent : tokens.textPrimary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode Kontras Tinggi (Outdoor POS)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                      Text(
                        isOutdoor
                            ? 'Aktif — kontras maksimal untuk sinar matahari langsung'
                            : 'Tingkatkan ketajaman huruf & border untuk area terang',
                        style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: isOutdoor,
                  activeColor: tokens.accent,
                  onChanged: (_) => themeCubit.toggleOutdoorHighContrast(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Cashier Fast-Lane Quick Grid (RBAC Safe — NO financial P&L / AP / Approvals)
        NusaCard(
          child: Row(
            children: [
              _fastLaneTile(tokens, Icons.point_of_sale_rounded, 'Kasir POS', () => context.push('/pos')),
              _fastLaneTile(tokens, Icons.lock_clock_rounded, 'Shift', () => context.push('/shifts')),
              _fastLaneTile(tokens, Icons.receipt_long_rounded, 'Riwayat', () => widget.onSwitchTab(2)),
              if (canCustomers)
                _fastLaneTile(tokens, Icons.groups_outlined, 'Pelanggan', () => context.push('/customers'))
              else
                _fastLaneTile(tokens, Icons.inventory_2_outlined, 'Cek Harga', () => widget.onSwitchTab(1)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.posFastLane),
      ],
    );
  }


  Widget _buildWarehouseWorkbenchWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    int lowStock,
    int expiring,
  ) {
    final canPurchases = MobileWorkspaceResolver.canManagePurchases(session);
    final canSuppliers = MobileWorkspaceResolver.canViewSuppliers(session);
    return Column(
      key: const Key('workspace_warehouse_workbench'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.warehouseWorkbench),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/inventory-ops?tab=1'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text(
                    'Scan Opname Stok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
            if (canPurchases) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/purchases?tab=0'),
                    icon: Icon(Icons.local_shipping_outlined, size: 18, color: tokens.positive),
                    label: const Text(
                      'Terima PO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: tokens.heroGradientColors),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Kesehatan Stok Gudang',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NusaBadge(
                    label: '${posState.allProducts.length} SKU',
                    variant: NusaBadgeVariant.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$lowStock Menipis • $expiring Batch FEFO',
                  style: AppTheme.moneyStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$_openTasksCount tugas gudang aktif • $_pendingApprovalsCount persetujuan stok menunggu',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.warehouseWorkbench),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.swap_horiz_rounded,
                accentColor: tokens.accent,
                label: 'Transfer Antar Cabang',
                value: 'Kirim & Terima',
                onTap: () => context.push('/inventory-ops?tab=3'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: canPurchases
                  ? _buildOperationalMetricTile(
                      tokens,
                      icon: Icons.auto_awesome_outlined,
                      accentColor: tokens.positive,
                      label: 'Saran Kulakan AI',
                      value: 'Reorder PO',
                      onTap: () => context.push('/purchases?tab=2'),
                    )
                  : _buildOperationalMetricTile(
                      tokens,
                      icon: Icons.tune_rounded,
                      accentColor: tokens.positive,
                      label: 'Penyesuaian Stok',
                      value: 'Koreksi Gudang',
                      onTap: () => context.push('/inventory-ops?tab=0'),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.swap_vert_rounded,
                accentColor: tokens.warning,
                label: 'Kartu Mutasi Stok',
                value: 'Audit Keluar/Masuk',
                onTap: () => context.push('/inventory-ops?tab=2'),
              ),
            ),
            if (canSuppliers) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _buildOperationalMetricTile(
                  tokens,
                  icon: Icons.business_outlined,
                  accentColor: tokens.textPrimary,
                  label: 'Data Pemasok',
                  value: 'Vendor & PO',
                  onTap: () => context.push('/suppliers'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }


  Widget _buildEmployeeEssWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    String displayName,
  ) {
    final canApprovals = MobileWorkspaceResolver.canViewApprovals(session);
    return Column(
      key: const Key('workspace_employee_ess'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.employeeEss),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: tokens.heroGradientColors),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NusaBadge(
                label: 'PORTAL STAF OPERASIONAL',
                variant: NusaBadgeVariant.primary,
              ),
              const SizedBox(height: 10),
              Text(
                '$_openTasksCount Tugas Cabang Aktif',
                style: AppTheme.moneyStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Administrasi HRD, absensi, slip gaji, PPh 21 & BPJS dikelola secara terpusat di OXORA Cloud Web (/admin).',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (canApprovals) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/approvals'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.verified_user_outlined, size: 20),
                    label: Text(
                      'Meja Persetujuan ($_pendingApprovalsCount Menunggu)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.employeeEss),
        const SizedBox(height: 12),
        Text(
          'Tugas Operasional Anda ($_openTasksCount)',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (_tasksList.isEmpty)
          const NusaEmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'Tidak Ada Tugas Tertunda',
            subtitle: 'Seluruh tugas operasional Anda hari ini dalam status selesai.',
          )
        else
          ..._tasksList.take(5).map(
                (t) => NusaCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.assignment_outlined, color: tokens.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (t['title'] ?? 'Tugas Cabang').toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: tokens.textPrimary,
                              ),
                            ),
                            if (t['description'] != null)
                              Text(
                                t['description'].toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }


  Widget _fastLaneTile(
    NusaThemeTokens tokens,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: tokens.isHighContrast ? tokens.borderDefault : Colors.transparent,
                    width: tokens.borderWidth,
                  ),
                ),
                child: Icon(icon, color: tokens.accentDark, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _compactStatChip(
    NusaThemeTokens tokens, {
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: tokens.textSecondary),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: AppTheme.moneyStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent),
          ),
        ],
      ),
    );
  }
}
