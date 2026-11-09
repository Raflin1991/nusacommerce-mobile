import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/database/offline_database.dart';
import 'core/hardware/printer_service.dart';
import 'core/network/api_client.dart';
import 'features/auth/bloc/auth_cubit.dart';
import 'features/pos/bloc/pos_cubit.dart';

final GetIt sl = GetIt.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock portrait orientation for optimal one-handed smartphone & handheld POS ergonomics
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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
  final apiClient = ApiClient(secureStorage: secureStorage, prefs: prefs);
  final printerService = PrinterService();

  sl.registerSingleton<SharedPreferences>(prefs);
  sl.registerSingleton<OfflineDatabase>(offlineDb);
  sl.registerSingleton<ApiClient>(apiClient);
  sl.registerSingleton<PrinterService>(printerService);

  final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
  final posCubit = PosCubit(apiClient: apiClient, offlineDb: offlineDb);

  sl.registerSingleton<AuthCubit>(authCubit);
  sl.registerSingleton<PosCubit>(posCubit);

  // Bootstrap Catalog & Check Session
  await posCubit.initializeCatalog(seedDefaultCart: true);
  await authCubit.checkExistingSession();

  runApp(
    NusaCommerceMobileApp(
      apiClient: apiClient,
      offlineDb: offlineDb,
      printerService: printerService,
      authCubit: authCubit,
      posCubit: posCubit,
    ),
  );
}
