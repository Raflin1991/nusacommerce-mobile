import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/edge_discovery_service.dart';
import 'package:nusacommerce_mobile/core/network/network_connectivity_service.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline POS & Multi-Device Sync Parity (Pillars 1-5)', () {
    test('Pillar 3: Two fresh devices auto-generate distinct node codes and <=32 char partitioned receipt numbers', () async {
      SharedPreferences.setMockInitialValues({});
      final prefsA = await SharedPreferences.getInstance();
      final discoveryA = EdgeDiscoveryService(prefsA);
      final codeA = discoveryA.getMobileNodeCode();
      expect(codeA, matches(RegExp(r'^M[A-Z0-9]{4}$')));
      // Stable on repeat reads for same device
      expect(discoveryA.getMobileNodeCode(), codeA);

      // Simulate second fresh device
      SharedPreferences.setMockInitialValues({});
      final prefsB = await SharedPreferences.getInstance();
      final discoveryB = EdgeDiscoveryService(prefsB);
      final codeB = discoveryB.getMobileNodeCode();
      expect(codeB, matches(RegExp(r'^M[A-Z0-9]{4}$')));
      expect(codeB, isNot(codeA));

      // Long store code must stay strictly <= 32 characters (sales.number VARCHAR(32))
      final db = OfflineDatabase(prefsA);
      final num1 = await db.generatePartitionedFallbackNumber(
        storeCode: 'CABANG-JAKARTA-SELATAN-01',
        nodeCode: codeA,
        now: DateTime(2026, 11, 22),
      );
      expect(num1.length, lessThanOrEqualTo(32));
      expect(num1, contains('-$codeA-202611-00001'));
    });

    test('Pillar 1 & 3: Offline checkout fast-path completes without HTTP wait and uses partitioned receipt number', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      await db.saveStoreProfile({'name': 'Toko Uji', 'code': 'JKT01', 'branch': 'Jakarta 01'});

      int httpCalls = 0;
      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      await apiClient.edgeDiscovery.setMobileNodeCode('M07');
      apiClient.dio.httpClientAdapter = _StubAdapter((opts) async {
        httpCalls++;
        throw DioException.connectionError(requestOptions: opts, reason: 'Should never be called while offline');
      });

      final connectivity = _FakeConnectivityService(online: false);
      final cubit = PosCubit(
        apiClient: apiClient,
        offlineDb: db,
        connectivityService: connectivity,
      );

      final prod = ProductModel(
        id: 101,
        name: 'Kopi Tubruk',
        sku: 'KPI-01',
        barcode: '8991001',
        sellingPrice: 15000,
        stock: 10,
      );
      await db.cacheProducts([prod.toJson()]);
      await cubit.initializeCatalog();
      cubit.addToCart(prod);

      final receipt = await cubit.completeCheckout(
        payments: [
          {'payment_method_id': 1, 'amount': 15000.0, 'tendered_amount': 20000.0},
        ],
        paymentMethodNames: ['Tunai'],
        paidTotal: 15000.0,
        changeReturned: 5000.0,
        balanceDue: 0.0,
      );

      // Fast-path skipped blocking HTTP timeout completely!
      expect(httpCalls, 0);
      expect(receipt['is_offline_pending'], isTrue);
      expect(receipt['number'], startsWith('INV-JKT01-M07-'));
      expect(receipt['origin_node_code'], 'M07');
      expect(db.getOfflineSalesQueue().length, 1);
      expect(db.getOfflineSalesQueue().first['synced_from_offline'], isTrue);
      expect(db.getCachedProducts().first['stock'], 9.0);

      await cubit.close();
      connectivity.dispose();
    });

    test('Pillar 2: Offline queue sync sends exact persisted local_uuid as X-Idempotency-Key across retries & deduplicates concurrent calls', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);

      const persistedUuid = '11111111-2222-4333-8444-555555555555';
      await db.enqueueOfflineSale({
        'local_uuid': persistedUuid,
        'number': 'INV-MAIN-M02-202611-00001',
        'origin_node_code': 'M02',
        'items': [
          {'product_id': 1, 'quantity': 1, 'unit_price': 10000},
        ],
        'payments': [
          {'payment_method_id': 1, 'amount': 10000},
        ],
      });

      final capturedHeaders = <String?>[];
      final capturedSyncedFlags = <dynamic>[];
      int attempt = 0;

      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      apiClient.dio.httpClientAdapter = _StubAdapter((opts) async {
        attempt++;
        capturedHeaders.add(opts.headers['X-Idempotency-Key']?.toString());
        final body = opts.data is Map ? Map<String, dynamic>.from(opts.data as Map) : {};
        capturedSyncedFlags.add(body['synced_from_offline']);

        if (attempt == 1) {
          throw DioException.connectionTimeout(
            requestOptions: opts,
            timeout: const Duration(seconds: 1),
          );
        }

        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _jsonResponse({
          'success': true,
          'data': {'id': 77, 'number': 'INV-MAIN-M02-202611-00001'},
          'meta': {'synced_from_offline': true, 'conflict_flagged': false},
        }, status: 201);
      });

      // Attempt 1 fails with network timeout -> stays queued
      final firstCount = await db.syncOfflineQueue(apiClient);
      expect(firstCount, 0);
      expect(db.getOfflineSalesQueue().length, 1);

      // Concurrent Attempt 2a & 2b must be mutex-deduplicated to a single POST using the exact same X-Idempotency-Key
      final results = await Future.wait([
        db.syncOfflineQueue(apiClient),
        db.syncOfflineQueue(apiClient),
      ]);
      expect(results, [1, 1]);
      expect(attempt, 2);
      expect(capturedHeaders, [persistedUuid, persistedUuid]);
      expect(capturedSyncedFlags, [true, true]);
      expect(db.getOfflineSalesQueue(), isEmpty);
    });

    test('Pillar 5: First-time login with empty local DB pulls paginated master data + payment methods with progress updates', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);
      expect(db.hasMasterDataSnapshot, isFalse);

      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
      );
      apiClient.dio.httpClientAdapter = _StubAdapter((opts) async {
        if (opts.path.endsWith('/products')) {
          final page = opts.queryParameters['page'] ?? 1;
          if (page == 1) {
            return _jsonResponse({
              'success': true,
              'data': [
                {'id': 1, 'name': 'Produk Halaman 1', 'sku': 'SKU-1', 'selling_price': 10000, 'stock': 5},
              ],
              'meta': {'current_page': 1, 'last_page': 2},
            });
          }
          return _jsonResponse({
            'success': true,
            'data': [
              {'id': 2, 'name': 'Produk Halaman 2', 'sku': 'SKU-2', 'selling_price': 20000, 'stock': 8},
            ],
            'meta': {'current_page': 2, 'last_page': 2},
          });
        }
        if (opts.path.endsWith('/pos/payment-methods')) {
          return _jsonResponse({
            'success': true,
            'data': [
              {'id': 1, 'code': 'cash', 'name': 'Tunai'},
              {'id': 2, 'code': 'qris', 'name': 'QRIS'},
            ],
          });
        }
        return _jsonResponse({'success': true, 'data': []});
      });

      final connectivity = _FakeConnectivityService(online: true);
      final cubit = PosCubit(
        apiClient: apiClient,
        offlineDb: db,
        connectivityService: connectivity,
      );

      final restoreStates = <bool>[];
      final sub = cubit.stream.listen((s) => restoreStates.add(s.isInitialRestoring));

      await cubit.syncWithCloud(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(restoreStates, contains(true));
      expect(cubit.state.isInitialRestoring, isFalse);
      expect(cubit.state.allProducts.length, 2);
      expect(cubit.state.allProducts.map((p) => p.sku), containsAll(['SKU-1', 'SKU-2']));
      expect(db.hasMasterDataSnapshot, isTrue);
      expect(db.getCachedPaymentMethods().length, 2);

      await sub.cancel();
      await cubit.close();
      connectivity.dispose();
    });

    test('Pillar 2 & 3 (Unified Numbering): Custom Cloud format without {node} auto-injects {node} locally offline with 0% collision and <=32 chars', () async {
      SharedPreferences.setMockInitialValues({});
      final prefsA = await SharedPreferences.getInstance();
      final dbA = OfflineDatabase(prefsA);
      await dbA.cacheNumberingFormats({
        'sale': 'FJ-{store}-{Ym}-{seq:04}',
        '_custom': {
          'sale': 'FJ-{store}-{Ym}-{seq:04}',
          'expense': 'BIAYA-OPERASIONAL-CABANG-{store}-{Ym}-{seq:04}',
        },
      });

      final ts = DateTime(2026, 11, 22, 15, 0);
      final dev1Sale1 = await dbA.generatePartitionedFallbackNumber(
        storeCode: 'JKT01',
        docType: 'sale',
        nodeCode: 'M01',
        now: ts,
      );
      final dev1Sale2 = await dbA.generatePartitionedFallbackNumber(
        storeCode: 'JKT01',
        docType: 'sale',
        nodeCode: 'M01',
        now: ts,
      );
      final dev2Sale1 = await dbA.generatePartitionedFallbackNumber(
        storeCode: 'JKT01',
        docType: 'sale',
        nodeCode: 'M02',
        now: ts,
      );
      final longExp1 = await dbA.generatePartitionedFallbackNumber(
        storeCode: 'JKT01',
        docType: 'expense',
        nodeCode: 'M01',
        now: ts,
      );
      final longExp2 = await dbA.generatePartitionedFallbackNumber(
        storeCode: 'JKT01',
        docType: 'expense',
        nodeCode: 'M02',
        now: ts,
      );

      expect(dev1Sale1, 'FJ-JKT01-202611-M01-0001');
      expect(dev1Sale2, 'FJ-JKT01-202611-M01-0002');
      expect(dev2Sale1, 'FJ-JKT01-202611-M02-0001');
      expect({dev1Sale1, dev1Sale2, dev2Sale1}.length, 3);
      expect(longExp1.length, lessThanOrEqualTo(32));
      expect(longExp2.length, lessThanOrEqualTo(32));
      expect(longExp1, contains('M01-0001'));
      expect(longExp2, contains('M02-0001'));
      expect(longExp1, isNot(longExp2));
    });
  });
}
