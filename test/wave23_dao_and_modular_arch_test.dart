import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nusacommerce_mobile/core/database/daos/error_log_dao.dart';
import 'package:nusacommerce_mobile/core/database/daos/product_local_dao.dart';
import 'package:nusacommerce_mobile/core/database/daos/sales_queue_dao.dart';
import 'package:nusacommerce_mobile/core/database/daos/shift_local_dao.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
import 'package:nusacommerce_mobile/core/network/repositories/product_repository.dart';
import 'package:nusacommerce_mobile/core/network/repositories/restaurant_table_repository.dart';
import 'package:nusacommerce_mobile/core/network/repositories/sale_repository.dart';
import 'package:nusacommerce_mobile/core/theme/app_theme.dart';
import 'package:nusacommerce_mobile/core/theme/nusa_theme_tokens.dart';
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/cart_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/catalog_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/restaurant_table_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/sync_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:nusacommerce_mobile/features/pos/presentation/pos_catalog_screen.dart';

class _StubConnectivityService extends NetworkConnectivityService {
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

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Wave 2.3 — SQLite DAOs, Domain Cubits & Modular PosCatalogScreen', () {
    test('ErrorLogDao redacts Bearer tokens, PINs, and passwords', () {
      const raw =
          'Header Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig {"supervisor_pin":"123456","password":"secretPassword"} pin=998877';
      final sanitized = ErrorLogDao.sanitizeSensitiveText(raw);
      expect(sanitized, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(sanitized, isNot(contains('123456')));
      expect(sanitized, isNot(contains('secretPassword')));
      expect(sanitized, isNot(contains('998877')));
      expect(sanitized, contains('Bearer [REDACTED]'));
      expect(sanitized, contains('[REDACTED]'));
    });

    test('ProductLocalDao, SalesQueueDao & ShiftLocalDao round-trip row codecs', () {
      final prodRow = ProductLocalDao.productToRow({
        'id': 501,
        'name': 'Kopi Susu Gula Aren',
        'sku': 'MN-KOPI-01',
        'barcode': '899100200301',
        'selling_price': 34000.0,
        'cost_price': 12000.0,
        'stock': 25.0,
        'reorder_level': 5.0,
        'category': {'id': 2, 'name': 'Coffee & Espresso Bar'},
        'unit': {'code': 'cup'},
      });
      final decodedProd = ProductLocalDao.decodeProductRow(prodRow);
      expect(decodedProd['id'], 501);
      expect(decodedProd['name'], 'Kopi Susu Gula Aren');
      expect(decodedProd['stock'], 25.0);
      expect(decodedProd['is_low_stock'], isFalse);

      final shiftRow = ShiftLocalDao.shiftToRow({
        'id': 77,
        'shift_number': 'SHF-20261125-001',
        'cashier_name': 'Siti Rahma',
        'status': 'open',
        'opening_cash': 500000.0,
        'entries': [
          {'type': 'drawer_open_no_sale', 'amount': 0.0},
        ],
      });
      final decodedShift = ShiftLocalDao.decodeShiftRow(shiftRow);
      expect(decodedShift['id'], 77);
      expect(decodedShift['opening_cash'], 500000.0);
      expect(decodedShift['no_sale_opens_count'], 1);

      final recRow = SalesQueueDao.receivablePaymentToRow({
        'id': 'uuid-rec-01',
        'sale_id': 901,
        'amount': 150000.0,
        'payment_method_id': 1,
        'payment_method_name': 'Tunai',
        'created_at': '2026-11-25T02:00:00Z',
      });
      final decodedRec = SalesQueueDao.decodeReceivablePaymentRow(recRow);
      expect(decodedRec['id'], 'uuid-rec-01');
      expect(decodedRec['sale_id'], 901);
      expect(decodedRec['amount'], 150000.0);
    });

    test('CatalogCubit, CartCubit & SyncCubit stay in reactive lockstep with PosCubit', () async {
      final prefs = await SharedPreferences.getInstance();
      final offlineDb = OfflineDatabase(prefs);
      await offlineDb.saveAuthSession({
        'is_local_trial': true,
        'user_name': 'Kasir Kemang',
        'active_store': {'id': 1, 'name': 'Nusa Manunggal Kemang', 'pos_mode': 'restaurant'},
      });
      await offlineDb.cacheProducts([
        {
          'id': 101,
          'name': 'Nasi Goreng Kampung Nusantara',
          'sku': 'MN-NASGOR',
          'barcode': '899001',
          'selling_price': 54000.0,
          'cost_price': 22000.0,
          'stock': 40.0,
          'category_id': 10,
          'category_name': 'Makanan Utama Nusantara',
        },
        {
          'id': 102,
          'name': 'Es Kopi Susu Gula Aren',
          'sku': 'MN-KOPISUSU',
          'barcode': '899002',
          'selling_price': 34000.0,
          'cost_price': 11000.0,
          'stock': 60.0,
          'category_id': 11,
          'category_name': 'Coffee & Espresso Bar',
        },
      ]);

      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      final connectivity = _StubConnectivityService();
      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: offlineDb,
        connectivityService: connectivity,
      );
      final catalogCubit = CatalogCubit(
        posCubit: posCubit,
        productRepository: ProductRepository(apiClient),
      );
      final cartCubit = CartCubit(
        posCubit: posCubit,
        saleRepository: SaleRepository(apiClient),
      );
      final syncCubit = SyncCubit(posCubit: posCubit, offlineDb: offlineDb);
      final tableCubit = RestaurantTableCubit(
        repository: RestaurantTableRepository(apiClient),
      );

      await posCubit.initializeCatalog(seedDefaultCart: false, awaitCloudSync: false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(catalogCubit.state.allProducts.length, 2);
      catalogCubit.selectCategory(11);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(catalogCubit.state.filteredProducts.length, 1);
      expect(catalogCubit.state.filteredProducts.first.sku, 'MN-KOPISUSU');

      cartCubit.addProduct(
        ProductModel.fromJson(offlineDb.getCachedProducts().first),
        quantity: 2,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cartCubit.state.items.length, 1);
      expect(cartCubit.state.grandTotal, 108000.0);

      tableCubit.selectSection('Indoor');
      expect(tableCubit.state.selectedSection, 'Indoor');
      expect(syncCubit.state.offlinePendingCount, 0);

      await tableCubit.close();
      await syncCubit.close();
      await cartCubit.close();
      await catalogCubit.close();
      await posCubit.close();
      connectivity.disposeStub();
    });

    testWidgets('Modular PosCatalogScreen renders at 360x640 narrow viewport without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prefs = await SharedPreferences.getInstance();
      final offlineDb = OfflineDatabase(prefs);
      await offlineDb.saveAuthSession({
        'is_local_trial': true,
        'user_name': 'Kasir Kemang',
        'active_store': {'id': 1, 'name': 'Nusa Manunggal Kemang', 'pos_mode': 'restaurant'},
      });
      await offlineDb.cacheProducts([
        {
          'id': -201,
          'is_local_only': true,
          'name': 'Iga Bakar Madu Kemang Spesial',
          'sku': 'MN-IGA-BAKAR',
          'barcode': '899201',
          'selling_price': 118000.0,
          'cost_price': 55000.0,
          'stock': 15.0,
          'category_id': 10,
          'category_name': 'Makanan Utama Nusantara',
        },
      ]);

      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      final connectivity = _StubConnectivityService();
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      await authCubit.checkExistingSession(awaitRemoteRefresh: false);
      final posCubit = PosCubit(
        apiClient: apiClient,
        offlineDb: offlineDb,
        connectivityService: connectivity,
      );
      final catalogCubit = CatalogCubit(
        posCubit: posCubit,
        productRepository: ProductRepository(apiClient),
      );
      final cartCubit = CartCubit(
        posCubit: posCubit,
        saleRepository: SaleRepository(apiClient),
      );
      final syncCubit = SyncCubit(posCubit: posCubit, offlineDb: offlineDb);

      addTearDown(() async {
        await syncCubit.close();
        await cartCubit.close();
        await catalogCubit.close();
        await posCubit.close();
        await authCubit.close();
        connectivity.disposeStub();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<PosCubit>.value(value: posCubit),
            BlocProvider<CatalogCubit>.value(value: catalogCubit),
            BlocProvider<CartCubit>.value(value: cartCubit),
            BlocProvider<SyncCubit>.value(value: syncCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.forMode(NusaThemeMode.warmLinenLight),
            home: const PosCatalogScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Iga Bakar Madu Kemang'), findsWidgets);
    });
  });
}
