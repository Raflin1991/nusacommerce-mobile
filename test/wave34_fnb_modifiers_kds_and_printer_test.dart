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
import 'package:nusacommerce_mobile/features/auth/bloc/auth_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/bloc/pos_cubit.dart';
import 'package:nusacommerce_mobile/features/pos/models/pos_models.dart';
import 'package:nusacommerce_mobile/features/restaurant/presentation/kds_screen.dart';

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

  group('Wave 3.4 — F&B Modifiers, KOT Station Routing & KDS SLA Narrow-Viewport Parity', () {
    test('CartItemModel preserves structured modifiers, cooking_notes, and kds_station round-trip', () {
      const beverage = ProductModel(
        id: 101,
        name: 'Es Kopi Susu Gula Aren',
        sku: 'BR-KOPI-01',
        barcode: '89900101',
        sellingPrice: 34000,
        stock: 50,
        kdsStation: 'bar',
      );

      final item = CartItemModel(
        product: beverage,
        quantity: 2,
        unitPrice: 34000,
        cookingNotes: 'Es batu dipisah, gelas besar',
        modifiers: const [
          {'name': 'Less Sugar 30%', 'price': 0},
          {'name': 'Extra Shot', 'price': 0},
        ],
      );

      final json = item.toJson();
      expect(json['kds_station'], 'bar');
      expect(json['cooking_notes'], 'Es batu dipisah, gelas besar');
      expect((json['modifiers'] as List).length, 2);

      final restored = CartItemModel.fromJson(json);
      expect(restored.product.kdsStation, 'bar');
      expect(restored.cookingNotes, 'Es batu dipisah, gelas besar');
      expect(restored.modifierLabels, ['Less Sugar 30%', 'Extra Shot']);
    });

    test('PrinterService formats structured F&B modifiers & cooking_notes on KOT and Customer Receipt', () {
      final printer = PrinterService();
      final kot = printer.formatKitchenOrderTicket(
        tableName: 'Meja VIP-01',
        sectionName: 'Indoor',
        pax: 4,
        stationLabel: 'BAR',
        items: [
          {
            'product_name': 'Es Kopi Susu Gula Aren',
            'quantity': 2,
            'kds_station': 'bar',
            'cooking_notes': 'Es batu dipisah',
            'modifiers': [
              {'name': 'Less Sugar 30%', 'price': 0},
              {'name': 'Extra Shot', 'price': 0},
            ],
          },
        ],
      );

      expect(kot, contains('KOT [BAR]'));
      expect(kot, contains('+ Less Sugar 30%, Extra Shot'));
      expect(kot, contains('>> CATATAN: Es batu dipisah'));

      final receipt = printer.formatThermalReceiptText(
        storeProfile: {'name': 'Nusa Manunggal Kemang', 'address': 'Kemang Raya 88', 'phone': '0217182940'},
        sale: {
          'number': 'INV-KMG-0001',
          'sale_datetime': '25 Nov 2026 12:30',
          'subtotal': 68000,
          'grand_total': 68000,
          'paid_total': 70000,
          'change_returned': 2000,
          'payment_methods': ['Tunai'],
          'items': [
            {
              'product_name': 'Es Kopi Susu Gula Aren',
              'quantity': 2,
              'unit_price': 34000,
              'line_total': 68000,
              'cooking_notes': 'Es batu dipisah',
              'modifiers': [
                {'name': 'Less Sugar 30%', 'price': 0},
              ],
            },
          ],
        },
      );

      expect(receipt, contains('+ Less Sugar 30%'));
      expect(receipt, contains('*Masak: Es batu dipisah'));
    });

    testWidgets('KdsScreen renders Station Filter & SLA badges cleanly at 360x640 and 300x640 without overflow',
        (tester) async {
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
      GetIt.instance.registerSingleton<ApiClient>(apiClient);
      final authCubit = AuthCubit(apiClient: apiClient, offlineDb: offlineDb);
      await authCubit.checkExistingSession(awaitRemoteRefresh: false);

      final connectivity = _OfflineStubConnectivity();
      final posCubit = PosCubit(
        offlineDb: offlineDb,
        apiClient: apiClient,
        connectivityService: connectivity,
      );

      addTearDown(() async {
        await posCubit.close();
        await authCubit.close();
        connectivity.disposeStub();
      });

      const barProduct = ProductModel(
        id: 201,
        name: 'Matcha Espresso Fusion',
        sku: 'BR-MATCHA-01',
        barcode: '89900201',
        sellingPrice: 46000,
        stock: 25,
        kdsStation: 'bar',
      );
      const kitchenProduct = ProductModel(
        id: 202,
        name: 'Iga Bakar Madu Kemang',
        sku: 'KT-IGA-01',
        barcode: '89900202',
        sellingPrice: 118000,
        stock: 15,
        kdsStation: 'kitchen',
      );

      posCubit.addToCart(
        barProduct,
        quantity: 2,
        cookingNotes: 'Oat milk, less ice',
        modifiers: const [
          {'name': 'Less Sugar 30%', 'price': 0},
        ],
      );
      posCubit.addToCart(
        kitchenProduct,
        quantity: 1,
        cookingNotes: 'Tanpa bawang goreng',
        modifiers: const [
          {'name': 'Pedas Lv.2', 'price': 0},
        ],
      );
      await posCubit.holdCurrentCart('Meja 08');

      for (final width in [360.0, 300.0]) {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthCubit>.value(value: authCubit),
              BlocProvider<PosCubit>.value(value: posCubit),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const KdsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Semua Stasiun'), findsOneWidget);
        expect(find.text('Bar & Coffee'), findsOneWidget);

        // Tap 'Semua Stasiun' first to reset across loop iterations
        await tester.ensureVisible(find.text('Semua Stasiun'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Semua Stasiun'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('+ Less Sugar 30%'), findsOneWidget);
        expect(find.textContaining('Catatan Masak: Oat milk'), findsOneWidget);

        // Tap 'Bar & Coffee' station filter -> shows Bar item, hides Kitchen item
        await tester.ensureVisible(find.text('Bar & Coffee'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bar & Coffee'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Matcha Espresso Fusion'), findsOneWidget);
        expect(find.text('Iga Bakar Madu Kemang'), findsNothing);
      }
    });
  });
}
