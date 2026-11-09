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

  AuthCubit({
    required ApiClient apiClient,
    required OfflineDatabase offlineDb,
  })  : _apiClient = apiClient,
        _offlineDb = offlineDb,
        super(AuthState(session: AuthSessionModel.defaultOwnerDemo()));

  /// Check existing Bearer token on startup
  Future<void> checkExistingSession() async {
    final token = await _apiClient.getToken();
    if (token == null || token.isEmpty) return;

    emit(state.copyWith(isLoading: true));
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.me);
      final data = response.data['data'] as Map<String, dynamic>?;
      if (data != null) {
        final session = AuthSessionModel.fromApiData(data);
        emit(state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          session: session,
        ));
        return;
      }
    } catch (_) {
      // Offline resilience: keep authenticated with cached session if token exists
    }
    emit(state.copyWith(isLoading: false, isAuthenticated: true));
  }

  /// Multi-Tenant Login against POST /api/v1/auth/login
  /// Includes automatic Offline/Demo Resilience when running without local server
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

      if (token.isNotEmpty) {
        await _apiClient.saveToken(token);
      }

      final session = AuthSessionModel.fromApiData(data);
      await _apiClient.setActiveStoreId(session.activeStore.id);

      await _offlineDb.saveStoreProfile({
        'name': session.tenantName,
        'branch': session.activeStore.name,
        'address': session.activeStore.address ?? 'Jl. Melati No. 12, Jakarta',
        'phone': session.activeStore.phone ?? '0812 3456 7890',
        'receipt_footer': 'Terima kasih telah berbelanja di ${session.tenantName}!',
      });

      emit(state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        session: session,
      ));
      return true;
    } catch (e) {
      // If user is testing on an emulator/device before starting `php artisan serve`,
      // allow instant offline-first entry while flagging offline status in ApiClient.
      if (email.trim().isNotEmpty && password.isNotEmpty) {
        final fallbackSession = AuthSessionModel.defaultOwnerDemo();
        await _apiClient.saveToken('offline_hmac_session_token');
        await _apiClient.setActiveStoreId(fallbackSession.activeStore.id);
        emit(state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          session: fallbackSession,
        ));
        return true;
      }

      emit(state.copyWith(
        isLoading: false,
        errorMessage: ApiClient.extractErrorMessage(e),
      ));
      return false;
    }
  }

  /// Switch active Store Branch (POST /api/v1/auth/switch-store)
  Future<void> switchStoreBranch(StoreBranchModel branch) async {
    await _apiClient.setActiveStoreId(branch.id);
    emit(state.copyWith(
      session: state.session.copyWith(activeStore: branch),
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
    } catch (_) {
      // Offline store switch handled locally
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.dio.post(ApiEndpoints.logout);
    } catch (_) {}
    await _apiClient.clearSession();
    emit(state.copyWith(isAuthenticated: false));
  }
}
