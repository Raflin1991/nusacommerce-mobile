import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nusacommerce_mobile/core/config/mobile_workspace_config.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/barcode_service.dart';
import 'package:nusacommerce_mobile/core/hardware/printer_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/core/theme/theme_cubit.dart';
import 'package:nusacommerce_mobile/features/approvals/presentation/owner_approvals_screen.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/auth/models/auth_session_model.dart';
import 'package:nusacommerce_mobile/features/owner_reports/models/mobile_report_catalog.dart';
import 'package:nusacommerce_mobile/features/owner_reports/presentation/business_reports_screen.dart';
import 'package:nusacommerce_mobile/features/owner_reports/presentation/mobile_report_detail_screen.dart';
import 'package:nusacommerce_mobile/features/owner_reports/services/mobile_report_repository.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/presentation/pos_catalog_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestHttpAdapter implements HttpClientAdapter {
  final Future<(int, Map<String, dynamic>)> Function(RequestOptions options) onHandle;

  _TestHttpAdapter({required this.onHandle});

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

class _FixedConnectivityService extends NetworkConnectivityService {
  final bool online;

  _FixedConnectivityService({required this.online});

  @override
  Future<bool> checkOnline() async => online;

  @override
  Stream<bool> get onOnlineChanged => const Stream<bool>.empty();

  Future<void> dispose() async {}
}

