import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/database/offline_database.dart';
import 'core/hardware/printer_service.dart';
import 'core/network/api_client.dart';
import 'core/network/network_connectivity_service.dart';
import 'core/network/repositories/backoffice_repository.dart';
import 'core/network/repositories/product_repository.dart';
import 'core/network/repositories/restaurant_table_repository.dart';
import 'core/network/repositories/sale_repository.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/bloc/auth_cubit.dart';
import 'features/pos/bloc/cart_cubit.dart';
import 'features/pos/bloc/catalog_cubit.dart';
import 'features/pos/bloc/pos_cubit.dart';
import 'features/pos/bloc/restaurant_table_cubit.dart';
import 'features/pos/bloc/sync_cubit.dart';

final GetIt sl = GetIt.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow flexible portrait/landscape desktop-replacement mode on tablets (>= 600dp),
  // while keeping portrait ergonomics on smartphones.
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final logicalShortestSide = views.isNotEmpty
      ? MediaQueryData.fromView(views.first).size.shortestSide
      : 0.0;
  if (logicalShortestSide >= 600) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } else {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Core Dependencies (DI)
  final prefs = await SharedPreferences.getInstance();
  const secureStorage = FlutterSecureStorage();
  final offlineDb = OfflineDatabase(prefs);
  await offlineDb.initialize();
  installGlobalCrashTelemetry(offlineDb);
  final apiClient = ApiClient(secureStorage: secureStorage, prefs: prefs);
  final connectivityService = NetworkConnectivityService();
  final printerService = PrinterService();
  await printerService.initialize(prefs);

  final productRepo = ProductRepository(apiClient);
  final saleRepo = SaleRepository(apiClient);
  final tableRepo = RestaurantTableRepository(apiClient);
  final backofficeRepo = BackofficeRepository(apiClient);

  sl.registerSingleton<SharedPreferences>(prefs);
  sl.registerSingleton<OfflineDatabase>(offlineDb);
  sl.registerSingleton<ApiClient>(apiClient);
  sl.registerSingleton<NetworkConnectivityService>(connectivityService);
  sl.registerSingleton<PrinterService>(printerService);
  sl.registerSingleton<ProductRepository>(productRepo);
  sl.registerSingleton<SaleRepository>(saleRepo);
  sl.registerSingleton<RestaurantTableRepository>(tableRepo);
  sl.registerSingleton<BackofficeRepository>(backofficeRepo);

  final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
  final posCubit = PosCubit(
    apiClient: apiClient,
    offlineDb: offlineDb,
    connectivityService: connectivityService,
  );
  final catalogCubit = CatalogCubit(posCubit: posCubit, productRepository: productRepo);
  final cartCubit = CartCubit(posCubit: posCubit, saleRepository: saleRepo);
  final syncCubit = SyncCubit(posCubit: posCubit, offlineDb: offlineDb);
  final tableCubit = RestaurantTableCubit(repository: tableRepo);
  final themeCubit = ThemeCubit(prefs: prefs);

  sl.registerSingleton<AuthCubit>(authCubit);
  sl.registerSingleton<PosCubit>(posCubit);
  sl.registerSingleton<CatalogCubit>(catalogCubit);
  sl.registerSingleton<CartCubit>(cartCubit);
  sl.registerSingleton<SyncCubit>(syncCubit);
  sl.registerSingleton<RestaurantTableCubit>(tableCubit);
  sl.registerSingleton<ThemeCubit>(themeCubit);

  // Bootstrap Session & local SQLite catalog immediately without blocking offline cold start
  // on 12-15s remote HTTP timeouts; Cloud sync runs reactively in the background once mounted.
  await authCubit.checkExistingSession(awaitRemoteRefresh: false);
  await posCubit.initializeCatalog(seedDefaultCart: false, awaitCloudSync: false);

  runApp(
    NusaCommerceMobileApp(
      apiClient: apiClient,
      offlineDb: offlineDb,
      printerService: printerService,
      authCubit: authCubit,
      posCubit: posCubit,
      themeCubit: themeCubit,
    ),
  );
}

/// Hardening #3: Hooks Flutter widget framework & Dart PlatformDispatcher uncaught
/// exceptions into sanitized `local_error_logs` (Bearer/PIN/password redacted, 500-row cap).
void installGlobalCrashTelemetry(OfflineDatabase offlineDb) {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
    unawaited(
      offlineDb.recordLocalError(
        errorType: 'FlutterError',
        message: details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
        context: {
          'library': details.library ?? 'flutter',
          'silent': details.silent,
        },
      ),
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(
      offlineDb.recordLocalError(
        errorType: error.runtimeType.toString(),
        message: error.toString(),
        stackTrace: stack.toString(),
        context: const {'source': 'PlatformDispatcher'},
      ),
    );
    return true;
  };
}
