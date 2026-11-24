import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';
import '../../../core/network/repositories/product_repository.dart';

part 'inventory_operations_screen_part1.dart';
part 'inventory_operations_screen_part2.dart';

/// PUSAT OPERASI INVENTARIS & GUDANG
/// Monitor Stok (Tersedia/Menipis/Minus), Penyesuaian & Stock Opname Multi-Item,
/// Kartu Mutasi Stok, Batch FEFO & Transfer Antar Cabang.
class InventoryOperationsScreen extends StatefulWidget {
  final int initialTab;

  const InventoryOperationsScreen({super.key, this.initialTab = 0});

  @override
  State<InventoryOperationsScreen> createState() => _InventoryOperationsScreenState();
}


class _InventoryOperationsScreenState extends State<InventoryOperationsScreen>
    with SingleTickerProviderStateMixin {
  final ProductRepository _productRepo = ProductRepository.resolve();

  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  late TabController _tabController;


  bool _loading = false;

  String _monitorFilter = 'Semua'; // Semua, Tersedia, Menipis, Minus

  int? _movementProductFilter;

  List<Map<String, dynamic>> _movements = [];

  List<Map<String, dynamic>> _batches = [];

  List<Map<String, dynamic>> _transfers = [];

  List<Map<String, dynamic>> _adjustmentReasons = [
    {'id': 1, 'name': 'Hasil Stock Opname Fisik'},
    {'id': 2, 'name': 'Barang Rusak / Pecah / Expired'},
    {'id': 3, 'name': 'Bonus / Sampel / Hilang'},
  ];


  // Multi-item Stock Adjustment Cart
  final List<Map<String, dynamic>> _opnameDraftItems = [];

  String _opnameReason = 'Hasil Stock Opname Fisik';

  final TextEditingController _opnameNotesCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    _loadInventoryOps();
  }


  @override
  void dispose() {
    _tabController.dispose();
    _opnameNotesCtrl.dispose();
    super.dispose();
  }


  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final products = context.watch<PosCubit>().state.allProducts;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        backgroundColor: tokens.bgSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Inventaris & Gudang'),
        actions: [
          IconButton(
            onPressed: _loadInventoryOps,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: tokens.accent,
          unselectedLabelColor: tokens.textSecondary,
          indicatorColor: tokens.accent,
          tabs: const [
            Tab(text: 'Monitor Stok'),
            Tab(text: 'Opname Multi-Item'),
            Tab(text: 'Kartu Mutasi'),
            Tab(text: 'FEFO & Transfer'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStockMonitorTab(products),
                _buildOpnameTab(products),
                _buildMovementsTab(products),
                _buildFefoAndTransferTab(),
              ],
            ),
    );
  }
}
