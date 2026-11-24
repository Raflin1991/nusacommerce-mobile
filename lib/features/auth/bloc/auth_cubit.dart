import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/secure_license_vault.dart';
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
  final SecureLicenseVault _licenseVault;

  AuthCubit({
    required ApiClient apiClient,
    required OfflineDatabase offlineDb,
    SecureLicenseVault? licenseVault,
  })  : _apiClient = apiClient,
        _offlineDb = offlineDb,
        _licenseVault = licenseVault ??
            SecureLicenseVault(
              secureStorage: apiClient.secureStorage,
              prefs: offlineDb.prefs,
            ),
        super(AuthState(
          session: AuthSessionModel.empty(),
        ));

  OfflineDatabase get offlineDb => _offlineDb;
  SecureLicenseVault get licenseVault => _licenseVault;

  bool get hasStandalonePin {
    final profile = _offlineDb.getSavedStoreProfile();
    final hash = (profile?['cashier_pin_hash'] ?? '').toString().trim();
    return hash.isNotEmpty;
  }

  static String _hashPin(String pin) {
    // Legacy domain salt retained unchanged so stored offline PIN hashes remain valid across OXORA upgrade.
    final digest = SecureLicenseVault.sha256(
      Uint8List.fromList(utf8.encode('OXO.ID::OFFLINE_PIN::${pin.trim()}')),
    );
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Configure or remove optional 4-6 digit Offline Cashier PIN stored as SHA-256 hash.
  Future<void> setStandaloneCashierPin(String? pin) async {
    final existing = _offlineDb.getStoreProfile();
    final cleaned = (pin ?? '').trim();
    if (cleaned.isEmpty) {
      existing.remove('cashier_pin_hash');
    } else {
      existing['cashier_pin_hash'] = _hashPin(cleaned);
    }
    await _offlineDb.saveStoreProfile(existing);
  }

  /// Check existing session on startup without ever forcing auto-logout on transient/expired responses.
  /// Enforces cryptographic PRO/Enterprise entitlement verification via [SecureLicenseVault].
  Future<void> checkExistingSession({bool awaitRemoteRefresh = true}) async {
    final cachedMap = _offlineDb.getCachedAuthSession();
    AuthSessionModel? cachedSession =
        cachedMap != null ? AuthSessionModel.fromJson(cachedMap) : null;

    if (cachedSession != null) {
      final verified = await _licenseVault.verifyAndEnforce(cachedSession);
      cachedSession = verified.session;
      if (verified.tampered) {
        await _offlineDb.saveAuthSession(cachedSession.toJson());
      }
    }

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
        await _licenseVault.sealSessionEntitlements(session);
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
      'is_standalone': session.isLocalTrial,
      'name': session.tenantName.isNotEmpty ? session.tenantName : 'OXORA POS',
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
      await _licenseVault.sealSessionEntitlements(session);
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
    String? cashierPin,
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
    await _licenseVault.sealSessionEntitlements(session);
    await _offlineDb.saveAuthSession(session.toJson());
    await _offlineDb.setSavedBusinessVertical(normalizedVertical);

    final cleanPin = (cashierPin ?? '').trim();
    await _offlineDb.saveStoreProfile({
      'is_standalone': true,
      'business_vertical': normalizedVertical,
      'name': session.tenantName,
      'code': session.activeStore.code.isNotEmpty ? session.activeStore.code : 'TRIAL',
      'branch': session.activeStore.name,
      'address': session.activeStore.address ?? 'Mode Toko Mandiri (Offline Lokal)',
      'phone': '-',
      'paper_size': '58mm',
      'receipt_footer': 'Terima kasih telah berbelanja di ${session.tenantName}!',
      if (cleanPin.isNotEmpty) 'cashier_pin_hash': _hashPin(cleanPin),
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

  /// Bug 1 Fix: Resume an already-configured Offline Mandiri store after logout
  /// WITHOUT wiping SQLite products, customers, held bills, shifts, or sales history!
  Future<bool> resumeLocalTrialSession({String? pin}) async {
    final savedProfile = _offlineDb.getSavedStoreProfile();
    if (savedProfile == null) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Profil toko offline tidak ditemukan. Silakan buat toko baru.',
      ));
      return false;
    }

    final expectedPinHash = (savedProfile['cashier_pin_hash'] ?? '').toString().trim();
    if (expectedPinHash.isNotEmpty) {
      final provided = (pin ?? '').trim();
      if (provided.isEmpty || _hashPin(provided) != expectedPinHash) {
        emit(state.copyWith(
          isLoading: false,
          errorMessage: 'PIN kasir salah. Silakan periksa kembali PIN Anda.',
        ));
        return false;
      }
    }

    emit(state.copyWith(isLoading: true, errorMessage: null));

    final storeName = (savedProfile['name'] ?? 'Toko Saya').toString().trim();
    final savedVertical = (savedProfile['business_vertical'] ??
            _offlineDb.getSavedBusinessVertical() ??
            'retail')
        .toString()
        .trim()
        .toLowerCase();
    final normalizedVertical = savedVertical.isEmpty ? 'retail' : savedVertical;

    // Never forceClear! Only align tenant identity so existing SQLite rows stay 100% intact.
    await _offlineDb.setActiveTenantIdentity('local-trial:$normalizedVertical');
    await _offlineDb.setSavedBusinessVertical(normalizedVertical);

    final baseSession = AuthSessionModel.createLocalTrialSession(
      storeName: storeName,
      businessVertical: normalizedVertical,
    );
    final restoredStore = StoreBranchModel(
      id: baseSession.activeStore.id,
      name: (savedProfile['branch'] ?? storeName).toString(),
      code: (savedProfile['code'] ?? 'LOKAL-01').toString(),
      city: 'Offline Lokal',
      address: savedProfile['address']?.toString() ?? baseSession.activeStore.address,
      phone: savedProfile['phone']?.toString() ?? '-',
      businessType: normalizedVertical,
      posMode: normalizedVertical,
    );
    final session = baseSession.copyWith(
      activeStore: restoredStore,
      tenantName: storeName,
    );

    await _apiClient.setActiveStoreId(session.activeStore.id);
    await _apiClient.setTenantSlug(session.tenantSubdomain);
    await _licenseVault.sealSessionEntitlements(session);
    await _offlineDb.saveAuthSession(session.toJson());

    emit(AuthState(
      isLoading: false,
      isAuthenticated: true,
      session: session,
      sessionRevision: state.sessionRevision + 1,
    ));
    return true;
  }

  /// Switch active Store Branch (POST /api/v1/auth/switch-store)
  Future<void> switchStoreBranch(StoreBranchModel branch) async {
    await _apiClient.setActiveStoreId(branch.id);
    if (branch.preferredVerticalRaw != null &&
        (_offlineDb.getSavedBusinessVertical() ?? '').trim().isEmpty) {
      await _offlineDb.setSavedBusinessVertical(branch.preferredVerticalRaw!);
    }
    final updatedSession = state.session.copyWith(activeStore: branch);
    await _licenseVault.sealSessionEntitlements(updatedSession);
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

        await _licenseVault.sealSessionEntitlements(refreshed);
        await _offlineDb.saveAuthSession(refreshed.toJson());
        await _persistStoreProfileFromSession(refreshed);
        emit(state.copyWith(session: refreshed));
      }
    } catch (_) {
      // Offline store switch handled locally
    }
  }

  /// Bug 1 Fix:
  /// - In Offline Mandiri mode (`isLocalTrial == true`), ONLY clears active cashier session
  ///   (`clearAuthSession()`). NEVER deletes SQLite tables or SharedPreferences store data!
  /// - In Cloud mode, preserves unsynced offline queues if any pending offline mutations exist,
  ///   otherwise purges foreign tenant cache for strict multi-tenant isolation.
  Future<void> logout() async {
    final cached = _offlineDb.getCachedAuthSession();
    final isStandaloneSession = state.session.isLocalTrial ||
        cached?['is_local_trial'] == true ||
        (_offlineDb.hasExistingStandaloneStore &&
            (state.session.tenantSubdomain.isEmpty ||
                state.session.tenantSubdomain == 'local-trial'));

    if (isStandaloneSession) {
      await _offlineDb.clearAuthSession();
      emit(AuthState(
        isLoading: false,
        isAuthenticated: false,
        session: AuthSessionModel.empty(),
        sessionRevision: state.sessionRevision,
      ));
      return;
    }

    try {
      await _apiClient.dio.post(ApiEndpoints.logout);
    } catch (_) {}
    await _apiClient.clearSession();
    await _offlineDb.clearAuthSession();
    if (!_offlineDb.hasAnyPendingSyncItems) {
      await _offlineDb.clearTenantCache();
      await _licenseVault.clearVault();
    }
    emit(AuthState(
      isLoading: false,
      isAuthenticated: false,
      session: AuthSessionModel.empty(),
      sessionRevision: state.sessionRevision,
    ));
  }

  /// Explicit Factory Reset ("Reset Pabrik / Hapus Seluruh Database") from Settings.
  /// Permanently wipes SQLite (`_sqlite.clearAll()`), SharedPreferences store data,
  /// license vault, and active session.
  Future<void> factoryResetLocalDatabase() async {
    await _apiClient.clearSession();
    await _offlineDb.factoryResetAll();
    await _licenseVault.clearVault();
    emit(AuthState(
      isLoading: false,
      isAuthenticated: false,
      session: AuthSessionModel.empty(),
      sessionRevision: state.sessionRevision + 1,
    ));
  }
}
