import 'package:equatable/equatable.dart';

class ProductBatchModel extends Equatable {
  final int id;
  final String batchNumber;
  final String? expiryDate;
  final double quantity;
  final bool isExpired;

  const ProductBatchModel({
    required this.id,
    required this.batchNumber,
    this.expiryDate,
    required this.quantity,
    this.isExpired = false,
  });

  factory ProductBatchModel.fromJson(Map<String, dynamic> json) {
    final exp = json['expiry_date']?.toString();
    bool expired = json['is_expired'] == true;
    if (!expired && exp != null && exp.isNotEmpty) {
      final parsed = DateTime.tryParse(exp);
      if (parsed != null && parsed.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
        expired = true;
      }
    }
    return ProductBatchModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      batchNumber: (json['batch_number'] ?? 'BATCH-01').toString(),
      expiryDate: exp,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      isExpired: expired,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'batch_number': batchNumber,
        'expiry_date': expiryDate,
        'quantity': quantity,
        'is_expired': isExpired,
      };

  @override
  List<Object?> get props => [id, batchNumber, expiryDate, quantity, isExpired];
}

class ProductVariantModel extends Equatable {
  final int id;
  final String name;
  final String sku;
  final double sellingPrice;
  final double stock;

  const ProductVariantModel({
    required this.id,
    required this.name,
    required this.sku,
    required this.sellingPrice,
    required this.stock,
  });

  factory ProductVariantModel.fromJson(Map<String, dynamic> json) {
    String label = (json['name'] ?? '').toString();
    if (label.isEmpty && json['attributes'] is Map) {
      label = (json['attributes'] as Map).values.join(' • ');
    }
    if (label.isEmpty) {
      label = (json['sku'] ?? 'Varian').toString();
    }
    return ProductVariantModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: label,
      sku: (json['sku'] ?? '').toString(),
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toDouble() ?? 20.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'selling_price': sellingPrice,
        'stock': stock,
      };

  @override
  List<Object?> get props => [id, name, sku, sellingPrice, stock];
}

class ProductModel extends Equatable {
  final int id;
  final String name;
  final String sku;
  final String barcode;
  final String type; // standard, variable, kit, digital
  final double sellingPrice;
  final double costPrice;
  final double stock;
  final String unitCode;
  final int categoryId;
  final String categoryName;
  final bool isLowStock;
  final bool soldByWeight;
  final String? scalePlu;
  final String? digitalTargetLabel;
  final String? shelfLocation;
  final String iconType;
  final String? imageUrl;
  final List<ProductVariantModel> variants;
  final List<ProductBatchModel> batches;

