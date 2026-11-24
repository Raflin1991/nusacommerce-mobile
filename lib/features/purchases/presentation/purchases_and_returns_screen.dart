import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';
import '../../../core/network/repositories/backoffice_repository.dart';

part 'purchases_and_returns_screen_part1.dart';
part 'purchases_and_returns_screen_part2.dart';
part 'purchases_and_returns_screen_part3.dart';
part 'purchases_and_returns_screen_part4.dart';
part 'purchases_and_returns_screen_part5.dart';

/// PUSAT PEMBELIAN (PO MULTI-ITEM + AI REORDER) & RETUR PEMBELIAN KE PEMASOK
class PurchasesAndReturnsScreen extends StatefulWidget {
  final int initialTab;

  const PurchasesAndReturnsScreen({super.key, this.initialTab = 0});

  @override
  State<PurchasesAndReturnsScreen> createState() => _PurchasesAndReturnsScreenState();
}


class _PurchasesAndReturnsScreenState extends State<PurchasesAndReturnsScreen>
    with SingleTickerProviderStateMixin {
  final BackofficeRepository _repo = BackofficeRepository.resolve();

  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();

  late TabController _tabController;


  bool _loading = true;

  List<Map<String, dynamic>> _purchases = [];

  List<Map<String, dynamic>> _returns = [];

  List<Map<String, dynamic>> _reorderSuggestions = [];


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    if (_isLocalStandalone) {
      _loading = false;
      _purchases = _offlineDb.getLocalPurchases();
      _returns = _offlineDb.getLocalPurchaseReturns();
      _reorderSuggestions = context
          .read<PosCubit>()
          .state
          .allProducts
          .where((p) => !p.isServiceOrNonStockItem && p.stock <= p.reorderLevel)
          .map((p) => {
                'product_id': p.id,
                'name': p.name,
                'sku': p.sku,
                'unit_code': p.unitCode,
                'current_stock': p.stock,
                'reorder_level': p.reorderLevel,
                'suggested_qty': ((p.reorderLevel * 2) - p.stock).clamp(5.0, 50.0),
                'cost_price': p.costPrice > 0 ? p.costPrice : p.sellingPrice * 0.7,
                'supplier_name': null,
              })
          .toList();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Pembelian & Retur Supplier'),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          indicatorColor: tokens.accent,
          tabs: const [
            Tab(text: 'Pesanan Beli (PO)'),
            Tab(text: 'Retur Pembelian'),
            Tab(text: 'Saran Kulakan AI'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreatePurchaseModal(),
        backgroundColor: tokens.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('Buat Pembelian Baru'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _purchases.isEmpty
                    ? const NusaEmptyState(
                        icon: Icons.shopping_bag_outlined,
                        title: 'Belum Ada Transaksi Pembelian',
                        subtitle: 'Catat kulakan / restok barang dari supplier agar HPP, stok, dan hutang tempo terkelola rapi.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        itemCount: _purchases.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final po = _purchases[idx];
                          final total = (po['grand_total'] as num?)?.toDouble() ?? 0.0;
                          final balance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
                          final status = (po['status'] ?? '').toString().toLowerCase();
                          final isDraft = status == 'draft' || status == 'submitted' || status == 'approved';
                          final isReceived = status == 'received' || status == 'partially_received' || status == 'partially_paid' || status == 'paid';
                          final isFullyReturned = po['is_fully_returned'] == true || (isReceived && ((po['total_returnable_qty'] as num?)?.toDouble() ?? 1.0) <= 0.0001 && po['is_returnable'] == false);
                          final canReceive = po['can_receive'] == true || isDraft || status == 'partially_received';

                          String badgeLabel;
                          NusaBadgeVariant badgeVariant;
                          if (isDraft) {
                            badgeLabel = status == 'draft' ? 'DRAF (BELUM TERIMA)' : 'DIPESAN';
                            badgeVariant = NusaBadgeVariant.neutral;
                          } else if (status == 'partially_received') {
                            badgeLabel = 'DITERIMA SEBAGIAN';
                            badgeVariant = NusaBadgeVariant.warning;
                          } else if (status == 'cancelled') {
                            badgeLabel = 'BATAL';
                            badgeVariant = NusaBadgeVariant.danger;
                          } else if (isFullyReturned) {
                            badgeLabel = 'SEMUA DIRETUR';
                            badgeVariant = NusaBadgeVariant.neutral;
                          } else if (balance > 0.5) {
                            badgeLabel = 'TEMPO / HUTANG';
                            badgeVariant = NusaBadgeVariant.warning;
                          } else {
                            badgeLabel = 'LUNAS';
                            badgeVariant = NusaBadgeVariant.success;
                          }

                          return NusaCard(
                            onTap: () => _openPurchaseDetailModal(po),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              (po['number'] ?? po['purchase_number'] ?? '-').toString(),
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.visibility_outlined,
                                            size: 15,
                                            color: NusaThemeTokens.of(context).textTertiary,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    NusaBadge(
                                      label: badgeLabel,
                                      variant: badgeVariant,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pemasok: ${po['supplier_name'] ?? 'Umum'} • ${(po['purchase_date'] ?? '').toString().split('T').first}',
                                  style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(context).textSecondary),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Total: ${IdrCurrencyFormatter.format(total)}',
                                          style: AppTheme.moneyStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                                        ),
                                        if (balance > 0.5 && !isDraft)
                                          Text(
                                            'Sisa: ${IdrCurrencyFormatter.format(balance)}',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: NusaThemeTokens.of(context).danger,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (canReceive) ...[
                                          ElevatedButton.icon(
                                            onPressed: () => _openReceivePurchaseModal(po),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: NusaThemeTokens.of(context).positive,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.inventory_rounded, size: 14),
                                            label: Text(
                                              status == 'partially_received' ? 'Terima Sisa' : 'Terima Barang',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        if (balance > 0.5 && !isDraft) ...[
                                          ElevatedButton.icon(
                                            onPressed: () => _openPayPurchaseModal(po),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: tokens.accent,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.payment_rounded, size: 15),
                                            label: const Text(
                                              'Bayar PO',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                          if (isReceived && !isFullyReturned)
                                            TextButton.icon(
                                              onPressed: () => _openReturnPurchaseModal(po),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                minimumSize: const Size(0, 32),
                                              ),
                                              icon: const Icon(Icons.assignment_return_outlined, size: 16),
                                              label: const Text('Retur PO', style: TextStyle(fontSize: 12)),
                                            ),
                                          if (isFullyReturned)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: tokens.bgPage,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: tokens.borderDefault),
                                              ),
                                              child: Text(
                                                'Habis Diretur',
                                                style: TextStyle(fontSize: 11, color: NusaThemeTokens.of(context).textSecondary, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                _returns.isEmpty
                    ? const NusaEmptyState(
                        icon: Icons.assignment_return_outlined,
                        title: 'Belum Ada Retur Pembelian',
                        subtitle: 'Pilih tombol "Retur PO" pada tab Pesanan Beli jika ada barang rusak/tidak sesuai saat penerimaan.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _returns.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final ret = _returns[idx];
                          return NusaCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (ret['return_number'] ?? ret['number'] ?? '-').toString(),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      Text(
                                        'Ref: ${ret['purchase_number'] ?? '-'} • ${ret['supplier_name'] ?? '-'}',
                                        style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(context).textSecondary),
                                      ),
                                      if ((ret['notes'] ?? '').toString().isNotEmpty)
                                        Text(
                                          ret['notes'].toString(),
                                          style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  IdrCurrencyFormatter.format(
                                      ((ret['total_amount'] ?? ret['grand_total']) as num?)?.toDouble() ?? 0),
                                  style: AppTheme.moneyStyle(fontSize: 14, color: NusaThemeTokens.of(context).danger),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                _buildAiReorderTab(),
              ],
            ),
    );
  }
}
