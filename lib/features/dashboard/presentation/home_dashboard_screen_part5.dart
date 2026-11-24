// ignore_for_file: invalid_use_of_protected_member
part of 'home_dashboard_screen.dart';

extension _HomeDashboardScreenStatePart5Ext on _HomeDashboardScreenState {

  Widget _buildModulesDirectory(
    BuildContext context,
    NusaThemeTokens tokens,
    VerticalCapabilities capabilities,
  ) {
    final session = context.watch<AuthCubit>().state.session;
    final onlineGated = session.isModuleGated('online_store');

    final modules = [
      (
        icon: Icons.point_of_sale_rounded,
        color: tokens.accent,
        title: capabilities.posDisplayName,
        subtitle: capabilities.posSubtitle,
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/pos'),
      ),
      (
        icon: Icons.analytics_outlined,
        color: const Color(0xFF0284C7),
        title: 'Pusat Laporan Bisnis (50)',
        subtitle: '50 laporan paritas Cloud, WA & PDF',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/reports'),
      ),
      (
        icon: Icons.verified_user_outlined,
        color: tokens.warning,
        title: 'Meja Persetujuan Owner',
        subtitle: _pendingApprovalsCount > 0
            ? '$_pendingApprovalsCount permintaan menunggu keputusan'
            : 'Otorisasi Maker-Checker, Void & PO',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/approvals'),
      ),
      (
        icon: Icons.inventory_2_outlined,
        color: NusaThemeTokens.of(context).purple,
        title: 'Katalog & Opname Stok',
        subtitle: 'Produk, HPP, FEFO & kamera',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => widget.onSwitchTab(1),
      ),
      (
        icon: Icons.local_shipping_outlined,
        color: tokens.warning,
        title: 'Pemasok & Stok Masuk',
        subtitle: 'Supplier, rekening & beli stok',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/suppliers?tab=stock-in'),
      ),
      (
        icon: Icons.people_outline_rounded,
        color: tokens.accentDark,
        title: 'Pelanggan & Member',
        subtitle: 'Diskon grup, poin & kasbon',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/customers'),
      ),
      (
        icon: Icons.menu_book_outlined,
        color: tokens.danger,
        title: 'Buku Bon & Biaya Toko',
        subtitle: 'Piutang, hutang & pengeluaran',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/debts'),
      ),
      (
        icon: Icons.lock_clock_outlined,
        color: tokens.positive,
        title: 'Shift Kasir & Z-Report',
        subtitle: 'Kas laci, mutasi & blind count',
        isGated: false,
        requiredTier: 'STARTER',
        onTap: () => context.push('/shifts'),
      ),
      if (capabilities.hasTableManagement)
        (
          icon: Icons.table_restaurant_outlined,
          color: tokens.accentDark,
          title: 'Denah Meja & Resto F&B',
          subtitle: 'Open tab, pindah meja & KOT',
          isGated: false,
          requiredTier: 'STARTER',
          onTap: () => context.push('/restaurant'),
        ),
      (
        icon: Icons.shopping_bag_outlined,
        color: tokens.accent,
        title: 'Pesanan Toko Online',
        subtitle: onlineGated
            ? 'Etalase web & order otomatis'
            : (_pendingOnlineOrdersCount > 0
                ? '$_pendingOnlineOrdersCount pesanan menunggu proses'
                : 'Kelola webstore, status & resi'),
        isGated: onlineGated,
        requiredTier: 'PRO',
        onTap: () {
          if (onlineGated) {
            showCascadeModuleTeaserModal(
              context,
              moduleKey: 'online_store',
              moduleTitle: 'Pesanan Toko Online (Webstore)',
              requiredTier: 'PRO',
              currentTier: session.tier,
              description:
                  'Terima order online pelanggan langsung ke POS dengan potong stok terpusat.',
              benefits: const [
                'Katalog web toko siap pakai dengan subdomain toko',
                'Proses order online & resi langsung dari HP kasir',
                'Terhubung dengan saldo & pelanggan member',
              ],
            );
          } else {
            _showOnlineOrdersSheet(context);
          }
        },
      ),
    ];

    return Column(
      children: [
        for (int i = 0; i < modules.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildModuleDirectoryCard(
                  tokens,
                  icon: modules[i].icon,
                  color: modules[i].color,
                  title: modules[i].title,
                  subtitle: modules[i].subtitle,
                  isGated: modules[i].isGated,
                  requiredTier: modules[i].requiredTier,
                  onTap: modules[i].onTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < modules.length
                    ? _buildModuleDirectoryCard(
                        tokens,
                        icon: modules[i + 1].icon,
                        color: modules[i + 1].color,
                        title: modules[i + 1].title,
                        subtitle: modules[i + 1].subtitle,
                        isGated: modules[i + 1].isGated,
                        requiredTier: modules[i + 1].requiredTier,
                        onTap: modules[i + 1].onTap,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }


  Widget _buildModuleDirectoryCard(
    NusaThemeTokens tokens, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isGated = false,
    String requiredTier = 'PRO',
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isGated ? tokens.warningSoft : tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isGated ? tokens.warning : tokens.borderSubtle,
            width: tokens.borderWidth,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (isGated) ...[
                        const SizedBox(width: 4),
                        CascadeCrownBadge(requiredTier: requiredTier),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.textSecondary,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<bool> _decideApproval(int approvalId, String decision, {String? notes}) async {
    try {
      final res = await _backofficeRepo.decideApproval(
        approvalId,
        {
          'decision': decision,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      if (res.data is Map && res.data['success'] == true) {
        if (mounted) {
          setState(() {
            _approvalsList.removeWhere((a) => (a['id'] as num?)?.toInt() == approvalId);
            _pendingApprovalsCount = _approvalsList.length;
          });
        }
        return true;
      }
    } catch (_) {}
    return false;
  }


  Future<void> _showOnlineOrdersSheet(BuildContext context) async {
    final tokens = NusaThemeTokens.of(context);
    List<Map<String, dynamic>> orders = [];
    bool loadingOrders = true;
    String? ordersError;
    String? modalActionError;
    String selectedFilter = 'all';

    Future<void> fetchOrders(StateSetter setModalState) async {
      setModalState(() {
        loadingOrders = true;
        ordersError = null;
      });
      try {
        final params = <String, dynamic>{};
        if (selectedFilter != 'all') {
          params['online_order_status'] = selectedFilter;
        }
        final res = await _saleRepo.fetchOnlineOrdersWithParams(params);
        final raw = (res.data['data'] as List<dynamic>?) ?? [];
        orders = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        ordersError = ApiClient.extractErrorMessage(e);
      } finally {
        setModalState(() => loadingOrders = false);
      }
    }

    Future<void> updateOrderInline(
      int orderId,
      String newStatus,
      StateSetter setModalState, {
      String? trackingNumber,
    }) async {
      setModalState(() => modalActionError = null);
      try {
        await _saleRepo.updateOnlineOrderStatus(
          orderId,
          {
            'online_order_status': newStatus,
            if (trackingNumber != null && trackingNumber.trim().isNotEmpty)
              'shipping_tracking_number': trackingNumber.trim(),
          },
        );
        await fetchOrders(setModalState);
      } catch (e) {
        setModalState(() => modalActionError = ApiClient.extractErrorMessage(e));
      }
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool initialized = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!initialized) {
              initialized = true;
              Future.microtask(() => fetchOrders(setModalState));
            }
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              maxChildSize: 0.94,
              builder: (_, scrollCtrl) => Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pesanan Toko Online (Webstore)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: loadingOrders ? null : () => fetchOrders(setModalState),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final f in const [
                            ('all', 'Semua'),
                            ('pending_payment', 'Menunggu Bayar'),
                            ('paid', 'Sudah Dibayar'),
                            ('processing', 'Diproses'),
                            ('shipped', 'Dikirim'),
                            ('completed', 'Selesai'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: NusaPillFilter(
                                label: f.$2,
                                selected: selectedFilter == f.$1,
                                onTap: () {
                                  selectedFilter = f.$1;
                                  fetchOrders(setModalState);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (modalActionError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tokens.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.danger),
                        ),
                        child: Text(
                          modalActionError!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.danger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: loadingOrders
                          ? const NusaListSkeleton(itemCount: 4)
                          : ordersError != null
                              ? Center(
                                  child: Text(
                                    ordersError!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: tokens.danger),
                                  ),
                                )
                              : orders.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Belum ada pesanan toko online pada filter ini.',
                                        style: TextStyle(color: tokens.textSecondary),
                                      ),
                                    )
                                  : ListView.separated(
                                      controller: scrollCtrl,
                                      itemCount: orders.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (_, idx) {
                                        final o = orders[idx];
                                        final id = (o['id'] as num?)?.toInt() ?? 0;
                                        final status =
                                            (o['online_order_status'] ?? 'pending_payment').toString();
                                        final total = (o['grand_total'] as num?)?.toDouble() ?? 0;
                                        return NusaCard(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '${o['number'] ?? '#ONLINE'} • ${o['customer_name'] ?? 'Pelanggan'}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 13,
                                                        color: tokens.textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    IdrCurrencyFormatter.format(total),
                                                    style: AppTheme.moneyStyle(
                                                      fontSize: 13.5,
                                                      fontWeight: FontWeight.w800,
                                                      color: tokens.accent,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${o['items_count'] ?? 0} item • Status: ${status.toUpperCase()}'
                                                '${o['tracking_number'] != null ? ' • Resi: ${o['tracking_number']}' : ''}',
                                                style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: [
                                                  if (status == 'pending_payment' || status == 'paid')
                                                    OutlinedButton(
                                                      onPressed: () => updateOrderInline(
                                                        id,
                                                        'processing',
                                                        setModalState,
                                                      ),
                                                      style: OutlinedButton.styleFrom(
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                      child: const Text('Proses Order'),
                                                    ),
                                                  if (status == 'processing' || status == 'paid')
                                                    ElevatedButton(
                                                      onPressed: () => _promptShipOnlineOrder(
                                                        ctx,
                                                        id,
                                                        (tracking) => updateOrderInline(
                                                          id,
                                                          'shipped',
                                                          setModalState,
                                                          trackingNumber: tracking,
                                                        ),
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                      child: const Text('Input Resi & Kirim'),
                                                    ),
                                                  if (status == 'shipped')
                                                    ElevatedButton(
                                                      onPressed: () => updateOrderInline(
                                                        id,
                                                        'completed',
                                                        setModalState,
                                                      ),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: tokens.positive,
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                      child: const Text('Tandai Selesai'),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      await _loadDashboard();
    }
  }


  Future<void> _promptShipOnlineOrder(
    BuildContext context,
    int orderId,
    Future<void> Function(String tracking) onConfirm,
  ) async {
    final resiCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kirim Pesanan Online', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: resiCtrl,
          decoration: const InputDecoration(
            labelText: 'Nomor Resi / Kurir (Opsional)',
            hintText: 'Contoh: JNE-102938475',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
        ],
      ),
    );
    if (ok == true) {
      await onConfirm(resiCtrl.text);
    }
  }
}
