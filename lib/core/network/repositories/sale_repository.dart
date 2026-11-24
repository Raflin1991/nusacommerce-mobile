import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../constants/api_endpoints.dart';
import '../api_client.dart';

/// Domain Repository for POS Sales, Checkout, Quotations, Online Orders, and Supervisor PINs.
class SaleRepository {
  final ApiClient _apiClient;

  const SaleRepository(this._apiClient);

  factory SaleRepository.resolve([ApiClient? apiClient]) {
    if (apiClient == null && GetIt.instance.isRegistered<SaleRepository>()) {
      return GetIt.instance<SaleRepository>();
    }
    return SaleRepository(apiClient ?? GetIt.instance<ApiClient>());
  }

  Future<Response<dynamic>> fetchOnlineOrders({String statusFilter = 'all'}) {
    return _apiClient.dio.get(
      ApiEndpoints.onlineOrders,
      queryParameters: statusFilter == 'all' ? null : {'online_order_status': statusFilter},
    );
  }

  Future<Response<dynamic>> fetchOnlineOrdersWithParams(Map<String, dynamic> params) {
    return _apiClient.dio.get(ApiEndpoints.onlineOrders, queryParameters: params);
  }

  Future<Response<dynamic>> updateOnlineOrderStatus(
    int orderId,
    Map<String, dynamic> payload,
  ) {
    return _apiClient.dio.post(ApiEndpoints.updateOnlineOrderStatus(orderId), data: payload);
  }

  Future<Response<dynamic>> fetchQuotations() {
    return _apiClient.dio.get(ApiEndpoints.quotations);
  }

  Future<Response<dynamic>> createQuotation(Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.quotations, data: payload);
  }

  Future<Response<dynamic>> verifySupervisorPin(String pin, {String? action}) {
    return _apiClient.dio.post(
      ApiEndpoints.verifyPin,
      data: {
        'pin': pin,
        if (action != null && action.isNotEmpty) 'action': action,
      },
    );
  }
}
