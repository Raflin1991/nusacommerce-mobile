import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nusacommerce_mobile/core/constants/api_endpoints.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/hardware/printer_service.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/auth/models/auth_session_model.dart';
import 'package:nusacommerce_mobile/features/dashboard/presentation/all_modules_directory_view.dart';
import 'package:nusacommerce_mobile/features/dashboard/presentation/main_navigation_shell.dart';
import 'package:nusacommerce_mobile/features/hr/presentation/hr_attendance_screen.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:nusacommerce_mobile/features/purchases/presentation/purchases_and_returns_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  Future<OfflineDatabase> createDb() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return OfflineDatabase(prefs);
  }

  group('Desktop-to-Mobile Feature Parity Verification', () {
    test('Taxonomies & Customer Groups CRUD + Tenant Isolation Purge', () async {
      final db = await createDb();
      await db.setActiveTenantIdentity('local-trial');

      final cat = await db.addOrUpdateLocalCategory({'name': 'Minuman Dingin'});
      final brand = await db.addOrUpdateLocalBrand({'name': 'NusaRoast'});
      final unit = await db.addOrUpdateLocalUnit({'code': 'box', 'name': 'Kotak Isi 12'});
      final reason = await db.addOrUpdateLocalReturnReason({
        'code': 'CRACKED',
        'name': 'Kemasan Retak',
        'default_restock': false,
      });
      final expCat = await db.addOrUpdateLocalExpenseCategory({'name': 'Packaging Khusus'});
      final group = await db.addOrUpdateLocalCustomerGroup({
        'name': 'Reseller Platinum',
        'default_discount_percent': 8.0,
        'loyalty_multiplier': 2.0,
      });

      expect(db.getCachedCategories().any((c) => c['id'] == cat['id'] && c['name'] == 'Minuman Dingin'), isTrue);
      expect(db.getCachedBrands().any((b) => b['id'] == brand['id'] && b['name'] == 'NusaRoast'), isTrue);
      expect(db.getCachedUnits().any((u) => u['id'] == unit['id'] && u['code'] == 'box'), isTrue);
      expect(db.getCachedReturnReasons().any((r) => r['id'] == reason['id'] && r['code'] == 'CRACKED'), isTrue);
      expect(db.getCachedExpenseCategories().any((e) => e['id'] == expCat['id'] && e['name'] == 'Packaging Khusus'), isTrue);
      expect(db.getCachedCustomerGroups().any((g) => g['id'] == group['id'] && g['default_discount_percent'] == 8.0), isTrue);

      await db.deleteLocalCategory((cat['id'] as num).toInt());
      expect(db.getCachedCategories().any((c) => c['id'] == cat['id']), isFalse);

      // Tenant isolation switch clears previous tenant parity data completely
      await db.ensureTenantIsolation('cloud:tenant-baru');
      expect(db.getCachedCategories().any((c) => c['name'] == 'Minuman Dingin'), isFalse);
      expect(db.getCachedBrands().any((b) => b['name'] == 'NusaRoast'), isFalse);
      expect(db.getCachedCustomerGroups().any((g) => g['name'] == 'Reseller Platinum'), isFalse);
    });

    test('Multi-Item Purchase PO, Stock Increment, Ledger Entry & Purchase Return', () async {
      final db = await createDb();
      await db.cacheProducts([
        {
          'id': 10,
          'name': 'Gula Aren Cair 1L',
          'sku': 'GAC-01',
          'cost_price': 28000.0,
          'selling_price': 45000.0,
          'stock': 2.0,
          'reorder_level': 5.0,
          'unit_code': 'btl',
          'track_stock': true,
        },
        {
          'id': 11,
          'name': 'Susu UHT Full Cream',
          'sku': 'UHT-01',
          'cost_price': 16000.0,
          'selling_price': 25000.0,
          'stock': 4.0,
          'reorder_level': 5.0,
          'unit_code': 'pcs',
          'track_stock': true,
        },
      ]);

      final po = await db.addLocalPurchase(
        supplierId: 77,
        supplierName: 'PT Bahan Kue Makmur',
        invoiceNumber: 'INV-SUP-009',
        paymentMode: 'partial',
        paidAmount: 200000.0,
        paymentMethod: 'Transfer Bank BCA',
        items: [
          {'product_id': 10, 'product_name': 'Gula Aren Cair 1L', 'sku': 'GAC-01', 'quantity': 10.0, 'unit_cost': 30000.0},
          {'product_id': 11, 'product_name': 'Susu UHT Full Cream', 'sku': 'UHT-01', 'quantity': 10.0, 'unit_cost': 17000.0},
        ],
      );

      expect((po['grand_total'] as num).toDouble(), 470000.0);
      expect((po['paid_total'] as num).toDouble(), 200000.0);
      expect((po['balance_due'] as num).toDouble(), 270000.0);

      // Stock updated & WAC updated
      final prod10 = db.getCachedProducts().firstWhere((p) => p['id'] == 10);
      expect((prod10['stock'] as num).toDouble(), 12.0);
      expect((prod10['cost_price'] as num).toDouble(), 30000.0);

      // Payable created for remaining Rp 270.000
      final payables = db.getLocalPayables();
      expect(payables.length, 1);
      expect((payables.first['balance_due'] as num).toDouble(), 270000.0);

      // Stock movement cards recorded
      final movements = db.getLocalStockMovements(productId: 10);
      expect(movements.length, 1);
      expect(movements.first['type'], 'purchase');
      expect((movements.first['quantity_delta'] as num).toDouble(), 10.0);

      // Cash ledger recorded non-cash outflow Rp 200.000
      final ledger = db.computeLocalCashLedger(channelFilter: 'non_cash');
      final summary = ledger['summary'] as Map<String, dynamic>;
      expect((summary['non_cash_out'] as num).toDouble(), 200000.0);

      // Purchase Return deducts stock & logs purchase_return movement
      final ret = await db.addLocalPurchaseReturn(
        purchaseId: (po['id'] as num).toInt(),
        purchaseNumber: po['number'].toString(),
        supplierName: 'PT Bahan Kue Makmur',
        items: [
          {'product_id': 10, 'quantity': 2.0, 'unit_cost': 30000.0},
        ],
        notes: 'Botol bocor saat diterima',
      );
      expect((ret['grand_total'] as num).toDouble(), 60000.0);
      final prod10After = db.getCachedProducts().firstWhere((p) => p['id'] == 10);
      expect((prod10After['stock'] as num).toDouble(), 10.0);
      expect(db.getLocalStockMovements(productId: 10, type: 'purchase_return').length, 1);
    });

    test('Cash Ledger Net Flow, Payable & Receivable Settlements + Thermal Receipts', () async {
      final db = await createDb();

      await db.addLocalCashEntry(
        title: 'Setoran Modal Awal',
        category: 'Mutasi Manual',
        direction: 'in',
        channel: 'cash',
        methodName: 'Tunai',
        amount: 500000.0,
      );
      await db.addLocalCashEntry(
        title: 'Transfer Supplier Bahan',
        category: 'Mutasi Manual',
        direction: 'out',
        channel: 'non_cash',
        methodName: 'QRIS / Bank',
        amount: 150000.0,
      );

      final ledger = db.computeLocalCashLedger(channelFilter: 'all');
      final sum = ledger['summary'] as Map<String, dynamic>;
      expect((sum['cash_balance'] as num).toDouble(), 500000.0);
      expect((sum['non_cash_balance'] as num).toDouble(), -150000.0);
      expect((sum['net_cash_flow'] as num).toDouble(), 350000.0);

      // Payable partial settlement logs payment history & deducts cash ledger
      final payable = await db.addLocalPayable(
        supplierName: 'CV Sembako Jaya',
        totalAmount: 400000.0,
        paidAmount: 0.0,
        invoiceNumber: 'INV-SMK-01',
      );
      final settled = await db.payLocalPayable(
        payableId: (payable['id'] as num).toInt(),
        amount: 150000.0,
        paymentMethod: 'Tunai',
      );
      expect(settled, isNotNull);
      expect((settled!['balance_due'] as num).toDouble(), 250000.0);
      expect(settled['status'], 'partial');
      expect((settled['payments'] as List).length, 1);

      final printer = PrinterService();
      final kwitansi = printer.formatSettlementReceipt(
        storeProfile: {'name': 'Toko Berkah'},
        type: 'receivable',
        partyName: 'Budi Santoso',
        invoiceNumber: 'TRX-001',
        paidAmount: 150000,
        remainingBalance: 0,
        paymentMethod: 'Tunai',
      );
      expect(kwitansi, contains('KWITANSI PIUTANG'));
      expect(kwitansi, contains('Budi Santoso'));
      expect(kwitansi, contains('LUNAS'));

      final label = printer.formatBarcodeLabelText(
        storeName: 'Toko Berkah',
        productName: 'Kopi Tubruk 250g',
        sku: 'KOP-250',
        barcode: '8991234567890',
        price: 35000,
      );
      expect(label, contains('Kopi Tubruk 250g'));
      expect(label, contains('8991234567890'));
    });

    test('Quotations 1-Click Load into PosCubit Cart & Extended Analytics', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.options.baseUrl = 'http://127.0.0.1:59999/api/v1';

      await db.cacheProducts([
        {
          'id': 501,
          'name': 'Paket Catering Box A',
          'sku': 'CAT-A',
          'cost_price': 20000.0,
          'selling_price': 32000.0,
          'stock': 25.0,
          'category_id': 1,
          'category': {'id': 1, 'name': 'Makanan'},
        },
        {
          'id': 502,
          'name': 'Es Jeruk Peras',
          'sku': 'JERK-01',
          'cost_price': 4000.0,
          'selling_price': 12000.0,
          'stock': 10.0,
          'category_id': 2,
          'category': {'id': 2, 'name': 'Minuman'},
        },
      ]);
      await db.cacheCustomers([
        {'id': 88, 'name': 'PT Maju Bersama', 'phone': '08123456789'},
      ]);

      final quote = await db.addOrUpdateLocalQuotation({
        'quotation_number': 'QT-2026-001',
        'customer_id': 88,
        'customer_name': 'PT Maju Bersama',
        'discount_amount': 10000.0,
        'notes': 'Acara Rapat Kantor',
        'items': [
          {'product_id': 501, 'product_name': 'Paket Catering Box A', 'quantity': 5.0, 'unit_price': 32000.0},
        ],
      });
      expect(db.getLocalQuotations().length, 1);

      final posCubit = PosCubit(apiClient: apiClient, offlineDb: db);
      await posCubit.initializeCatalog(seedDefaultCart: false);
      posCubit.loadCartFromQuotation(quote);

      expect(posCubit.state.cart.length, 1);
      expect(posCubit.state.cart.first.product.id, 501);
      expect(posCubit.state.cart.first.quantity, 5.0);
      expect(posCubit.state.cartDiscountAmount, 10000.0);
      expect(posCubit.state.selectedCustomer?['name'], 'PT Maju Bersama');
      expect(posCubit.state.orderNotes, contains('QT-2026-001'));

      final analytics = db.computeLocalExtendedAnalytics();
      final val = analytics['valuation'] as Map<String, dynamic>;
      // 25 * 20000 + 10 * 4000 = 540.000 cost valuation
      expect((val['total_cost_value'] as num).toDouble(), 540000.0);
      // 25 * 32000 + 10 * 12000 = 920.000 retail valuation
      expect((val['total_retail_value'] as num).toDouble(), 920000.0);
      expect((analytics['dead_stock'] as List).length, 2);

      await posCubit.close();
    });

    testWidgets('UX Reorganization: AllModulesDirectoryView 4-Category Hub & Search Filter',
        (WidgetTester tester) async {
      final db = await createDb();
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      final switchedTabs = <int>[];

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            home: AllModulesDirectoryView(
              onOpenDrawer: () {},
              onSwitchTab: switchedTabs.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sticky header & completeness badge
      expect(find.text('Pusat Modul & Fitur Toko'), findsOneWidget);
      expect(find.text('100% Lengkap'), findsOneWidget);

      final listScrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );

      // Verify top categories and test tab switch callbacks while at top
      expect(find.text('1. KASIR & OPERASIONAL'), findsOneWidget);
      expect(find.text('2. PENJUALAN & ORDER'), findsOneWidget);
      expect(find.text('3. PRODUK & KATALOG'), findsOneWidget);

      await tester.ensureVisible(find.text('Riwayat Struk'));
      await tester.tap(find.text('Riwayat Struk'));
      await tester.pump();
      expect(switchedTabs, contains(2));

      await tester.ensureVisible(find.text('Data Barang'));
      await tester.tap(find.text('Data Barang'));
      await tester.pump();
      expect(switchedTabs, containsAllInOrder([2, 1]));

      // Scroll ListView explicitly to render below-fold categories
      await tester.scrollUntilVisible(
        find.text('4. INVENTARIS & GUDANG'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('4. INVENTARIS & GUDANG'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('5. PEMBELIAN & BIAYA'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('5. PEMBELIAN & BIAYA'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('6. CRM & PELANGGAN'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('6. CRM & PELANGGAN'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('7. TOKO ONLINE'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('7. TOKO ONLINE'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('8. KONTROL OWNER & LAPORAN'),
        200,
        scrollable: listScrollable,
      );
      expect(find.text('8. KONTROL OWNER & LAPORAN'), findsOneWidget);

      // Test real-time search filtering & Reset Pencarian
      await tester.enterText(find.byType(TextField), 'Kategori');
      await tester.pumpAndSettle();
      expect(find.text('Kategori & Brand'), findsOneWidget);
      expect(find.text('3. PRODUK & KATALOG'), findsOneWidget);
      expect(find.text('1. KASIR & OPERASIONAL'), findsNothing);

      // Test empty state & Reset Pencarian button
      await tester.enterText(find.byType(TextField), 'TidakAdaFiturXyz');
      await tester.pumpAndSettle();
      expect(find.text('Modul tidak ditemukan'), findsOneWidget);
      await tester.tap(find.text('Reset Pencarian'));
      await tester.pumpAndSettle();
      expect(find.text('1. KASIR & OPERASIONAL'), findsOneWidget);

      await authCubit.close();
    });

    test('API Key, Header & Endpoint Contract Sync (Cloud <-> Mobile APK)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      await apiClient.saveToken('tenantTokenPayload.hmacSignature123');
      await apiClient.setTenantSlug('manunggal');
      await apiClient.setActiveStoreId(7);

      final capturedHeaders = <Map<String, dynamic>>[];
      apiClient.dio.httpClientAdapter = _RecordingHttpClientAdapter(
        onFetch: (options) => capturedHeaders.add(Map<String, dynamic>.from(options.headers)),
      );

      await apiClient.dio.get(ApiEndpoints.categories);
      await apiClient.dio.post(ApiEndpoints.purchases, data: {'items': []});
      await apiClient.dio.put(ApiEndpoints.brandDetail(5), data: {'name': 'Brand A'});
      await apiClient.dio.delete(ApiEndpoints.unitDetail(3));

      expect(capturedHeaders.length, 4);
      final uuidV4Pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );

      // GET request has Bearer + multi-tenant headers and does not force X-Idempotency-Key
      expect(capturedHeaders[0]['Authorization'], 'Bearer tenantTokenPayload.hmacSignature123');
      expect(capturedHeaders[0]['X-Tenant-Slug'], 'manunggal');
      expect(capturedHeaders[0]['X-Tenant-Domain'], 'manunggal');
      expect(capturedHeaders[0]['X-Store-Id'], '7');
      expect(capturedHeaders[0].containsKey('X-Idempotency-Key'), isFalse);

      // POST / PUT / DELETE automatically receive valid UUIDv4 X-Idempotency-Key headers
      for (final i in [1, 2, 3]) {
        expect(capturedHeaders[i]['Authorization'], 'Bearer tenantTokenPayload.hmacSignature123');
        expect(capturedHeaders[i]['X-Tenant-Slug'], 'manunggal');
        expect(capturedHeaders[i]['X-Store-Id'], '7');
        expect(uuidV4Pattern.hasMatch((capturedHeaders[i]['X-Idempotency-Key'] ?? '').toString()), isTrue);
      }

      // Verify core & parity endpoints match Laravel /api/v1/* routes
      expect(ApiEndpoints.defaultBaseUrl, endsWith('/api/v1'));
      expect(ApiEndpoints.login, '/auth/login');
      expect(ApiEndpoints.switchStore, '/auth/switch-store');
      expect(ApiEndpoints.products, '/products');
      expect(ApiEndpoints.categories, '/categories');
      expect(ApiEndpoints.brands, '/brands');
      expect(ApiEndpoints.units, '/units');
      expect(ApiEndpoints.stockMovements, '/inventory/stock-movements');
      expect(ApiEndpoints.stockTakes, '/inventory/stock-takes');
      expect(ApiEndpoints.stockTransfers, '/inventory/transfers');
      expect(ApiEndpoints.kdsQueue, '/pos/kds-queue');
      expect(ApiEndpoints.updateKdsStatus(9), '/pos/kds-queue/9/status');
      expect(ApiEndpoints.quotations, '/quotations');
      expect(ApiEndpoints.checkout, '/pos/checkout');
      expect(ApiEndpoints.purchases, '/purchases');
      expect(ApiEndpoints.purchaseReturns, '/purchase-returns');
      expect(ApiEndpoints.cashLedger, '/cash-ledger');
      expect(ApiEndpoints.expenseCategories, '/expense-categories');
      expect(ApiEndpoints.onlineOrders, '/online-orders');
      expect(ApiEndpoints.updateOnlineOrderStatus(4), '/online-orders/4/status');
      expect(ApiEndpoints.reportInventoryAnalytics, '/reports/inventory-analytics');
      expect(ApiEndpoints.reportCrmAndPurchases, '/reports/crm-and-purchases');
      expect(ApiEndpoints.reportCashAndExpenses, '/reports/cash-and-expenses');
      expect(ApiEndpoints.reportEnterpriseCompliance, '/reports/enterprise-compliance');
      expect(ApiEndpoints.purchaseAiReorder, '/purchases/ai-reorder');
      expect(ApiEndpoints.hrSummary, '/hr/summary');
      expect(ApiEndpoints.hrEmployees, '/hr/employees');
      expect(ApiEndpoints.hrClock, '/hr/attendance/clock');

      // Distinguish offline errors from HTTP 4xx/5xx server rejections
      expect(
        ApiClient.isNetworkOfflineError(
          DioException(
            requestOptions: RequestOptions(path: '/cash-ledger'),
            type: DioExceptionType.connectionError,
          ),
        ),
        isTrue,
      );
      expect(
        ApiClient.isNetworkOfflineError(
          DioException(
            requestOptions: RequestOptions(path: '/cash-ledger'),
            response: Response(
              requestOptions: RequestOptions(path: '/cash-ledger'),
              statusCode: 422,
              data: {'message': 'Validasi gagal'},
            ),
            type: DioExceptionType.badResponse,
          ),
        ),
        isFalse,
      );
    });

    test('AuthSessionModel copyWith preserves and updates branch permissions cleanly', () {
      const store1 = StoreBranchModel(id: 1, name: 'Pusat', code: 'MAIN');
      const store2 = StoreBranchModel(id: 2, name: 'Cabang 2', code: 'CAB2');
      const base = AuthSessionModel(
        userId: 10,
        userName: 'Supervisor',
        userEmail: 'spv@nusa.test',
        userRole: 'Supervisor',
        isOwner: false,
        tenantName: 'Nusa',
        tenantSubdomain: 'nusa',
        planName: 'enterprise',
        tier: 'enterprise',
        activeStore: store1,
        availableStores: [store1, store2],
        permissions: ['sales.create', 'products.view'],
      );

      final switched = base.copyWith(
        activeStore: store2,
        permissions: ['sales.create', 'products.adjust_stock'],
      );
      expect(switched.activeStore.id, 2);
      expect(switched.permissions, contains('products.adjust_stock'));
      expect(switched.permissions, isNot(contains('products.view')));
    });

    testWidgets('Tablet Desktop-Replacement Layout: MainNavigationShell uses NavigationRail at >= 768dp',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await GetIt.instance.reset();
      final db = await createDb();
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      apiClient.dio.httpClientAdapter = _RecordingHttpClientAdapter(onFetch: (_) {});
      final connectivity = NetworkConnectivityService();
      final printer = PrinterService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);
      GetIt.instance.registerSingleton<PrinterService>(printer);

      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.startLocalTrialSession(storeName: 'Toko Tablet', businessVertical: 'retail');
      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: db,
        connectivityService: connectivity,
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
          ],
          child: const MaterialApp(
            home: MainNavigationShell(initialIndex: 3),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Landscape/tablet displays left NavigationRail + Kasir POS action and 3-column All Modules grid (>=900dp)
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Kasir POS'), findsWidgets);
      expect(find.text('Pusat Modul & Fitur Toko'), findsOneWidget);

      await authCubit.close();
      await posCubit.close();
      await GetIt.instance.reset();
    });

    testWidgets('HrAttendanceScreen and PurchasesAndReturnsScreen 3-tab AI Reorder render cleanly',
        (WidgetTester tester) async {
      await GetIt.instance.reset();
      final db = await createDb();
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final connectivity = NetworkConnectivityService();
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      GetIt.instance.registerSingleton<OfflineDatabase>(db);
      GetIt.instance.registerSingleton<NetworkConnectivityService>(connectivity);

      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: db);
      await authCubit.startLocalTrialSession(storeName: 'Toko Tablet', businessVertical: 'retail');
      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: db,
        connectivityService: connectivity,
      );

      // Render HR screen in Local Trial mode cleanly
      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: const MaterialApp(home: HrAttendanceScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('HRD, Tim & Presensi'), findsOneWidget);
      expect(find.text('HRD & Absensi Terhubung Cloud'), findsOneWidget);

      // Render Purchases 3-tab screen including Saran Kulakan AI tab
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
          ],
          child: const MaterialApp(home: PurchasesAndReturnsScreen(initialTab: 2)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Pesanan Beli (PO)'), findsOneWidget);
      expect(find.text('Retur Pembelian'), findsOneWidget);
      expect(find.text('Saran Kulakan AI'), findsOneWidget);

      await authCubit.close();
      await posCubit.close();
      await GetIt.instance.reset();
    });

    test('saveProductInventory surfaces HTTP 422 without fake local save, and syncWithCloud auto-uploads local_only products',
        () async {
      final db = await createDb();
      final prefs = await SharedPreferences.getInstance();
      final apiClient = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final connectivity = NetworkConnectivityService();
      await db.saveAuthSession({
        'user_id': 1,
        'name': 'Owner',
        'email': 'owner@toko.id',
        'tenant_subdomain': 'demo',
        'is_local_trial': false,
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'S1'},
      });

      int phase = 0; // 0 = reject 422, 1 = accept upload & return synced product
      final uploadedPayloads = <Map<String, dynamic>>[];

      apiClient.dio.httpClientAdapter = _DynamicHttpClientAdapter(onHandle: (options) {
        if (options.path.endsWith('/products') && options.method == 'POST') {
          if (phase == 0) {
            return (
              422,
              {'success': false, 'message': 'Tipe item tidak valid.'},
            );
          }
          uploadedPayloads.add(Map<String, dynamic>.from(options.data as Map));
          return (
            201,
            {
              'success': true,
              'data': {'id': 888, 'name': 'Xiaomi 17', 'sku': 'PRD-159', 'stock': 25},
            },
          );
        }
        if (options.path.endsWith('/products') && options.method == 'GET') {
          return (
            200,
            {
              'success': true,
              'data': [
                {
                  'id': 888,
                  'name': 'Xiaomi 17',
                  'sku': 'PRD-159',
                  'barcode': 'PRD-159',
                  'type': 'simple',
                  'selling_price': 17000000,
                  'cost_price': 16500000,
                  'stock': 25,
                  'unit_code': 'pcs',
                  'category_id': 0,
                  'category_name': 'Umum',
                }
              ],
            },
          );
        }
        return (200, {'success': true, 'data': []});
      });

      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: db,
        connectivityService: connectivity,
      );

      // Case 1: Server rejects with 422 -> must return error and NOT store fake local-only item
      final rejected = await posCubit.saveProductInventory(
        ProductModel(
          id: DateTime.now().millisecondsSinceEpoch,
          name: 'Xiaomi 17',
          sku: 'PRD-159',
          barcode: 'PRD-159',
          type: 'physical',
          sellingPrice: 17000000,
          costPrice: 16500000,
          stock: 25,
          unitCode: 'pcs',
          categoryId: 0,
          categoryName: 'Umum',
          isLowStock: false,
        ),
        isNew: true,
      );
      expect(rejected.ok, isFalse);
      expect(rejected.syncedToCloud, isFalse);
      expect(rejected.errorMessage, contains('Tipe item tidak valid'));
      expect(db.getCachedProducts(), isEmpty);

      // Case 2: Trapped offline local-only product auto-uploads on syncWithCloud
      await db.addOrUpdateLocalProduct({
        'id': -159,
        'name': 'Xiaomi 17',
        'sku': 'PRD-159',
        'barcode': 'PRD-159',
        'type': 'physical',
        'selling_price': 17000000,
        'cost_price': 16500000,
        'stock': 25,
        'shelf_location': 'Rak Utama',
        'is_local_only': true,
      });
      phase = 1;
      await posCubit.syncWithCloud(force: true);

      expect(uploadedPayloads.length, 1);
      expect(uploadedPayloads.first['type'], 'simple');
      expect(uploadedPayloads.first['initial_stock'], 25.0);
      expect(posCubit.state.allProducts.any((p) => p.id == 888 && p.name == 'Xiaomi 17'), isTrue);
      expect(db.getCachedProducts().any((p) => p['is_local_only'] == true), isFalse);

      await posCubit.close();
    });
  });
}

class _DynamicHttpClientAdapter implements HttpClientAdapter {
  final (int, Map<String, dynamic>) Function(RequestOptions options) onHandle;

  _DynamicHttpClientAdapter({required this.onHandle});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, body) = onHandle(options);
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

class _RecordingHttpClientAdapter implements HttpClientAdapter {
  final void Function(RequestOptions options) onFetch;

  _RecordingHttpClientAdapter({required this.onFetch});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    onFetch(options);
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'status': 'success', 'data': {}}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
