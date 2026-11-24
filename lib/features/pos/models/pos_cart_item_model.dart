part of 'pos_models.dart';

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
  final String? cookingNotes;
  final List<Map<String, dynamic>> modifiers;
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
    this.cookingNotes,
    this.modifiers = const [],
    this.digitalTargetValue,
    this.stylistName,
    this.selectedUnitCode = '',
    this.multiplier = 1.0,
  });

  String get effectiveUnitCode =>
      selectedUnitCode.trim().isNotEmpty ? selectedUnitCode : product.unitCode;

  List<String> get modifierLabels {
    final out = <String>[];
    for (final m in modifiers) {
      final name = (m['name'] ?? m['label'] ?? '').toString().trim();
      if (name.isNotEmpty) out.add(name);
    }
    return out;
  }

  double get modifierUnitDelta {
    double sum = 0.0;
    for (final m in modifiers) {
      sum += (m['price'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  String get displayName {
    if (variant != null) {
      return '${product.name} (${variant!.name})';
    }
    return product.name;
  }

  double get lineSubtotal => (quantity * unitPrice).roundToDouble();

  /// A.1 & A.2: Clamp item-level discount so lineTotal is never negative and stays consistent at Rupiah precision.
  double get effectiveDiscountAmount => isExchangeReturn
      ? 0.0
      : discountAmount.clamp(0.0, math.max(0.0, lineSubtotal)).roundToDouble();

  double get lineTotal => isExchangeReturn
      ? lineSubtotal
      : (lineSubtotal - effectiveDiscountAmount).clamp(0.0, double.infinity).roundToDouble();

  CartItemModel copyWith({
    int? saleItemId,
    bool? isExchangeReturn,
    ProductModel? product,
    double? quantity,
    double? unitPrice,
    double? discountAmount,
    String? notes,
    String? cookingNotes,
    List<Map<String, dynamic>>? modifiers,
    String? digitalTargetValue,
    String? stylistName,
    ProductBatchModel? batch,
    String? selectedUnitCode,
    double? multiplier,
  }) {
    return CartItemModel(
      saleItemId: saleItemId ?? this.saleItemId,
      isExchangeReturn: isExchangeReturn ?? this.isExchangeReturn,
      product: product ?? this.product,
      variant: variant,
      batch: batch ?? this.batch,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      notes: notes ?? this.notes,
      cookingNotes: cookingNotes ?? this.cookingNotes,
      modifiers: modifiers ?? this.modifiers,
      digitalTargetValue: digitalTargetValue ?? this.digitalTargetValue,
      stylistName: stylistName ?? this.stylistName,
      selectedUnitCode: selectedUnitCode ?? this.selectedUnitCode,
      multiplier: multiplier ?? this.multiplier,
    );
  }

  Map<String, dynamic> toJson() => {
        if (saleItemId != null) 'sale_item_id': saleItemId,
        'is_exchange_return': isExchangeReturn,
        'product': product.toJson(),
        'product_id': product.id,
        'product_name': product.name,
        'kds_station': product.kdsStation,
        if (variant != null) 'variant': variant!.toJson(),
        if (variant != null) 'variant_id': variant!.id,
        if (batch != null) 'batch': batch!.toJson(),
        if (batch != null) 'batch_id': batch!.id,
        'quantity': quantity,
        'unit_price': unitPrice,
        'discount_amount': discountAmount,
        if (notes != null) 'notes': notes,
        if (cookingNotes != null && cookingNotes!.trim().isNotEmpty)
          'cooking_notes': cookingNotes!.trim(),
        if (modifiers.isNotEmpty) 'modifiers': modifiers,
        if (digitalTargetValue != null) 'digital_target_value': digitalTargetValue,
        if (stylistName != null) 'stylist_name': stylistName,
        'selected_unit_code': selectedUnitCode,
        'multiplier': multiplier,
      };

  factory CartItemModel.fromJson(
    Map<String, dynamic> json, {
    List<ProductModel>? catalogProducts,
  }) {
    ProductModel resolvedProduct;
    if (json['product'] is Map) {
      resolvedProduct = ProductModel.fromJson(
        Map<String, dynamic>.from(json['product'] as Map),
      );
    } else {
      final pid = (json['product_id'] as num?)?.toInt() ?? 0;
      final matched = catalogProducts?.where((p) => p.id == pid).toList() ?? const [];
      resolvedProduct = matched.isNotEmpty
          ? matched.first
          : ProductModel(
              id: pid,
              name: (json['product_name'] ?? 'Produk').toString(),
              sku: (json['sku'] ?? 'SKU').toString(),
              barcode: '',
              sellingPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
              stock: 99,
            );
    }

    final variant = json['variant'] is Map
        ? ProductVariantModel.fromJson(Map<String, dynamic>.from(json['variant'] as Map))
        : null;
    final batch = json['batch'] is Map
        ? ProductBatchModel.fromJson(Map<String, dynamic>.from(json['batch'] as Map))
        : null;

    final rawMods = json['modifiers'] as List<dynamic>? ?? const [];
    final parsedMods = <Map<String, dynamic>>[];
    for (final m in rawMods) {
      if (m is Map) {
        parsedMods.add(Map<String, dynamic>.from(m));
      } else if (m != null && m.toString().trim().isNotEmpty) {
        parsedMods.add({'name': m.toString().trim(), 'price': 0});
      }
    }

    return CartItemModel(
      saleItemId: (json['sale_item_id'] as num?)?.toInt(),
      isExchangeReturn: json['is_exchange_return'] == true,
      product: resolvedProduct,
      variant: variant,
      batch: batch,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? resolvedProduct.sellingPrice,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes']?.toString(),
      cookingNotes: json['cooking_notes']?.toString(),
      modifiers: parsedMods,
      digitalTargetValue: json['digital_target_value']?.toString(),
      stylistName: json['stylist_name']?.toString(),
      selectedUnitCode: (json['selected_unit_code'] ?? resolvedProduct.unitCode).toString(),
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
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
        cookingNotes,
        modifiers,
        digitalTargetValue,
        stylistName,
        selectedUnitCode,
        multiplier,
      ];
}
