import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/printer_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/core/theme/theme_cubit.dart';
import 'package:nusacommerce_mobile/core/widgets/shift_inactivity_lock_guard.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:nusacommerce_mobile/features/settings/presentation/settings_screen.dart';
import 'package:nusacommerce_mobile/main.dart';

class _OfflineStubConnectivity extends NetworkConnectivityService {
  final StreamController<bool> _ctrl = StreamController<bool>.broadcast();

  @override
  Stream<bool> get onOnlineChanged => _ctrl.stream;

  @override
  Future<bool> checkOnline() async => false;

  void disposeStub() {
    _ctrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Hardening #3: Crash telemetry records uncaught errors and redacts Bearer/PIN/password secrets', () async {
    final prefs = await SharedPreferences.getInstance();
    final offlineDb = OfflineDatabase(prefs);
    final prevFlutterError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = prevFlutterError);

    installGlobalCrashTelemetry(offlineDb);

    final row = await offlineDb.recordLocalError(
      errorType: 'DioException',
      message: 'Auth failed Header Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.secret with pin=123456',
      stackTrace: '{"supervisor_pin":"998877","password":"mySecretPassword"}',
      context: {'token': 'raw-secret-token', 'module': 'pos_checkout'},
    );

    expect(row['message'].toString(), contains('Bearer [REDACTED]'));
    expect(row['message'].toString(), contains('pin=[REDACTED]'));
    expect(row['message'].toString(), isNot(contains('123456')));
    expect(row['stack_trace'].toString(), isNot(contains('998877')));
    expect(row['stack_trace'].toString(), isNot(contains('mySecretPassword')));
    expect(row['context'].toString(), isNot(contains('raw-secret-token')));

    final recent = await offlineDb.getRecentLocalErrors();
    expect(recent, isNotEmpty);
    expect(recent.first['error_type'], 'DioException');
  });

  testWidgets(
    'Hardening #4: ShiftInactivityLockGuard locks on idle without clearing cart, shows inline error on bad PIN, and unlocks at 300x640 narrow viewport',
    (tester) async {
      tester.view.physicalSize = const Size(300, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      const secureStorage = FlutterSecureStorage();
      final offlineDb = OfflineDatabase(prefs);
      await offlineDb.saveAuthSession({
        'is_local_trial': true,
        'user_name': 'Hendra Wijaya',
        'active_store': {'id': 1, 'name': 'Kemang Flagship', 'code': 'KMG'},
      });

      final apiClient = ApiClient(secureStorage: secureStorage, prefs: prefs);
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      await authCubit.checkExistingSession(awaitRemoteRefresh: false);
      await authCubit.setStandaloneCashierPin('2468');

      final connectivity = _OfflineStubConnectivity();
      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: offlineDb,
        connectivityService: connectivity,
      );
      posCubit.addToCart(
        ProductModel.fromJson(const {
          'id': -501,
          'is_local_only': true,
          'sku': 'MN-KOPI-GAYO',
          'name': 'Es Kopi Susu Gula Aren',
          'selling_price': 34000.0,
          'stock': 25.0,
          'track_stock': true,
        }),
      );
      expect(posCubit.state.cart.length, 1);

      addTearDown(() async {
        await posCubit.close();
        await authCubit.close();
        connectivity.disposeStub();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.forMode(NusaThemeMode.warmLinenLight),
            home: ShiftInactivityLockGuard(
              apiClient: apiClient,
              offlineDb: offlineDb,
              idleTimeoutOverride: const Duration(seconds: 5),
              child: const Scaffold(
                body: Center(child: Text('POS Active Canvas')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('shift_inactivity_lock_overlay')), findsNothing);

      // Idle 6 seconds -> auto-locks without clearing cart!
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shift_inactivity_lock_overlay')), findsOneWidget);
      expect(posCubit.state.cart.length, 1);

      // Wrong PIN -> inline error inside modal (never SnackBar)
      await tester.enterText(find.byKey(const Key('shift_inactivity_pin_input')), '9999');
      await tester.tap(find.byKey(const Key('shift_inactivity_unlock_button')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shift_inactivity_unlock_error')), findsOneWidget);
      expect(find.byKey(const Key('shift_inactivity_lock_overlay')), findsOneWidget);

      // Correct PIN -> unlocks cleanly & preserves cart!
      await tester.enterText(find.byKey(const Key('shift_inactivity_pin_input')), '2468');
      await tester.tap(find.byKey(const Key('shift_inactivity_unlock_button')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('shift_inactivity_lock_overlay')), findsNothing);
      expect(posCubit.state.cart.length, 1);
    },
  );

  testWidgets(
    'Edge LAN Probe & Auto-Lock Settings render cleanly on narrow 360x640 viewport',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      const secureStorage = FlutterSecureStorage();
      final offlineDb = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: secureStorage, prefs: prefs);
      apiClient.lastLeaseState = 'valid:7d';
      final printerService = PrinterService();
      await printerService.initialize(prefs);

      GetIt.instance.registerSingleton<SharedPreferences>(prefs);
      GetIt.instance.registerSingleton<OfflineDatabase>(offlineDb);
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<PrinterService>(printerService);

      final connectivity = _OfflineStubConnectivity();
      addTearDown(connectivity.disposeStub);

      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: offlineDb,
        connectivityService: connectivity,
      );
      final themeCubit = ThemeCubit(prefs: prefs);

      addTearDown(() async {
        await themeCubit.close();
        await posCubit.close();
        await authCubit.close();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.forMode(NusaThemeMode.warmLinenDark),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Auto-Lock Layar Kasir Saat Idle'), findsOneWidget);
      expect(find.textContaining('Lease: valid:7d'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Server Cloud, Edge & Kode Terminal'),
        150,
      );
      await tester.tap(find.text('Server Cloud, Edge & Kode Terminal'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('probe_edge_lan_button')), findsOneWidget);
      expect(find.textContaining('Lease Ed25519: valid:7d'), findsOneWidget);
    },
  );
}
