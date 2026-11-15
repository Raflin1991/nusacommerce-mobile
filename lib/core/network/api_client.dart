import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  String? _cachedToken;
  VoidCallback? onUnauthorized;

  ApiClient({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs {
    final storedToken = _prefs.getString(_keyToken);
    if (_isValidTokenFormat(storedToken)) {
      _cachedToken = storedToken;
    } else if (storedToken != null && storedToken.isNotEmpty) {
      _cachedToken = null;
      _prefs.remove(_keyToken);
    }

    var savedUrl = _prefs.getString(_keyBaseUrl);
    if (kIsWeb) {
      if (savedUrl == null || savedUrl.contains('10.0.2.2')) {
        savedUrl = ApiEndpoints.laragonDomainUrl;
      }
    } else {
      savedUrl ??= ApiEndpoints.defaultBaseUrl;
    }

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
          // Jangan pernah melakukan auto-logout / memicu "Sesi login telah berakhir"
          // pada background request atau saat mode lokal mandiri aktif.
          handler.next(e);
        },
      ),
    );
  }

  static bool _isValidTokenFormat(String? token) {
    if (token == null || token.isEmpty || token.startsWith('offline_')) {
      return false;
    }
    final parts = token.split('.');
    return parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty;
  }

  String get baseUrl => dio.options.baseUrl;

  Future<void> setBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    dio.options.baseUrl = cleaned;
    await _prefs.setString(_keyBaseUrl, cleaned);
  }

  /// Normalizes product/catalog image URLs so they work on BOTH:
  /// - Android APK (10.0.2.2 / LAN IP / HTTPS production — never fails on `.test` DNS)
  /// - Flutter Web (routes `/storage/...` through CORS-safe `/api/v1/media/...`)
  String? resolveMediaUrl(String? rawUrl) {
    final trimmed = rawUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final origin = baseUrl.replaceFirst(RegExp(r'/api(/v\d+)?/?$'), '');
    final lower = trimmed.toLowerCase();

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null) return trimmed;

      final path = parsed.path;
      if (path.startsWith('/storage/')) {
        final rel = path.substring('/storage/'.length);
        return '$origin/api/v1/media/$rel';
      }

      if (path.startsWith('/api/v1/media/')) {
        final h = parsed.host.toLowerCase();
        final originUri = Uri.tryParse(origin);
        final isLocalAlias = h.endsWith('.test') ||
            h == 'localhost' ||
            h == '127.0.0.1' ||
            h == '10.0.2.2';
        if (isLocalAlias && originUri != null && originUri.host != parsed.host) {
          return '$origin$path';
        }
        return trimmed;
      }

      return trimmed;
    }

    final rel = trimmed.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    if (rel.startsWith('api/v1/media/')) {
      return '$origin/$rel';
    }
    if (rel.startsWith('storage/')) {
      return '$origin/api/v1/media/${rel.substring('storage/'.length)}';
    }
    return '$origin/api/v1/media/$rel';
  }

  Future<void> saveToken(String token) async {
    if (!_isValidTokenFormat(token)) {
      await clearSession();
      return;
    }
    _cachedToken = token;
    await _prefs.setString(_keyToken, token);
    try {
      await _secureStorage.write(key: _keyToken, value: token);
    } catch (_) {
      // Safe fallback when WebCrypto / secure storage is unavailable in browser contexts
    }
  }

  Future<String?> getToken() async {
    if (_isValidTokenFormat(_cachedToken)) {
      return _cachedToken;
    }

    final prefToken = _prefs.getString(_keyToken);
    if (_isValidTokenFormat(prefToken)) {
      _cachedToken = prefToken;
      return prefToken;
    } else if (prefToken != null && prefToken.isNotEmpty) {
      await _prefs.remove(_keyToken);
    }

    try {
      final secToken = await _secureStorage.read(key: _keyToken);
      if (_isValidTokenFormat(secToken)) {
        _cachedToken = secToken;
        await _prefs.setString(_keyToken, secToken!);
        return secToken;
      } else if (secToken != null && secToken.isNotEmpty) {
        await _secureStorage.delete(key: _keyToken);
      }
    } catch (_) {
      // Safe fallback when secure storage read/decrypt fails (e.g. WebCrypto mismatch)
    }

    _cachedToken = null;
    return null;
  }

  Future<void> clearSession() async {
    _cachedToken = null;
    await _prefs.remove(_keyToken);
    try {
      await _secureStorage.delete(key: _keyToken);
    } catch (_) {}
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