AuthSessionModel _ownerSession() {
  return const AuthSessionModel(
    userId: 10,
    userName: 'Owner OXORA',
    userEmail: 'owner@oxora.test',
    userRole: 'Pemilik Usaha',
    isOwner: true,
    permissions: ['*'],
    tenantName: 'Toko OXORA Jaya',
    tenantSubdomain: 'oxorajaya',
    planName: 'Enterprise',
    tier: 'enterprise',
    activeStore: StoreBranchModel(id: 1, name: 'Cabang Pusat', code: 'HQ-01'),
    availableStores: [
      StoreBranchModel(id: 1, name: 'Cabang Pusat', code: 'HQ-01'),
      StoreBranchModel(id: 2, name: 'Cabang Selatan', code: 'BR-02'),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('Pilar 1 — Mobile-First 50-Report BI Center & Offline Resilience', () {
    test('MobileReportCatalog exposes exact 50 Cloud-parity reports across 8 categories + oversold audit', () {
      expect(MobileReportCatalog.categories.length, 8);
      expect(MobileReportCatalog.totalReportCount, 50);

      final ids = MobileReportCatalog.allReports.map((r) => r.id).toSet();
      expect(ids.length, 50, reason: 'All 50 report IDs must be unique');

      // Spot-check critical Cloud parity IDs + oversold audit
      expect(MobileReportCatalog.findById('sales-report'), isNotNull);
      expect(MobileReportCatalog.findById('low-stock'), isNotNull);
      expect(MobileReportCatalog.findById('aged-receivables'), isNotNull);
      expect(MobileReportCatalog.findById('aged-payables'), isNotNull);
      expect(MobileReportCatalog.findById('tax-summary'), isNotNull);
      expect(MobileReportCatalog.findById('profit-and-loss'), isNotNull);
      expect(MobileReportCatalog.findById('balance-sheet'), isNotNull);
      expect(MobileReportCatalog.findById('oversold'), isNotNull);
      expect(MobileReportCatalog.oversoldAuditDefinition.id, 'oversold');

      // RBAC filter restricts cashier-only user away from accounting/tax financial statements
      const cashierOnly = AuthSessionModel(
        userId: 2,
        userName: 'Kasir',
        userEmail: 'kasir@oxora.test',
        userRole: 'Cashier',
        isOwner: false,
        permissions: ['reports.view_sales'],
        tenantName: 'Toko',
        tenantSubdomain: 'toko',
        planName: 'Pro',
        activeStore: StoreBranchModel(id: 1, name: 'Pusat', code: 'HQ'),
        availableStores: [StoreBranchModel(id: 1, name: 'Pusat', code: 'HQ')],
      );
      final cashierReports = MobileReportCatalog.visibleCategoriesFor(cashierOnly)
          .expand((c) => c.reports)
          .map((r) => r.id)
          .toSet();
      expect(cashierReports, contains('sales-report'));
      expect(cashierReports, isNot(contains('balance-sheet')));
      expect(cashierReports, isNot(contains('trial-balance')));
    });

    test('MobileReportRepository computes offline local reports with last-sync label & NEVER masks online HTTP 403', () async {
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final syncTime = DateTime(2026, 11, 22, 14, 30);
      await db.setLastCloudSyncAt(syncTime);
      expect(db.getLastCloudSyncAt(), isNotNull);

      await db.cacheProducts([
        {
          'id': 1,
          'name': 'Kopi Arabika 250g',
          'sku': 'KOP-001',
          'stock': 2,
          'min_stock': 5,
          'selling_price': 65000,
          'cost_price': 40000,
          'category_name': 'Minuman',
          'brand_name': 'NusaRoast',
        },
        {
          'id': 2,
          'name': 'Gula Aren Organik',
          'sku': 'GUL-002',
          'stock': -3,
          'min_stock': 5,
          'selling_price': 30000,
          'cost_price': 18000,
          'category_name': 'Bahan',
          'brand_name': 'SariAlam',
        },
      ]);

      await db.saveSaleToLocalHistory({
        'number': 'INV-OFF-001',
        'sale_datetime': DateTime.now().toIso8601String(),
        'grand_total': 130000.0,
        'discount_total': 5000.0,
        'payment_methods': ['Tunai'],
        'items': [
          {
            'product_id': 1,
            'name': 'Kopi Arabika 250g',
            'qty': 2,
            'unit_price': 65000.0,
            'cost_price': 40000.0,
            'line_total': 130000.0,
          },
        ],
      });

      final apiOffline = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiOffline.dio.options.connectTimeout = null;
      apiOffline.dio.options.receiveTimeout = null;
      final offlineConnectivity = _FixedConnectivityService(online: false);
      addTearDown(offlineConnectivity.dispose);
      final offlineRepo = MobileReportRepository(
        api: apiOffline,
        offlineDb: db,
        connectivity: offlineConnectivity,
      );

      final salesPayload = await offlineRepo.fetchReport(
        definition: MobileReportCatalog.findById('sales-report')!,
        periodKey: 'today',
        storeScope: '1',
        storeLabel: 'Cabang Pusat',
        isLocalTrial: false,
      );
      expect(salesPayload.isOfflineData, isTrue);
      expect(salesPayload.lastSyncLabel, isNotNull);
      expect(salesPayload.kpis, isNotEmpty);

      final oversoldPayload = await offlineRepo.fetchReport(
        definition: MobileReportCatalog.oversoldAuditDefinition,
        periodKey: 'today',
        storeScope: '1',
        storeLabel: 'Cabang Pusat',
        isLocalTrial: false,
      );
      expect(oversoldPayload.isOfflineData, isTrue);
      expect(oversoldPayload.items.any((i) => i.title.contains('Gula Aren')), isTrue);

      // WhatsApp 1-click summary includes emoji, title, store & offline timestamp
      final waText = MobileReportRepository.buildWhatsAppSummary(
        definition: MobileReportCatalog.findById('sales-report')!,
        storeLabel: 'Cabang Pusat',
        periodLabel: 'Hari Ini',
        kpis: salesPayload.kpis,
        items: salesPayload.items,
        isOfflineData: true,
        lastSyncLabel: salesPayload.lastSyncLabel,
      );
      expect(waText, contains('OXORA'));
      expect(waText, contains('Cabang Pusat'));
      expect(waText, contains('Data Offline'));

      // Online HTTP 403 MUST throw MobileReportApiException and NEVER return fake local data
      final apiOnline403 = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiOnline403.dio.options.connectTimeout = null;
      apiOnline403.dio.options.receiveTimeout = null;
      apiOnline403.dio.httpClientAdapter = _TestHttpAdapter(
        onHandle: (_) async => (
          403,
          {'success': false, 'message': 'Akses laporan dibatasi oleh kebijakan RBAC.'},
        ),
      );
      final onlineConnectivity = _FixedConnectivityService(online: true);
      addTearDown(onlineConnectivity.dispose);
      final onlineRepo = MobileReportRepository(
        api: apiOnline403,
        offlineDb: db,
        connectivity: onlineConnectivity,
      );
      await expectLater(
        () => onlineRepo.fetchReport(
          definition: MobileReportCatalog.findById('profit-and-loss')!,
          periodKey: '7d',
          storeScope: '1',
          storeLabel: 'Cabang Pusat',
          isLocalTrial: false,
        ),
        throwsA(
          isA<MobileReportApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    testWidgets('BusinessReportsScreen offline banner + MobileReportDetailScreen drill-down & export sheet render with zero overflow at 360x640',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.setLastCloudSyncAt(DateTime(2026, 11, 22, 10, 15));
      await db.cacheProducts([
        {
          'id': 11,
          'name': 'Teh Hijau Premium',
          'sku': 'TEH-011',
          'stock': 1,
          'min_stock': 10,
          'selling_price': 25000,
          'cost_price': 12000,
        },
      ]);

      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.connectTimeout = null;
      apiClient.dio.options.receiveTimeout = null;
      apiClient.dio.httpClientAdapter = _TestHttpAdapter(
        onHandle: (_) async => (200, {'success': true, 'data': []}),
      );
      final connectivity = _FixedConnectivityService(online: false);
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      await db.saveAuthSession(_ownerSession().toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenLight);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
        await connectivity.dispose();
      });

      // 1. Offline Hub renders explicit "Data Offline (Sinkronisasi Terakhir: ...)" banner
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const BusinessReportsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Data Offline (Sinkronisasi Terakhir:'), findsOneWidget);

      // 2. MobileReportDetailScreen for Low Stock opens drill-down sheet on row tap
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: MobileReportDetailScreen(
              definition: MobileReportCatalog.findById('low-stock')!,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Teh Hijau Premium'), findsOneWidget);

      // Tap row card -> Drill-Down Bottom Sheet
      await tester.tap(find.text('Teh Hijau Premium'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Salin'), findsOneWidget);
      expect(tester.takeException(), isNull);

      Navigator.of(tester.element(find.text('Salin'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Open Export Sheet -> verifies WA, PDF & CSV actions
      await tester.tap(find.byTooltip('Ekspor PDF / CSV'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('Kirim Ringkasan via WhatsApp'), findsOneWidget);
      expect(find.textContaining('Ekspor PDF'), findsOneWidget);
      expect(find.textContaining('Ekspor CSV'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Pilar 2 — POS Fast-Lane, HID Wedge, Quick Price Checker & WiFi Thermal Printer', () {
    test('HardwareBarcodeWedgeBuffer captures rapid HID burst + Enter and ignores slow typing', () {
      final wedge = HardwareBarcodeWedgeBuffer(maxInterKeyMs: 80, minLength: 4);
      final t0 = DateTime(2026, 11, 22, 12, 0, 0);

      // Fast scanner burst (15ms intervals) -> emits complete barcode on Enter
      expect(wedge.onKeyCharacter(character: '8', now: t0), isNull);
      expect(wedge.onKeyCharacter(character: '9', now: t0.add(const Duration(milliseconds: 15))), isNull);
      expect(wedge.onKeyCharacter(character: '9', now: t0.add(const Duration(milliseconds: 30))), isNull);
      expect(wedge.onKeyCharacter(character: '1', now: t0.add(const Duration(milliseconds: 45))), isNull);
      expect(wedge.onKeyCharacter(character: '2', now: t0.add(const Duration(milliseconds: 60))), isNull);
      final code = wedge.onKeyCharacter(isEnter: true, now: t0.add(const Duration(milliseconds: 75)));
      expect(code, '89912');

      // Slow manual typing (300ms gap resets buffer) -> returns null
      expect(wedge.onKeyCharacter(character: 'A', now: t0), isNull);
      expect(wedge.onKeyCharacter(character: 'B', now: t0.add(const Duration(milliseconds: 300))), isNull);
      expect(wedge.onKeyCharacter(isEnter: true, now: t0.add(const Duration(milliseconds: 320))), isNull);
    });

    test('PrinterService persists WiFi/LAN TCP 9100 mode & activePrinterLabel cleanly', () async {
      final prefs = await SharedPreferences.getInstance();
      final printer = PrinterService();
      await printer.initialize(prefs);

      expect(printer.isWifiMode, isFalse);

      await printer.saveWifiPrinter(ipAddress: '192.168.1.200', port: 9100, activateWifiMode: true);
      expect(printer.isWifiMode, isTrue);
      expect(printer.activePrinterLabel, 'WiFi LAN (192.168.1.200:9100)');

      // Re-initialize new instance from SharedPreferences -> restores WiFi config
      final restored = PrinterService();
      await restored.initialize(prefs);
      expect(restored.isWifiMode, isTrue);
      expect(restored.wifiPrinterIp, '192.168.1.200');
      expect(restored.wifiPrinterPort, 9100);
      expect(restored.activePrinterLabel, 'WiFi LAN (192.168.1.200:9100)');
    });

    testWidgets('PosCatalogScreen filters by Brand, displays Grosir badge & opens Quick Price Checker cleanly',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.cacheProducts([
        {
          'id': 101,
          'name': 'Beras Pandan Wangi 5kg',
          'sku': 'BRS-5KG',
          'barcode': '8991234567890',
          'stock': 24,
          'selling_price': 75000,
          'cost_price': 62000,
          'category_id': 1,
          'category_name': 'Sembako',
          'brand_id': 10,
          'brand_name': 'Cap Rojo',
          'rack_location': 'RAK-A1',
          'volume_tiers': [
            {'min_qty': 5, 'unit_price': 70000},
          ],
        },
        {
          'id': 102,
          'name': 'Minyak Goreng 2L',
          'sku': 'MNY-2L',
          'barcode': '8990001112223',
          'stock': 15,
          'selling_price': 36000,
          'cost_price': 30000,
          'category_id': 1,
          'category_name': 'Sembako',
          'brand_id': 20,
          'brand_name': 'SuryaMas',
        },
      ]);

      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.httpClientAdapter = _TestHttpAdapter(
        onHandle: (_) async => (200, {'success': true, 'data': []}),
      );
      final connectivity = _FixedConnectivityService(online: false);
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      await db.saveAuthSession(_ownerSession().toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db, connectivityService: connectivity);
      await posCubit.initializeCatalog(seedDefaultCart: false, awaitCloudSync: false);
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenLight);
      addTearDown(() async {
        await authCubit.close();
        await posCubit.close();
        await themeCubit.close();
      });

      // Brand filter unit check
      expect(posCubit.state.posBrands.length, greaterThanOrEqualTo(3)); // Semua + 2 brands
      posCubit.selectBrand(10);
      expect(posCubit.state.filteredProducts.length, 1);
      expect(posCubit.state.filteredProducts.first.name, 'Beras Pandan Wangi 5kg');
      posCubit.selectBrand(0);
      expect(posCubit.state.filteredProducts.length, 2);

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
      expect(find.text('Cap Rojo'), findsOneWidget);
      expect(find.text('Grosir'), findsWidgets);

      // Open Quick Price Checker modal from AppBar
      await tester.tap(find.byTooltip('Cek Harga Cepat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Cek Harga & Stok Cepat'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('Pilar 3 — Owner Approvals Desk & Focused 4-Workspace Scope', () {
    test('Operational workspaces exclude heavy HRD/Payroll while keeping RBAC isolation intact', () {
      expect(MobileWorkspaceResolver.operationalWorkspaces.length, 4);
      expect(
        MobileWorkspaceResolver.operationalWorkspaces,
        isNot(contains(MobileWorkspaceRole.employeeEss)),
      );
    });

    testWidgets('OwnerApprovalsScreen shows Maker-Checker SoD guard & surfaces inline HTTP 422 error inside decision sheet',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.httpClientAdapter = _TestHttpAdapter(
        onHandle: (opts) async {
          if (opts.path.endsWith('/approvals')) {
            return (
              200,
              {
                'success': true,
                'data': [
                  {
                    'id': 501,
                    'store_id': 1,
                    'store_name': 'Cabang Pusat',
                    'approvable_type': 'Sale',
                    'approvable_id': 9001,
                    'action_type': 'void_sale',
                    'status': 'pending',
                    'amount': 250000,
                    'reason': 'Pelanggan salah pesan menu',
                    'requested_by': 'Kasir Rina',
                    'requested_by_id': 99,
                    'created_at': '2026-11-22T09:15:00+07:00',
                  },
                  {
                    'id': 502,
                    'store_id': 1,
                    'store_name': 'Cabang Pusat',
                    'approvable_type': 'StockTransfer',
                    'approvable_id': 33,
                    'action_type': 'stock_transfer',
                    'status': 'pending',
                    'amount': 500000,
                    'reason': 'Kirim stok ke Cabang Selatan',
                    'requested_by': 'Owner OXORA',
                    'requested_by_id': 10, // Same as owner session userId -> Maker-Checker SoD guard
                    'created_at': '2026-11-22T10:00:00+07:00',
                  },
                ],
              },
            );
          }
          if (opts.path.endsWith('/approvals/501/decide')) {
            return (
              422,
              {'success': false, 'message': 'Otorisasi ditolak: Dokumen sudah diproses di cabang lain.'},
            );
          }
          return (200, {'success': true, 'data': {}});
        },
      );

      final connectivity = _FixedConnectivityService(online: true);
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);

      await db.saveAuthSession(_ownerSession().toJson());
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.checkExistingSession();
      final themeCubit = ThemeCubit(prefs: prefs, initialMode: NusaThemeMode.warmLinenLight);
      addTearDown(() async {
        await authCubit.close();
        await themeCubit.close();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const OwnerApprovalsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Pembatalan Nota (Void)'), findsOneWidget);
      expect(find.text('Rp 250.000'), findsOneWidget);
      expect(find.textContaining('Aturan Maker-Checker (SoD)'), findsOneWidget);

      // Tap Setujui on #501 -> opens confirmation modal -> submit returns 422 -> inline error shown inside modal
      await tester.tap(find.text('Setujui'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Konfirmasi Setujui'), findsOneWidget);

      await tester.tap(find.text('Konfirmasi Setujui'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.textContaining('Dokumen sudah diproses di cabang lain'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
