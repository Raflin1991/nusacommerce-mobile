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
import 'core/theme/theme_cubit.dart';
import 'features/auth/bloc/auth_cubit.dart';
import 'features/pos/bloc/pos_cubit.dart';

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
  final apiClient = ApiClient(secureStorage: secureStorage, prefs: prefs);
  final connectivityService = NetworkConnectivityService();
  final printerService = PrinterService();
  await printerService.initialize(prefs);

  sl.registerSingleton<SharedPreferences>(prefs);
  sl.registerSingleton<OfflineDatabase>(offlineDb);
  sl.registerSingleton<ApiClient>(apiClient);
  sl.registerSingleton<NetworkConnectivityService>(connectivityService);
  sl.registerSingleton<PrinterService>(printerService);

  final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
  final posCubit = PosCubit(
    apiClient: apiClient,
    offlineDb: offlineDb,
    connectivityService: connectivityService,
  );
  final themeCubit = ThemeCubit(prefs: prefs);

  sl.registerSingleton<AuthCubit>(authCubit);
  sl.registerSingleton<PosCubit>(posCubit);
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
