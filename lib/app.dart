import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'core/database/offline_database.dart';
import 'core/hardware/printer_service.dart';
import 'core/network/api_client.dart';
import 'core/network/repositories/product_repository.dart';
import 'core/network/repositories/restaurant_table_repository.dart';
import 'core/network/repositories/sale_repository.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/nusa_theme_tokens.dart';
import 'core/theme/theme_cubit.dart';
import 'core/widgets/shift_inactivity_lock_guard.dart';
import 'features/approvals/presentation/owner_approvals_screen.dart';
import 'features/auth/bloc/auth_cubit.dart';
import 'features/pos/bloc/cart_cubit.dart';
import 'features/pos/bloc/catalog_cubit.dart';
import 'features/pos/bloc/restaurant_table_cubit.dart';
import 'features/pos/bloc/sync_cubit.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/splash_welcome_screen.dart';
import 'features/cash_ledger/presentation/cash_ledger_screen.dart';
import 'features/catalog/presentation/catalog_taxonomies_screen.dart';
import 'features/customers/presentation/customer_list_screen.dart';
import 'features/dashboard/presentation/main_navigation_shell.dart';
import 'features/debt_book/presentation/debt_book_screen.dart';
import 'features/inventory/presentation/inventory_operations_screen.dart';
import 'features/online_orders/presentation/online_orders_screen.dart';
import 'features/owner_reports/models/mobile_report_catalog.dart';
import 'features/owner_reports/presentation/business_reports_screen.dart';
import 'features/owner_reports/presentation/mobile_report_detail_screen.dart';
import 'features/payments/presentation/payment_checkout_screen.dart';
import 'features/payments/presentation/receipt_preview_screen.dart';
import 'features/pos/bloc/pos_cubit.dart';
import 'features/pos/presentation/pos_catalog_screen.dart';
import 'features/purchases/presentation/purchases_and_returns_screen.dart';
import 'features/quotations/presentation/quotations_screen.dart';
import 'features/restaurant/presentation/kds_screen.dart';
import 'features/restaurant/presentation/restaurant_tables_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/settings/presentation/store_profile_screen.dart';
import 'features/shifts/presentation/shift_management_screen.dart';
import 'features/suppliers/presentation/supplier_list_screen.dart';

class NusaCommerceMobileApp extends StatefulWidget {
  final ApiClient apiClient;
  final OfflineDatabase offlineDb;
  final PrinterService printerService;
  final AuthCubit authCubit;
  final PosCubit posCubit;
  final ThemeCubit? themeCubit;

  const NusaCommerceMobileApp({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    required this.printerService,
    required this.authCubit,
    required this.posCubit,
    this.themeCubit,
  });

  @override
  State<NusaCommerceMobileApp> createState() => _NusaCommerceMobileAppState();
}

class _NusaCommerceMobileAppState extends State<NusaCommerceMobileApp> {
  late final GoRouter _router;
  late final _GoRouterRefreshStream _authRefreshNotifier;
  late final ThemeCubit _effectiveThemeCubit;
  late final bool _ownsThemeCubit;

