import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../constants/api_endpoints.dart';
import '../api_client.dart';

/// Domain Repository for Restaurant Floor Tables (Open, Transfer, Merge) & KDS Kitchen Queue.
class RestaurantTableRepository {
  final ApiClient _apiClient;

  const RestaurantTableRepository(this._apiClient);

  factory RestaurantTableRepository.resolve([ApiClient? apiClient]) {
    if (apiClient == null && GetIt.instance.isRegistered<RestaurantTableRepository>()) {
      return GetIt.instance<RestaurantTableRepository>();
    }
    return RestaurantTableRepository(apiClient ?? GetIt.instance<ApiClient>());
  }

  Future<List<Map<String, dynamic>>> getTables() async {
    final res = await _apiClient.dio.get(ApiEndpoints.restaurantTables);
    final raw = (res.data is Map ? res.data['data'] : null) as List<dynamic>? ?? const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Response<dynamic>> openTable(int tableId, {int pax = 2, String? customerName}) {
    return _apiClient.dio.post(
      ApiEndpoints.openTable(tableId),
      data: {
        'pax': pax,
        if (customerName != null && customerName.trim().isNotEmpty)
          'customer_name': customerName.trim(),
      },
    );
  }

  Future<Response<dynamic>> transferTable(int sourceTableId, int destinationTableId) {
    return _apiClient.dio.post(
      ApiEndpoints.transferTable(sourceTableId),
      data: {'destination_table_id': destinationTableId},
    );
  }

  Future<Response<dynamic>> mergeTables({
    required int targetTableId,
    required List<int> sourceTableIds,
  }) {
    return _apiClient.dio.post(
      '/pos/tables/$targetTableId/merge',
      data: {'source_table_ids': sourceTableIds},
    );
  }

  Future<List<Map<String, dynamic>>> getKdsQueue({String? station}) async {
    final res = await _apiClient.dio.get(
      ApiEndpoints.kdsQueue,
      queryParameters: (station != null && station.isNotEmpty && station != 'all')
          ? {'station': station}
          : null,
    );
    final raw = (res.data is Map ? res.data['data'] : null) as List<dynamic>? ?? const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Response<dynamic>> updateKdsStatus(int saleId, String nextStatus) {
    return _apiClient.dio.post(
      ApiEndpoints.updateKdsStatus(saleId),
      data: {'kitchen_status': nextStatus},
    );
  }
}
