import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../constants/api_endpoints.dart';
import '../api_client.dart';

/// Domain Repository for Catalog, Inventory, Stock Opname, and Inter-Branch Stock Transfers.
class ProductRepository {
  final ApiClient _apiClient;

  const ProductRepository(this._apiClient);

  factory ProductRepository.resolve([ApiClient? apiClient]) {
    if (apiClient == null && GetIt.instance.isRegistered<ProductRepository>()) {
      return GetIt.instance<ProductRepository>();
    }
    return ProductRepository(apiClient ?? GetIt.instance<ApiClient>());
  }

  Future<Response<dynamic>> fetchProducts({Map<String, dynamic>? queryParameters}) {
    return _apiClient.dio.get(ApiEndpoints.products, queryParameters: queryParameters);
  }

  Future<Response<dynamic>> fetchCategories() {
    return _apiClient.dio.get(ApiEndpoints.categories);
  }

  Future<Response<dynamic>> fetchBrands() {
    return _apiClient.dio.get(ApiEndpoints.brands);
  }

  Future<Response<dynamic>> fetchUnits() {
    return _apiClient.dio.get(ApiEndpoints.units);
  }

  Future<Response<dynamic>> fetchWarehouseStock(int productId, {int? variantId}) {
    return _apiClient.dio.get(
      ApiEndpoints.posWarehouseStock,
      queryParameters: {
        'product_id': productId,
        if (variantId != null && variantId > 0) 'variant_id': variantId,
      },
    );
  }

  Future<Response<dynamic>> fetchInventoryCollection(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _apiClient.dio.get(path, queryParameters: queryParameters);
  }

  Future<Response<dynamic>> submitStockTake(Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.stockTakes, data: payload);
  }

  Future<Response<dynamic>> submitStockTransfer(Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.stockTransfers, data: payload);
  }

  Future<Response<dynamic>> receiveStockTransfer(int transferId) {
    return _apiClient.dio.post(ApiEndpoints.receiveStockTransfer(transferId));
  }
}
