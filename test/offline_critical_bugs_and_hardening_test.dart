import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
import 'package:nusacommerce_mobile/core/security/secure_license_vault.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/auth/models/auth_session_model.dart';
import 'package:nusacommerce_mobile/features/auth/presentation/login_screen.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _StubAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

class _FakeConnectivityService extends NetworkConnectivityService {
  bool online;
  final StreamController<bool> _ctrl = StreamController<bool>.broadcast();

  _FakeConnectivityService({this.online = true});

  @override
  Future<bool> checkOnline() async => online;

  @override
  Stream<bool> get onOnlineChanged => _ctrl.stream;

  void emitStatus(bool value) {
    online = value;
    _ctrl.add(value);
  }

  void dispose() {
    _ctrl.close();
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

String _toHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

final Map<String, String> _mockKeystore = <String, String>{};

void _installMockSecureStorageChannel() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    final key = args['key']?.toString();
    switch (call.method) {
      case 'write':
        if (key != null && args['value'] != null) {
          _mockKeystore[key] = args['value'].toString();
        }
        return null;
      case 'read':
        return key == null ? null : _mockKeystore[key];
      case 'delete':
        if (key != null) _mockKeystore.remove(key);
        return null;
      case 'deleteAll':
        _mockKeystore.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(_mockKeystore);
      case 'containsKey':
        return key != null && _mockKeystore.containsKey(key);
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _mockKeystore.clear();
    _installMockSecureStorageChannel();
  });

  group('BUG 1 — Offline Logout Preserves Data, Login Restore, Optional PIN & Factory Reset', () {
    test('Standalone logout ONLY clears active session and preserves SQLite/store profile/products/sales/held bills', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final authCubit = AuthCubit(apiClient: api, offlineDb: db);
      addTearDown(authCubit.close);

      await authCubit.startLocalTrialSession(
        storeName: 'Warung Kopi Nusantara',
        businessVertical: 'restaurant',
      );

      // Add custom product, hold a bill, and save a sale
      await db.addOrUpdateLocalProduct({
        'id': -5001,
        'name': 'Kopi Susu Gula Aren',
        'sku': 'KSGA-01',
        'barcode': '',
        'selling_price': 22000.0,
        'cost_price': 9000.0,
        'stock': 40.0,
        'is_local_only': true,
      });
      await db.saveHeldSale({
        'id': -9001,
        'label': 'Meja 3',
        'items': [
          {'product_id': -5001, 'product_name': 'Kopi Susu Gula Aren', 'quantity': 2.0, 'unit_price': 22000.0},
        ],
        'total': 44000.0,
        'saved_at': DateTime.now().toIso8601String(),
      });
      await db.saveSaleToLocalHistory({
        'id': 1700000100001,
        'number': 'OFF-0001',
        'grand_total': 22000.0,
        'paid_total': 22000.0,
        'status': 'completed',
      });

      // Perform Logout in Offline Standalone mode
      await authCubit.logout();

      expect(authCubit.state.isAuthenticated, isFalse);
      expect(db.getCachedAuthSession(), isNull);
      // ALL offline business data MUST remain 100% intact!
      expect(db.hasExistingStandaloneStore, isTrue);
      expect(db.getSavedStoreProfile()?['name'], 'Warung Kopi Nusantara');
      expect(db.getCachedProducts().any((p) => p['name'] == 'Kopi Susu Gula Aren'), isTrue);
      expect(db.getHeldSales().length, 1);
      expect(db.getLocalSalesHistory().length, 1);

      // Resume store cleanly without wiping data
      final resumed = await authCubit.resumeLocalTrialSession();
      expect(resumed, isTrue);
      expect(authCubit.state.isAuthenticated, isTrue);
      expect(authCubit.state.session.activeStore.name, 'Warung Kopi Nusantara');
      expect(db.getCachedProducts().any((p) => p['name'] == 'Kopi Susu Gula Aren'), isTrue);
      expect(db.getHeldSales().length, 1);
    });

    test('Optional standalone cashier PIN protects resumeLocalTrialSession and Factory Reset wipes all', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final authCubit = AuthCubit(apiClient: api, offlineDb: db);
      addTearDown(authCubit.close);

      await authCubit.startLocalTrialSession(
        storeName: 'Toko Aman Jaya',
        businessVertical: 'retail',
      );
      await authCubit.setStandaloneCashierPin('2580');
      expect(authCubit.hasStandalonePin, isTrue);

      await authCubit.logout();

      // Wrong PIN rejected
      final wrongOk = await authCubit.resumeLocalTrialSession(pin: '1111');
      expect(wrongOk, isFalse);
      expect(authCubit.state.errorMessage, contains('PIN'));

      // Correct PIN accepted
      final rightOk = await authCubit.resumeLocalTrialSession(pin: '2580');
      expect(rightOk, isTrue);
      expect(authCubit.state.isAuthenticated, isTrue);

      // Explicit Factory Reset wipes EVERYTHING cleanly
      await authCubit.factoryResetLocalDatabase();
      expect(authCubit.state.isAuthenticated, isFalse);
      expect(db.hasExistingStandaloneStore, isFalse);
      expect(db.getSavedStoreProfile(), isNull);
      expect(db.getCachedProducts(), isEmpty);
      expect(db.getHeldSales(), isEmpty);
      expect(authCubit.hasStandalonePin, isFalse);
    });

