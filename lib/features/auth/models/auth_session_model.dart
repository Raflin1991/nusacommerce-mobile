import 'package:equatable/equatable.dart';

class StoreBranchModel extends Equatable {
  final int id;
  final String name;
  final String code;
  final String? city;
  final String? address;
  final String? phone;
  final String? businessType;
  final String? posMode;
  final bool isWarehouse;

  const StoreBranchModel({
    required this.id,
    required this.name,
    required this.code,
    this.city,
    this.address,
    this.phone,
    this.businessType,
    this.posMode,
    this.isWarehouse = false,
  });

  String? get preferredVerticalRaw =>
      (posMode != null && posMode!.trim().isNotEmpty)
          ? posMode
          : ((businessType != null && businessType!.trim().isNotEmpty)
              ? businessType
              : null);

  factory StoreBranchModel.fromJson(Map<String, dynamic> json) {
    return StoreBranchModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: (json['name'] ?? 'Toko Utama').toString(),
      code: (json['code'] ?? 'MAIN').toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      businessType: json['business_type']?.toString(),
      posMode: json['pos_mode']?.toString(),
      isWarehouse: json['is_warehouse'] == true || json['type']?.toString() == 'warehouse',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'city': city,
        'address': address,
        'phone': phone,
        'business_type': businessType,
        'pos_mode': posMode,
        'is_warehouse': isWarehouse,
      };

  @override
  List<Object?> get props => [id, name, code, city, businessType, posMode, isWarehouse];
}

class AuthSessionModel extends Equatable {
  final int userId;
  final String userName;
  final String userEmail;
  final String userRole;
  final bool isOwner;
  final String tenantName;
  final String tenantSubdomain;
  final String planName;
  final String tier;
  final List<String> activeModules;
  final List<String> hiddenModules;
  final StoreBranchModel activeStore;
  final List<StoreBranchModel> availableStores;
  final List<String> permissions;
  final bool isLocalTrial;

  static const List<String> _enterpriseDefaultModules = [
    'cash_debt',
    'accounting',
    'tax',
    'assets',
    'warehouse',
    'online_store',
    'crm',
    'loyalty',
    'hr',
  ];

  static const List<String> _proDefaultModules = [
    'cash_debt',
    'accounting',
    'online_store',
    'crm',
    'loyalty',
  ];

  static String _normalizeModuleKey(String raw) => raw.trim().toLowerCase();

  static String _normalizeTier(dynamic rawTier, String fallbackPlan) {
    final candidate = (rawTier ?? fallbackPlan).toString().trim().toLowerCase();
    if (candidate.contains('enterprise') || candidate.contains('korporat')) {
      return 'enterprise';
    }
    if (candidate.contains('pro') || candidate.contains('business')) {
      return 'pro';
    }
    return 'starter';
  }

  static List<String> _parseActiveModules(dynamic entitlementsRaw, String tier) {
    final result = <String>{'cash_debt'};
    if (entitlementsRaw is Map) {
      final modulesRaw = entitlementsRaw['active_modules'] ?? entitlementsRaw['modules'];
      if (modulesRaw is Map) {
        modulesRaw.forEach((key, value) {
          final isEnabled = value == true || value == 1 || value.toString().toLowerCase() == 'true';
          if (isEnabled) {
            result.add(_normalizeModuleKey(key.toString()));
          }
        });
        return result.toList();
      } else if (modulesRaw is List) {
        for (final item in modulesRaw) {
          final k = _normalizeModuleKey(item.toString());
          if (k.isNotEmpty) result.add(k);
        }
        return result.toList();
      }
    }

    if (tier == 'enterprise') {
      result.addAll(_enterpriseDefaultModules);
    } else if (tier == 'pro') {
      result.addAll(_proDefaultModules);
    }
    return result.toList();
  }

