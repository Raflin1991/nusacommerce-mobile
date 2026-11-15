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

  const StoreBranchModel({
    required this.id,
    required this.name,
    required this.code,
    this.city,
    this.address,
    this.phone,
    this.businessType,
    this.posMode,
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
      };

  @override
  List<Object?> get props => [id, name, code, city, businessType, posMode];
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
  final StoreBranchModel activeStore;
  final List<StoreBranchModel> availableStores;
  final List<String> permissions;

  const AuthSessionModel({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
    required this.isOwner,
    required this.tenantName,
    required this.tenantSubdomain,
    required this.planName,
    required this.activeStore,
    required this.availableStores,
    this.permissions = const [],
  });

  factory AuthSessionModel.fromApiData(Map<String, dynamic> data) {
    final user = Map<String, dynamic>.from((data['user'] as Map?) ?? {});
    final tenant = Map<String, dynamic>.from((data['tenant'] as Map?) ?? {});
    final storeJson = Map<String, dynamic>.from((data['active_store'] as Map?) ?? {});
    final storesList = (data['available_stores'] as List<dynamic>? ?? [])
        .map((e) => StoreBranchModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final activeStore = storeJson.isNotEmpty
        ? StoreBranchModel.fromJson(storeJson)
        : (storesList.isNotEmpty
            ? storesList.first
            : const StoreBranchModel(id: 1, name: 'Toko Utama', code: 'MAIN', city: 'Indonesia'));

    final roles = (user['roles'] as List<dynamic>? ?? [user['role'] ?? 'Pemilik Usaha'])
        .map((e) => e.toString())
        .toList();
    final roleLabel = roles.isNotEmpty ? roles.first : 'Pemilik Usaha';
    final isOwner = (user['is_owner'] == true) ||
        roleLabel.toLowerCase().contains('admin') ||
        roleLabel.toLowerCase().contains('owner') ||
        roleLabel.toLowerCase().contains('pemilik') ||
        (user['is_super_admin'] == true);

    return AuthSessionModel(
      userId: (user['id'] as num?)?.toInt() ?? 0,
      userName: (user['name'] ?? '').toString(),
      userEmail: (user['email'] ?? '').toString(),
      userRole: isOwner ? 'Pemilik Usaha' : roleLabel,
      isOwner: isOwner,
      tenantName: (tenant['name'] ?? '').toString(),
      tenantSubdomain: (tenant['subdomain'] ?? '').toString(),
      planName: (tenant['plan_name'] ?? '').toString(),
      activeStore: activeStore,
      availableStores: storesList.isNotEmpty ? storesList : [activeStore],
      permissions: (data['permissions'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
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
      activeStore: StoreBranchModel(id: 0, name: '-', code: '-', city: ''),
      availableStores: [],
      permissions: [],
    );
  }

  factory AuthSessionModel.defaultOwnerDemo() {
    const mainStore = StoreBranchModel(
      id: 1,
      name: 'Nusa Manunggal Grand Sudirman',
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
      tenantName: 'NusaCommerce',
      tenantSubdomain: 'manunggal',
      planName: 'Enterprise',
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

    return AuthSessionModel(
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      userName: (json['user_name'] ?? '').toString(),
      userEmail: (json['user_email'] ?? '').toString(),
      userRole: (json['user_role'] ?? '').toString(),
      isOwner: json['is_owner'] == true,
      tenantName: (json['tenant_name'] ?? '').toString(),
      tenantSubdomain: (json['tenant_subdomain'] ?? '').toString(),
      planName: (json['plan_name'] ?? '').toString(),
      activeStore: active,
      availableStores: availableList.isNotEmpty ? availableList : (active.id > 0 ? [active] : []),
      permissions: (json['permissions'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
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
        'active_store': activeStore.toJson(),
        'available_stores': availableStores.map((s) => s.toJson()).toList(),
        'permissions': permissions,
      };

  AuthSessionModel copyWith({
    StoreBranchModel? activeStore,
    String? userName,
    String? tenantName,
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
      activeStore: activeStore ?? this.activeStore,
      availableStores: availableStores,
      permissions: permissions,
    );
  }

  @override
  List<Object?> get props => [userId, userName, tenantSubdomain, activeStore];
}
