import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '../../constants/api_endpoints.dart';
import '../api_client.dart';

/// Domain Repository for Backoffice Operations: Shifts, Debt Book (AR/AP/Expenses),
/// Purchasing/GRN/Returns, Cash Ledger, Owner Approvals, HR Attendance, Reports & Copilot.
class BackofficeRepository {
  final ApiClient _apiClient;

  const BackofficeRepository(this._apiClient);

  factory BackofficeRepository.resolve([ApiClient? apiClient]) {
    if (apiClient == null && GetIt.instance.isRegistered<BackofficeRepository>()) {
      return GetIt.instance<BackofficeRepository>();
    }
    return BackofficeRepository(apiClient ?? GetIt.instance<ApiClient>());
  }

  // Generic safe GET/POST delegators for dynamic dashboard endpoints
  Future<Response<dynamic>> getEndpoint(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _apiClient.dio.get(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<dynamic>> postEndpoint(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _apiClient.dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<dynamic>> putEndpoint(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _apiClient.dio.put(path, data: data, options: options);
  }

  Future<Response<dynamic>> deleteEndpoint(
    String path, {
    dynamic data,
    Options? options,
  }) {
    return _apiClient.dio.delete(path, data: data, options: options);
  }

  // Approvals
  Future<Response<dynamic>> fetchApprovals(Map<String, dynamic> params) {
    return _apiClient.dio.get(ApiEndpoints.approvals, queryParameters: params);
  }

  Future<Response<dynamic>> decideApproval(int id, Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.decideApproval(id), data: payload);
  }

  // Cash Ledger
  Future<Response<dynamic>> fetchCashLedger({required String channel}) {
    return _apiClient.dio.get(ApiEndpoints.cashLedger, queryParameters: {'channel': channel});
  }

  Future<Response<dynamic>> recordCashLedgerEntry(Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.cashLedger, data: payload);
  }

  // Customers & Debt Book (AR / AP / Expenses)
  Future<Response<dynamic>> fetchReceivables() => _apiClient.dio.get(ApiEndpoints.receivables);
  Future<Response<dynamic>> fetchPayables() => _apiClient.dio.get(ApiEndpoints.payables);
  Future<Response<dynamic>> fetchExpenses() => _apiClient.dio.get(ApiEndpoints.expenses);
  Future<Response<dynamic>> fetchPaymentMethods() =>
      _apiClient.dio.get(ApiEndpoints.paymentMethods);

  Future<Response<dynamic>> payReceivable(
    int saleId,
    Map<String, dynamic> payload, {
    Options? options,
  }) {
    return _apiClient.dio.post(ApiEndpoints.payReceivable(saleId), data: payload, options: options);
  }

  Future<Response<dynamic>> payPayable(
    int purchaseId,
    Map<String, dynamic> payload, {
    Options? options,
  }) {
    return _apiClient.dio.post(
      ApiEndpoints.payPayable(purchaseId),
      data: payload,
      options: options,
    );
  }

  Future<Response<dynamic>> createExpense(Map<String, dynamic> payload, {Options? options}) {
    return _apiClient.dio.post(ApiEndpoints.expenses, data: payload, options: options);
  }

  Future<Response<dynamic>> updateExpense(int id, Map<String, dynamic> payload) {
    return _apiClient.dio.put(ApiEndpoints.expenseDetail(id), data: payload);
  }

  Future<Response<dynamic>> deleteExpense(int id) {
    return _apiClient.dio.delete(ApiEndpoints.expenseDetail(id));
  }

  Future<Response<dynamic>> fetchCustomerStatement(int customerId) {
    return _apiClient.dio.get(ApiEndpoints.customerStatement(customerId));
  }

  Future<Response<dynamic>> topupCustomerStoreCredit(
    int customerId,
    Map<String, dynamic> payload,
  ) {
    return _apiClient.dio.post(ApiEndpoints.customerStoreCreditTopup(customerId), data: payload);
  }

  // HR Attendance
  Future<List<Response<dynamic>>> fetchHrSummaryAndEmployees(Map<String, dynamic> params) {
    return Future.wait([
      _apiClient.dio.get(ApiEndpoints.hrSummary, queryParameters: params),
      _apiClient.dio.get(ApiEndpoints.hrEmployees, queryParameters: params),
    ]);
  }

  Future<Response<dynamic>> submitHrClock(Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.hrClock, data: payload);
  }

  // Purchases, GRN & Purchase Returns
  Future<Response<dynamic>> fetchPurchases() => _apiClient.dio.get(ApiEndpoints.purchases);
  Future<Response<dynamic>> fetchPurchaseReturns() =>
      _apiClient.dio.get(ApiEndpoints.purchaseReturns);
  Future<Response<dynamic>> fetchPurchaseAiReorder() =>
      _apiClient.dio.get(ApiEndpoints.purchaseAiReorder);

  Future<Response<dynamic>> createPurchase(Map<String, dynamic> payload, {Options? options}) {
    return _apiClient.dio.post(ApiEndpoints.purchases, data: payload, options: options);
  }

  Future<Response<dynamic>> receivePurchase(
    int purchaseId,
    Map<String, dynamic> payload, {
    Options? options,
  }) {
    return _apiClient.dio.post(
      ApiEndpoints.receivePurchase(purchaseId),
      data: payload,
      options: options,
    );
  }

  Future<Response<dynamic>> createPurchaseReturn(
    Map<String, dynamic> payload, {
    Options? options,
  }) {
    return _apiClient.dio.post(ApiEndpoints.purchaseReturns, data: payload, options: options);
  }

  // Shifts
  Future<Response<dynamic>> fetchCurrentShift() => _apiClient.dio.get(ApiEndpoints.currentShift);

  Future<Response<dynamic>> openShift(Map<String, dynamic> payload, {Options? options}) {
    return _apiClient.dio.post(ApiEndpoints.openShift, data: payload, options: options);
  }

  Future<Response<dynamic>> closeShift(Map<String, dynamic> payload, {Options? options}) {
    return _apiClient.dio.post(ApiEndpoints.closeShift, data: payload, options: options);
  }

  Future<Response<dynamic>> addShiftCashEntry(Map<String, dynamic> payload, {Options? options}) {
    return _apiClient.dio.post(ApiEndpoints.cashEntry, data: payload, options: options);
  }

  // Reports & Copilot
  Future<Response<dynamic>> fetchOwnerDashboard(Map<String, dynamic> params) {
    return _apiClient.dio.get(ApiEndpoints.ownerDashboard, queryParameters: params);
  }

  Future<Response<dynamic>> fetchSalesSummary(Map<String, dynamic> params) {
    return _apiClient.dio.get(ApiEndpoints.salesSummary, queryParameters: params);
  }

  Future<Response<dynamic>> fetchReportCatalog() {
    return _apiClient.dio.get(ApiEndpoints.reportCatalog);
  }

  Future<Response<dynamic>> sendCopilotMessage(Map<String, dynamic> payload) {
    return _apiClient.dio.post(ApiEndpoints.copilotChat, data: payload);
  }
}
