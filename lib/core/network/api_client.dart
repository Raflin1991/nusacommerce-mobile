import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_endpoints.dart';

class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  static const String _keyToken = 'nusa_mobile_bearer_token';
  static const String _keyTenantSlug = 'nusa_mobile_tenant_slug';
  static const String _keyStoreId = 'nusa_mobile_active_store_id';
  static const String _keyBaseUrl = 'nusa_mobile_base_url';

  bool isOnline = true;

  ApiClient({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs {
    final savedUrl = _prefs.getString(_keyBaseUrl) ?? ApiEndpoints.defaultBaseUrl;

    dio = Dio(
      BaseOptions(
        baseUrl: savedUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          final tenantSlug = getTenantSlug();
          if (tenantSlug != null && tenantSlug.isNotEmpty) {
            options.headers['X-Tenant-Slug'] = tenantSlug;
            options.headers['X-Tenant-Domain'] = tenantSlug;
          }
          final storeId = getActiveStoreId();
          if (storeId != null) {
            options.headers['X-Store-Id'] = storeId.toString();
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          isOnline = true;
          handler.next(response);
        },
        onError: (DioException e, handler) {
          if (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout) {
            isOnline = false;
          }
          handler.next(e);
        },
      ),
    );
  }

  String get baseUrl => dio.options.baseUrl;

  Future<void> setBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    dio.options.baseUrl = cleaned;
    await _prefs.setString(_keyBaseUrl, cleaned);
  }

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _keyToken, value: token);
  }

  Future<String?> getToken() async {
    return _secureStorage.read(key: _keyToken);
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: _keyToken);
    await _prefs.remove(_keyTenantSlug);
    await _prefs.remove(_keyStoreId);
  }

  Future<void> setTenantSlug(String slug) async {
    await _prefs.setString(_keyTenantSlug, slug.trim().toLowerCase());
  }

  String? getTenantSlug() => _prefs.getString(_keyTenantSlug);

  Future<void> setActiveStoreId(int storeId) async {
    await _prefs.setInt(_keyStoreId, storeId);
  }

  int? getActiveStoreId() => _prefs.getInt(_keyStoreId);

  /// Extract user-friendly Indonesian error message from DioException
  static String extractErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        if (data['message'] != null) {
          return data['message'].toString();
        }
        if (data['errors'] is Map) {
          final firstErr = (data['errors'] as Map).values.first;
          if (firstErr is List && firstErr.isNotEmpty) {
            return firstErr.first.toString();
          }
        }
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Tidak dapat terhubung ke server Cloud. Mode Offline-First aktif.';
      }
      return 'Terjadi kesalahan jaringan (${error.response?.statusCode ?? 'Timeout'}).';
    }
    return error.toString();
  }
}