    testWidgets('LoginScreen displays saved offline store card instead of setup wizard after logout',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final authCubit = AuthCubit(apiClient: api, offlineDb: db);
      addTearDown(authCubit.close);

      await authCubit.startLocalTrialSession(
        storeName: 'Apotek Sehat Mandiri',
        businessVertical: 'pharmacy',
      );
      await authCubit.logout();

      await tester.pumpWidget(
        BlocProvider<AuthCubit>.value(
          value: authCubit,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: LoginScreen(apiClient: api),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Saved offline store card must appear, NOT the fresh setup wizard
      expect(find.byKey(const Key('existing_standalone_store_card')), findsOneWidget);
      expect(find.text('Apotek Sehat Mandiri'), findsOneWidget);
      expect(find.byKey(const Key('resume_standalone_store_button')), findsOneWidget);
      expect(find.text('Buat Toko Baru (Offline Lokal)'), findsNothing);
    });
  });

  group('BUG 2 — Hold Bill (Nota Tahan) Persistent Across App Restart / Crash', () {
    test('Holding 2 bills survives complete PosCubit destruction & cold restart, then recalls cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.saveAuthSession({
        'is_local_trial': true,
        'token': 'local-trial',
        'user': {'id': 1, 'name': 'Kasir A', 'email': 'a@local'},
        'active_store': {'id': 1, 'name': 'Resto Uji', 'code': 'RST'},
      });

      final prod1 = ProductModel(
        id: -101,
        name: 'Nasi Goreng Spesial',
        sku: 'NG-01',
        barcode: '899000101',
        sellingPrice: 35000,
        costPrice: 15000,
        stock: 50,
        isLocalOnly: true,
      );
      final prod2 = ProductModel(
        id: -102,
        name: 'Es Teh Manis',
        sku: 'ETM-01',
        barcode: '899000102',
        sellingPrice: 8000,
        costPrice: 2000,
        stock: 100,
        isLocalOnly: true,
      );
      await db.cacheProducts([prod1.toJson(), prod2.toJson()]);

      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final conn = _FakeConnectivityService(online: false);
      addTearDown(conn.dispose);

      // Session 1: Hold 2 carts
      final cubit1 = PosCubit(apiClient: api, offlineDb: db, connectivityService: conn);
      await cubit1.initializeCatalog(awaitCloudSync: false);

      cubit1.addToCart(prod1);
      cubit1.addToCart(prod2);
      cubit1.setOrderNotes('Pedas sedang');
      await cubit1.holdCurrentCart('Meja 01');

      cubit1.addToCart(prod2);
      cubit1.selectCustomer({'id': 77, 'name': 'Budi Santoso', 'phone': '08123456'});
      await cubit1.holdCurrentCart('Meja 05');

      expect(cubit1.state.heldCarts.length, 2);
      expect(cubit1.state.cart, isEmpty);

      // Simulate Force Close / Battery Dead / Full App Restart
      await cubit1.close();

      // Session 2: Brand-new OfflineDatabase & PosCubit instance on same storage
      final dbRestarted = OfflineDatabase(prefs);
      final cubit2 = PosCubit(apiClient: api, offlineDb: dbRestarted, connectivityService: conn);
      addTearDown(cubit2.close);
      await cubit2.initializeCatalog(awaitCloudSync: false);

      expect(cubit2.state.heldCarts.length, 2);
      final labels = cubit2.state.heldCarts.map((h) => h['held_label']).toList();
      expect(labels, containsAll(['Meja 01', 'Meja 05']));

      // Recall Meja 05 (index 0 because latest inserted at top) and verify items & customer
      cubit2.recallHeldSale(0);
      expect(cubit2.state.cart.length, 1);
      expect(cubit2.state.cart.first.product.name, 'Es Teh Manis');
      expect(cubit2.state.selectedCustomer?['name'], 'Budi Santoso');
      expect(cubit2.state.heldCarts.length, 1);

      // Wait briefly for unawaited persist, then confirm persistence after a 3rd restart
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final dbThird = OfflineDatabase(prefs);
      expect(dbThird.getHeldSales().length, 1);
      expect(dbThird.getHeldSales().first['held_label'], 'Meja 01');
    });
  });

  group('BUG 3, 4, 5, 6 — Full Offline Sync Parity (Products, Sales, Receivables, Expenses, Shifts)', () {
    test('BUG 3: Offline receivable payments sync to POST /debts/receivables/{saleId}/pay (including remapping offline credit sale)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);

      final calls = <Map<String, dynamic>>[];
      api.dio.httpClientAdapter = _StubAdapter((options) async {
        final data = options.data is Map ? Map<String, dynamic>.from(options.data as Map) : {};
        calls.add({
          'path': options.path,
          'headers': Map<String, dynamic>.from(options.headers),
          'data': data,
        });
        if (options.path.endsWith('/pos/checkout')) {
          return _jsonResponse({
            'success': true,
            'data': {'id': 777, 'number': 'POS-CLOUD-777'},
          }, status: 201);
        }
        if (options.path.contains('/debts/receivables/') && options.path.endsWith('/pay')) {
          return _jsonResponse({'success': true, 'data': {'balance_due': 0}}, status: 200);
        }
        return _jsonResponse({'success': true, 'data': {}});
      });

      // Scenario A: Existing Cloud receivable paid offline
      await db.cacheCloudReceivables([
        {
          'sale_id': 501,
          'number': 'INV-501',
          'grand_total': 200000.0,
          'paid_total': 0.0,
          'balance_due': 200000.0,
          'customer': {'id': 12, 'name': 'Toko Maju'},
        },
      ]);
      await db.payLocalReceivable(
        saleId: 501,
        amount: 150000.0,
        paymentMethod: 'Tunai',
        paymentMethodId: 1,
        enqueueForCloudSync: true,
      );
      expect(db.getCachedCloudReceivables().first['balance_due'], 50000.0);

      // Scenario B: Offline credit sale + offline installment BEFORE sale synced
      const offlineSaleUuid = '11111111-2222-4333-8444-555555555555';
      await db.enqueueOfflineSale({
        'local_uuid': offlineSaleUuid,
        'number': 'OFF-CREDIT-01',
        'items': [
          {'product_id': 10, 'quantity': 1, 'unit_price': 100000},
        ],
        'payments': [],
      });
      await db.saveSaleToLocalHistory({
        'id': 1700000999000,
        'local_uuid': offlineSaleUuid,
        'number': 'OFF-CREDIT-01',
        'grand_total': 100000.0,
        'paid_total': 0.0,
        'balance_due': 100000.0,
        'customer': {'id': 15, 'name': 'Pelanggan Bon'},
      });
      await db.payLocalReceivable(
        saleId: 1700000999000,
        saleLocalUuid: offlineSaleUuid,
        amount: 60000.0,
        paymentMethod: 'QRIS',
        paymentMethodId: 2,
        enqueueForCloudSync: true,
      );

      expect(db.pendingReceivablePaymentsCount, 2);

      final syncedTotal = await db.syncOfflineQueue(api);
      expect(syncedTotal, 3); // 1 offline sale + 2 receivable payments
      expect(db.pendingReceivablePaymentsCount, 0);

      final paths = calls.map((c) => c['path'].toString()).toList();
      expect(paths, [
        '/pos/checkout',
        '/debts/receivables/501/pay',
        '/debts/receivables/777/pay', // Remapped from local sale 1700000999000 -> Cloud 777!
      ]);
      // Every receivable payment carries an X-Idempotency-Key
      expect((calls[1]['headers']['X-Idempotency-Key'] ?? '').toString().isNotEmpty, isTrue);
      expect((calls[2]['headers']['X-Idempotency-Key'] ?? '').toString().isNotEmpty, isTrue);
      expect(calls[1]['data']['amount'], 150000.0);
      expect(calls[2]['data']['payment_method_id'], 2);
    });

    test('BUG 4: Offline products (negative ID AND legacy positive timestamp ID) sync to Cloud and remap sales & held bills', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.saveAuthSession({
        'is_local_trial': false,
        'token': 'cloud-token',
        'user': {'id': 1, 'name': 'Kasir Cloud', 'email': 'k@oxora.id'},
        'active_store': {'id': 1, 'name': 'Cabang Utama', 'code': 'CBG'},
      });

      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final conn = _FakeConnectivityService(online: false);
      addTearDown(conn.dispose);

      int nextServerProductId = 801;
      final assignedByName = <String, int>{};
      final postedProducts = <Map<String, dynamic>>[];
      final postedCheckouts = <Map<String, dynamic>>[];

      api.dio.httpClientAdapter = _StubAdapter((options) async {
        final Map<String, dynamic> data =
            options.data is Map ? Map<String, dynamic>.from(options.data as Map) : <String, dynamic>{};
        if (options.method == 'POST' && options.path.endsWith('/products')) {
          final assignedId = nextServerProductId++;
          final name = (data['name'] ?? '').toString();
          assignedByName[name] = assignedId;
          postedProducts.add({
            'id': assignedId,
            'name': name,
            'idempotencyKey': options.headers['X-Idempotency-Key'],
          });
          return _jsonResponse({
            'success': true,
            'data': {'id': assignedId, 'name': name},
          }, status: 201);
        }
        if (options.method == 'POST' && options.path.endsWith('/pos/checkout')) {
          postedCheckouts.add(data);
          return _jsonResponse({
            'success': true,
            'data': {'id': 9001, 'number': 'POS-9001'},
          }, status: 201);
        }
        if (options.method == 'GET' && options.path.endsWith('/pos/catalog')) {
          return _jsonResponse({
            'success': true,
            'data': {
              'products': [
                {'id': 801, 'name': 'Produk Baru Negatif', 'barcode': '', 'selling_price': 15000, 'stock': 10},
                {'id': 802, 'name': 'Produk Legacy Positif', 'barcode': '', 'selling_price': 20000, 'stock': 5},
              ],
              'categories': [],
              'customers': [],
              'suppliers': [],
              'payment_methods': [{'id': 1, 'name': 'Tunai', 'type': 'cash'}],
            },
          });
        }
        return _jsonResponse({'success': true, 'data': []});
      });

      final cubit = PosCubit(apiClient: api, offlineDb: db, connectivityService: conn);
      addTearDown(cubit.close);
      await cubit.initializeCatalog(awaitCloudSync: false);

      // 1) Create new product offline via saveProductInventory (negative ID + isLocalOnly: true)
      final saveRes = await cubit.saveProductInventory(
        ProductModel(
          id: -1700000001000,
          name: 'Produk Baru Negatif',
          sku: 'PBN-01',
          barcode: '899888001',
          sellingPrice: 15000,
          costPrice: 10000,
          stock: 10,
          isLocalOnly: true,
        ),
        isNew: true,
      );
      expect(saveRes.ok, isTrue);
      expect(saveRes.syncedToCloud, isFalse);

      // 2) Seed a legacy pre-fix product that was stored with positive millisecondsSinceEpoch ID!
      const legacyId = 1760000000123;
      await db.addOrUpdateLocalProduct({
        'id': legacyId,
        'name': 'Produk Legacy Positif',
        'sku': 'PLP-01',
        'barcode': '899888002',
        'selling_price': 20000.0,
        'cost_price': 12000.0,
        'stock': 5.0,
      });

      // Queue an offline sale AND a held sale referencing both local IDs
      await db.enqueueOfflineSale({
        'local_uuid': '22222222-3333-4444-8555-666666666666',
        'number': 'OFF-PROD-01',
        'items': [
          {'product_id': -1700000001000, 'quantity': 1, 'unit_price': 15000},
          {'product_id': legacyId, 'quantity': 2, 'unit_price': 20000},
        ],
        'payments': [{'payment_method_id': 1, 'amount': 55000}],
      });
      await db.saveHeldSale({
        'id': -77,
        'label': 'Parkir Produk Baru',
        'items': [
          {'product_id': legacyId, 'product_name': 'Produk Legacy Positif', 'quantity': 1, 'unit_price': 20000},
        ],
        'total': 20000.0,
        'saved_at': DateTime.now().toIso8601String(),
      });

      // Go online & sync!
      conn.online = true;
      final synced = await cubit.syncOfflineTransactions();
      expect(synced, greaterThanOrEqualTo(3)); // 2 products + 1 sale
      expect(postedProducts.length, 2);
      expect(postedProducts.every((p) => (p['idempotencyKey'] ?? '').toString().isNotEmpty), isTrue);

      // Verify offline sale was remapped to exact official Cloud IDs BEFORE checkout POST!
      expect(postedCheckouts.length, 1);
      final syncedItems = (postedCheckouts.first['items'] as List).cast<Map<String, dynamic>>();
      expect(syncedItems.map((i) => i['product_id']).toList(), [
        assignedByName['Produk Baru Negatif'],
        assignedByName['Produk Legacy Positif'],
      ]);

      // Verify held sale was ALSO remapped to the official Cloud ID for Produk Legacy Positif!
      final heldItems = (db.getHeldSales().first['items'] as List).cast<Map<String, dynamic>>();
      expect(heldItems.first['product_id'], assignedByName['Produk Legacy Positif']);
    });

    test('BUG 5: Offline petty cash expenses sync to POST /expenses and flip is_synced = 1', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);

      final postedExpenses = <Map<String, dynamic>>[];
      api.dio.httpClientAdapter = _StubAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/expenses')) {
          postedExpenses.add({
            'data': Map<String, dynamic>.from(options.data as Map),
            'key': options.headers['X-Idempotency-Key'],
          });
          return _jsonResponse({'success': true, 'data': {'id': 300 + postedExpenses.length}}, status: 201);
        }
        return _jsonResponse({'success': true, 'data': {}});
      });

      await db.addLocalExpense(
        category: 'Listrik & Air',
        categoryId: 2,
        amount: 75000,
        description: 'Token Listrik Toko',
        paymentMethod: 'Tunai',
      );
      await db.addLocalExpense(
        category: 'Perlengkapan',
        categoryId: 4,
        amount: 25000,
        description: 'Kantong Kresek',
        paymentMethod: 'Tunai',
      );

      expect(db.pendingLocalExpensesCount, 2);
      final synced = await db.syncOfflineQueue(api);
      expect(synced, 2);
      expect(db.pendingLocalExpensesCount, 0);
      expect(postedExpenses.length, 2);
      expect(postedExpenses.first['data']['description'], 'Token Listrik Toko');
      expect(postedExpenses.first['data']['category_id'], 2);
      expect((postedExpenses.first['key'] ?? '').toString().isNotEmpty, isTrue);

      // Re-running sync must NOT repost already-synced expenses
      final secondRun = await db.syncOfflineQueue(api);
      expect(secondRun, 0);
      expect(postedExpenses.length, 2);
    });

    test('BUG 6: Offline shift closure queues and syncs AFTER offline sales with X-Idempotency-Key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);

      final callOrder = <String>[];
      Map<String, dynamic>? shiftClosePayload;
      String? shiftCloseIdemKey;

      api.dio.httpClientAdapter = _StubAdapter((options) async {
        callOrder.add(options.path);
        if (options.path.endsWith('/pos/checkout')) {
          return _jsonResponse({'success': true, 'data': {'id': 601, 'number': 'POS-601'}}, status: 201);
        }
        if (options.path.endsWith('/shifts/close')) {
          shiftClosePayload = Map<String, dynamic>.from(options.data as Map);
          shiftCloseIdemKey = options.headers['X-Idempotency-Key']?.toString();
          return _jsonResponse({'success': true, 'data': {'id': 42, 'status': 'closed'}}, status: 200);
        }
        return _jsonResponse({'success': true, 'data': {}});
      });

      await db.enqueueOfflineSale({
        'local_uuid': '33333333-4444-4555-8666-777777777777',
        'number': 'OFF-SHIFT-SALE-1',
        'items': [{'product_id': 1, 'quantity': 1, 'unit_price': 50000}],
        'payments': [{'payment_method_id': 1, 'amount': 50000}],
      });
      await db.enqueuePendingShiftClosure(
        shiftId: 42,
        closingCashCounted: 550000,
        closingDenominations: {'100000': 5, '50000': 1},
        notes: 'Tutup shift saat internet mati',
      );

      expect(db.pendingShiftClosuresCount, 1);
      expect(db.hasPendingClosureForShift(42), isTrue);

      final synced = await db.syncOfflineQueue(api);
      expect(synced, 2);
      expect(db.pendingShiftClosuresCount, 0);
      expect(db.hasPendingClosureForShift(42), isFalse);

      // CRITICAL INVARIANT: Offline sale MUST sync BEFORE shift closure!
      expect(callOrder, ['/pos/checkout', '/shifts/close']);
      expect(shiftClosePayload?['shift_id'], 42);
      expect(shiftClosePayload?['closing_cash_counted'], 550000.0);
      expect((shiftCloseIdemKey ?? '').isNotEmpty, isTrue);
    });
  });

  group('ENTERPRISE HARDENING — ACID, Idempotency Retries, SecureLicenseVault & Dead-Letter Queue', () {
    test('Hardening #1 (ACID): Offline checkout atomically updates queue, history, stock, movements, customer debt & shift', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.saveAuthSession({
        'is_local_trial': false,
        'token': 'cloud-token',
        'user': {'id': 1, 'name': 'Kasir ACID', 'email': 'acid@oxora.id'},
        'active_store': {'id': 1, 'name': 'Toko ACID', 'code': 'ACD'},
      });

      final prod = ProductModel(
        id: 10,
        name: 'Beras 5kg',
        sku: 'BRS-5',
        barcode: '899000500',
        sellingPrice: 70000,
        costPrice: 60000,
        stock: 20,
      );
      await db.cacheProducts([prod.toJson()]);
      await db.cacheCustomers([
        {'id': 5, 'name': 'Bu Siti', 'phone': '08111', 'outstanding_balance': 10000.0, 'store_credit_balance': 0.0},
      ]);
      await db.cachePaymentMethods([
        {'id': 1, 'name': 'Tunai', 'type': 'cash'},
      ]);
      await db.openLocalShift(openingCash: 200000, cashierName: 'Kasir ACID');

      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final conn = _FakeConnectivityService(online: false);
      addTearDown(conn.dispose);

      final cubit = PosCubit(apiClient: api, offlineDb: db, connectivityService: conn);
      addTearDown(cubit.close);
      await cubit.initializeCatalog(awaitCloudSync: false);

      cubit.selectCustomer({'id': 5, 'name': 'Bu Siti', 'phone': '08111', 'outstanding_balance': 10000.0});
      cubit.addToCart(prod);
      cubit.addToCart(prod); // 2 x 70,000 = 140,000

      // Partial cash payment (100,000) + 40,000 kasbon
      final receipt = await cubit.completeCheckout(
        payments: [
          {'payment_method_id': 1, 'method_name': 'Tunai', 'amount': 100000.0},
        ],
        paymentMethodNames: ['Tunai'],
        paidTotal: 100000.0,
        changeReturned: 0.0,
        balanceDue: 40000.0,
      );

      expect(receipt['is_offline_pending'], isTrue);
      // Verify ALL atomic artifacts match identically
      expect(db.getOfflineSalesQueue().length, 1);
      expect(db.getLocalSalesHistory().length, 1);
      expect(db.getCachedProducts().first['stock'], 18.0); // 20 - 2
      expect(db.getLocalStockMovements().first['quantity_delta'], -2.0);
      expect(db.getCachedCustomers().first['outstanding_balance'], 50000.0); // 10k + 40k
      expect(db.getCurrentLocalShift()?['expected_cash'], 300000.0); // 200k + 100k cash
    });

    test('Hardening #2 (Idempotency): Transient network failure retries reuse the EXACT same X-Idempotency-Key', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);

      final seenKeys = <String>[];
      int attempt = 0;
      api.dio.httpClientAdapter = _StubAdapter((options) async {
        attempt++;
        seenKeys.add((options.headers['X-Idempotency-Key'] ?? '').toString());
        if (attempt == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
            message: 'Simulated flaky 4G timeout',
          );
        }
        return _jsonResponse({'success': true, 'data': {'id': 999}}, status: 201);
      });

      await db.addLocalExpense(
        category: 'Transport',
        amount: 35000,
        description: 'Bensin Kurir',
      );

      // Attempt 1 fails due to network timeout -> expense stays pending
      final sync1 = await db.syncOfflineQueue(api);
      expect(sync1, 0);
      expect(db.pendingLocalExpensesCount, 1);

      // Attempt 2 succeeds -> MUST send exact same UUIDv4 X-Idempotency-Key!
      final sync2 = await db.syncOfflineQueue(api);
      expect(sync2, 1);
      expect(db.pendingLocalExpensesCount, 0);
      expect(seenKeys.length, 2);
      expect(seenKeys[0].isNotEmpty, isTrue);
      expect(seenKeys[0], equals(seenKeys[1]));
    });

    test('Hardening #3 (SecureLicenseVault): RFC 6234/2104 vectors pass & SharedPreferences PRO tampering is blocked', () async {
      // 1. Verify cryptographic primitives against NIST / RFC 4231 test vectors
      expect(
        _toHex(SecureLicenseVault.sha256(Uint8List.fromList(utf8.encode('abc')))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        _toHex(SecureLicenseVault.hmacSha256(
          Uint8List.fromList(utf8.encode('Jefe')),
          Uint8List.fromList(utf8.encode('what do ya want for nothing?')),
        )),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );

      // 2. Seal a Starter session, then simulate attacker tampering SharedPreferences to Enterprise PRO
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final vault = SecureLicenseVault(secureStorage: api.secureStorage, prefs: prefs);

      const store = StoreBranchModel(id: 1, name: 'Toko Jujur', code: 'JJR');
      const legitimateStarter = AuthSessionModel(
        userId: 10,
        userName: 'Kasir',
        userEmail: 'kasir@toko.id',
        userRole: 'cashier',
        isOwner: false,
        tenantName: 'Toko Jujur',
        tenantSubdomain: 'jujur',
        planName: 'Starter',
        tier: 'starter',
        activeModules: ['cash_debt'],
        activeStore: store,
        availableStores: [store],
      );
      await vault.sealSessionEntitlements(legitimateStarter);

      // Attacker edits SharedPreferences to escalate tier -> 'enterprise' & unlock PRO modules!
      final forgedSession = legitimateStarter.copyWith(
        tier: 'enterprise',
        activeModules: const ['cash_debt', 'accounting', 'loyalty', 'warehouse'],
      );
      expect(await vault.hasValidSeal(forgedSession), isFalse);

      // Vault restores authentic sealed Starter entitlements from secure Keystore!
      final enforced = await vault.verifyAndEnforce(forgedSession);
      expect(enforced.tampered, isTrue);
      expect(enforced.session.tier, 'starter');
      expect(enforced.session.activeModules, ['cash_debt']);

      // 3. Even if Keystore is cleared, an unsealed forged PRO session fails CLOSED to starter!
      await vault.clearVault();
      final failClosed = await vault.verifyAndEnforce(forgedSession);
      expect(failClosed.tampered, isTrue);
      expect(failClosed.session.tier, 'starter');
      expect(failClosed.session.activeModules, ['cash_debt']);
      expect(db.getCachedAuthSession(), isNull);
    });

    test('Hardening #4 (Dead-Letter Queue): Rejected 422 payload is quarantined without jamming queue, supports override retry & discard', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.saveAuthSession({
        'is_local_trial': false,
        'token': 'cloud-tok',
        'user': {'id': 1, 'name': 'Kasir DLQ', 'email': 'dlq@oxora.id'},
        'active_store': {'id': 1, 'name': 'Toko DLQ', 'code': 'DLQ'},
      });

      final api = ApiClient(secureStorage: const FlutterSecureStorage(), prefs: prefs);
      final conn = _FakeConnectivityService(online: true);
      addTearDown(conn.dispose);

      final seenShiftKeys = <String>[];
      api.dio.httpClientAdapter = _StubAdapter((options) async {
        final data = options.data is Map ? Map<String, dynamic>.from(options.data as Map) : {};
        if (options.path.endsWith('/expenses')) {
          if ((data['description'] ?? '').toString().contains('INVALID')) {
            return _jsonResponse({
              'success': false,
              'error_code': 'ValidationError',
              'message': 'Kategori biaya tidak ditemukan di Cloud',
            }, status: 422);
          }
          return _jsonResponse({'success': true, 'data': {'id': 401}}, status: 201);
        }
        if (options.path.endsWith('/shifts/close')) {
          seenShiftKeys.add((options.headers['X-Idempotency-Key'] ?? '').toString());
          if ((data['variance_reason'] ?? '').toString().isEmpty) {
            return _jsonResponse({
              'success': false,
              'error_code': 'VarianceReasonRequired',
              'requires_variance_reason': true,
              'message': 'Alasan selisih kas wajib diisi.',
            }, status: 422);
          }
          return _jsonResponse({'success': true, 'data': {'id': 99, 'status': 'closed'}}, status: 200);
        }
        return _jsonResponse({'success': true, 'data': {}});
      });

      // Queue 1 bad expense, 1 healthy expense, and 1 shift closure needing variance_reason
      await db.addLocalExpense(category: 'Bad', amount: 10000, description: 'INVALID EXPENSE');
      await db.addLocalExpense(category: 'Good', amount: 20000, description: 'Beli Galon Air');
      await db.enqueuePendingShiftClosure(shiftId: 99, closingCashCounted: 450000);

      final synced = await db.syncOfflineQueue(api);
      // Healthy expense STILL synced despite bad expense before it!
      expect(synced, 1);
      expect(db.deadLetterCount, 2); // 1 rejected expense + 1 rejected shift closure
      expect(db.pendingLocalExpensesCount, 0); // Neither jams future auto-sync!
      expect(db.pendingShiftClosuresCount, 0);

      final cubit = PosCubit(apiClient: api, offlineDb: db, connectivityService: conn);
      addTearDown(cubit.close);
      cubit.refreshOfflinePendingState();
      expect(cubit.state.deadLetterItems.length, 2);

      // Retry the quarantined shift closure with `variance_reason` override
      final shiftDlq = cubit.state.deadLetterItems
          .firstWhere((d) => d['entity_type'] == 'shift_closure');
      final retryRes = await cubit.retryDeadLetterItem(
        shiftDlq['id'].toString(),
        payloadOverrides: {'variance_reason': 'miscount'},
      );
      expect(retryRes.success, isTrue);
      expect(seenShiftKeys.length, 2);
      expect(seenShiftKeys[0], equals(seenShiftKeys[1])); // Exact same X-Idempotency-Key!
      expect(cubit.state.deadLetterItems.length, 1);

      // Discard the invalid expense cleanly
      final expDlq = cubit.state.deadLetterItems.first;
      await cubit.discardDeadLetterItem(expDlq['id'].toString());
      expect(cubit.state.deadLetterItems, isEmpty);
      expect(db.deadLetterCount, 0);
    });
  });
}
