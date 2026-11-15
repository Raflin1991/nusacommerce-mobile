import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'core/database/offline_database.dart';
import 'core/hardware/printer_service.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_cubit.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/splash_welcome_screen.dart';
import 'features/customers/presentation/customer_list_screen.dart';
import 'features/dashboard/presentation/main_navigation_shell.dart';
import 'features/debt_book/presentation/debt_book_screen.dart';
import 'features/payments/presentation/payment_checkout_screen.dart';
import 'features/payments/presentation/receipt_preview_screen.dart';
import 'features/pos/bloc/pos_cubit.dart';
import 'features/pos/presentation/pos_catalog_screen.dart';
import 'features/restaurant/presentation/restaurant_tables_screen.dart';
import 'features/settings/presentation/store_profile_screen.dart';
import 'features/shifts/presentation/shift_management_screen.dart';
import 'features/suppliers/presentation/supplier_list_screen.dart';

class NusaCommerceMobileApp extends StatefulWidget {
  final ApiClient apiClient;
  final OfflineDatabase offlineDb;
  final PrinterService printerService;
  final AuthCubit authCubit;
  final PosCubit posCubit;

  const NusaCommerceMobileApp({
    super.key,
    required this.apiClient,
    required this.offlineDb,
    required this.printerService,
    required this.authCubit,
    required this.posCubit,
  });

  @override
  State<NusaCommerceMobileApp> createState() => _NusaCommerceMobileAppState();
}

class _NusaCommerceMobileAppState extends State<NusaCommerceMobileApp> {
  late final GoRouter _router;
  late final _GoRouterRefreshStream _authRefreshNotifier;

  @override
  void initState() {
    super.initState();
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
      ],
    );
  }

  @override
  void dispose() {
    _authRefreshNotifier.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: widget.authCubit),
        BlocProvider<PosCubit>.value(value: widget.posCubit),
      ],
      child: MaterialApp.router(
        title: 'NusaCommerce Mobile POS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
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
