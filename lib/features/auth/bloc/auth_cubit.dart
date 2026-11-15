import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../models/auth_session_model.dart';

class AuthState extends Equatable {
  final bool isLoading;
  final bool isAuthenticated;
  final AuthSessionModel session;
  final String? errorMessage;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    required this.session,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    AuthSessionModel? session,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      session: session ?? this.session,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [isLoading, isAuthenticated, session, errorMessage];
}

class AuthCubit extends Cubit<AuthState> {
  final ApiClient _apiClient;
  final OfflineDatabase _offlineDb;
  bool _handlingUnauthorized = false;

  AuthCubit({
    required ApiClient apiClient,
    required OfflineDatabase offlineDb,
  })  : _apiClient = apiClient,
        _offlineDb = offlineDb,
        super(AuthState(
          session: AuthSessionModel.empty(),
        )) {
    _apiClient.onUnauthorized = _handleUnauthorizedSession;
  }

  Future<void> _handleUnauthorizedSession() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      await _apiClient.clearSession();
      await _offlineDb.clearAuthSession();
      if (!isClosed) {
        emit(AuthState(
          isLoading: false,
          isAuthenticated: false,
          session: AuthSessionModel.empty(),
          errorMessage: 'Sesi login telah berakhir atau diperbarui. Silakan masuk kembali.',
        ));
      }
    } finally {
      _handlingUnauthorized = false;
    }
  }

  /// Check existing Bearer token on startup & validate against GET /api/v1/auth/me
  Future<void> checkExistingSession() async {
    final cachedMap = _offlineDb.getCachedAuthSession();
    final cachedSession = cachedMap != null ? AuthSessionModel.fromJson(cachedMap) : null;

    if (cachedSession != null && cachedSession.isLocalTrial) {
      final vertical = cachedSession.activeStore.preferredVerticalRaw;
      if (vertical != null && vertical.isNotEmpty && (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
        await _offlineDb.setSavedBusinessVertical(vertical);
      }
      emit(AuthState(
        isLoading: false,
        isAuthenticated: true,
        session: cachedSession,
      ));
      return;
    }

    final token = await _apiClient.getToken();
    if (token == null || token.isEmpty) {
      await _offlineDb.clearAuthSession();
      emit(AuthState(
        isLoading: false,
        isAuthenticated: false,
        session: AuthSessionModel.empty(),
      ));
      return;
    }

    emit(state.copyWith(
      isLoading: true,
      session: cachedSession ?? state.session,
      errorMessage: null,
    ));

    try {
      final response = await _apiClient.dio.get(ApiEndpoints.me);
      final data = response.data['data'] as Map<String, dynamic>?;
      if (data != null) {
        final session = AuthSessionModel.fromApiData(data);
        await _apiClient.setActiveStoreId(session.activeStore.id);
        if (session.tenantSubdomain.isNotEmpty) {
          await _apiClient.setTenantSlug(session.tenantSubdomain);
        }
        if (session.activeStore.preferredVerticalRaw != null &&
            (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
          await _offlineDb.setSavedBusinessVertical(session.activeStore.preferredVerticalRaw!);
        }
        await _offlineDb.saveAuthSession(session.toJson());
        emit(AuthState(
          isLoading: false,
          isAuthenticated: true,
          session: session,
        ));
        return;
      }
    } catch (e) {
      final isNetworkOffline = e is DioException && e.response == null;
      final statusCode = e is DioException ? e.response?.statusCode : null;

      if (statusCode == 401 || statusCode == 403 || statusCode == 404) {
        await _apiClient.clearSession();
        await _offlineDb.clearAuthSession();
        emit(AuthState(
          isLoading: false,
          isAuthenticated: false,
          session: AuthSessionModel.empty(),
          errorMessage: 'Sesi login tidak valid atau telah kedaluwarsa. Silakan login kembali.',
        ));
        return;
      }

      if (isNetworkOffline && cachedSession != null && cachedSession.userId > 0) {
        emit(AuthState(
          isLoading: false,
          isAuthenticated: true,
          session: cachedSession,
        ));
        return;
      }
    }

    await _apiClient.clearSession();
    await _offlineDb.clearAuthSession();
    emit(AuthState(
      isLoading: false,
      isAuthenticated: false,
      session: AuthSessionModel.empty(),
    ));
  }

  /// Multi-Tenant Login against POST /api/v1/auth/login
  Future<bool> login({
    required String tenantDomain,
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    await _apiClient.setTenantSlug(tenantDomain);

    try {
      final response = await _apiClient.dio.post(
        ApiEndpoints.login,
        data: {
          'tenant_domain': tenantDomain.trim(),
          'email': email.trim(),
          'password': password,
        },
      );

      final body = response.data as Map<String, dynamic>;
      final data = Map<String, dynamic>.from((body['data'] as Map?) ?? {});
      final token = (data['token'] ?? data['access_token'] ?? '').toString();

      if (token.isEmpty) {
        throw Exception('Token otentikasi tidak diterima dari server.');
      }
      await _apiClient.saveToken(token);

      final session = AuthSessionModel.fromApiData(data);
      if (session.tenantSubdomain.isNotEmpty) {
        await _apiClient.setTenantSlug(session.tenantSubdomain);
      }
      await _apiClient.setActiveStoreId(session.activeStore.id);
      if (session.activeStore.preferredVerticalRaw != null &&
          (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
        await _offlineDb.setSavedBusinessVertical(session.activeStore.preferredVerticalRaw!);
      }
      await _offlineDb.saveAuthSession(session.toJson());

      await _offlineDb.saveStoreProfile({
        'name': session.tenantName.isNotEmpty ? session.tenantName : 'NusaCommerce POS',
        'branch': session.activeStore.name,
        'address': (session.activeStore.address ?? '').trim().isNotEmpty ? session.activeStore.address : '-',
        'phone': (session.activeStore.phone ?? '').trim().isNotEmpty ? session.activeStore.phone : '-',
        'receipt_footer':
            'Terima kasih telah berbelanja di ${session.tenantName.isNotEmpty ? session.tenantName : session.activeStore.name}!',
      });

      emit(AuthState(
        isLoading: false,
        isAuthenticated: true,
        session: session,
      ));
      return true;
    } catch (e) {
      final isNetworkOffline = e is DioException && e.response == null;
      emit(state.copyWith(
        isLoading: false,
        isAuthenticated: state.session.isLocalTrial ? state.isAuthenticated : false,
        errorMessage: isNetworkOffline
            ? 'Gagal terhubung ke server Cloud. Periksa koneksi jaringan atau URL Server API.'
            : ApiClient.extractErrorMessage(e),
      ));
      return false;
    }
  }

  /// Day-0 Zero-Barrier Onboarding: Mode Toko Mandiri (100% Lokal & Offline)
  Future<void> startLocalTrialSession({
    required String storeName,
    required String businessVertical,
    double openingCash = 100000,
  }) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    final normalizedVertical = businessVertical.trim().isEmpty
        ? 'retail'
        : businessVertical.trim().toLowerCase();

    final session = AuthSessionModel.createLocalTrialSession(
      storeName: storeName,
      businessVertical: normalizedVertical,
      openingCash: openingCash,
    );

    await _apiClient.setActiveStoreId(session.activeStore.id);
    await _apiClient.setTenantSlug(session.tenantSubdomain);
    await _offlineDb.saveAuthSession(session.toJson());
    await _offlineDb.setSavedBusinessVertical(normalizedVertical);

    await _offlineDb.saveStoreProfile({
      'name': session.tenantName,
      'branch': session.activeStore.name,
      'address': session.activeStore.address ?? 'Mode Toko Mandiri (Offline Lokal)',
      'phone': '-',
      'receipt_footer': 'Terima kasih telah berbelanja di ${session.tenantName}!',
    });

    await _offlineDb.seedVerticalSampleProductsIfEmpty(normalizedVertical);

    if (_offlineDb.getCurrentLocalShift() == null) {
      await _offlineDb.openLocalShift(
        openingCash: openingCash,
        cashierName: session.userName,
        notes: 'Shift Awal Mode Mandiri',
      );
    }

    emit(AuthState(
      isLoading: false,
      isAuthenticated: true,
      session: session,
    ));
  }

  /// Switch active Store Branch (POST /api/v1/auth/switch-store)
  Future<void> switchStoreBranch(StoreBranchModel branch) async {
    await _apiClient.setActiveStoreId(branch.id);
    if (branch.preferredVerticalRaw != null &&
        (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
      await _offlineDb.setSavedBusinessVertical(branch.preferredVerticalRaw!);
    }
    final updatedSession = state.session.copyWith(activeStore: branch);
    await _offlineDb.saveAuthSession(updatedSession.toJson());
    emit(state.copyWith(
      session: updatedSession,
    ));

    try {
      final res = await _apiClient.dio.post(
        ApiEndpoints.switchStore,
        data: {'store_id': branch.id},
      );
      final data = res.data['data'] as Map<String, dynamic>?;
      final newToken = data?['token']?.toString();
      if (newToken != null && newToken.isNotEmpty) {
        await _apiClient.saveToken(newToken);
      }
      if (data?['entitlements'] is Map) {
        final ent = Map<String, dynamic>.from(data!['entitlements'] as Map);
        final refreshed = AuthSessionModel.fromApiData({
          'user': {
            'id': updatedSession.userId,
            'name': updatedSession.userName,
            'email': updatedSession.userEmail,
            'roles': [updatedSession.userRole],
            'is_owner': updatedSession.isOwner,
          },
          'tenant': {
            'name': updatedSession.tenantName,
            'subdomain': updatedSession.tenantSubdomain,
            'plan_name': updatedSession.planName,
          },
          'entitlements': ent,
          'active_store': (data['active_store'] as Map?) ?? updatedSession.activeStore.toJson(),
          'available_stores': updatedSession.availableStores.map((s) => s.toJson()).toList(),
          'permissions': data['permissions'] ?? updatedSession.permissions,
        });
        await _offlineDb.saveAuthSession(refreshed.toJson());
        emit(state.copyWith(session: refreshed));
      }
    } catch (_) {
      // Offline store switch handled locally
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.dio.post(ApiEndpoints.logout);
    } catch (_) {}
    await _apiClient.clearSession();
    await _offlineDb.clearAuthSession();
    emit(AuthState(
      isLoading: false,
      isAuthenticated: false,
      session: AuthSessionModel.empty(),
    ));
  }
}
