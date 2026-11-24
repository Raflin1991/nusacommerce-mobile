import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/hardware/barcode_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_barcode_scanner_view.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/product_illustration_widget.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/pos_cubit.dart';
import '../models/pos_models.dart';


part 'widgets/pos_item_input_sheets.dart';
part 'widgets/pos_cart_item_and_customer_sheets.dart';
part 'widgets/pos_catalog_header_and_filters.dart';
part 'widgets/pos_product_cards.dart';
part 'widgets/pos_vertical_and_customer_bars.dart';
part 'widgets/pos_cart_panels.dart';
part 'widgets/pos_warehouse_and_price_sheets.dart';

/// LAYAR 3 — PENJUALAN BARU (POS CATALOG & FLOATING CART)
/// OXORA Mobile Enterprise POS Catalog Screen
class PosCatalogScreen extends StatefulWidget {
  const PosCatalogScreen({super.key});

  @override
  State<PosCatalogScreen> createState() => _PosCatalogScreenState();
}

class _PosCatalogScreenState extends State<PosCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _hardwareScannerFocusNode = FocusNode(skipTraversal: true);
  final HardwareBarcodeWedgeBuffer _wedgeBuffer = HardwareBarcodeWedgeBuffer();
  bool _isListView = false;
  bool _isCartExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PosCubit>().syncWithCloud(force: false);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hardwareScannerFocusNode.dispose();
    super.dispose();
  }

  void _handleHardwareScannerKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText) return;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    final scanned = _wedgeBuffer.onKeyCharacter(
      character: event.character,
      isEnter: isEnter,
    );
    if (scanned != null && scanned.isNotEmpty) {
      final ok = context.read<PosCubit>().handleBarcodeScanned(scanned);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('Scanner HID: $scanned ditambahkan ke keranjang.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PosCubit, PosState>(
      listener: (context, state) {
        if (state.alertMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: NusaThemeTokens.of(context).danger,
              content: Text(state.alertMessage!),
            ),
          );
        }
      },
      builder: (context, state) {
        final tokens = NusaThemeTokens.of(context);
        final activeStore = context.watch<AuthCubit>().state.session.activeStore;
        final capabilities = state.capabilities;
        final screenWidth = MediaQuery.of(context).size.width;
        final isTablet = screenWidth >= 600;
        final sideCartWidth = screenWidth >= 960 ? 380.0 : (screenWidth >= 760 ? 340.0 : 300.0);
        final catalogWidth = isTablet ? (screenWidth - sideCartWidth) : screenWidth;
        final gridColumns = catalogWidth >= 780
            ? 4
            : (catalogWidth >= 450 ? 3 : 2);

        return Scaffold(
          backgroundColor: tokens.bgPage,
          appBar: AppBar(
            backgroundColor: tokens.bgSurface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
            ),
            titleSpacing: 4,
            title: InkWell(
              onTap: (capabilities.hasTableManagement && state.selectedTable != null)
                  ? null
                  : () => _showStoreWarehouseSwitcherSheet(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capabilities.posDisplayName,
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (capabilities.hasTableManagement && state.selectedTable != null)
                              ? Icons.table_restaurant_rounded
                              : (activeStore.isWarehouse
                                  ? Icons.warehouse_rounded
                                  : Icons.storefront_rounded),
                          size: 12,
                          color: (capabilities.hasTableManagement && state.selectedTable != null)
                              ? tokens.accent
                              : tokens.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            capabilities.hasTableManagement && state.selectedTable != null
                                ? 'Meja: ${state.selectedTable!['name']} (${state.selectedTable!['section']})'
                                : activeStore.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: (capabilities.hasTableManagement && state.selectedTable != null)
                                  ? tokens.accent
                                  : tokens.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!(capabilities.hasTableManagement && state.selectedTable != null)) ...[
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 15,
                            color: tokens.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // Quick Shift Status Pill
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: InkWell(
                  onTap: () => context.push('/shifts'),
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: NusaThemeTokens.of(context).positiveSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 7, color: NusaThemeTokens.of(context).positive),
                            SizedBox(width: 4),
                            Text(
                              'Shift',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: NusaThemeTokens.of(context).positive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Held Carts Badge -> opens Held Carts Picker Sheet
              if (state.heldCarts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => _showHeldCartsSheet(context, state),
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: NusaThemeTokens.of(context).warningSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pause_circle_outline_rounded, size: 14, color: NusaThemeTokens.of(context).warning),
                              const SizedBox(width: 4),
                              Text(
                                '${state.heldCarts.length}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: NusaThemeTokens.of(context).warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Quick Price & Stock Checker Button
              IconButton(
                tooltip: 'Cek Harga Cepat',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                onPressed: () => _showQuickPriceCheckerSheet(context),
                icon: Icon(Icons.price_check_rounded, color: tokens.textSecondary, size: 21),
              ),
              // Restaurant Mode Switcher Button (Capabilities-Driven)
              if (capabilities.hasTableManagement)
                IconButton(
                  tooltip: 'Denah Meja Restoran (F&B)',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                  onPressed: () => context.push('/restaurant'),
                  icon: Icon(Icons.table_restaurant_outlined, color: tokens.textSecondary, size: 20),
                ),
              // Sync with Cloud Button
              IconButton(
                tooltip: 'Sinkronkan Data Cloud',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
                onPressed: () async {
                  await context.read<PosCubit>().syncWithCloud(force: false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Katalog berhasil disinkronkan dengan server Cloud.')),
                    );
                  }
                },
                icon: Icon(
                  state.isLoading ? Icons.sync_rounded : Icons.cloud_done_outlined,
                  color: tokens.accent,
                  size: 20,
                ),
              ),
            ],
          ),
          body: KeyboardListener(
            focusNode: _hardwareScannerFocusNode,
            onKeyEvent: _handleHardwareScannerKeyEvent,
            child: isTablet
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _buildCatalogColumn(
                          context,
                          state,
                          gridColumns,
                          screenWidth,
                          isTablet: true,
                        ),
                      ),
                      _buildTabletSideCartPanel(context, state, sideCartWidth),
                    ],
                  )
                : _buildCatalogColumn(
                    context,
                    state,
                    gridColumns,
                    screenWidth,
                    isTablet: false,
                  ),
          ),
        );
      },
    );
  }
}