  @override
  void initState() {
    super.initState();
    _ownsThemeCubit = widget.themeCubit == null;
    _effectiveThemeCubit = widget.themeCubit ?? ThemeCubit();
    _authRefreshNotifier = _GoRouterRefreshStream(widget.authCubit.stream);
    _router = GoRouter(
      initialLocation: widget.authCubit.state.isAuthenticated ? '/home' : '/login',
      refreshListenable: _authRefreshNotifier,
      redirect: (context, state) {
        final isAuthed = widget.authCubit.state.isAuthenticated;
        final loc = state.matchedLocation;
        if (!isAuthed && loc != '/login' && loc != '/') {
          return '/login';
        }
        if (isAuthed && (loc == '/login' || loc == '/')) {
          return '/home';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SplashWelcomeScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => LoginScreen(apiClient: widget.apiClient),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) {
            final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
            return MainNavigationShell(initialIndex: tab);
          },
        ),
        GoRoute(
          path: '/pos',
          builder: (context, state) => const PosCatalogScreen(),
        ),
        GoRoute(
          path: '/pos/payment',
          builder: (context, state) => PaymentCheckoutScreen(offlineDb: widget.offlineDb),
        ),
        GoRoute(
          path: '/pos/receipt',
          builder: (context, state) {
            final extra = state.extra is Map<String, dynamic>
                ? state.extra as Map<String, dynamic>
                : <String, dynamic>{
                    'number': '#INV-0000',
                    'sale_datetime': '-',
                    'grand_total': 0.0,
                    'paid_total': 0.0,
                    'change_returned': 0.0,
                    'balance_due': 0.0,
                    'payment_methods': const ['Tunai'],
                    'items': const [],
                  };
            return ReceiptPreviewScreen(
              receiptData: extra,
              offlineDb: widget.offlineDb,
              printerService: widget.printerService,
            );
          },
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomerListScreen(),
        ),
        GoRoute(
          path: '/suppliers',
          builder: (context, state) {
            final tabParam = state.uri.queryParameters['tab'];
            return SupplierListScreen(initialTab: tabParam == 'stock-in' ? 1 : 0);
          },
        ),
        GoRoute(
          path: '/store-profile',
          builder: (context, state) => StoreProfileScreen(offlineDb: widget.offlineDb),
        ),
        GoRoute(
          path: '/restaurant',
          builder: (context, state) => RestaurantTablesScreen(printerService: widget.printerService),
        ),
        GoRoute(
          path: '/shifts',
          builder: (context, state) => const ShiftManagementScreen(),
        ),
        GoRoute(
          path: '/debts',
          builder: (context, state) {
            final tabParam = state.uri.queryParameters['tab'];
            final tabIndex = tabParam == 'expenses' ? 2 : (tabParam == 'payables' ? 1 : 0);
            return DebtBookScreen(initialTab: tabIndex);
          },
        ),
        GoRoute(
          path: '/catalog-taxonomies',
          builder: (context, state) {
            final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
            return CatalogTaxonomiesScreen(initialTab: tab.clamp(0, 3));
          },
        ),
        GoRoute(
          path: '/inventory-ops',
          builder: (context, state) {
            final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
            return InventoryOperationsScreen(initialTab: tab.clamp(0, 3));
          },
        ),
        GoRoute(
          path: '/purchases',
          builder: (context, state) {
            final tab = int.tryParse(state.uri.queryParameters['tab'] ?? '0') ?? 0;
            return PurchasesAndReturnsScreen(initialTab: tab.clamp(0, 2));
          },
        ),
        GoRoute(
          path: '/cash-ledger',
          builder: (context, state) => const CashLedgerScreen(),
        ),
        GoRoute(
          path: '/quotations',
          builder: (context, state) => const QuotationsScreen(),
        ),
        GoRoute(
          path: '/online-orders',
          builder: (context, state) => const OnlineOrdersScreen(),
        ),
        GoRoute(
          path: '/kds',
          builder: (context, state) => const KdsScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const BusinessReportsScreen(),
        ),
        GoRoute(
          path: '/reports/:reportId',
          builder: (context, state) {
            final reportId = state.pathParameters['reportId'] ?? '';
            final definition = MobileReportCatalog.findById(reportId);
            if (definition == null) {
              return const BusinessReportsScreen();
            }
            return MobileReportDetailScreen(definition: definition);
          },
        ),
        GoRoute(
          path: '/approvals',
          builder: (context, state) => const OwnerApprovalsScreen(),
        ),
        GoRoute(
          path: '/hr',
          builder: (context, state) => const _CloudWebHrRedirectScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _authRefreshNotifier.dispose();
    _router.dispose();
    if (_ownsThemeCubit) {
      _effectiveThemeCubit.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: widget.authCubit),
        BlocProvider<PosCubit>.value(value: widget.posCubit),
        BlocProvider<CatalogCubit>(
          create: (_) => CatalogCubit(
            posCubit: widget.posCubit,
            productRepository: ProductRepository.resolve(widget.apiClient),
          ),
        ),
        BlocProvider<CartCubit>(
          create: (_) => CartCubit(
            posCubit: widget.posCubit,
            saleRepository: SaleRepository.resolve(widget.apiClient),
          ),
        ),
        BlocProvider<SyncCubit>(
          create: (_) => SyncCubit(
            posCubit: widget.posCubit,
            offlineDb: widget.offlineDb,
          ),
        ),
        BlocProvider<RestaurantTableCubit>(
          create: (_) => RestaurantTableCubit(
            repository: RestaurantTableRepository.resolve(widget.apiClient),
          ),
        ),
        BlocProvider<ThemeCubit>.value(value: _effectiveThemeCubit),
      ],
      child: BlocBuilder<ThemeCubit, NusaThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp.router(
            title: 'OXORA Mobile POS',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forMode(themeMode),
            routerConfig: _router,
            builder: (context, child) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  // Guard against transient sub-120px Chromium DevTools / OS resize
                  // frames (e.g. 1.6x1.6) that otherwise trigger AppBar _ToolbarSlot
                  // RenderFlex overflows in the web console.
                  if (constraints.maxWidth < 120 || constraints.maxHeight < 120) {
                    return ColoredBox(
                      color: AppTheme.forMode(themeMode).scaffoldBackgroundColor,
                    );
                  }
                  return ShiftInactivityLockGuard(
                    apiClient: widget.apiClient,
                    offlineDb: widget.offlineDb,
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _CloudWebHrRedirectScreen extends StatelessWidget {
  const _CloudWebHrRedirectScreen();

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(title: const Text('HRD & Payroll di Cloud Web')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public_rounded, color: tokens.accent, size: 32),
                const SizedBox(height: 12),
                Text(
                  'Modul HRD & Payroll Dikelola di OXORA Cloud Web',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Agar aplikasi Kasir Mobile tetap super cepat dan bebas clutter, pengelolaan absensi lengkap, penggajian (Payroll), PPh 21 TER, dan BPJS tersedia di OXORA Cloud Web (/admin).',
                  style: TextStyle(fontSize: 13, color: tokens.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home_rounded, size: 18),
                    label: const Text('Kembali ke Beranda Operasional'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
