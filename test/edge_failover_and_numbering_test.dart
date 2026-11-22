import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nusacommerce_mobile/core/database/offline_database.dart';
import 'package:nusacommerce_mobile/core/network/api_client.dart';
import 'package:nusacommerce_mobile/core/network/edge_discovery_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubHttpAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _StubHttpAdapter(this.handler);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NusaEdge 3-Tier Discovery & Partitioned Failover Numbering', () {
    test('probing resolves LAN Edge first, then Cloud Master, then Device SQLite', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final discovery = EdgeDiscoveryService(prefs);

      await discovery.setEdgeBaseUrl('https://192.168.10.10/api/v1');
      await discovery.setCloudBaseUrl('https://cloud.nusacommerce.id/api/v1');
      await discovery.setMobileNodeCode('M02');

      final apiClient = ApiClient(
        secureStorage: const FlutterSecureStorage(),
        prefs: prefs,
        edgeDiscovery: discovery,
      );

      // 1. LAN Edge healthy -> selects lanEdge
      final dioLan = Dio()
        ..httpClientAdapter = _StubHttpAdapter((opts) async {
          if (opts.uri.host == '192.168.10.10') {
            return ResponseBody.fromString(
              jsonEncode({'success': true, 'data': {'mode': 'branch_edge'}}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          throw DioException.connectionTimeout(
            requestOptions: opts,
            timeout: const Duration(milliseconds: 100),
          );
        });

      final tier1 = await apiClient.switchToBestEndpoint(probeDio: dioLan);
      expect(tier1, EdgeConnectionTier.lanEdge);
      expect(apiClient.baseUrl, 'https://192.168.10.10/api/v1');
      expect(apiClient.isOnline, isTrue);

      // 2. LAN Edge down, Cloud healthy -> selects cloudMaster
      final dioCloud = Dio()
        ..httpClientAdapter = _StubHttpAdapter((opts) async {
          if (opts.uri.host == 'cloud.nusacommerce.id') {
            return ResponseBody.fromString(
              jsonEncode({'success': true, 'data': {'mode': 'cloud'}}),
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          throw DioException.connectionError(
            requestOptions: opts,
            reason: 'LAN unreachable',
          );
        });

      final tier2 = await apiClient.switchToBestEndpoint(probeDio: dioCloud);
      expect(tier2, EdgeConnectionTier.cloudMaster);
      expect(apiClient.baseUrl, 'https://cloud.nusacommerce.id/api/v1');

      // 3. Both LAN Edge and Cloud unreachable -> drops to deviceSqlite failover
      final dioOffline = Dio()
        ..httpClientAdapter = _StubHttpAdapter((opts) async {
          throw DioException.connectionError(
            requestOptions: opts,
            reason: 'No internet & Edge power off',
          );
        });

      final tier3 = await apiClient.switchToBestEndpoint(probeDio: dioOffline);
      expect(tier3, EdgeConnectionTier.deviceSqlite);
      expect(apiClient.isOnline, isFalse);
    });

    test('partitioned Tier-3 fallback numbering isolates M01 vs M02 and resets monthly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = OfflineDatabase(prefs);

      final nov = DateTime(2026, 11, 21, 9, 0);
      final dec = DateTime(2026, 12, 1, 9, 0);

      final m1a = await db.generatePartitionedFallbackNumber(storeCode: 'KTP-01', nodeCode: 'M01', now: nov);
      final m1b = await db.generatePartitionedFallbackNumber(storeCode: 'KTP-01', nodeCode: 'M01', now: nov);
      final m2a = await db.generatePartitionedFallbackNumber(storeCode: 'KTP-01', nodeCode: 'M02', now: nov);
      final m1Dec = await db.generatePartitionedFallbackNumber(storeCode: 'KTP-01', nodeCode: 'M01', now: dec);

      expect(m1a, 'INV-KTP01-M01-202611-00001');
      expect(m1b, 'INV-KTP01-M01-202611-00002');
      expect(m2a, 'INV-KTP01-M02-202611-00001');
      expect(m1Dec, 'INV-KTP01-M01-202612-00001');
      expect({m1a, m1b, m2a, m1Dec}.length, 4);
    });

    test('extractErrorMessage provides clear Indonesian messages for HTTP 402 and 423 Edge locks', () {
      final err402 = DioException(
        requestOptions: RequestOptions(path: '/pos/checkout'),
        response: Response(
          requestOptions: RequestOptions(path: '/pos/checkout'),
          statusCode: 402,
        ),
        type: DioExceptionType.badResponse,
      );
      final err423 = DioException(
        requestOptions: RequestOptions(path: '/pos/checkout'),
        response: Response(
          requestOptions: RequestOptions(path: '/pos/checkout'),
          statusCode: 423,
        ),
        type: DioExceptionType.badResponse,
      );

      expect(ApiClient.extractErrorMessage(err402), contains('Baca-Saja'));
      expect(ApiClient.extractErrorMessage(err423), contains('terkunci'));
    });
  });
}
