import 'package:equatable/equatable.dart';

class ProductVolumeTier extends Equatable {
  final double minQuantity;
  final double tierPrice;
  final String? label;

  const ProductVolumeTier({
    required this.minQuantity,
    required this.tierPrice,
    this.label,
  });

  factory ProductVolumeTier.fromJson(Map<String, dynamic> json) {
    return ProductVolumeTier(
      minQuantity: (json['min_quantity'] as num?)?.toDouble() ??
          (json['min_qty'] as num?)?.toDouble() ??
          1.0,
      tierPrice: (json['tier_price'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble() ??
          0.0,
      label: json['label']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'min_quantity': minQuantity,
        'tier_price': tierPrice,
        'label': label,
      };

  @override
  List<Object?> get props => [minQuantity, tierPrice, label];
}

class ProductUnitConversion extends Equatable {
  final String unitCode; // e.g. 'pcs', 'renteng', 'lusin', 'dus'
  final String unitName;
  final double multiplier; // e.g. 1 dus = 24 pcs, 1 lusin = 12 pcs
  final double price; // Tiered wholesale price for this unit

  const ProductUnitConversion({
    required this.unitCode,
    required this.unitName,
    required this.multiplier,
    required this.price,
  });

  factory ProductUnitConversion.fromJson(Map<String, dynamic> json) {
    final code = (json['unit_code'] ?? json['code'] ?? 'pcs').toString();
    return ProductUnitConversion(
      unitCode: code,
      unitName: (json['unit_name'] ?? json['name'] ?? code.toUpperCase()).toString(),
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      price: (json['price'] as num?)?.toDouble() ??
          (json['selling_price'] as num?)?.toDouble() ??
          0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'unit_code': unitCode,
        'unit_name': unitName,
        'multiplier': multiplier,
        'price': price,
      };

  @override
  List<Object?> get props => [unitCode, unitName, multiplier, price];
}

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

  bool get isExpiringSoon {
    if (isExpired || quantity <= 0 || expiryDate == null || expiryDate!.isEmpty) {
      return false;
    }
    final parsed = DateTime.tryParse(expiryDate!);
    if (parsed == null) return false;
    return parsed.difference(DateTime.now()).inDays <= 30;
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
  final List<ProductUnitConversion> unitConversions;
  final List<ProductVolumeTier> volumeTiers;

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
    this.unitConversions = const [],
    this.volumeTiers = const [],
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
    final inferredIcon = (json['icon_type'] ?? '').toString().isNotEmpty
        ? json['icon_type'].toString()
        : 'default';

    final variantsList = (json['variants'] as List<dynamic>? ?? [])
        .map((v) => ProductVariantModel.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();

    final batchesList = (json['batches'] as List<dynamic>? ?? [])
        .map((b) => ProductBatchModel.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();

    final rawTiers = (json['volume_tiers'] ??
            json['price_tiers'] ??
            json['wholesale_tiers'] ??
            const <dynamic>[]) as List<dynamic>;
    final volumeTiersList = rawTiers
        .whereType<Map>()
        .map((t) => ProductVolumeTier.fromJson(Map<String, dynamic>.from(t)))
        .toList();

    final type = (json['type'] ?? 'standard').toString();
    final sellingPrice = (json['selling_price'] as num?)?.toDouble() ?? 0.0;
    final unitCode = unitMap != null
        ? (unitMap['code'] ?? 'pcs').toString()
        : (json['unit_code'] ?? 'pcs').toString();
    final soldByWeight = json['sold_by_weight'] == true;

    final rawUnits = (json['unit_conversions'] as List<dynamic>? ?? json['units'] as List<dynamic>? ?? []);
    List<ProductUnitConversion> unitConversionsList = rawUnits
        .map((u) => ProductUnitConversion.fromJson(Map<String, dynamic>.from(u as Map)))
        .toList();

    if (unitConversionsList.isNotEmpty) {
      final hasBase = unitConversionsList.any((u) => (u.multiplier - 1.0).abs() < 0.0001);
      if (!hasBase) {
        unitConversionsList.insert(
          0,
          ProductUnitConversion(
            unitCode: unitCode,
            unitName: unitCode.toUpperCase(),
            multiplier: 1.0,
            price: sellingPrice,
          ),
        );
      }
    } else if (!soldByWeight &&
        type != 'digital' &&
        sellingPrice > 0 &&
        !const {'kg', 'gram', 'g', 'liter', 'l'}.contains(unitCode.toLowerCase())) {
      final lusinPrice = ((sellingPrice * 12 * 0.95) / 100).round() * 100.0;
      final dusPrice = ((sellingPrice * 24 * 0.90) / 100).round() * 100.0;
      unitConversionsList = [
        ProductUnitConversion(
          unitCode: unitCode,
          unitName: unitCode.toUpperCase(),
          multiplier: 1.0,
          price: sellingPrice,
        ),
        ProductUnitConversion(
          unitCode: 'lusin',
          unitName: 'Lusin (12 $unitCode)',
          multiplier: 12.0,
          price: lusinPrice > 0 ? lusinPrice : sellingPrice * 12,
        ),
        ProductUnitConversion(
          unitCode: 'dus',
          unitName: 'Dus (24 $unitCode)',
          multiplier: 24.0,
          price: dusPrice > 0 ? dusPrice : sellingPrice * 24,
        ),
      ];
    }

    final stockVal = (json['stock'] as num?)?.toDouble() ?? 0.0;
    final minStock = (json['reorder_level'] as num?)?.toDouble() ?? 5.0;
    final lowStock = json['is_low_stock'] == true || stockVal <= minStock;

    return ProductModel(
      id: (json['id'] as num?)?.toInt() ?? 1,
      name: name,
      sku: (json['sku'] ?? 'SKU-01').toString(),
      barcode: (json['barcode'] ?? '').toString(),
      type: type,
      sellingPrice: sellingPrice,
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
      stock: stockVal,
      unitCode: unitCode,
      categoryId: categoryMap != null
          ? ((categoryMap['id'] as num?)?.toInt() ?? 1)
          : ((json['category_id'] as num?)?.toInt() ?? 1),
      categoryName: categoryMap != null
          ? (categoryMap['name'] ?? 'Umum').toString()
          : (json['category_name'] ?? 'Umum').toString(),
      isLowStock: lowStock,
      soldByWeight: soldByWeight,
      scalePlu: json['scale_plu']?.toString(),
      digitalTargetLabel: digitalMap != null
          ? digitalMap['target_label']?.toString()
          : json['digital_target_label']?.toString(),
      shelfLocation: shelfStr ?? 'Rak Utama A1',
      iconType: inferredIcon,
      imageUrl: json['image_url']?.toString(),
      variants: variantsList,
      batches: batchesList,
      unitConversions: unitConversionsList,
      volumeTiers: volumeTiersList,
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
        'unit_conversions': unitConversions.map((u) => u.toJson()).toList(),
        'volume_tiers': volumeTiers.map((t) => t.toJson()).toList(),
      };

  /// Phase 2.4: Resolve wholesale/tiered unit price based on cart quantity.
  double resolveUnitPriceForQuantity(double quantity, {double? basePriceOverride}) {
    final fallback = basePriceOverride ?? sellingPrice;
    if (volumeTiers.isEmpty) return fallback;
    final sorted = List<ProductVolumeTier>.from(volumeTiers)
      ..sort((a, b) => b.minQuantity.compareTo(a.minQuantity));
    for (final tier in sorted) {
      if (quantity >= tier.minQuantity && tier.minQuantity > 0) {
        return tier.tierPrice;
      }
    }
    return fallback;
  }

  /// Resolve earliest non-expired FEFO batch automatically
  ProductBatchModel? get fefoBatch {
    for (final b in batches) {
      if (!b.isExpired && b.quantity > 0) return b;
    }
    return batches.isNotEmpty ? batches.first : null;
  }

  /// True when any active batch expires within <= 30 days (FEFO alert)
  bool get hasExpiringSoonBatch => batches.any((b) => b.isExpiringSoon);

  @override
  List<Object?> get props => [id, name, sku, sellingPrice, stock, isLowStock, batches, unitConversions, volumeTiers];
}

class CartItemModel extends Equatable {
  final int? saleItemId;
  final bool isExchangeReturn;
  final ProductModel product;
  final ProductVariantModel? variant;
  final ProductBatchModel? batch;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final String? notes;
  final String? digitalTargetValue;
  final String? stylistName;
  final String selectedUnitCode;
  final double multiplier;

  const CartItemModel({
    this.saleItemId,
    this.isExchangeReturn = false,
    required this.product,
    this.variant,
    this.batch,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0,
    this.notes,
    this.digitalTargetValue,
    this.stylistName,
    this.selectedUnitCode = '',
    this.multiplier = 1.0,
  });

  String get effectiveUnitCode =>
      selectedUnitCode.trim().isNotEmpty ? selectedUnitCode : product.unitCode;

  String get displayName {
    if (variant != null) {
      return '${product.name} (${variant!.name})';
    }
    return product.name;
  }

  double get lineSubtotal => quantity * unitPrice;

  double get lineTotal => isExchangeReturn
      ? lineSubtotal
      : (lineSubtotal - discountAmount).clamp(0, double.infinity);

  CartItemModel copyWith({
    int? saleItemId,
    bool? isExchangeReturn,
    double? quantity,
    double? unitPrice,
    double? discountAmount,
    String? notes,
    String? digitalTargetValue,
    String? stylistName,
    ProductBatchModel? batch,
    String? selectedUnitCode,
    double? multiplier,
  }) {
    return CartItemModel(
      saleItemId: saleItemId ?? this.saleItemId,
      isExchangeReturn: isExchangeReturn ?? this.isExchangeReturn,
      product: product,
      variant: variant,
      batch: batch ?? this.batch,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      notes: notes ?? this.notes,
      digitalTargetValue: digitalTargetValue ?? this.digitalTargetValue,
      stylistName: stylistName ?? this.stylistName,
      selectedUnitCode: selectedUnitCode ?? this.selectedUnitCode,
      multiplier: multiplier ?? this.multiplier,
    );
  }

  @override
  List<Object?> get props => [
        saleItemId,
        isExchangeReturn,
        product.id,
        variant?.id,
        batch?.id,
        quantity,
        unitPrice,
        discountAmount,
        notes,
        digitalTargetValue,
        stylistName,
        selectedUnitCode,
        multiplier,
      ];
}
