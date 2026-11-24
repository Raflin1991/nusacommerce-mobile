import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/cascade_entitlement_teaser.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';

/// Hub "Semua Menu" — Pusat direktori modul ERP & POS OXORA (Strict RBAC + CDO Warm Linen).
/// Hanya menampilkan modul yang diizinkan oleh hak akses peran (RBAC) pengguna.
class AllModulesDirectoryView extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSwitchTab;

  const AllModulesDirectoryView({
    super.key,
    required this.onOpenDrawer,
    required this.onSwitchTab,
  });

  @override
  State<AllModulesDirectoryView> createState() => _AllModulesDirectoryViewState();
}

class _AllModulesDirectoryViewState extends State<AllModulesDirectoryView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final authState = context.watch<AuthCubit>().state;
    final session = authState.session;
    final hasFullCatalogAccess = MobileWorkspaceResolver.canSwitchWorkspaces(session) ||
        (!authState.isAuthenticated &&
            session.userId == 0 &&
            session.userRole.trim().isEmpty &&
            session.permissions.isEmpty);
    final onlineGated = session.isModuleGated('online_store');

    final categories = _buildCategories(
      context,
      tokens: tokens,
      session: session,
      hasFullCatalogAccess: hasFullCatalogAccess,
      onlineGated: onlineGated,
      currentTier: session.tier,
    );

    final totalVisibleModules =
        categories.fold<int>(0, (sum, cat) => sum + cat.items.length);

    final q = _searchQuery.trim().toLowerCase();
    final filteredCategories = <_ModuleCategory>[];
    for (final cat in categories) {
      if (q.isEmpty) {
        filteredCategories.add(cat);
      } else {
        final matchedItems = cat.items.where((item) {
          return item.title.toLowerCase().contains(q) ||
              item.subtitle.toLowerCase().contains(q) ||
              cat.title.toLowerCase().contains(q) ||
              (item.secondaryActionLabel?.toLowerCase().contains(q) ?? false);
        }).toList();
        if (matchedItems.isNotEmpty) {
          filteredCategories.add(cat.copyWithItems(matchedItems));
        }
      }
    }

    return Scaffold(
      backgroundColor: tokens.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            _buildStickyHeader(
              context,
              tokens,
              totalVisibleModules: totalVisibleModules,
              hasFullCatalogAccess: hasFullCatalogAccess,
            ),
            Expanded(
              child: filteredCategories.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: tokens.textTertiary),
                            const SizedBox(height: 10),
                            Text(
                              'Modul tidak ditemukan',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tidak ada fitur yang cocok dengan "$_searchQuery".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Text('Reset Pencarian', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      itemCount: filteredCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) => _buildCategoryCard(tokens, filteredCategories[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyHeader(
    BuildContext context,
    NusaThemeTokens tokens, {
    required int totalVisibleModules,
    required bool hasFullCatalogAccess,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: widget.onOpenDrawer,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: tokens.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                  ),
                  child: Icon(Icons.menu_rounded, size: 20, color: tokens.textPrimary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pusat Modul & Fitur Toko',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Modul terfilter sesuai hak akses peran Anda',
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                    width: tokens.borderWidth,
                  ),
                ),
                child: Text(
                  hasFullCatalogAccess ? '100% Lengkap' : '$totalVisibleModules Modul',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accentDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (value) => setState(() => _searchQuery = value),
            style: TextStyle(fontSize: 13, color: tokens.textPrimary),
            decoration: InputDecoration(
              hintText: 'Cari modul, fitur, atau laporan...',
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
              filled: true,
              fillColor: tokens.bgElevated,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.accent, width: tokens.isHighContrast ? 2.0 : 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(NusaThemeTokens tokens, _ModuleCategory category) {
    final fullSpanItems = category.items.where((i) => i.fullSpan).toList();
    final gridItems = category.items.where((i) => !i.fullSpan).toList();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : (width < 340 ? 1 : 2);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        boxShadow: tokens.isDark || tokens.isHighContrast ? null : AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: category.accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${category.items.length} Modul',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < gridItems.length; i += columns) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: i + col < gridItems.length
                        ? _buildModuleTile(tokens, gridItems[i + col], category.accentColor)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
          for (final wideItem in fullSpanItems) ...[
            if (gridItems.isNotEmpty || wideItem != fullSpanItems.first) const SizedBox(height: 8),
            _buildModuleTile(tokens, wideItem, category.accentColor),
          ],
        ],
      ),
    );
  }

  Widget _buildModuleTile(NusaThemeTokens tokens, _ModuleEntry item, Color categoryAccent) {
    return Material(
      color: item.isGated ? tokens.warningSoft : tokens.bgElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.isGated
                  ? tokens.warning.withOpacity(tokens.isHighContrast ? 1.0 : 0.45)
                  : tokens.borderSubtle,
              width: tokens.borderWidth,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: categoryAccent.withOpacity(tokens.isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 18, color: categoryAccent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (item.isGated) ...[
                          const SizedBox(width: 4),
                          CascadeCrownBadge(requiredTier: item.requiredTier),
                        ] else if (item.badge != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: categoryAccent.withOpacity(tokens.isDark ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.badge!,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: categoryAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.secondaryActionLabel != null && item.onSecondaryTap != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: item.onSecondaryTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: categoryAccent.withOpacity(tokens.isHighContrast ? 1.0 : 0.5),
                        width: tokens.borderWidth,
                      ),
                    ),
                    child: Text(
                      item.secondaryActionLabel!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: categoryAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

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
        accentColor: AppColors.purple,
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

class _ModuleCategory {
  final String title;
  final Color accentColor;
  final List<_ModuleEntry> items;

  const _ModuleCategory({
    required this.title,
    required this.accentColor,
    required this.items,
  });

  _ModuleCategory copyWithItems(List<_ModuleEntry> newItems) {
    return _ModuleCategory(
      title: title,
      accentColor: accentColor,
      items: newItems,
    );
  }
}

class _ModuleEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isGated;
  final String requiredTier;
  final String? badge;
  final bool fullSpan;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryTap;

  const _ModuleEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isGated = false,
    this.requiredTier = 'PRO',
    this.badge,
    this.fullSpan = false,
    this.secondaryActionLabel,
    this.onSecondaryTap,
  });
}