  static List<String> _parseHiddenModules(dynamic entitlementsRaw) {
    if (entitlementsRaw is Map) {
      final hidden = entitlementsRaw['hidden_modules'];
      if (hidden is List) {
        return hidden
            .map((e) => _normalizeModuleKey(e.toString()))
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  const AuthSessionModel({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    required this.isOwner,
    required this.tenantName,
    required this.tenantSubdomain,
    required this.planName,
    this.tier = 'starter',
    this.activeModules = const ['cash_debt'],
    this.hiddenModules = const [],
    required this.activeStore,
    required this.availableStores,
    this.permissions = const [],
    this.isLocalTrial = false,
  });

  factory AuthSessionModel.createLocalTrialSession({
    required String storeName,
    required String businessVertical,
    double openingCash = 100000,
  }) {
    final normalizedName = storeName.trim().isEmpty ? 'Toko Saya' : storeName.trim();
    final mainStore = StoreBranchModel(
      id: 1,
      name: normalizedName,
      code: 'LOKAL-01',
      city: 'Offline Lokal',
      address: 'Mode Toko Mandiri (Tersimpan di HP/Tablet)',
      phone: '-',
      businessType: businessVertical,
      posMode: businessVertical,
    );
    return AuthSessionModel(
      userId: 999999,
      userName: 'Pemilik $normalizedName',
      userEmail: 'owner@lokal.oxora.id',
      userRole: 'Pemilik Usaha',
      isOwner: true,
      tenantName: normalizedName,
      tenantSubdomain: 'local-trial',
      planName: 'Mode Mandiri (Gratis)',
      tier: 'starter',
      activeModules: const ['cash_debt'],
      hiddenModules: const [],
      activeStore: mainStore,
      availableStores: [mainStore],
      permissions: const [],
      isLocalTrial: true,
    );
  }

  /// Checks whether the tenant's active subscription plan unlocks [moduleKey].
  bool hasModule(String moduleKey) {
    final key = _normalizeModuleKey(moduleKey);
    if (key.isEmpty || key == 'cash_debt') return true;
    if (activeModules.any((m) => _normalizeModuleKey(m) == key)) {
      return true;
    }
    if (key == 'loyalty' && activeModules.any((m) => _normalizeModuleKey(m) == 'crm')) {
      return true;
    }
    if (key == 'crm' && activeModules.any((m) => _normalizeModuleKey(m) == 'loyalty')) {
      return true;
    }
    return false;
  }

  /// Checks whether [moduleKey] should display the Cascade upgrade Crown gate.
  bool isModuleGated(String moduleKey) {
    final key = _normalizeModuleKey(moduleKey);
    if (key.isEmpty || key == 'cash_debt') return false;
    return !hasModule(key);
  }

  factory AuthSessionModel.fromApiData(Map<String, dynamic> data) {
    final user = Map<String, dynamic>.from((data['user'] as Map?) ?? {});
    final tenant = Map<String, dynamic>.from((data['tenant'] as Map?) ?? {});
    final entitlements = Map<String, dynamic>.from((data['entitlements'] as Map?) ?? {});
    final storeJson = Map<String, dynamic>.from((data['active_store'] as Map?) ?? {});
    final storesList = (data['available_stores'] as List<dynamic>? ?? [])
        .map((e) => StoreBranchModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final activeStore = storeJson.isNotEmpty
        ? StoreBranchModel.fromJson(storeJson)
        : (storesList.isNotEmpty
            ? storesList.first
            : const StoreBranchModel(id: 1, name: 'Toko Utama', code: 'MAIN', city: 'Indonesia'));

    final rawRoles = (user['roles'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];
    final singleRole = (user['role'] ?? '').toString().trim();
    final roleLabel = rawRoles.isNotEmpty
        ? rawRoles.first
        : (singleRole.isNotEmpty ? singleRole : 'Operator');
    final normalizedRole = roleLabel.trim().toLowerCase();
    const ownerExactRoles = {
      'admin',
      'administrator',
      'owner',
      'pemilik',
      'pemilik usaha',
      'direktur',
      'super admin',
      'superadmin',
    };
    final parsedPermissions = (data['permissions'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final hasExplicitIsOwner = user.containsKey('is_owner') && user['is_owner'] is bool;
    final hasExplicitRole = rawRoles.isNotEmpty || singleRole.isNotEmpty;
    final isOwner = (user['is_owner'] == true) ||
        (user['is_super_admin'] == true) ||
        (!hasExplicitIsOwner &&
            hasExplicitRole &&
            ownerExactRoles.contains(normalizedRole));

    final planName = (tenant['plan_name'] ?? '').toString();
    final tier = _normalizeTier(entitlements['tier'] ?? tenant['tier'], planName);
    final activeModules = _parseActiveModules(entitlements.isNotEmpty ? entitlements : null, tier);
    final hiddenModules = _parseHiddenModules(entitlements);

    return AuthSessionModel(
      userId: (user['id'] as num?)?.toInt() ?? 0,
      userName: (user['name'] ?? '').toString(),
      userEmail: (user['email'] ?? '').toString(),
      userRole: isOwner ? 'Pemilik Usaha' : roleLabel,
      isOwner: isOwner,
      tenantName: (tenant['name'] ?? '').toString(),
      tenantSubdomain: (tenant['subdomain'] ?? '').toString(),
      planName: planName,
      tier: tier,
      activeModules: activeModules,
      hiddenModules: hiddenModules,
      activeStore: activeStore,
      availableStores: storesList.isNotEmpty ? storesList : [activeStore],
      permissions: parsedPermissions,
    );
  }

  factory AuthSessionModel.empty() {
    return const AuthSessionModel(
      userId: 0,
      userName: '',
      userEmail: '',
      userRole: '',
      isOwner: false,
      tenantName: '',
      tenantSubdomain: '',
      planName: '',
      tier: 'starter',
      activeModules: ['cash_debt'],
      hiddenModules: [],
      activeStore: StoreBranchModel(id: 0, name: '-', code: '-', city: ''),
      availableStores: [],
      permissions: [],
    );
  }

  factory AuthSessionModel.defaultOwnerDemo() {
    const mainStore = StoreBranchModel(
      id: 1,
      name: 'OXORA Official Store Grand Sudirman',
      code: 'STORE-01',
      city: 'Jakarta Selatan',
      address: 'Jl. Jend. Sudirman Kav. 1, Jakarta',
      phone: '-',
    );
    return const AuthSessionModel(
      userId: 1,
      userName: 'Direktur Manunggal',
      userEmail: 'direktur@manunggal.co.id',
      userRole: 'Pemilik Usaha',
      isOwner: true,
      tenantName: 'OXORA',
      tenantSubdomain: 'manunggal',
      planName: 'Enterprise',
      tier: 'enterprise',
      activeModules: _enterpriseDefaultModules,
      hiddenModules: [],
      activeStore: mainStore,
      availableStores: [mainStore],
      permissions: ['*'],
    );
  }

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    final activeStoreMap = Map<String, dynamic>.from((json['active_store'] as Map?) ?? {});
    final availableList = (json['available_stores'] as List<dynamic>? ?? [])
        .map((e) => StoreBranchModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final active = activeStoreMap.isNotEmpty
        ? StoreBranchModel.fromJson(activeStoreMap)
        : (availableList.isNotEmpty
            ? availableList.first
            : const StoreBranchModel(id: 0, name: '-', code: '-', city: ''));

    final planName = (json['plan_name'] ?? '').toString();
    final tier = _normalizeTier(json['tier'], planName);
    final rawActiveModules = json['active_modules'];
    final activeModules = rawActiveModules is List
        ? <String>{
            'cash_debt',
            ...rawActiveModules.map((e) => _normalizeModuleKey(e.toString())).where((e) => e.isNotEmpty),
          }.toList()
        : _parseActiveModules(null, tier);
    final hiddenModules = (json['hidden_modules'] as List<dynamic>? ?? [])
        .map((e) => _normalizeModuleKey(e.toString()))
        .where((e) => e.isNotEmpty)
        .toList();

    return AuthSessionModel(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      userName: (json['user_name'] ?? '').toString(),
      userEmail: (json['user_email'] ?? '').toString(),
      userRole: (json['user_role'] ?? '').toString(),
      isOwner: json['is_owner'] == true,
      tenantName: (json['tenant_name'] ?? '').toString(),
      tenantSubdomain: (json['tenant_subdomain'] ?? '').toString(),
      planName: planName,
      tier: tier,
      activeModules: activeModules,
      hiddenModules: hiddenModules,
      activeStore: active,
      availableStores: availableList.isNotEmpty ? availableList : (active.id > 0 ? [active] : []),
      permissions: (json['permissions'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      isLocalTrial: json['is_local_trial'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'user_name': userName,
        'user_email': userEmail,
        'user_role': userRole,
        'is_owner': isOwner,
        'tenant_name': tenantName,
        'tenant_subdomain': tenantSubdomain,
        'plan_name': planName,
        'tier': tier,
        'active_modules': activeModules,
        'hidden_modules': hiddenModules,
        'active_store': activeStore.toJson(),
        'available_stores': availableStores.map((s) => s.toJson()).toList(),
        'permissions': permissions,
        'is_local_trial': isLocalTrial,
      };

  AuthSessionModel copyWith({
    StoreBranchModel? activeStore,
    String? userName,
    String? tenantName,
    String? tier,
    List<String>? activeModules,
    List<String>? hiddenModules,
    List<String>? permissions,
    bool? isLocalTrial,
  }) {
    return AuthSessionModel(
      userId: userId,
      userName: userName ?? this.userName,
      userEmail: userEmail,
      userRole: userRole,
      isOwner: isOwner,
      tenantName: tenantName ?? this.tenantName,
      tenantSubdomain: tenantSubdomain,
      planName: planName,
      tier: tier ?? this.tier,
      activeModules: activeModules ?? this.activeModules,
      hiddenModules: hiddenModules ?? this.hiddenModules,
      activeStore: activeStore ?? this.activeStore,
      availableStores: availableStores,
      permissions: permissions ?? this.permissions,
      isLocalTrial: isLocalTrial ?? this.isLocalTrial,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        userName,
        tenantSubdomain,
        tier,
        activeModules,
        hiddenModules,
        activeStore,
        permissions,
        isLocalTrial,
      ];
}
