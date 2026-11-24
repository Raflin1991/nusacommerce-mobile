// ignore_for_file: invalid_use_of_protected_member
part of 'all_modules_directory_view.dart';

extension _AllModulesDirectoryViewStatePart2Ext on _AllModulesDirectoryViewState {

  List<_ModuleCategory> _buildCategories(
    BuildContext context, {
    required NusaThemeTokens tokens,
    required AuthSessionModel session,
    required bool hasFullCatalogAccess,
    required bool onlineGated,
    required String currentTier,
  }) {
    final canPos = hasFullCatalogAccess || MobileWorkspaceResolver.canUsePos(session);
    final canShifts = hasFullCatalogAccess || MobileWorkspaceResolver.canViewShifts(session);
    final canKds = hasFullCatalogAccess || MobileWorkspaceResolver.canViewKds(session);
    final canSalesHistory = hasFullCatalogAccess || MobileWorkspaceResolver.canViewSalesHistory(session);
    final canQuotations = hasFullCatalogAccess || MobileWorkspaceResolver.canManageQuotations(session);
    final canReceivables = hasFullCatalogAccess || MobileWorkspaceResolver.canViewReceivables(session);
    final canProducts = hasFullCatalogAccess || MobileWorkspaceResolver.canViewProducts(session);
    final canTaxonomies = hasFullCatalogAccess || MobileWorkspaceResolver.canManageCatalogTaxonomies(session);
    final canInventory = hasFullCatalogAccess || MobileWorkspaceResolver.canManageInventory(session);
    final canPurchases = hasFullCatalogAccess || MobileWorkspaceResolver.canManagePurchases(session);
    final canExpenses = hasFullCatalogAccess || MobileWorkspaceResolver.canManageExpensesOrPayables(session);
    final canCustomers = hasFullCatalogAccess || MobileWorkspaceResolver.canViewCustomers(session);
    final canSuppliers = hasFullCatalogAccess || MobileWorkspaceResolver.canViewSuppliers(session);
    final canOnlineStore = hasFullCatalogAccess || MobileWorkspaceResolver.canManageOnlineStore(session);
    final canCashLedger = hasFullCatalogAccess || MobileWorkspaceResolver.canViewCashLedger(session);
    final canReports = hasFullCatalogAccess || MobileWorkspaceResolver.canViewOwnerDashboard(session);
    final canApprovals = hasFullCatalogAccess || MobileWorkspaceResolver.canViewApprovals(session);
    final canPrinter = hasFullCatalogAccess || MobileWorkspaceResolver.canManageStoreProfileAndPrinter(session);

    final rawCategories = <_ModuleCategory>[
      _ModuleCategory(
        title: 'Kasir & Operasional',
        accentColor: tokens.accent,
        items: [
          if (canPos)
            _ModuleEntry(
              icon: Icons.point_of_sale_rounded,
              title: 'Kasir POS',
              subtitle: 'Scan & Transaksi Cepat',
              onTap: () => context.push('/pos'),
            ),
          if (canShifts)
            _ModuleEntry(
              icon: Icons.lock_clock_outlined,
              title: 'Shift & Buka/Tutup Kas',
              subtitle: 'Laci Kas & Blind Count',
              onTap: () => context.push('/shifts'),
            ),
          if (canKds)
            _ModuleEntry(
              icon: Icons.table_restaurant_outlined,
              title: 'Meja Resto & KDS Dapur',
              subtitle: 'F&B Dine-In & Tiket Masak',
              badge: 'F&B',
              fullSpan: true,
              secondaryActionLabel: 'Layar KDS',
              onSecondaryTap: () => context.push('/kds'),
              onTap: () => context.push('/restaurant'),
            ),
        ],
      ),
      _ModuleCategory(
        title: 'Penjualan & Order',
        accentColor: const Color(0xFF0284C7),
        items: [
          if (canSalesHistory)
            _ModuleEntry(
              icon: Icons.receipt_long_rounded,
              title: 'Riwayat Struk',
              subtitle: 'Retur & Cetak Ulang',
              onTap: () => widget.onSwitchTab(2),
            ),
          if (canPos)
            _ModuleEntry(
              icon: Icons.add_shopping_cart_rounded,
              title: 'Input Penjualan',
              subtitle: 'Entri Nota Baru',
              onTap: () => context.push('/pos'),
            ),
          if (canQuotations)
            _ModuleEntry(
              icon: Icons.request_quote_outlined,
              title: 'Surat Penawaran',
              subtitle: 'Quotation Sales B2B',
              onTap: () => context.push('/quotations'),
            ),
          if (canReceivables)
            _ModuleEntry(
              icon: Icons.menu_book_outlined,
              title: 'Piutang & Bon Pelanggan',
              subtitle: 'Kasbon & Pelunasan',
              onTap: () => context.push('/debts'),
            ),
        ],
      ),
      _ModuleCategory(
        title: 'Produk & Katalog',
        accentColor: NusaThemeTokens.of(context).purple,
        items: [
          if (canProducts)
            _ModuleEntry(
              icon: Icons.inventory_2_outlined,
              title: 'Data Barang',
              subtitle: 'Katalog & Harga Jual',
              onTap: () => widget.onSwitchTab(1),
            ),
          if (canTaxonomies) ...[
            _ModuleEntry(
              icon: Icons.category_outlined,
              title: 'Kategori & Brand',
              subtitle: 'Atur Taksonomi Merek',
              onTap: () => context.push('/catalog-taxonomies?tab=0'),
            ),
            _ModuleEntry(
              icon: Icons.straighten_rounded,
              title: 'Satuan (Unit)',
              subtitle: 'Pcs, Box, Dus, Kg',
              onTap: () => context.push('/catalog-taxonomies?tab=2'),
            ),
            _ModuleEntry(
              icon: Icons.qr_code_2_rounded,
              title: 'Cetak Barcode',
              subtitle: 'Label Thermal QR/Barcode',
              onTap: () => context.push('/catalog-taxonomies?tab=3'),
            ),
          ],
        ],
      ),
      _ModuleCategory(
        title: 'Inventaris & Gudang',
        accentColor: tokens.warning,
        items: [
          if (canInventory) ...[
            _ModuleEntry(
              icon: Icons.fact_check_outlined,
              title: 'Opname Stok',
              subtitle: 'Audit Fisik Scanner',
              onTap: () => context.push('/inventory-ops?tab=1'),
            ),
            _ModuleEntry(
              icon: Icons.swap_vert_rounded,
              title: 'Mutasi Stok',
              subtitle: 'Kartu Keluar Masuk',
              onTap: () => context.push('/inventory-ops?tab=2'),
            ),
            _ModuleEntry(
              icon: Icons.tune_rounded,
              title: 'Penyesuaian Stok',
              subtitle: 'Koreksi Rusak / Selisih',
              onTap: () => context.push('/inventory-ops?tab=0'),
            ),
            _ModuleEntry(
              icon: Icons.local_shipping_outlined,
              title: 'FEFO & Transfer Multi-Gudang',
              subtitle: 'Batch Expired & Kirim Cabang',
              fullSpan: true,
              onTap: () => context.push('/inventory-ops?tab=3'),
            ),
          ],
        ],
      ),
      _ModuleCategory(
        title: 'Pembelian & Biaya',
        accentColor: tokens.positive,
        items: [
          if (canPurchases) ...[
            _ModuleEntry(
              icon: Icons.shopping_cart_outlined,
              title: 'Order Beli (PO)',
              subtitle: 'Restok ke Supplier',
              onTap: () => context.push('/purchases?tab=0'),
            ),
            _ModuleEntry(
              icon: Icons.assignment_return_outlined,
              title: 'Retur Pembelian',
              subtitle: 'Kembalikan Barang Rusak',
              onTap: () => context.push('/purchases?tab=1'),
            ),
          ],
          if (canExpenses) ...[
            _ModuleEntry(
              icon: Icons.payments_outlined,
              title: 'Biaya Operasional',
              subtitle: 'Pengeluaran Toko Harian',
              onTap: () => context.push('/debts?tab=expenses'),
            ),
            _ModuleEntry(
              icon: Icons.store_mall_directory_outlined,
              title: 'Hutang Tempo Supplier',
              subtitle: 'Faktur Jatuh Tempo PO',
              onTap: () => context.push('/debts?tab=payables'),
            ),
          ],
        ],
      ),
      _ModuleCategory(
        title: 'CRM & Pelanggan',
        accentColor: const Color(0xFF0D9488),
        items: [
          if (canCustomers)
            _ModuleEntry(
              icon: Icons.groups_outlined,
              title: 'Pelanggan CRM',
              subtitle: 'Member & Grup Diskon',
              onTap: () => context.push('/customers'),
            ),
          if (canSuppliers)
            _ModuleEntry(
              icon: Icons.business_outlined,
              title: 'Pemasok / Supplier',
              subtitle: 'Direktori Vendor & Kontak',
              onTap: () => context.push('/suppliers'),
            ),
          if (canCustomers)
            _ModuleEntry(
              icon: Icons.chat_outlined,
              title: 'Saluran WhatsApp & CRM',
              subtitle: 'Struk WA & Reminder Otomatis',
              fullSpan: true,
              onTap: () => context.push('/customers'),
            ),
        ],
      ),
      _ModuleCategory(
        title: 'Toko Online',
        accentColor: const Color(0xFFE11D48),
        items: [
          if (canOnlineStore) ...[
            _ModuleEntry(
              icon: Icons.storefront_outlined,
              title: 'Pesanan E-Commerce',
              subtitle: 'Webstore Online Orders',
              isGated: onlineGated,
              requiredTier: 'PRO',
              onTap: () {
                if (onlineGated) {
                  showCascadeModuleTeaserModal(
                    context,
                    moduleKey: 'online_store',
                    moduleTitle: 'Toko Online & Katalog Web',
                    requiredTier: 'PRO',
                    currentTier: currentTier,
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
            ),
            _ModuleEntry(
              icon: Icons.public_outlined,
              title: 'Katalog Web & Domain',
              subtitle: 'Desain Etalase Web Toko',
              isGated: onlineGated,
              requiredTier: 'PRO',
              onTap: () {
                if (onlineGated) {
                  showCascadeModuleTeaserModal(
                    context,
                    moduleKey: 'online_store',
                    moduleTitle: 'Toko Online & Domain Web',
                    requiredTier: 'PRO',
                    currentTier: currentTier,
                    description:
                        'Katalog toko online langsung aktif dengan subdomain atau custom domain sendiri.',
                    benefits: const [
                      'Katalog web e-commerce responsive di semua browser',
                      'Checkout langsung kirim ke WhatsApp kasir',
                      'Terhubung otomatis dengan stok kasir toko',
                    ],
                  );
                } else {
                  final activeSession = context.read<AuthCubit>().state.session;
                  final slug = activeSession.tenantSubdomain.isEmpty ? 'toko' : activeSession.tenantSubdomain;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Etalase Webstore Aktif', style: TextStyle(fontWeight: FontWeight.w800)),
                      content: Text(
                        'Etalase katalog online cabang ${activeSession.activeStore.name} siap menerima pesanan pelanggan secara otomatis via Cloud ($slug).',
                        style: TextStyle(fontSize: 13.5, color: tokens.textSecondary),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.push('/online-orders');
                          },
                          child: const Text('Kelola Pesanan Web'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ],
        ],
      ),
      _ModuleCategory(
        title: (hasFullCatalogAccess || canReports)
            ? 'Kontrol Owner & Laporan'
            : 'Kontrol & Pengaturan',
        accentColor: tokens.accentDark,
        items: [
          if (canReports)
            _ModuleEntry(
              icon: Icons.analytics_outlined,
              title: 'Pusat Laporan Bisnis',
              subtitle: '50 Laporan Paritas Cloud & WA',
              badge: '50',
              onTap: () => context.push('/reports'),
            ),
          if (canApprovals)
            _ModuleEntry(
              icon: Icons.verified_user_outlined,
              title: 'Meja Persetujuan Owner',
              subtitle: 'Otorisasi Void, Diskon & PO',
              onTap: () => context.push('/approvals'),
            ),
          if (canCashLedger)
            _ModuleEntry(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Buku Kas Toko',
              subtitle: 'Arus Kas & Petty Cash',
              onTap: () => context.push('/cash-ledger'),
            ),
          if (canPrinter)
            _ModuleEntry(
              icon: Icons.print_outlined,
              title: 'Profil & Printer',
              subtitle: 'Header Struk, BT & WiFi LAN',
              onTap: () => context.push('/store-profile'),
            ),
          _ModuleEntry(
            icon: Icons.settings_outlined,
            title: 'Pengaturan Aplikasi & Akun',
            subtitle: 'Server, PIN Supervisor & Sesi',
            fullSpan: true,
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    ];

    // Omit empty categories and dynamically re-number visible categories cleanly.
    final visible = <_ModuleCategory>[];
    var seq = 1;
    for (final cat in rawCategories) {
      if (cat.items.isNotEmpty) {
        visible.add(
          _ModuleCategory(
            title: '$seq. ${cat.title}',
            accentColor: cat.accentColor,
            items: cat.items,
          ),
        );
        seq++;
      }
    }
    return visible;
  }
}
