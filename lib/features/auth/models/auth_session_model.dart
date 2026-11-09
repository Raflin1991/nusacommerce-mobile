import 'package:equatable/equatable.dart';

class StoreBranchModel extends Equatable {
  final int id;
  final String name;
  final String code;
  final String? city;
  final String? address;
  final String? phone;

  const StoreBranchModel({
    required this.id,
    required this.name,
    required this.code,
    this.city,
    this.address,
    this.phone,
  });

  factory StoreBranchModel.fromJson(Map<String, dynamic> json) {
    return StoreBranchModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: (json['name'] ?? 'Toko Kemang').toString(),
      code: (json['code'] ?? 'KMG').toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'city': city,
        'address': address,
        'phone': phone,
      };

  @override
  List<Object?> get props => [id, name, code, city];
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
            : const StoreBranchModel(id: 1, name: 'Toko Kemang', code: 'KMG', city: 'Jakarta Selatan'));

    final roles = (user['roles'] as List<dynamic>? ?? ['Pemilik Usaha']).map((e) => e.toString()).toList();
    final roleLabel = roles.isNotEmpty ? roles.first : 'Pemilik Usaha';
    final isOwner = roleLabel.toLowerCase().contains('admin') ||
        roleLabel.toLowerCase().contains('owner') ||
        roleLabel.toLowerCase().contains('pemilik') ||
        (user['is_super_admin'] == true);

    return AuthSessionModel(
      userId: (user['id'] as num?)?.toInt() ?? 1,
      userName: (user['name'] ?? 'Raflin Abdul').toString(),
      userEmail: (user['email'] ?? 'raflin@nusacommerce.id').toString(),
      userRole: isOwner ? 'Pemilik Usaha' : roleLabel,
      isOwner: isOwner,
      tenantName: (tenant['name'] ?? 'Toko Berkah Jaya').toString(),
      tenantSubdomain: (tenant['subdomain'] ?? 'belewarna').toString(),
      planName: (tenant['plan_name'] ?? 'Enterprise Pro').toString(),
      activeStore: activeStore,
      availableStores: storesList.isNotEmpty
          ? storesList
          : [
              activeStore,
              const StoreBranchModel(id: 2, name: 'Cabang Bandung', code: 'BDG', city: 'Bandung'),
            ],
      permissions: (data['permissions'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
    );
  }

  factory AuthSessionModel.defaultOwnerDemo() {
    const kmg = StoreBranchModel(
      id: 1,
      name: 'Toko Kemang',
      code: 'KMG',
      city: 'Jakarta Selatan',
      address: 'Jl. Melati No. 12, Jakarta',
      phone: '0812 3456 7890',
    );
    const bdg = StoreBranchModel(
      id: 2,
      name: 'Cabang Bandung',
      code: 'BDG',
      city: 'Bandung',
      address: 'Jl. Braga No. 45, Bandung',
      phone: '0813 8899 7766',
    );
    return const AuthSessionModel(
      userId: 1,
      userName: 'Raflin',
      userEmail: 'raflin@belewarna.com',
      userRole: 'Pemilik Usaha',
      isOwner: true,
      tenantName: 'Toko Berkah Jaya',
      tenantSubdomain: 'belewarna',
      planName: 'Enterprise Omnichannel',
      activeStore: kmg,
      availableStores: [kmg, bdg],
      permissions: ['*'],
    );
  }

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
