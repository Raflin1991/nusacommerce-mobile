import 'dart:async';
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
  final int sessionRevision;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    required this.session,
    this.errorMessage,
    this.sessionRevision = 0,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    AuthSessionModel? session,
    String? errorMessage,
    int? sessionRevision,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      session: session ?? this.session,
      errorMessage: errorMessage,
      sessionRevision: sessionRevision ?? this.sessionRevision,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isAuthenticated,
        session,
        errorMessage,
        sessionRevision,
      ];
}

class AuthCubit extends Cubit<AuthState> {
  final ApiClient _apiClient;
  final OfflineDatabase _offlineDb;

  AuthCubit({
    required ApiClient apiClient,
    required OfflineDatabase offlineDb,
  })  : _apiClient = apiClient,
        _offlineDb = offlineDb,
        super(AuthState(
          session: AuthSessionModel.empty(),
        ));

  /// Check existing session on startup without ever forcing auto-logout on transient/expired responses.
  /// When [awaitRemoteRefresh] is `false` and a valid cached session exists, emits immediately
  /// (zero offline cold-start freeze) and refreshes `/auth/me` silently in the background.
  Future<void> checkExistingSession({bool awaitRemoteRefresh = true}) async {
    final cachedMap = _offlineDb.getCachedAuthSession();
    final cachedSession = cachedMap != null ? AuthSessionModel.fromJson(cachedMap) : null;

    if (cachedSession != null && cachedSession.isLocalTrial) {
      final vertical = cachedSession.activeStore.preferredVerticalRaw ??
          _offlineDb.getSavedBusinessVertical() ??
          'retail';
      final normalizedVertical = vertical.trim().isEmpty ? 'retail' : vertical.trim().toLowerCase();
      await _offlineDb.ensureTenantIsolation('local-trial:$normalizedVertical');
      if ((_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
        await _offlineDb.setSavedBusinessVertical(normalizedVertical);
      }
      await _offlineDb.seedVerticalSampleProductsIfEmpty(normalizedVertical);
      emit(AuthState(
        isLoading: false,
        isAuthenticated: true,
        session: cachedSession,
        sessionRevision: state.sessionRevision,
      ));
      return;
    }

    if (cachedSession != null && cachedSession.tenantSubdomain.isNotEmpty) {
      await _offlineDb.ensureTenantIsolation('cloud:${cachedSession.tenantSubdomain.toLowerCase()}');
    }

    final token = await _apiClient.getToken();
    if (token == null || token.isEmpty) {
      if (cachedSession != null && cachedSession.userId > 0) {
        emit(AuthState(
          isLoading: false,
          isAuthenticated: true,
          session: cachedSession,
          sessionRevision: state.sessionRevision,
        ));
        return;
      }
      await _offlineDb.clearAuthSession();
      emit(AuthState(
        isLoading: false,
        isAuthenticated: false,
        session: AuthSessionModel.empty(),
        sessionRevision: state.sessionRevision,
      ));
      return;
    }

    if (cachedSession != null && cachedSession.userId > 0) {
      emit(AuthState(
        isLoading: false,
        isAuthenticated: true,
        session: cachedSession,
        sessionRevision: state.sessionRevision,
      ));
      if (!awaitRemoteRefresh) {
        unawaited(_refreshSessionFromCloudSilently());
        return;
      }
    } else {
      emit(state.copyWith(
        isLoading: true,
        session: state.session,
        errorMessage: null,
      ));
    }

    final refreshed = await _refreshSessionFromCloudSilently();
    if (refreshed) return;

    if (cachedSession != null && cachedSession.userId > 0) {
      emit(AuthState(
        isLoading: false,
        isAuthenticated: true,
        session: cachedSession,
        sessionRevision: state.sessionRevision,
      ));
      return;
    }

    emit(AuthState(
      isLoading: false,
      isAuthenticated: false,
      session: AuthSessionModel.empty(),
      sessionRevision: state.sessionRevision,
    ));
  }

  Future<bool> _refreshSessionFromCloudSilently() async {
    try {
      final response = await _apiClient.dio.get(ApiEndpoints.me);
      final data = response.data['data'] as Map<String, dynamic>?;
      if (data != null) {
        final session = AuthSessionModel.fromApiData(data);
        if (session.tenantSubdomain.isNotEmpty) {
          await _offlineDb.ensureTenantIsolation('cloud:${session.tenantSubdomain.toLowerCase()}');
          await _apiClient.setTenantSlug(session.tenantSubdomain);
        }
        await _apiClient.setActiveStoreId(session.activeStore.id);
        if (session.activeStore.preferredVerticalRaw != null &&
            (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
          await _offlineDb.setSavedBusinessVertical(session.activeStore.preferredVerticalRaw!);
        }
        await _offlineDb.saveAuthSession(session.toJson());
        if (data['numbering_formats'] is Map) {
          await _offlineDb.cacheNumberingFormats(
            Map<String, dynamic>.from(data['numbering_formats'] as Map),
          );
        }
        await _persistStoreProfileFromSession(session);
        if (!isClosed) {
          emit(AuthState(
            isLoading: false,
            isAuthenticated: true,
            session: session,
            sessionRevision: state.sessionRevision,
          ));
        }
        return true;
      }
    } catch (_) {
      // Jangan pernah paksa logout ("Sesi login telah berakhir") saat refresh background gagal.
      // Pertahankan sesi aktif di perangkat hingga pengguna menekan Keluar Sesi (Logout).
    }
    return false;
  }

  Future<void> _persistStoreProfileFromSession(AuthSessionModel session) async {
    final existing = _offlineDb.getStoreProfile();
    await _offlineDb.saveStoreProfile({
      ...existing,
      'name': session.tenantName.isNotEmpty ? session.tenantName : 'OXO.ID POS',
      'code': session.activeStore.code.isNotEmpty ? session.activeStore.code : 'MAIN',
      'branch': session.activeStore.name,
      'address': (session.activeStore.address ?? '').trim().isNotEmpty
          ? session.activeStore.address
          : (existing['address'] ?? '-'),
      'phone': (session.activeStore.phone ?? '').trim().isNotEmpty
          ? session.activeStore.phone
          : (existing['phone'] ?? '-'),
      'paper_size': existing['paper_size'] ?? '58mm',
      'receipt_footer':
          'Terima kasih telah berbelanja di ${session.tenantName.isNotEmpty ? session.tenantName : session.activeStore.name}!',
    });
  }

  /// Multi-Tenant Login against POST /api/v1/auth/login
  Future<bool> login({
    required String tenantDomain,
    required String email,
    required String password,
    bool preserveLocalForMigration = false,
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
      final targetSubdomain = session.tenantSubdomain.isNotEmpty
          ? session.tenantSubdomain.toLowerCase()
          : tenantDomain.trim().toLowerCase();
      final targetIdentity = 'cloud:$targetSubdomain';
      if (!preserveLocalForMigration) {
        final switchingFromTrial = state.session.isLocalTrial;
        final switchingCloudTenant = state.session.tenantSubdomain.isNotEmpty &&
            state.session.tenantSubdomain.toLowerCase() != targetSubdomain;
        await _offlineDb.ensureTenantIsolation(
          targetIdentity,
          forceClear: switchingFromTrial || switchingCloudTenant,
        );
      } else {
        await _offlineDb.setActiveTenantIdentity(targetIdentity);
      }

      if (session.tenantSubdomain.isNotEmpty) {
        await _apiClient.setTenantSlug(session.tenantSubdomain);
      }
      await _apiClient.setActiveStoreId(session.activeStore.id);
      if (session.activeStore.preferredVerticalRaw != null &&
          (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
        await _offlineDb.setSavedBusinessVertical(session.activeStore.preferredVerticalRaw!);
      }
      await _offlineDb.saveAuthSession(session.toJson());
      if (data['numbering_formats'] is Map) {
        await _offlineDb.cacheNumberingFormats(
          Map<String, dynamic>.from(data['numbering_formats'] as Map),
        );
      }

      await _persistStoreProfileFromSession(session);

      emit(AuthState(
        isLoading: false,
        isAuthenticated: true,
        session: session,
        sessionRevision: state.sessionRevision + 1,
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

    // Purge any stale Cloud Bearer token and isolate local cache completely
    await _apiClient.clearSession();

    final normalizedVertical = businessVertical.trim().isEmpty
        ? 'retail'
        : businessVertical.trim().toLowerCase();

    await _offlineDb.ensureTenantIsolation(
      'local-trial:$normalizedVertical',
      forceClear: true,
    );

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
      'code': session.activeStore.code.isNotEmpty ? session.activeStore.code : 'TRIAL',
      'branch': session.activeStore.name,
      'address': session.activeStore.address ?? 'Mode Toko Mandiri (Offline Lokal)',
      'phone': '-',
      'paper_size': '58mm',
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
      sessionRevision: state.sessionRevision + 1,
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
    await _persistStoreProfileFromSession(updatedSession);
    emit(state.copyWith(
      session: updatedSession,
      sessionRevision: state.sessionRevision + 1,
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
      if (data != null) {
        final nextStore = data['active_store'] is Map
            ? StoreBranchModel.fromJson(Map<String, dynamic>.from(data['active_store'] as Map))
            : updatedSession.activeStore;
        final nextPermissions = (data['permissions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            updatedSession.permissions;

        final AuthSessionModel refreshed;
        if (data['entitlements'] is Map) {
          final ent = Map<String, dynamic>.from(data['entitlements'] as Map);
          refreshed = AuthSessionModel.fromApiData({
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
            'active_store': nextStore.toJson(),
            'available_stores': updatedSession.availableStores.map((s) => s.toJson()).toList(),
            'permissions': nextPermissions,
          });
        } else {
          refreshed = updatedSession.copyWith(
            activeStore: nextStore,
            permissions: nextPermissions,
          );
        }

        await _offlineDb.saveAuthSession(refreshed.toJson());
        await _persistStoreProfileFromSession(refreshed);
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
    await _offlineDb.clearTenantCache();
    await _offlineDb.clearAuthSession();
    emit(AuthState(
      isLoading: false,
      isAuthenticated: false,
      session: AuthSessionModel.empty(),
    ));
  }
}
