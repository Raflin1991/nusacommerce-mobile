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
import 'features/dashboard/presentation/main_navigation_shell.dart';
import 'features/debt_book/presentation/debt_book_screen.dart';
import 'features/payments/presentation/payment_checkout_screen.dart';
import 'features/payments/presentation/receipt_preview_screen.dart';
import 'features/pos/bloc/pos_cubit.dart';
import 'features/pos/presentation/pos_catalog_screen.dart';
import 'features/restaurant/presentation/restaurant_tables_screen.dart';
import 'features/settings/presentation/store_profile_screen.dart';
import 'features/shifts/presentation/shift_management_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/',
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
                    'number': '#INV-1024',
                    'sale_datetime': '31 Okt 2026 • 15:30',
                    'grand_total': 17000.0,
                    'paid_total': 20000.0,
                    'change_returned': 3000.0,
                    'balance_due': 0.0,
                    'payment_methods': ['Tunai'],
                    'items': [
                      {'product_name': 'Air Mineral 600ml', 'quantity': 1, 'unit_price': 5000.0, 'line_total': 5000.0},
                      {'product_name': 'Teh Botol Sosro', 'quantity': 2, 'unit_price': 6000.0, 'line_total': 12000.0},
                    ],
                  };
            return ReceiptPreviewScreen(
              receiptData: extra,
              offlineDb: widget.offlineDb,
              printerService: widget.printerService,
            );
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
            final isExpenses = state.uri.queryParameters['tab'] == 'expenses';
            return DebtBookScreen(initialTab: isExpenses ? 1 : 0);
          },
        ),
      ],
    );
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
