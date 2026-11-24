import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nusacommerce_mobile/app.dart';
import 'package:nusacommerce_mobile/core/config/mobile_workspace_config.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/printer_service.dart';
import 'package:nusacommerce_mobile/core/hardware/voice_input_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/core/theme/theme_cubit.dart';
import 'package:nusacommerce_mobile/core/widgets/nusa_skeleton.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/auth/models/auth_session_model.dart';
import 'package:nusacommerce_mobile/features/auth/presentation/login_screen.dart';
import 'package:nusacommerce_mobile/features/cash_ledger/presentation/cash_ledger_screen.dart';
import 'package:nusacommerce_mobile/features/copilot/presentation/nusa_copilot_sheet.dart';
import 'package:nusacommerce_mobile/features/dashboard/presentation/all_modules_directory_view.dart';
import 'package:nusacommerce_mobile/features/dashboard/presentation/home_dashboard_screen.dart';
import 'package:nusacommerce_mobile/features/dashboard/presentation/main_navigation_shell.dart';
import 'package:nusacommerce_mobile/features/debt_book/presentation/debt_book_screen.dart';
import 'package:nusacommerce_mobile/features/inventory/presentation/inventory_operations_screen.dart';
import 'package:nusacommerce_mobile/features/inventory/presentation/products_inventory_screen.dart';
import 'package:nusacommerce_mobile/features/owner_reports/presentation/business_reports_screen.dart';
import 'package:nusacommerce_mobile/features/payments/presentation/payment_checkout_screen.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:nusacommerce_mobile/features/pos/presentation/pos_catalog_screen.dart';
import 'package:nusacommerce_mobile/features/purchases/presentation/purchases_and_returns_screen.dart';
import 'package:nusacommerce_mobile/features/sales_history/presentation/transactions_history_screen.dart';
import 'package:nusacommerce_mobile/features/settings/presentation/settings_screen.dart';
import 'package:nusacommerce_mobile/features/shifts/presentation/shift_management_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthSessionModel _sessionForRole({
  required String role,
  required bool isOwner,
  List<String> permissions = const [],
}) {
  const store = StoreBranchModel(id: 1, name: 'Cabang Sudirman', code: 'HQ-01');
  return AuthSessionModel(
    userId: 10,
    userName: 'User $role',
    userEmail: '${role.toLowerCase()}@nusa.test',
    userRole: role,
    isOwner: isOwner,
    tenantName: 'Nusa Demo',
    tenantSubdomain: 'nusa-demo',
    planName: 'Enterprise',
    tier: 'enterprise',
    activeModules: const ['cash_debt', 'accounting', 'online_store', 'hr', 'warehouse', 'crm'],
    activeStore: store,
    availableStores: const [store],
    permissions: permissions,
    isLocalTrial: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    NusaVoiceInputService.debugCaptureOverride = null;
    await GetIt.instance.reset();
  });

  group('Gelombang 5 — Role-Adaptive Super-App, CDO Warm Linen, Parallel Fetch, Copilot & Blind Drop', () {
    test('MobileWorkspaceResolver maps 5 roles cleanly and isolates non-owner RBAC', () {
      final owner = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      final manager = _sessionForRole(
        role: 'Manager',
        isOwner: false,
        permissions: const ['reports.view_sales', 'approvals.view', 'sales.create', 'shifts.view_all'],
      );
      final cashier = _sessionForRole(
        role: 'Cashier',
        isOwner: false,
        permissions: const ['sales.create', 'shifts.open', 'shifts.close_own', 'products.view'],
      );
      final warehouse = _sessionForRole(
        role: 'Warehouse Manager',
        isOwner: false,
        permissions: const ['products.view', 'products.adjust_stock', 'warehouse.view', 'purchases.create'],
      );
      final employee = _sessionForRole(
        role: 'HRD',
        isOwner: false,
        permissions: const ['hr.view', 'hr.manage_attendances', 'tasks.view'],
      );

      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(owner), MobileWorkspaceRole.ownerPulse);
      expect(MobileWorkspaceResolver.allowedWorkspaces(owner).length, 4);
      expect(MobileWorkspaceResolver.allowedWorkspaces(owner), isNot(contains(MobileWorkspaceRole.employeeEss)));
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(owner), isTrue);

      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(manager), MobileWorkspaceRole.managerDesk);
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(manager), isFalse);
      expect(
        MobileWorkspaceResolver.sanitizeActiveWorkspace(manager, MobileWorkspaceRole.ownerPulse),
        MobileWorkspaceRole.managerDesk,
      );

      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(cashier), MobileWorkspaceRole.posFastLane);
      expect(MobileWorkspaceResolver.canViewOwnerDashboard(cashier), isFalse);
      expect(MobileWorkspaceResolver.isSupervisorOrAbove(cashier), isFalse);
      expect(
        MobileWorkspaceResolver.sanitizeActiveWorkspace(cashier, MobileWorkspaceRole.ownerPulse),
        MobileWorkspaceRole.posFastLane,
      );

      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(warehouse), MobileWorkspaceRole.warehouseWorkbench);
      expect(MobileWorkspaceResolver.canUsePos(warehouse), isFalse);
      expect(MobileWorkspaceResolver.canViewOwnerDashboard(warehouse), isFalse);

      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(employee), MobileWorkspaceRole.employeeEss);
      expect(MobileWorkspaceResolver.canUsePos(employee), isFalse);
      expect(MobileWorkspaceResolver.canViewOwnerDashboard(employee), isFalse);
    });

    test('ThemeCubit persists & resolves CDO Warm Linen Light, Dark & High-Contrast Outdoor POS tokens', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cubit = ThemeCubit(prefs: prefs);

      expect(cubit.state, NusaThemeMode.warmLinenLight);
      expect(NusaThemeTokens.warmLinenLight.bgPage, const Color(0xFFFAF8F5));
      expect(NusaThemeTokens.warmLinenLight.accent, const Color(0xFFEA580C));

      await cubit.setThemeMode(NusaThemeMode.warmLinenDark);
      expect(cubit.state, NusaThemeMode.warmLinenDark);
      expect(prefs.getString(ThemeCubit.prefsKey), 'dark');
      expect(NusaThemeTokens.warmLinenDark.bgPage, const Color(0xFF08090A));

      await cubit.toggleOutdoorHighContrast();
      expect(cubit.state, NusaThemeMode.outdoorHighContrast);
      expect(prefs.getString(ThemeCubit.prefsKey), 'outdoor_hc');
      expect(NusaThemeTokens.outdoorHighContrast.isHighContrast, isTrue);
      expect(NusaThemeTokens.outdoorHighContrast.borderWidth, greaterThanOrEqualTo(1.8));
      expect(AppTheme.forMode(NusaThemeMode.outdoorHighContrast).scaffoldBackgroundColor, const Color(0xFFFFFFFF));

      // Restores from SharedPreferences on new boot
      final restored = ThemeCubit(prefs: prefs);
      expect(restored.state, NusaThemeMode.outdoorHighContrast);

      await cubit.close();
      await restored.close();
    });

    testWidgets('Role-Adaptive MainNavigationShell adapts tabs for Cashier & preserves Tablet NavigationRail',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      final requestedPaths = <String>[];
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        requestedPaths.add(options.path);
        if (options.path.endsWith('/shifts/current')) {
          return (
            200,
            {
              'success': true,
              'data': {
                'has_open_shift': true,
                'blind_drop_enforced': true,
                'can_view_expected_cash': false,
                'shift': {
                  'id': 41,
                  'status': 'open',
                  'opening_cash': 200000,
                  'expected_cash': null,
                  'sales_total': null,
                  'terminal': {'id': 1, 'name': 'POS-01'},
                  'entries': [],
                },
                'terminals': [],
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final cashierSession = _sessionForRole(
        role: 'Cashier',
        isOwner: false,
        permissions: const ['sales.create', 'shifts.open', 'shifts.close_own', 'products.view'],
      );
      await db.saveAuthSession(cashierSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MainNavigationShell(initialIndex: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tablet NavigationRail present with Cashier Fast-Lane labels and NO Owner workspace switcher
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Fast-Lane'), findsOneWidget);
      expect(find.text('Shift Kasir'), findsOneWidget);
      expect(find.byKey(const Key('workspace_pos_fast_lane')), findsOneWidget);
      expect(find.byKey(const Key('workspace_switcher_strip')), findsNothing);
      expect(find.text('Omzet Bersih Hari Ini'), findsNothing);
      // RBAC guard: Cashier MUST NOT call /reports/owner-dashboard
      expect(requestedPaths.any((p) => p.contains('/reports/owner-dashboard')), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Owner can switch Role-Adaptive Workspaces live on MainNavigationShell',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/reports/owner-dashboard')) {
          return (
            200,
            {
              'success': true,
              'data': {
                'kpi': {'net_sales': 1250000, 'transactions_count': 7, 'gross_profit': 410000},
                'operational_alerts': {'low_stock_count': 2, 'expiring_batches_count': 0},
                'anti_fraud_summary': {'voided_sales_count': 0, 'shift_variance_alerts_count': 0},
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final ownerSession = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(ownerSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MainNavigationShell(initialIndex: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Starts in Owner Pulse with workspace switcher visible
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byKey(const Key('workspace_owner_pulse')), findsOneWidget);
      expect(find.byKey(const Key('workspace_switcher_strip')), findsOneWidget);

      // Tap Warehouse chip -> NavigationRail and workspace adapt dynamically
      final warehouseChip = find.byKey(const Key('workspace_chip_warehouseWorkbench'));
      await tester.ensureVisible(warehouseChip);
      await tester.tap(warehouseChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('workspace_warehouse_workbench')), findsOneWidget);
      expect(find.text('Stok SKU'), findsOneWidget);
      expect(find.text('PO & Retur'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('HomeDashboardScreen fires parallel API fetch with Shimmer Skeleton before resolving',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;

      final gate = Completer<void>();
      int activeInFlight = 0;
      int maxConcurrent = 0;

      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        activeInFlight++;
        if (activeInFlight > maxConcurrent) maxConcurrent = activeInFlight;
        await gate.future;
        activeInFlight--;

        if (options.path.endsWith('/reports/owner-dashboard')) {
          return (
            200,
            {
              'success': true,
              'data': {
                'kpi': {'net_sales': 3450000, 'transactions_count': 18, 'gross_profit': 980000},
                'operational_alerts': {'low_stock_count': 3, 'expiring_batches_count': 1},
                'anti_fraud_summary': {'voided_sales_count': 0, 'shift_variance_alerts_count': 0},
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      final connectivity = _AlwaysOnlineConnectivity();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);

      final ownerSession = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(ownerSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: HomeDashboardScreen(
              onOpenDrawer: () {},
              onSwitchTab: (_) {},
              activeWorkspace: MobileWorkspaceRole.ownerPulse,
              onSelectWorkspace: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // While requests are in-flight: Shimmer Skeleton is visible AND multiple requests run concurrently!
      expect(find.byType(NusaDashboardSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(maxConcurrent, greaterThanOrEqualTo(4));

      // Release responses -> skeleton replaced by live owner pulse metrics
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(NusaDashboardSkeleton), findsNothing);
      expect(find.text('Rp 3.450.000'), findsOneWidget);
      expect(find.text('18 Transaksi'), findsOneWidget);
      expect(find.byKey(const Key('workspace_switcher_strip')), findsOneWidget);

      await authCubit.close();
      await posCubit.close();
      await themeCubit.close();
      await connectivity.dispose();
    });

    testWidgets('NusaCopilotSheet supports Chat, Voice Input & Inline Modal Error Guard (422)',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;

      final capturedPayloads = <Map<String, dynamic>>[];
      bool failNextRequest = false;

      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/ai/copilot/chat') && options.method == 'POST') {
          capturedPayloads.add(Map<String, dynamic>.from(options.data as Map));
          if (failNextRequest) {
            return (
              429,
              {'success': false, 'message': 'Kuota AI bulanan Anda telah habis.'},
            );
          }
          return (
            200,
            {
              'success': true,
              'data': {
                'reply': '**Ringkasan Cabang**: Omzet hari ini **Rp 2.500.000** (12 transaksi).',
                'engine_mode': 'local_grounded',
                'tokens_used': 0,
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);

      final ownerSession = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(ownerSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');

      NusaVoiceInputService.debugCaptureOverride = ({String locale = 'id-ID'}) async {
        return const VoiceCaptureResult(
          supported: true,
          transcript: 'Cek omzet hari ini lewat suara',
        );
      };

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: NusaCopilotSheet(workspace: MobileWorkspaceRole.ownerPulse),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Voice input captures transcript & sends input_mode: 'voice'
      await tester.tap(find.byKey(const Key('copilot_voice_button')));
      await tester.pumpAndSettle();
      expect(capturedPayloads.length, 1);
      expect(capturedPayloads.first['input_mode'], 'voice');
      expect(capturedPayloads.first['message'], 'Cek omzet hari ini lewat suara');
      expect(find.text('Input Suara'), findsOneWidget);
      expect(find.text('Analisis Lokal Real-Time'), findsOneWidget);

      // 2. HTTP 429 error renders visibly inline inside the sheet (never hidden behind sheet!)
      failNextRequest = true;
      await tester.enterText(find.byKey(const Key('copilot_text_input')), 'Tanya lagi');
      await tester.tap(find.byKey(const Key('copilot_send_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('copilot_inline_error')), findsOneWidget);
      expect(find.text('Kuota AI bulanan Anda telah habis.'), findsOneWidget);

      await authCubit.close();
    });

    testWidgets('NusaCopilotSheet renders Nusa Buddy mascot & 0-token Semantic Cache FAQ without overflow at 360x640',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;

      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/ai/copilot/chat') && options.method == 'POST') {
          return (
            200,
            {
              'success': true,
              'data': {
                'reply': '**SOP Terima Barang (GRN):** Buka Purchase Order Approved lalu tekan tombol Terima Barang.',
                'provider': 'semantic_cache',
                'engine_mode': 'semantic_cache',
                'notice': 'Dijawab instan dari Cache & FAQ Resmi Nusa Buddy (0 token · Rp 0).',
                'cache_hit': true,
                'tokens_used': 0,
                'estimated_cost_idr': 0.0,
                'avatar_state': 'guiding',
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);

      final ownerSession = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(ownerSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: NusaCopilotSheet(workspace: MobileWorkspaceRole.ownerPulse),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('copilot_nusa_buddy_mascot')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('copilot_text_input')), 'Bagaimana cara terima barang PO?');
      await tester.tap(find.byKey(const Key('copilot_send_button')));
      await tester.pumpAndSettle();

      expect(find.text('0 tok · Cache FAQ'), findsOneWidget);
      expect(find.textContaining('SOP Terima Barang', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);

      await authCubit.close();
    });

    testWidgets('NusaCopilotSheet renders interactive follow-up chips, multi-period IDR reply & offline error cleanly at 360x640',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;

      final capturedPayloads = <Map<String, dynamic>>[];
      bool simulateOffline = false;

      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/ai/copilot/chat') && options.method == 'POST') {
          if (simulateOffline) {
            throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'SocketException: Failed host lookup',
            );
          }
          final payload = Map<String, dynamic>.from(options.data as Map);
          capturedPayloads.add(payload);
          return (
            200,
            {
              'success': true,
              'data': {
                'session_id': 'mobile-srv-session-77',
                'reply': '### Analisa Mingguan\n- **Omzet Minggu Ini (WTD):** **Rp 2.500.000** (`2 transaksi`)\n- *Pertumbuhan WoW: +100%*',
                'provider': 'gemini_v2',
                'engine_mode': 'gemini_v2',
                'tokens_used': 120,
                'cache_hit': false,
                'avatar_state': 'idle',
                'follow_up_chips': [
                  {
                    'label': 'Omzet Bulan Ini (MTD)',
                    'prompt': 'Bagaimana performa omzet bulan ini dibandingkan bulan lalu?',
                  },
                  {
                    'label': 'Cek Stok Kritis',
                    'prompt': 'Produk apa saja yang stoknya kritis?',
                  },
                ],
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);

      final ownerSession = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(ownerSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: NusaCopilotSheet(workspace: MobileWorkspaceRole.ownerPulse),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Ask weekly revenue question -> receives formatted IDR + interactive follow-up chips
      await tester.enterText(find.byKey(const Key('copilot_text_input')), 'kalau omset minggu ini berapa?');
      await tester.tap(find.byKey(const Key('copilot_send_button')));
      await tester.pumpAndSettle();

      expect(capturedPayloads.length, 1);
      expect(capturedPayloads.first['workspace'], 'ownerPulse');
      expect((capturedPayloads.first['session_id'] ?? '').toString(), isNotEmpty);
      expect(find.textContaining('Rp 2.500.000', findRichText: true), findsOneWidget);
      expect(find.text('Gemini AI'), findsOneWidget);
      expect(find.byKey(const Key('copilot_followup_chips')), findsOneWidget);
      expect(find.text('Omzet Bulan Ini (MTD)'), findsOneWidget);

      // 2. Tap follow-up chip -> dispatches follow-up prompt reusing server session_id
      await tester.tap(find.text('Omzet Bulan Ini (MTD)'));
      await tester.pumpAndSettle();

      expect(capturedPayloads.length, 2);
      expect(capturedPayloads[1]['message'], 'Bagaimana performa omzet bulan ini dibandingkan bulan lalu?');
      expect(capturedPayloads[1]['session_id'], 'mobile-srv-session-77');

      // 3. Offline error surfaces clean Indonesian inline banner (never crashes)
      simulateOffline = true;
      await tester.enterText(find.byKey(const Key('copilot_text_input')), 'Cek stok offline');
      await tester.tap(find.byKey(const Key('copilot_send_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('copilot_inline_error')), findsOneWidget);
      expect(find.textContaining('Koneksi internet terputus'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await authCubit.close();
    });

    testWidgets('OXORA Buddy Mascot runs 5-phase asset choreography (Greeting -> Idle -> Thinking -> Success -> Idle -> Poke)',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;

      Completer<void>? pendingGate;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/ai/copilot/chat') && options.method == 'POST') {
          final gate = pendingGate;
          if (gate != null) {
            await gate.future;
          }
          return (
            200,
            {
              'success': true,
              'data': {
                'reply': 'Laporan omzet siap.',
                'engine_mode': 'local_grounded',
                'tokens_used': 0,
                'avatar_state': 'idle',
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);

      final ownerSession = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(ownerSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');

      String activeMascotAsset() {
        final images = tester.widgetList<Image>(
          find.descendant(
            of: find.byKey(const Key('copilot_nusa_buddy_mascot')),
            matching: find.byType(Image),
          ),
        );
        final provider = images.last.image;
        final assetImage = provider is ResizeImage
            ? provider.imageProvider as AssetImage
            : provider as AssetImage;
        return assetImage.assetName;
      }

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: NusaCopilotSheet(workspace: MobileWorkspaceRole.ownerPulse),
            ),
          ),
        ),
      );

      // Phase 1: Greeting (large perched full-body waving Animated WebP)
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('OXORA Buddy (greeting)'), findsOneWidget);
      expect(activeMascotAsset(), 'assets/images/buddy/buddy_greeting.webp');
      final mascotBox = tester.getSize(find.byKey(const Key('copilot_nusa_buddy_mascot')));
      expect(mascotBox.height, greaterThanOrEqualTo(100.0));

      // Auto-transition after 2.2s -> Phase 2: Idle (half-body living gaze/blink Animated WebP)
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.bySemanticsLabel('OXORA Buddy (idle)'), findsOneWidget);
      expect(activeMascotAsset(), 'assets/images/buddy/buddy_idle.webp');

      // Phase 3: Thinking / Typing (headphones + laptop typing Animated WebP) while API request is in-flight
      pendingGate = Completer<void>();
      await tester.enterText(find.byKey(const Key('copilot_text_input')), 'Ringkas omzet');
      await tester.tap(find.byKey(const Key('copilot_send_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.bySemanticsLabel('OXORA Buddy (thinking)'), findsOneWidget);
      expect(activeMascotAsset(), 'assets/images/buddy/buddy_working.webp');

      // Phase 4: Arrival / Success joyful bounce Animated WebP -> settles back to Phase 2 Idle
      pendingGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.bySemanticsLabel('OXORA Buddy (success)'), findsOneWidget);
      expect(activeMascotAsset(), 'assets/images/buddy/buddy_success.webp');

      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('OXORA Buddy (idle)'), findsOneWidget);
      expect(activeMascotAsset(), 'assets/images/buddy/buddy_idle.webp');

      // Phase 5: Poke / Tap squash & stretch reaction
      await tester.tap(find.byKey(const Key('copilot_nusa_buddy_mascot')));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await authCubit.close();
    });

    testWidgets('ShiftManagementScreen enforces Strict Blind Drop, handles VarianceReasonRequired inline & displays Server Z-Report',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      final printer = PrinterService();

      bool shiftIsOpen = true;
      final closePayloads = <Map<String, dynamic>>[];

      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/shifts/current') && options.method == 'GET') {
          if (!shiftIsOpen) {
            return (
              200,
              {
                'success': true,
                'data': {
                  'has_open_shift': false,
                  'blind_drop_enforced': true,
                  'can_view_expected_cash': false,
                  'shift': null,
                  'terminals': [],
                },
              },
            );
          }
          return (
            200,
            {
              'success': true,
              'data': {
                'has_open_shift': true,
                'blind_drop_enforced': true,
                'can_view_expected_cash': false,
                'shift': {
                  'id': 77,
                  'status': 'open',
                  'blind_drop_enforced': true,
                  'can_view_expected_cash': false,
                  'opening_cash': 200000,
                  'expected_cash': null,
                  'cash_sales': null,
                  'sales_total': null,
                  'sales_count': 4,
                  'pay_ins': 0,
                  'pay_outs': 0,
                  'payment_totals': [],
                  'terminal': {'id': 1, 'name': 'POS-01'},
                  'entries': [],
                },
                'terminals': [],
                'variance_reasons': [
                  {'code': 'miscount', 'name': 'Salah hitung uang / kembalian'},
                ],
              },
            },
          );
        }

        if (options.path.endsWith('/shifts/close') && options.method == 'POST') {
          final body = Map<String, dynamic>.from(options.data as Map);
          closePayloads.add(body);
          if (body['variance_reason'] == null) {
            return (
              422,
              {
                'success': false,
                'error_code': 'VarianceReasonRequired',
                'requires_variance_reason': true,
                'message': 'Selisih kas di luar toleransi. Pilih alasan selisih.',
                'variance_reasons': [
                  {'code': 'miscount', 'name': 'Salah hitung uang / kembalian'},
                ],
              },
            );
          }
          shiftIsOpen = false;
          return (
            200,
            {
              'success': true,
              'data': {
                'id': 77,
                'status': 'closed_with_variance',
                'expected_cash': 500000,
                'closing_cash_counted': 495000,
                'cash_variance': -5000,
                'cash_shortage': 5000,
                'cash_overage': 0,
                'z_report': {
                  'shift_id': 77,
                  'status': 'closed_with_variance',
                  'variance_status': 'shortage',
                  'opening_cash': 200000,
                  'cash_sales': 300000,
                  'sales_total': 300000,
                  'pay_ins': 0,
                  'pay_outs': 0,
                  'expected_cash': 500000,
                  'counted_cash': 495000,
                  'cash_variance': -5000,
                  'cash_shortage': 5000,
                  'cash_overage': 0,
                },
              },
            },
          );
        }
        return (200, {'success': true, 'data': {}});
      });

      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final cashierSession = _sessionForRole(
        role: 'Cashier',
        isOwner: false,
        permissions: const ['sales.create', 'shifts.open', 'shifts.close_own'],
      );
      await db.saveAuthSession(cashierSession.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('mockPayload.mockSignature');

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ShiftManagementScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Expected cash strictly hidden on open shift
      expect(find.text('Rp ••••••• (Terkunci Server)'), findsOneWidget);
      expect(find.text('STRICT BLIND DROP'), findsOneWidget);

      // 2. Enter physical count and lock (still MUST NOT reveal expected_cash!)
      await tester.enterText(find.byKey(const Key('shift_counted_cash_input')), '495000');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('shift_lock_count_btn')));
      await tester.tap(find.byKey(const Key('shift_lock_count_btn')));
      await tester.pumpAndSettle();
      expect(find.text('Rp ••••••• (Terkunci Server)'), findsOneWidget);

      // 3. Submit close -> server rejects with VarianceReasonRequired -> inline banner + reason picker shown
      await tester.ensureVisible(find.byKey(const Key('shift_close_submit_btn')));
      await tester.tap(find.byKey(const Key('shift_close_submit_btn')));
      await tester.pumpAndSettle();

      expect(closePayloads.length, 1);
      expect(closePayloads.first.containsKey('expected_cash'), isFalse);
      expect(find.byKey(const Key('shift_close_inline_error')), findsOneWidget);
      expect(find.text('Alasan Selisih Kas (Wajib untuk Audit Z-Report)'), findsOneWidget);

      // 4. Resubmit with selected variance reason -> server verifies & renders Z-Report card
      await tester.ensureVisible(find.byKey(const Key('shift_close_submit_btn')));
      await tester.tap(find.byKey(const Key('shift_close_submit_btn')));
      await tester.pumpAndSettle();

      expect(closePayloads.length, 2);
      expect(closePayloads[1]['variance_reason'], 'miscount');
      expect(find.byKey(const Key('shift_z_report_card')), findsOneWidget);
      expect(find.text('Ringkasan Z-Report Terverifikasi Server'), findsOneWidget);
      expect(find.text('SHORTAGE'), findsOneWidget);

      await authCubit.close();
    });

    test('Non-owner departmental admin titles (Admin Gudang, Admin HR, Admin Kasir) NEVER escalate to Owner', () {
      final adminGudang = _sessionForRole(
        role: 'Admin Gudang',
        isOwner: false,
        permissions: const ['products.view', 'warehouse.view', 'products.adjust_stock'],
      );
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(adminGudang), isFalse);
      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(adminGudang), MobileWorkspaceRole.warehouseWorkbench);
      expect(MobileWorkspaceResolver.canUsePos(adminGudang), isFalse);
      expect(MobileWorkspaceResolver.canViewOwnerDashboard(adminGudang), isFalse);

      final adminHr = _sessionForRole(
        role: 'Admin HR',
        isOwner: false,
        permissions: const ['hr.view', 'hr.manage_attendances', 'tasks.view'],
      );
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(adminHr), isFalse);
      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(adminHr), MobileWorkspaceRole.employeeEss);
      expect(MobileWorkspaceResolver.canUsePos(adminHr), isFalse);
      expect(MobileWorkspaceResolver.canViewOwnerDashboard(adminHr), isFalse);

      final adminKasir = _sessionForRole(
        role: 'Admin Kasir',
        isOwner: false,
        permissions: const ['sales.create', 'shifts.open', 'shifts.close_own'],
      );
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(adminKasir), isFalse);
      expect(MobileWorkspaceResolver.resolveDefaultWorkspace(adminKasir), MobileWorkspaceRole.posFastLane);
      expect(MobileWorkspaceResolver.canViewOwnerDashboard(adminKasir), isFalse);

      // AuthSessionModel.fromApiData must strictly honor is_owner=false and exact owner role allowlist
      final fromApiExplicit = AuthSessionModel.fromApiData({
        'user': {
          'id': 88,
          'name': 'Budi Gudang',
          'email': 'budi.gudang@nusa.test',
          'is_owner': false,
          'role': 'admin gudang',
          'roles': ['admin gudang'],
        },
        'permissions': ['products.view', 'warehouse.view'],
        'tenant': {'name': 'Nusa Demo', 'subdomain': 'nusa-demo', 'plan_name': 'Enterprise'},
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'HQ-01'},
      });
      expect(fromApiExplicit.isOwner, isFalse);
      expect(fromApiExplicit.userRole, 'admin gudang');
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(fromApiExplicit), isFalse);

      final fromApiImplicit = AuthSessionModel.fromApiData({
        'user': {
          'id': 89,
          'name': 'Sari HR',
          'email': 'sari.hr@nusa.test',
          'role': 'Admin HRD',
        },
        'permissions': ['hr.view'],
        'tenant': {'name': 'Nusa Demo', 'subdomain': 'nusa-demo', 'plan_name': 'Enterprise'},
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'HQ-01'},
      });
      expect(fromApiImplicit.isOwner, isFalse);
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(fromApiImplicit), isFalse);

      // Fail-closed: missing role/roles and missing is_owner MUST NEVER escalate to Owner
      final missingRole = AuthSessionModel.fromApiData({
        'user': {'id': 90, 'name': 'Staff Baru', 'email': 'staff@nusa.test'},
        'permissions': ['hr.view'],
        'tenant': {'name': 'Nusa Demo', 'subdomain': 'nusa-demo', 'plan_name': 'Enterprise'},
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'HQ-01'},
      });
      expect(missingRole.isOwner, isFalse);
      expect(missingRole.userRole, 'Operator');
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(missingRole), isFalse);

      // Fail-closed: explicit is_owner=false with role='admin' & empty permissions MUST NOT switch workspaces
      final restrictedAdmin = AuthSessionModel.fromApiData({
        'user': {'id': 91, 'name': 'Restricted', 'is_owner': false, 'role': 'admin'},
        'permissions': [],
        'tenant': {'name': 'Nusa Demo', 'subdomain': 'nusa-demo', 'plan_name': 'Enterprise'},
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'HQ-01'},
      });
      expect(restrictedAdmin.isOwner, isFalse);
      expect(MobileWorkspaceResolver.canSwitchWorkspaces(restrictedAdmin), isFalse);

      // Strict Blind Drop alignment: Warehouse Manager without shifts.* perms MUST NOT pass isSupervisorOrAbove
      final warehouseMgr = _sessionForRole(
        role: 'Warehouse Manager',
        isOwner: false,
        permissions: const ['products.view', 'warehouse.view', 'products.adjust_stock'],
      );
      expect(MobileWorkspaceResolver.isSupervisorOrAbove(warehouseMgr), isFalse);

      final shiftSup = _sessionForRole(
        role: 'Supervisor Shift',
        isOwner: false,
        permissions: const ['shifts.view_all', 'shifts.close_others'],
      );
      expect(MobileWorkspaceResolver.isSupervisorOrAbove(shiftSup), isTrue);
    });

    testWidgets('Phone 360x640 Outdoor High-Contrast POS Fast-Lane & ShiftManagementScreen (with Denom Calculator) have zero overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
        if (options.path.endsWith('/shifts/current')) {
          return (
            200,
            {
              'success': true,
              'data': {
                'has_open_shift': true,
                'blind_drop_enforced': true,
                'can_view_expected_cash': false,
                'shift': {
                  'id': 99,
                  'status': 'open',
                  'blind_drop_enforced': true,
                  'can_view_expected_cash': false,
                  'opening_cash': 1500000,
                  'expected_cash': null,
                  'cash_sales': null,
                  'sales_total': null,
                  'sales_count': 42,
                  'pay_ins': 250000,
                  'pay_outs': 50000,
                  'payment_totals': [],
                  'terminal': {'id': 1, 'name': 'POS Utama Cabang Sudirman'},
                  'entries': [],
                },
                'terminals': [],
              },
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      const store = StoreBranchModel(id: 1, name: 'Cabang Grand Sudirman Pusat', code: 'HQ-01');
      const cashier = AuthSessionModel(
        userId: 22,
        userName: 'Operator Cashier',
        userEmail: 'kasir@nusa.test',
        userRole: 'Cashier',
        isOwner: false,
        tenantName: 'Nusa Demo',
        tenantSubdomain: 'nusa-demo',
        planName: 'Enterprise',
        tier: 'enterprise',
        activeModules: ['cash_debt', 'accounting', 'online_store', 'hr', 'warehouse', 'crm'],
        activeStore: store,
        availableStores: [store],
        permissions: ['sales.create', 'shifts.open', 'shifts.close_own', 'products.view'],
        isLocalTrial: false,
      );
      await db.saveAuthSession(cashier.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('tok.sig');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.outdoorHighContrast);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.outdoorHighContrastTheme,
            home: const MainNavigationShell(initialIndex: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // Switch to ShiftManagementScreen tab (index 3) at 360x640 Outdoor HC
      await tester.tap(find.text('Shift Kasir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(ShiftManagementScreen), findsOneWidget);

      // Expand denomination calculator and increment Rp 100.000 at 360x640 -> zero overflow!
      final denomToggle = find.text('Hitung Pecahan Uang (100rb - 1rb)');
      await tester.ensureVisible(denomToggle);
      await tester.tap(denomToggle);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('AllModulesDirectoryView strictly isolates RBAC per role & adopts Dark Mode tokens',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);

      // 1. HRD/ESS user in Dark Mode must NOT see Laporan Laba Rugi, Kasir POS, Buku Kas, or PO
      final hrd = _sessionForRole(
        role: 'HRD',
        isOwner: false,
        permissions: const ['hr.view', 'hr.manage_attendances', 'tasks.view'],
      );
      await db.saveAuthSession(hrd.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      addTearDown(authCubit.close);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AllModulesDirectoryView(onOpenDrawer: () {}, onSwitchTab: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Laporan Laba Rugi'), findsNothing);
      expect(find.text('Pusat Laporan Bisnis'), findsNothing);
      expect(find.text('Kasir POS'), findsNothing);
      expect(find.text('Buku Kas Toko'), findsNothing);
      expect(find.text('Order Beli (PO)'), findsNothing);
      expect(find.text('HRD & Absensi Staf'), findsNothing);
      expect(find.text('Pengaturan Aplikasi & Akun'), findsOneWidget);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, NusaThemeTokens.warmLinenDark.bgPage);

      // 2. Admin Gudang sees Opname Stok & Data Barang, NOT Kasir POS or Laporan Laba Rugi
      final gudang = _sessionForRole(
        role: 'Admin Gudang',
        isOwner: false,
        permissions: const ['products.view', 'warehouse.view', 'products.adjust_stock'],
      );
      await db.saveAuthSession(gudang.toJson());
      final authGudang = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authGudang.checkExistingSession();
      addTearDown(authGudang.close);

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authGudang,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: AllModulesDirectoryView(onOpenDrawer: () {}, onSwitchTab: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Opname Stok'), findsOneWidget);
      expect(find.text('Data Barang'), findsOneWidget);
      expect(find.text('Kasir POS'), findsNothing);
      expect(find.text('Laporan Laba Rugi'), findsNothing);
      expect(find.text('HRD & Absensi Staf'), findsNothing);
    });

    test('NusaVoiceInputService MethodChannel contract invokes startVoiceRecognition (id-ID) & handles cancel/errors',
        () async {
      const channel = MethodChannel('com.nusacommerce.mobile/voice');
      final capturedCalls = <MethodCall>[];
      Object? nextReply = 'Ringkas omzet hari ini';

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        capturedCalls.add(call);
        final reply = nextReply;
        if (reply is PlatformException) {
          throw reply;
        }
        return reply;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = NusaVoiceInputService();

      // 0. Availability check (`isVoiceRecognitionAvailable`)
      nextReply = true;
      expect(await service.isAvailable(), isTrue);
      expect(capturedCalls.last.method, 'isVoiceRecognitionAvailable');

      // 1. Happy path transcript
      nextReply = 'Ringkas omzet hari ini';
      final ok = await service.listenOnce(locale: 'id-ID');
      expect(ok.supported, isTrue);
      expect(ok.transcript, 'Ringkas omzet hari ini');
      expect(capturedCalls.last.method, 'startVoiceRecognition');
      expect((capturedCalls.last.arguments as Map)['locale'], 'id-ID');

      // 2. Cancelled / empty speech
      nextReply = '';
      final empty = await service.listenOnce();
      expect(empty.supported, isTrue);
      expect(empty.transcript, isNull);
      expect(empty.infoMessage, isNotEmpty);

      // 3. Unavailable speech service on device
      nextReply = PlatformException(
        code: 'VOICE_UNAVAILABLE',
        message: 'Layanan pengenalan suara Android tidak tersedia.',
      );
      final err = await service.listenOnce();
      expect(err.supported, isFalse);
      expect(err.transcript, isNull);
      expect(err.infoMessage, contains('tidak tersedia'));
    });

    testWidgets('Core screens (PosCatalogScreen & SettingsScreen) honor Dark & Outdoor High-Contrast tokens without overflow at 360x640',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
        onHandle: (_) async => (200, {'success': true, 'data': []}),
      );
      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final owner = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(owner.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenDark);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      // 1. SettingsScreen in Dark Mode
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        NusaThemeTokens.warmLinenDark.bgPage,
      );

      // 2. PosCatalogScreen in Outdoor High-Contrast Mode at 360x640
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.outdoorHighContrastTheme,
            home: const PosCatalogScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        NusaThemeTokens.outdoorHighContrast.bgPage,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Read-only Auditor gets zero POS/write CTAs and adapts Primary CTA to Reports',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
        onHandle: (_) async => (200, {'success': true, 'data': []}),
      );
      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final auditor = _sessionForRole(
        role: 'Auditor',
        isOwner: false,
        permissions: const ['reports.view_sales', 'reports.view_financial', 'audit.view'],
      );
      await db.saveAuthSession(auditor.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('tok.sig');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenDark);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      final cta = MobileWorkspaceResolver.primaryCtaForSession(auditor, MobileWorkspaceRole.managerDesk);
      expect(cta.route, '/reports');
      expect(cta.shortLabel, 'Laporan');

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const MainNavigationShell(initialIndex: 0),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Buka Kasir POS'), findsNothing);
      expect(find.text('Kasir POS'), findsNothing);
      expect(find.text('+ Barang'), findsNothing);
      expect(find.text('Catat Kas'), findsNothing);
      expect(find.text('Scan Opname'), findsNothing);
      expect(find.text('Laporan'), findsOneWidget);
      expect(find.text('Buka Laporan & Audit Terpadu'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('HRD/ESS with products.view navigates to ProductsInventoryScreen (not HrAttendance) from AllModulesDirectoryView',
        (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
        onHandle: (_) async => (200, {'success': true, 'data': []}),
      );
      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final hrdWithCatalog = _sessionForRole(
        role: 'HRD',
        isOwner: false,
        permissions: const ['hr.view', 'products.view'],
      );
      await db.saveAuthSession(hrdWithCatalog.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenDark);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const MainNavigationShell(initialIndex: 3),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Data Barang'), findsOneWidget);
      await tester.tap(find.text('Data Barang'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(ProductsInventoryScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Populated daily & Warehouse screens have zero RenderFlex overflow and honor Dark Mode Scaffolds at 360x640',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
        onHandle: (opts) async {
          if (opts.path.endsWith('/reports/owner-dashboard')) {
            return (
              200,
              {
                'success': true,
                'data': {
                  'filter': {'profit_visible': true},
                  'kpi': {
                    'net_sales': 18450000,
                    'transactions_count': 124,
                    'gross_profit': 5420000,
                    'net_profit': 3900000,
                    'margin_percent': 29.4,
                    'expenses_total': 1520000,
                    'growth_vs_yesterday_percent': 12.4,
                  },
                  'operational_alerts': {
                    'low_stock_count': 8,
                    'expiring_batches_count': 3,
                    'receivables_total': 3200000,
                    'payables_total': 1850000,
                  },
                  'anti_fraud_summary': {
                    'voided_sales_count': 2,
                    'refunds_count': 1,
                    'shift_variance_alerts_count': 1,
                    'no_sale_drawer_opens_count': 3,
                  },
                },
              },
            );
          }
          if (opts.path.endsWith('/sales')) {
            return (
              200,
              {
                'success': true,
                'data': [
                  {
                    'id': 501,
                    'number': 'INV-20261120-0001',
                    'sale_datetime': '2026-11-20 10:15:00',
                    'customer': {'name': 'PT Pelanggan Nusantara Sejahtera'},
                    'grand_total': 245000,
                    'balance_due': 0,
                    'status': 'completed',
                    'payment_methods': ['Tunai'],
                  },
                ],
              },
            );
          }
          if (opts.path.endsWith('/receivables')) {
            return (
              200,
              {
                'success': true,
                'data': {
                  'summary': {'total_receivables': 1500000},
                  'invoices': [
                    {
                      'id': 1,
                      'sale_id': 1,
                      'number': 'INV-BON-001',
                      'customer_name': 'Warung Sejahtera Abadi',
                      'balance_due': 1500000,
                      'due_date': '2026-11-10',
                    }
                  ],
                },
              },
            );
          }
          if (opts.path.endsWith('/payables')) {
            return (200, {'success': true, 'data': {'summary': {'total_payables': 0}, 'invoices': []}});
          }
          if (opts.path.endsWith('/expenses')) {
            return (200, {'success': true, 'data': {'expenses': [], 'categories': []}});
          }
          return (200, {'success': true, 'data': []});
        },
      );
      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final owner = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(owner.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('tok.sig');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenDark);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      final screens = <(String, Widget)>[
        ('TransactionsHistoryScreen', TransactionsHistoryScreen(onOpenDrawer: () {})),
        ('BusinessReportsScreen', const BusinessReportsScreen()),
        ('DebtBookScreen', const DebtBookScreen()),
        ('CashLedgerScreen', const CashLedgerScreen()),
        ('LoginScreen', LoginScreen(apiClient: apiClient)),
        ('PurchasesAndReturnsScreen', const PurchasesAndReturnsScreen(initialTab: 0)),
        ('InventoryOperationsScreen', const InventoryOperationsScreen(initialTab: 0)),
      ];

      for (final (name, widget) in screens) {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<PosCubit>.value(value: posCubit),
              BlocProvider<ThemeCubit>.value(value: themeCubit),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: widget,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull, reason: '$name threw overflow/exception at 360x640 Dark Mode');
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          NusaThemeTokens.warmLinenDark.bgPage,
          reason: '$name Scaffold must use warmLinenDark.bgPage in Dark Mode',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('BusinessReportsScreen 8-category 50-Report Hub & Pajak/Finansial detail render with zero overflow at 360x640 Dark Mode',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      final capturedPaths = <String>[];
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
        onHandle: (opts) async {
          capturedPaths.add(opts.path);
          if (opts.path.endsWith('/reports/owner-dashboard')) {
            return (
              200,
              {
                'success': true,
                'data': {
                  'filter': {'profit_visible': true},
                  'kpi': {
                    'net_sales': 18450000,
                    'transactions_count': 124,
                    'gross_profit': 5420000,
                    'net_profit': 3900000,
                    'margin_percent': 29.4,
                    'expenses_total': 1520000,
                    'growth_vs_yesterday_percent': 12.4,
                  },
                  'operational_alerts': {
                    'low_stock_count': 4,
                    'expiring_batches_count': 2,
                    'receivables_total': 1500000,
                    'payables_total': 900000,
                  },
                  'anti_fraud_summary': {
                    'voided_sales_count': 1,
                    'refunds_count': 1,
                    'shift_variance_alerts_count': 0,
                    'no_sale_drawer_opens_count': 1,
                  },
                },
              },
            );
          }
          if (opts.path.endsWith('/reports/catalog')) {
            return (
              200,
              {
                'success': true,
                'data': {
                  'total_reports': 50,
                  'available_stores': [
                    {'id': 1, 'name': 'Cabang Utama', 'code': 'HQ-01'},
                  ],
                  'categories': [],
                },
              },
            );
          }
          if (opts.path.contains('/reports/run/tax-summary')) {
            return (
              200,
              {
                'success': true,
                'data': {
                  'report': {
                    'id': 'tax-summary',
                    'title': 'Ringkasan Pajak PPN & PB1 Resto',
                    'category': 'tax_financial',
                  },
                  'period': {'start_date': '2026-11-01', 'end_date': '2026-11-22'},
                  'summary': {
                    'ppn_output': 440000,
                    'ppn_input': 99000,
                    'ppn_net_payable': 341000,
                  },
                  'kpis': [
                    {'key': 'ppn_output', 'label': 'PPN Keluaran', 'value': 440000, 'formatted': 'Rp 440.000', 'tone': 'neutral'},
                    {'key': 'ppn_input', 'label': 'PPN Masukan', 'value': 99000, 'formatted': 'Rp 99.000', 'tone': 'positive'},
                    {'key': 'ppn_net_payable', 'label': 'PPN Kurang Bayar', 'value': 341000, 'formatted': 'Rp 341.000', 'tone': 'warning'},
                  ],
                  'items': [
                    {
                      'id': 'ppn-11',
                      'title': 'PPN 11% Penjualan POS',
                      'subtitle': 'Cabang Utama • 124 faktur',
                      'primary_value': 'Rp 440.000',
                      'secondary_value': 'DPP Rp 4.000.000',
                      'badge': 'PPN 11%',
                      'badge_tone': 'positive',
                      'details': {'Tarif': '11%', 'Total Pajak': 'Rp 440.000'},
                    },
                  ],
                },
              },
            );
          }
          return (200, {'success': true, 'data': {}});
        },
      );

      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final owner = _sessionForRole(role: 'Pemilik Usaha', isOwner: true, permissions: const ['*']);
      await db.saveAuthSession(owner.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('tok.sig');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenDark);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const BusinessReportsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tester.takeException(), isNull, reason: '50-Report Hub threw RenderFlex overflow at 360x640 Dark Mode');
      expect(capturedPaths.any((p) => p.endsWith('/reports/catalog')), isTrue);
      expect(find.text('Pusat Laporan Bisnis'), findsOneWidget);
      expect(find.textContaining('50 Laporan Cloud-Parity'), findsOneWidget);

      // Filter by searching "PPN" across the 50 reports and tap the Pajak report card
      await tester.enterText(find.byType(TextField).first, 'PPN');
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Ringkasan Pajak PPN & PB1'), findsOneWidget);

      await tester.tap(find.text('Ringkasan Pajak PPN & PB1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tester.takeException(), isNull, reason: 'Report Detail threw RenderFlex overflow at 360x640 Dark Mode');
      expect(capturedPaths.any((p) => p.contains('/reports/run/tax-summary')), isTrue);
      expect(find.text('PPN 11% Penjualan POS'), findsOneWidget);
      expect(find.text('Rp 440.000'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
        'BusinessReportsScreen surfaces online 403 error (never fake local report), neutralizes CSV formulas (SEC #18), and drills down real No-Sale Laci events',
        (WidgetTester tester) async {
      // 1. Unit assertions for SEC #18 CSV formula neutralization & quote escaping
      expect(BusinessReportsScreen.sanitizeCsvCell('=HYPERLINK("http://evil")'), '"\'=HYPERLINK(""http://evil"")"');
      expect(BusinessReportsScreen.sanitizeCsvCell('+SUM(A1:A2)'), '"\'+SUM(A1:A2)"');
      expect(BusinessReportsScreen.sanitizeCsvCell('-1+1'), '"\'-1+1"');
      expect(BusinessReportsScreen.sanitizeCsvCell('@cmd'), '"\'@cmd"');
      expect(BusinessReportsScreen.sanitizeCsvCell('Kopi "Arabika"\nPremium'), '"Kopi ""Arabika"" Premium"');

      // 2. Online 403 Forbidden MUST show error banner and NEVER fall back to fake local report even with cached products
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.cacheProducts([
        {'id': 1, 'name': 'Cached Product', 'sku': 'SKU-1', 'stock': 10, 'selling_price': 50000, 'cost_price': 25000},
      ]);

      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
        onHandle: (opts) async {
          if (opts.path.endsWith('/reports/owner-dashboard') || opts.path.endsWith('/reports/sales-summary')) {
            return (
              403,
              {'success': false, 'message': 'Akses ditolak: Anda tidak memiliki izin melihat laporan.'},
            );
          }
          return (403, {'success': false, 'message': 'Forbidden'});
        },
      );

      final connectivity = _AlwaysOnlineConnectivity();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final cashier = _sessionForRole(role: 'Cashier', isOwner: false, permissions: const ['sales.create']);
      await db.saveAuthSession(cashier.toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      await apiClient.saveToken('tok.sig');
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenDark);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const BusinessReportsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.textContaining('Akses ditolak'), findsOneWidget);
      expect(find.text('Coba Lagi'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'AppBar actions on PaymentCheckoutScreen/PosCatalogScreen (360x800) & transient 1.6x1.6 resize have zero overflow (BUG-025)',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final prevHandler = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);

        try {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final offlineDb = OfflineDatabase(prefs);
          await offlineDb.initialize();
          final apiClient = ApiClient(
            secureStorage: const FlutterSecureStorage(),
            prefs: prefs,
          );
          apiClient.dio.httpClientAdapter = _DynamicTestAdapter(
            onHandle: (opts) async => (200, {'success': true, 'data': []}),
          );
          final connectivity = _AlwaysOnlineConnectivity();
          final printerService = PrinterService();
          await printerService.initialize(prefs);
          final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
          final posCubit = PosCubit(
            apiClient: apiClient,
            offlineDb: offlineDb,
            connectivityService: connectivity,
          );
          final themeCubit = ThemeCubit(prefs: prefs);

          final prod = ProductModel.fromJson({
            'id': 1,
            'name': 'Apple iPhone 16 128GB',
            'sku': 'IP16-128',
            'selling_price': 16800000.0,
            'stock': 9.0,
            'tax_group': {'id': 5, 'name': 'PPN 12%', 'is_inclusive': false, 'total_rate': 12.0},
          });
          posCubit.addToCart(prod, quantity: 1);

          // 1. Test 360x800 on PaymentCheckoutScreen (with Split Bill AppBar action & PPN 12% hero)
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<PosCubit>.value(value: posCubit),
                BlocProvider<ThemeCubit>.value(value: themeCubit),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                home: PaymentCheckoutScreen(offlineDb: offlineDb),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.text('Pembayaran'), findsOneWidget);
          expect(find.text('Split Bill'), findsOneWidget);

          // 2. Test 360x800 on PosCatalogScreen (Shift + Table + Sync actions)
          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<PosCubit>.value(value: posCubit),
                BlocProvider<ThemeCubit>.value(value: themeCubit),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                home: const PosCatalogScreen(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));

          // 3. Test transient 1.6x1.6 resize frame inside NusaCommerceMobileApp builder
          tester.view.physicalSize = const Size(1.6, 1.6);
          await tester.pumpWidget(
            NusaCommerceMobileApp(
              apiClient: apiClient,
              offlineDb: offlineDb,
              printerService: printerService,
              authCubit: authCubit,
              posCubit: posCubit,
              themeCubit: themeCubit,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));

          tester.view.physicalSize = const Size(360, 800);
          await tester.pump(const Duration(milliseconds: 200));

          expect(
            errors.where((e) => e.toString().contains('RenderFlex')),
            isEmpty,
            reason: 'Expected zero RenderFlex overflow errors, got: $errors',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await posCubit.close();
          await authCubit.close();
          await connectivity.dispose();
          await themeCubit.close();
        } finally {
          FlutterError.onError = prevHandler;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );

    testWidgets(
      'PosCatalogScreen hides 0-stock tracked products, keeps service items, shows Multi-Warehouse stock & avoids Rp price ellipsis on 360x800',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        final prevHandler = FlutterError.onError;
        final errors = <FlutterErrorDetails>[];
        FlutterError.onError = (details) => errors.add(details);

        try {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final offlineDb = OfflineDatabase(prefs);
          final apiClient = ApiClient(
            secureStorage: const FlutterSecureStorage(),
            prefs: prefs,
          );
          apiClient.dio.options.connectTimeout = null;
          apiClient.dio.options.receiveTimeout = null;
          final connectivity = _AlwaysOnlineConnectivity();

          apiClient.dio.httpClientAdapter = _DynamicTestAdapter(onHandle: (options) async {
            if (options.path.endsWith('/products') && options.method == 'GET') {
              return (
                200,
                {
                  'success': true,
                  'data': [
                    {
                      'id': 1,
                      'name': 'Apple iPhone 16 128GB',
                      'sku': 'IP16-128',
                      'barcode': 'IP16-128',
                      'type': 'simple',
                      'selling_price': 16800000,
                      'stock': 4,
                      'track_stock': true,
                      'multi_warehouse_stock': 19,
                      'other_warehouses_stock': 15,
                      'warehouse_stocks': [
                        {'store_id': 1, 'store_name': 'Nusa Manunggal', 'is_warehouse': false, 'available': 4},
                        {'store_id': 2, 'store_name': 'Gudang Pusat', 'is_warehouse': true, 'available': 15},
                      ],
                      'unit': {'id': 1, 'name': 'Piece', 'code': 'pc'},
                      'category': {'id': 1, 'name': 'Smartphone'},
                    },
                    {
                      'id': 2,
                      'name': 'Samsung Galaxy Buds3 Pro',
                      'sku': 'TWS-PRO',
                      'barcode': 'TWS-PRO',
                      'type': 'simple',
                      'selling_price': 2850000,
                      'stock': 0,
                      'track_stock': true,
                      'multi_warehouse_stock': 8,
                      'other_warehouses_stock': 8,
                      'warehouse_stocks': [
                        {'store_id': 1, 'store_name': 'Nusa Manunggal', 'is_warehouse': false, 'available': 0},
                        {'store_id': 2, 'store_name': 'Gudang Pusat', 'is_warehouse': true, 'available': 8},
                      ],
                      'unit': {'id': 1, 'name': 'Piece', 'code': 'pc'},
                      'category': {'id': 2, 'name': 'Aksesori'},
                    },
                    {
                      'id': 3,
                      'name': 'Jasa Pasang Tempered',
                      'sku': 'SRV-01',
                      'barcode': 'SRV-01',
                      'type': 'service',
                      'selling_price': 50000,
                      'stock': 0,
                      'track_stock': false,
                      'unit': {'id': 1, 'name': 'Jasa', 'code': 'srv'},
                      'category': {'id': 3, 'name': 'Jasa'},
                    },
                  ],
                },
              );
            }
            if (options.path.endsWith('/pos/warehouse-stock')) {
              return (
                200,
                {
                  'success': true,
                  'data': {
                    'current_store_id': 1,
                    'current_store_name': 'Nusa Manunggal',
                    'results': [
                      {
                        'id': 2,
                        'name': 'Samsung Galaxy Buds3 Pro',
                        'sku': 'TWS-PRO',
                        'unit': 'pc',
                        'current_store_available': 0,
                        'total_other_stock': 8,
                        'total_network_stock': 8,
                        'warehouses': [
                          {'store_id': 1, 'store_name': 'Nusa Manunggal', 'is_warehouse': false, 'available': 0},
                          {'store_id': 2, 'store_name': 'Gudang Pusat', 'is_warehouse': true, 'available': 8},
                        ],
                      },
                    ],
                  },
                },
              );
            }
            return (200, {'success': true, 'data': []});
          });

          final session = _sessionForRole(role: 'Kasir', isOwner: false, permissions: const ['pos.access']);
          await offlineDb.saveAuthSession(session.toJson());
          final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
          await authCubit.checkExistingSession();
          final posCubit = PosCubit(
            apiClient: apiClient,
            offlineDb: offlineDb,
            connectivityService: connectivity,
          );
          final themeCubit = ThemeCubit(prefs: prefs);

          await tester.pumpWidget(
            MultiBlocProvider(
              providers: [
                BlocProvider<AuthCubit>.value(value: authCubit),
                BlocProvider<PosCubit>.value(value: posCubit),
                BlocProvider<ThemeCubit>.value(value: themeCubit),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                home: const PosCatalogScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Tracked product with stock=0 (TWS-PRO) MUST NOT appear in POS catalog
          expect(find.text('Apple iPhone 16 128GB'), findsOneWidget);
          expect(find.text('Jasa Pasang Tempered'), findsOneWidget);
          expect(find.text('Samsung Galaxy Buds3 Pro'), findsNothing);
          expect(find.text('+Gdg 15'), findsOneWidget);

          // 2. Open Multi-Warehouse Stock Lookup Modal -> reveals 0-stock item's warehouse stock cleanly
          await tester.tap(find.byIcon(Icons.warehouse_outlined));
          await tester.pumpAndSettle();
          expect(find.text('Cek Stok Multi-Gudang & Cabang'), findsOneWidget);
          expect(find.text('Samsung Galaxy Buds3 Pro'), findsOneWidget);
          expect(find.textContaining('Gudang Gudang Pusat: 8 pc'), findsOneWidget);

          await tester.tap(find.byIcon(Icons.close_rounded));
          await tester.pumpAndSettle();

          expect(
            errors.where((e) => e.toString().contains('RenderFlex') || e.toString().contains('overflowed')),
            isEmpty,
            reason: 'Expected zero overflow errors at 360x800, got: $errors',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await posCubit.close();
          await authCubit.close();
          await connectivity.dispose();
          await themeCubit.close();
        } finally {
          FlutterError.onError = prevHandler;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );
  });
}

class _AlwaysOnlineConnectivity extends NetworkConnectivityService {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> checkOnline() async => true;

  @override
  Stream<bool> get onOnlineChanged => _controller.stream;

  Future<void> dispose() => _controller.close();
}

class _DynamicTestAdapter implements HttpClientAdapter {
  final Future<(int, Map<String, dynamic>)> Function(RequestOptions options) onHandle;

  _DynamicTestAdapter({required this.onHandle});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, body) = await onHandle(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