  const ProductModel({
    required this.id,
    required this.name,
    required this.sku,
    required this.barcode,
    this.type = 'standard',
    required this.sellingPrice,
    this.costPrice = 0,
    required this.stock,
    this.unitCode = 'pcs',
    this.categoryId = 1,
    this.categoryName = 'Umum',
    this.isLowStock = false,
    this.soldByWeight = false,
    this.scalePlu,
    this.digitalTargetLabel,
    this.shelfLocation,
    this.iconType = 'default',
    this.imageUrl,
    this.variants = const [],
    this.batches = const [],
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final categoryMap = json['category'] is Map ? Map<String, dynamic>.from(json['category'] as Map) : null;
    final unitMap = json['unit'] is Map ? Map<String, dynamic>.from(json['unit'] as Map) : null;
    final locMap = json['shelf_location'] is Map ? Map<String, dynamic>.from(json['shelf_location'] as Map) : null;
    final digitalMap = json['digital_meta'] is Map ? Map<String, dynamic>.from(json['digital_meta'] as Map) : null;

    String? shelfStr;
    if (json['shelf_location'] is String) {
      shelfStr = json['shelf_location'] as String;
    } else if (locMap != null) {
      shelfStr = locMap['formatted']?.toString();
    }

    final name = (json['name'] ?? 'Produk').toString();
    final lower = name.toLowerCase();
    String inferredIcon = (json['icon_type'] ?? '').toString();
    if (inferredIcon.isEmpty) {
      if (lower.contains('air') || lower.contains('mineral')) {
        inferredIcon = 'water';
      } else if (lower.contains('teh') || lower.contains('kopi')) {
        inferredIcon = 'tea';
      } else if (lower.contains('mie') || lower.contains('indomie')) {
        inferredIcon = 'noodle';
      } else if (lower.contains('roti')) {
        inferredIcon = 'bread';
      } else if (lower.contains('biskuit') || lower.contains('roma')) {
        inferredIcon = 'biscuit';
      } else if (lower.contains('susu') || lower.contains('uht')) {
        inferredIcon = 'milk';
      } else if (lower.contains('beras') || lower.contains('gula')) {
        inferredIcon = 'rice';
      } else if (lower.contains('pulsa') || lower.contains('token')) {
        inferredIcon = 'digital';
      } else {
        inferredIcon = 'default';
      }
    }

    final variantsList = (json['variants'] as List<dynamic>? ?? [])
        .map((v) => ProductVariantModel.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();

    final batchesList = (json['batches'] as List<dynamic>? ?? [])
        .map((b) => ProductBatchModel.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();

    final stockVal = (json['stock'] as num?)?.toDouble() ?? 0.0;
    final lowStock = json['is_low_stock'] == true || (stockVal <= 25 && lower.contains('indomie')) || stockVal <= 5;

    return ProductModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: name,
      sku: (json['sku'] ?? 'SKU-01').toString(),
      barcode: (json['barcode'] ?? '').toString(),
      type: (json['type'] ?? 'standard').toString(),
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
      stock: stockVal,
      unitCode: unitMap != null
          ? (unitMap['code'] ?? 'pcs').toString()
          : (json['unit_code'] ?? 'pcs').toString(),
      categoryId: categoryMap != null
          ? ((categoryMap['id'] as num?)?.toInt() ?? 1)
          : ((json['category_id'] as num?)?.toInt() ?? 1),
      categoryName: categoryMap != null
          ? (categoryMap['name'] ?? 'Umum').toString()
          : (json['category_name'] ?? 'Umum').toString(),
      isLowStock: lowStock,
      soldByWeight: json['sold_by_weight'] == true,
      scalePlu: json['scale_plu']?.toString(),
      digitalTargetLabel: digitalMap != null
          ? digitalMap['target_label']?.toString()
          : json['digital_target_label']?.toString(),
      shelfLocation: shelfStr ?? 'Rak Utama A1',
      iconType: inferredIcon,
      imageUrl: json['image_url']?.toString(),
      variants: variantsList,
      batches: batchesList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'type': type,
        'selling_price': sellingPrice,
        'cost_price': costPrice,
        'stock': stock,
        'unit_code': unitCode,
        'category_id': categoryId,
        'category_name': categoryName,
        'is_low_stock': isLowStock,
        'sold_by_weight': soldByWeight,
        'scale_plu': scalePlu,
        'digital_target_label': digitalTargetLabel,
        'shelf_location': shelfLocation,
        'icon_type': iconType,
        'image_url': imageUrl,
        'variants': variants.map((v) => v.toJson()).toList(),
        'batches': batches.map((b) => b.toJson()).toList(),
      };

  /// Resolve earliest non-expired FEFO batch automatically
  ProductBatchModel? get fefoBatch {
    for (final b in batches) {
      if (!b.isExpired && b.quantity > 0) return b;
    }
    return batches.isNotEmpty ? batches.first : null;
  }

  @override
  List<Object?> get props => [id, name, sku, sellingPrice, stock, isLowStock];
}

class CartItemModel extends Equatable {
  final ProductModel product;
  final ProductVariantModel? variant;
  final ProductBatchModel? batch;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final String? notes;
  final String? digitalTargetValue;

  const CartItemModel({
    required this.product,
    this.variant,
    this.batch,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0,
    this.notes,
    this.digitalTargetValue,
  });

  String get displayName {
    if (variant != null) {
      return '${product.name} (${variant!.name})';
    }
    return product.name;
  }

  double get lineSubtotal => quantity * unitPrice;

  double get lineTotal => (lineSubtotal - discountAmount).clamp(0, double.infinity);

  CartItemModel copyWith({
    double? quantity,
    double? unitPrice,
    double? discountAmount,
    String? notes,
    String? digitalTargetValue,
    ProductBatchModel? batch,
  }) {
    return CartItemModel(
      product: product,
      variant: variant,
      batch: batch ?? this.batch,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      notes: notes ?? this.notes,
      digitalTargetValue: digitalTargetValue ?? this.digitalTargetValue,
    );
  }

  @override
  List<Object?> get props => [
        product.id,
        variant?.id,
        batch?.id,
        quantity,
        unitPrice,
        discountAmount,
        notes,
        digitalTargetValue,
      ];
}
