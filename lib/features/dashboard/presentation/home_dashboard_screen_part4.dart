// ignore_for_file: invalid_use_of_protected_member
part of 'home_dashboard_screen.dart';

extension _HomeDashboardScreenStatePart4Ext on _HomeDashboardScreenState {

  Widget _buildPeriodPill(String key, String label, NusaThemeTokens tokens) {
    final isSelected = _selectedPeriod == key;
    return InkWell(
      onTap: () {
        if (_selectedPeriod == key) return;
        setState(() {
          _selectedPeriod = key;
        });
        _loadDashboard(period: key);
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? tokens.accent : tokens.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? tokens.accent : tokens.borderSubtle,
            width: tokens.borderWidth,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : tokens.textSecondary,
          ),
        ),
      ),
    );
  }


  Widget _buildExecutivePulseCard(BuildContext context, NusaThemeTokens tokens) {
    final isUp = _growthPercent >= 0;
    final sign = _growthPercent > 0 ? '+' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPeriodPill('month', 'Bulan Ini (MTD)', tokens),
              const SizedBox(width: 6),
              _buildPeriodPill('today', 'Hari Ini', tokens),
              const SizedBox(width: 6),
              _buildPeriodPill('7d', '7 Hari', tokens),
              const SizedBox(width: 6),
              _buildPeriodPill('30d', '30 Hari', tokens),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => context.push('/reports'),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.heroGradientColors,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: tokens.isHighContrast ? null : NusaThemeTokens.of(context).cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _periodTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$_todayTxCount Transaksi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    IdrCurrencyFormatter.format(_todaySales),
                    style: AppTheme.moneyStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                            color: isUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '$sign${_growthPercent.toStringAsFixed(1)}% $_growthLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isUp ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Detail Laporan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded, color: Colors.white, size: 16),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildQuickActionSpeedDial(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
  ) {
    final canPos = MobileWorkspaceResolver.canUsePos(session);
    final canCashWrite = session.isOwner ||
        session.isLocalTrial ||
        MobileWorkspaceResolver.hasAnyPermission(session, const [
          'accounting.petty_cash',
          'expenses.create',
        ]);
    final canCreateProduct = session.isOwner ||
        session.isLocalTrial ||
        MobileWorkspaceResolver.hasAnyPermission(session, const [
          'products.create',
          'products.update',
        ]);
    final canOpname = MobileWorkspaceResolver.canManageInventory(session);

    final actions = [
      if (canPos)
        (
          label: 'Kasir POS',
          icon: Icons.point_of_sale_rounded,
          color: tokens.accent,
          onTap: () => context.push('/pos'),
        ),
      if (canCashWrite)
        (
          label: 'Catat Kas',
          icon: Icons.account_balance_wallet_rounded,
          color: tokens.positive,
          onTap: () => context.push('/cash-ledger'),
        ),
      if (canCreateProduct)
        (
          label: '+ Barang',
          icon: Icons.add_box_rounded,
          color: NusaThemeTokens.of(context).purple,
          onTap: () => widget.onSwitchTab(1),
        ),
      if (canOpname)
        (
          label: 'Scan Opname',
          icon: Icons.qr_code_scanner_rounded,
          color: tokens.warning,
          onTap: () => context.push('/inventory-ops?tab=1'),
        ),
    ];

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'AKSI CEPAT OPERASIONAL',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: tokens.textSecondary,
              ),
            ),
          ),
          Row(
            children: [
              for (final action in actions)
                Expanded(
                  child: InkWell(
                    onTap: action.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: action.color,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(action.icon, color: Colors.white, size: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            action.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildAllModulesBanner(BuildContext context, NusaThemeTokens tokens) {
    return InkWell(
      onTap: () => widget.onSwitchTab(3),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.grid_view_rounded, color: tokens.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semua Fitur & Modul Usaha',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kategori, PO Beli, Retur, Buku Kas, Penawaran, KDS & Toko Online.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Buka →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tokens.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildOperationalMetricsGrid(
    BuildContext context,
    NusaThemeTokens tokens,
    int lowStock,
    int expiring,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.monetization_on_outlined,
                accentColor: tokens.positive,
                label: _grossProfitTitle,
                value: IdrCurrencyFormatter.format(_grossProfit),
                onTap: () => context.push('/reports'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.receipt_long_outlined,
                accentColor: tokens.warning,
                label: 'Piutang Pelanggan (Bon)',
                value: IdrCurrencyFormatter.format(_totalReceivables),
                onTap: () => context.push('/debts'),
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
                icon: Icons.local_shipping_outlined,
                accentColor: tokens.accent,
                label: 'Hutang Supplier Tempo',
                value: IdrCurrencyFormatter.format(_totalPayables),
                onTap: () => context.push('/debts?tab=payables'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildOperationalMetricTile(
                tokens,
                icon: Icons.inventory_2_outlined,
                accentColor: (lowStock + expiring) > 0 ? tokens.danger : NusaThemeTokens.of(context).purple,
                label: 'Stok Menipis & FEFO',
                value: '$lowStock Menipis • $expiring FEFO',
                onTap: () => widget.onSwitchTab(1),
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildOperationalMetricTile(
    NusaThemeTokens tokens, {
    required IconData icon,
    required Color accentColor,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: AppTheme.moneyStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
