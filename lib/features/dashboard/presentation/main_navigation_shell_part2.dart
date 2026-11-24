// ignore_for_file: invalid_use_of_protected_member
part of 'main_navigation_shell.dart';

extension _MainNavigationShellStatePart2Ext on _MainNavigationShellState {

  Widget _buildEnterpriseDrawer(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    MobileWorkspaceRole workspace,
    MobilePrimaryCtaSpec primaryCta,
  ) {
    final capabilities = context.watch<PosCubit>().state.capabilities;
    final themeCubit = _maybeThemeCubit(context);
    final displayName =
        session.userName.trim().isEmpty ? 'Operator OXORA' : session.userName.trim();
    final roleLabel = session.userRole.isEmpty ? 'Operator' : session.userRole;
    final planLabel = session.planName.isEmpty ? 'Starter' : session.planName;
    final canSwitchWorkspaces = MobileWorkspaceResolver.canSwitchWorkspaces(session);
    final canPos = MobileWorkspaceResolver.canUsePos(session);
    final canSalesHistory = MobileWorkspaceResolver.canViewSalesHistory(session);
    final canProducts = MobileWorkspaceResolver.canViewProducts(session);
    final canWarehouse = MobileWorkspaceResolver.canManageInventory(session);
    final canPurchases = MobileWorkspaceResolver.canManagePurchases(session);
    final canCustomers = MobileWorkspaceResolver.canViewCustomers(session);
    final canFinance = MobileWorkspaceResolver.canViewCashLedger(session) ||
        MobileWorkspaceResolver.canViewOwnerDashboard(session);
    final canOnlineStore = MobileWorkspaceResolver.canManageOnlineStore(session);
    final canApprovals = MobileWorkspaceResolver.canViewApprovals(session);
    final spec = MobileWorkspaceResolver.specFor(workspace);

    return Drawer(
      backgroundColor: tokens.bgSurface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 46, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: tokens.heroGradientColors,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 23,
                      backgroundColor: Colors.white24,
                      child: Icon(Icons.person_rounded, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '$roleLabel • ${session.activeStore.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    session.isLocalTrial
                        ? 'Mode Toko Mandiri (Offline Lokal)'
                        : '${spec.title} • ${session.tenantSubdomain.isEmpty ? '-' : '${session.tenantSubdomain}.nusco.id'} ($planLabel)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                BlocBuilder<PosCubit, PosState>(
                  builder: (context, posState) {
                    return NusaSyncStatusPill(
                      isOnline: posState.isOnline,
                      isSyncing: posState.isSyncingOfflineQueue,
                      offlinePendingCount: posState.offlinePendingCount,
                      compact: true,
                      onTap: () => context.read<PosCubit>().syncOfflineTransactions(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(primaryCta.route);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: Icon(primaryCta.icon, size: 18),
                        label: Text(
                          primaryCta.shortLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showNusaCopilotSheet(context, workspace: workspace);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                      label: const Text('AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (canSwitchWorkspaces) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Text(
                      'WORKSPACE PERAN (OWNER / ADMIN)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: MobileWorkspaceResolver.operationalWorkspaces.map((r) {
                        final s = MobileWorkspaceResolver.specFor(r);
                        return NusaPillFilter(
                          label: s.shortTitle,
                          icon: s.icon,
                          selected: r == workspace,
                          onTap: () {
                            Navigator.pop(context);
                            _selectWorkspace(session, r);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  Divider(height: 18, color: tokens.borderSubtle),
                ],

                if (themeCubit != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: Text(
                      'TEMA TAMPILAN (WARM LINEN)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: NusaThemeMode.values.map((m) {
                        return NusaPillFilter(
                          label: m.shortLabel,
                          icon: m.icon,
                          selected: tokens.mode == m,
                          onTap: () => themeCubit.setThemeMode(m),
                        );
                      }).toList(),
                    ),
                  ),
                  Divider(height: 18, color: tokens.borderSubtle),
                ],

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: Text(
                    'OPERASIONAL & BISNIS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),

                if (canPos)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.point_of_sale_outlined,
                    title: 'Kasir & Operasional',
                    initiallyExpanded: true,
                    children: [
                      _drawerSubTile(tokens, 'Layar Kasir POS', () {
                        Navigator.pop(context);
                        context.push('/pos');
                      }),
                      if (capabilities.hasTableManagement) ...[
                        _drawerSubTile(tokens, 'Denah Meja Restoran', () {
                          Navigator.pop(context);
                          context.push('/restaurant');
                        }),
                        _drawerSubTile(tokens, 'Layar Dapur KDS', () {
                          Navigator.pop(context);
                          context.push('/kds');
                        }),
                      ],
                      _drawerSubTile(tokens, 'Shift Kasir & Blind Drop', () {
                        Navigator.pop(context);
                        context.push('/shifts');
                      }),
                    ],
                  ),

                if (canSalesHistory)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.receipt_long_outlined,
                    title: 'Penjualan & Order',
                    children: [
                      _drawerSubTile(tokens, 'Riwayat Transaksi & Retur', () {
                        Navigator.pop(context);
                        _openSalesHistoryTabOrRoute(session, workspace);
                      }),
                      if (MobileWorkspaceResolver.canManageQuotations(session))
                        _drawerSubTile(tokens, 'Surat Penawaran (Quotation)', () {
                          Navigator.pop(context);
                          context.push('/quotations');
                        }),
                    ],
                  ),

                if (canProducts || canWarehouse)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.inventory_2_outlined,
                    title: 'Produk & Katalog',
                    children: [
                      _drawerSubTile(tokens, 'Data Barang & Harga', () {
                        Navigator.pop(context);
                        _openProductsTabOrRoute(session, workspace);
                      }),
                      if (MobileWorkspaceResolver.canManageCatalogTaxonomies(session)) ...[
                        _drawerSubTile(tokens, 'Kategori Produk', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=0');
                        }),
                        _drawerSubTile(tokens, 'Merek / Brand', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=1');
                        }),
                        _drawerSubTile(tokens, 'Satuan / Unit', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=2');
                        }),
                        _drawerSubTile(tokens, 'Cetak Label Barcode', () {
                          Navigator.pop(context);
                          context.push('/catalog-taxonomies?tab=3');
                        }),
                      ],
                    ],
                  ),

                if (canWarehouse)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.warehouse_outlined,
                    title: 'Inventaris & Gudang',
                    children: [
                      _drawerSubTile(tokens, 'Monitor Stok & Menipis', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=0');
                      }),
                      _drawerSubTile(tokens, 'Opname & Penyesuaian Multi-Item', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=1');
                      }),
                      _drawerSubTile(tokens, 'Kartu Mutasi Stok', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=2');
                      }),
                      _drawerSubTile(tokens, 'Batch FEFO & Transfer Cabang', () {
                        Navigator.pop(context);
                        context.push('/inventory-ops?tab=3');
                      }),
                    ],
                  ),

                if (canPurchases)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.shopping_cart_outlined,
                    title: 'Pembelian & Pemasok',
                    children: [
                      _drawerSubTile(tokens, 'Pesanan Beli (PO) Multi-Item', () {
                        Navigator.pop(context);
                        context.push('/purchases?tab=0');
                      }),
                      _drawerSubTile(tokens, 'Retur Pembelian Supplier', () {
                        Navigator.pop(context);
                        context.push('/purchases?tab=1');
                      }),
                      _drawerSubTile(tokens, 'Saran Kulakan AI', () {
                        Navigator.pop(context);
                        context.push('/purchases?tab=2');
                      }),
                      _drawerSubTile(tokens, 'Data Pemasok / Supplier', () {
                        Navigator.pop(context);
                        context.push('/suppliers');
                      }),
                    ],
                  ),

                if (canCustomers)
                  _drawerAccordion(
                    tokens,
                    icon: Icons.groups_outlined,
                    title: 'CRM & Pelanggan',
                    children: [
                      _drawerSubTile(tokens, 'Pelanggan, Member & Grup', () {
                        Navigator.pop(context);
                        context.push('/customers');
                      }),
                    ],
                  ),

                if (canFinance) ...[
                  _drawerAccordion(
                    tokens,
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Kas, Piutang & Pelunasan',
                    children: [
                      _drawerSubTile(tokens, 'Buku Kas & Arus Kas', () {
                        Navigator.pop(context);
                        context.push('/cash-ledger');
                      }),
                      _drawerSubTile(tokens, 'Buku Bon Piutang & Kwitansi', () {
                        Navigator.pop(context);
                        context.push('/debts');
                      }),
                      _drawerSubTile(tokens, 'Hutang Tempo Supplier', () {
                        Navigator.pop(context);
                        context.push('/debts?tab=payables');
                      }),
                      _drawerSubTile(tokens, 'Biaya Operasional Toko', () {
                        Navigator.pop(context);
                        context.push('/debts?tab=expenses');
                      }),
                    ],
                  ),
                ],
                if (canOnlineStore)
                  _drawerTile(
                    tokens,
                    Icons.storefront_outlined,
                    'Toko Online & Pesanan Web',
                    () {
                      Navigator.pop(context);
                      if (session.isModuleGated('online_store')) {
                        showCascadeModuleTeaserModal(
                          context,
                          moduleKey: 'online_store',
                          moduleTitle: 'Toko Online & Katalog Web',
                          requiredTier: 'PRO',
                          currentTier: session.tier,
                          description:
                              'Terima pesanan online dari pelanggan langsung ke kasir POS dengan pemotongan stok otomatis secara real-time.',
                          benefits: const [
                            'Etalase web katalog toko siap pakai 24 jam',
                            'Notifikasi pesanan masuk real-time & cetak resi',
                            'Sinkronisasi stok tunggal antar kasir toko & webstore',
                          ],
                        );
                      } else {
                        context.push('/online-orders');
                      }
                    },
                    isGated: session.isModuleGated('online_store'),
                    requiredTier: 'PRO',
                  ),
                if (MobileWorkspaceResolver.canViewOwnerDashboard(session))
                  _drawerTile(tokens, Icons.analytics_outlined, 'Pusat Laporan Bisnis (50)', () {
                    Navigator.pop(context);
                    context.push('/reports');
                  }),
                if (canApprovals)
                  _drawerTile(tokens, Icons.verified_user_outlined, 'Meja Persetujuan Owner', () {
                    Navigator.pop(context);
                    context.push('/approvals');
                  }),

                Divider(height: 16, color: tokens.borderSubtle),
                _drawerTile(tokens, Icons.settings_outlined, 'Profil Toko, Printer & Tema', () {
                  Navigator.pop(context);
                  context.push('/settings');
                }),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    final posCubit = context.read<PosCubit>();
                    await context.read<AuthCubit>().logout();
                    await posCubit.resetForLogout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.danger,
                    side: BorderSide(color: tokens.danger.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text(
                    'Keluar Sesi (Logout)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _drawerAccordion(
    NusaThemeTokens tokens, {
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        leading: Icon(icon, color: tokens.accent, size: 22),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        childrenPadding: const EdgeInsets.only(left: 24, right: 8, bottom: 4),
        children: children,
      ),
    );
  }


  Widget _drawerSubTile(NusaThemeTokens tokens, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tokens.textSecondary,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, size: 16, color: tokens.textTertiary),
      onTap: onTap,
    );
  }


  Widget _drawerTile(
    NusaThemeTokens tokens,
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isGated = false,
    String requiredTier = 'PRO',
  }) {
    return ListTile(
      leading: Icon(icon, color: isGated ? tokens.textSecondary : tokens.accent),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: isGated ? tokens.textSecondary : tokens.textPrimary,
        ),
      ),
      trailing: isGated
          ? CascadeCrownBadge(requiredTier: requiredTier)
          : Icon(Icons.chevron_right_rounded, size: 18, color: tokens.textTertiary),
      onTap: onTap,
    );
  }
}
