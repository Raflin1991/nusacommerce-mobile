part of 'pos_cubit.dart';

class CheckoutServerException implements Exception {
  final String message;
  final String? errorCode;
  final int? statusCode;

  const CheckoutServerException({
    required this.message,
    this.errorCode,
    this.statusCode,
  });

  bool get isShiftRequired =>
      errorCode == 'ShiftRequired' ||
      message.toLowerCase().contains('shift kasir');

  @override
  String toString() => message;
}

class PosState extends Equatable {
  final bool isLoading;
  final bool isOnline;
  final bool isSyncingOfflineQueue;
  final bool isInitialRestoring;
  final double initialRestoreProgress;
  final String? initialRestoreStep;
  final String activeNodeCode;
  final BusinessVertical currentVertical;
  final String posMode; // 'retail' or 'restaurant'
  final String orderType; // 'retail', 'dine_in', 'takeaway', 'delivery'
  final List<ProductModel> allProducts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> suppliers;
  final int selectedCategoryId;
  final int selectedBrandId;
  final String searchQuery;
  final List<CartItemModel> cart;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedTable;
  final String? orderNotes;
  final Map<String, dynamic> verticalMetadata;
  final double cartDiscountAmount;
  final bool managerDiscountApproved;
  final int redeemedLoyaltyPoints;
  final List<Map<String, dynamic>> heldCarts;
  final List<Map<String, dynamic>> salesHistory;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> returnReasons;
  final List<Map<String, dynamic>> brands;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> expenseCategories;
  final List<Map<String, dynamic>> customerGroups;
  final List<Map<String, dynamic>> localSyncConflicts;
  final List<Map<String, dynamic>> deadLetterItems;
  final int? activeHeldSaleId;
  final Map<String, dynamic>? exchangeSourceSale;
  final int offlinePendingCount;
  final String? alertMessage;

  const PosState({
    this.isLoading = false,
    this.isOnline = true,
    this.isSyncingOfflineQueue = false,
    this.isInitialRestoring = false,
    this.initialRestoreProgress = 0.0,
    this.initialRestoreStep,
    this.activeNodeCode = 'M01',
    this.currentVertical = BusinessVertical.retail,
    this.posMode = 'retail',
    this.orderType = 'retail',
    this.allProducts = const [],
    this.categories = const [],
    this.customers = const [],
    this.suppliers = const [],
    this.selectedCategoryId = 0,
    this.selectedBrandId = 0,
    this.searchQuery = '',
    this.cart = const [],
    this.selectedCustomer,
    this.selectedTable,
    this.orderNotes,
    this.verticalMetadata = const {},
    this.cartDiscountAmount = 0,
    this.managerDiscountApproved = false,
    this.redeemedLoyaltyPoints = 0,
    this.heldCarts = const [],
    this.salesHistory = const [],
    this.paymentMethods = const [],
    this.returnReasons = const [],
    this.brands = const [],
    this.units = const [],
    this.expenseCategories = const [],
    this.customerGroups = const [],
    this.localSyncConflicts = const [],
    this.deadLetterItems = const [],
    this.activeHeldSaleId,
    this.exchangeSourceSale,
    this.offlinePendingCount = 0,
    this.alertMessage,
  });

  List<ProductModel> get filteredProducts {
    return allProducts.where((p) {
      // Cloud POS & APK POS consistency: tracked physical products with 0 balance do NOT appear in POS catalog
      if (!p.isSellableInPos) return false;
      final matchesCat = selectedCategoryId == 0 || p.categoryId == selectedCategoryId;
      if (!matchesCat) return false;
      final matchesBrand = selectedBrandId == 0 || p.brandId == selectedBrandId;
      if (!matchesBrand) return false;
      if (searchQuery.trim().isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q) ||
          p.categoryName.toLowerCase().contains(q) ||
          (p.brandName != null && p.brandName!.toLowerCase().contains(q)) ||
          (p.scalePlu != null && p.scalePlu!.contains(q));
    }).toList();
  }

  /// Categories with at least one sellable POS item (always keeping 'Semua' at id=0)
  List<Map<String, dynamic>> get posCategories {
    final sellableCatIds = allProducts
        .where((p) => p.isSellableInPos)
        .map((p) => p.categoryId)
        .toSet();
    return categories.where((c) {
      final id = (c['id'] as num?)?.toInt() ?? 0;
      return id == 0 || sellableCatIds.contains(id);
    }).toList();
  }

  /// Brands with at least one sellable POS item (always keeping 'Semua Merek' at id=0)
  List<Map<String, dynamic>> get posBrands {
    final sellableBrandNames = <int, String>{};
    for (final p in allProducts) {
      if (!p.isSellableInPos) continue;
      final bid = p.brandId;
      final bname = p.brandName?.trim();
      if (bid != null && bid > 0 && bname != null && bname.isNotEmpty) {
        sellableBrandNames[bid] = bname;
      }
    }
    if (sellableBrandNames.isEmpty) return const [];
    final entries = sellableBrandNames.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return [
      {'id': 0, 'name': 'Semua Merek'},
      for (final e in entries) {'id': e.key, 'name': e.value},
    ];
  }

  bool get isExchangeMode =>
      exchangeSourceSale != null || cart.any((c) => c.isExchangeReturn);

  double get exchangeReturnCreditTotal => cart
      .where((c) => c.isExchangeReturn)
      .fold(0.0, (sum, c) => sum + c.lineTotal.abs());

  double get replacementItemsSubtotal => cart
      .where((c) => !c.isExchangeReturn)
      .fold(0.0, (sum, c) => sum + c.lineTotal);

  double get totalItemsCount =>
      cart.fold(0.0, (sum, item) => sum + item.quantity.abs());

  double get subtotal => cart.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get customerGroupDiscount {
    final pct = (selectedCustomer?['default_discount_percent'] as num?)?.toDouble() ?? 0.0;
    if (pct <= 0 || subtotal <= 0) return 0.0;
    return (subtotal * (pct / 100.0)).roundToDouble();
  }

  double get loyaltyDiscountValue => redeemedLoyaltyPoints * 100.0; // 1 point = Rp 100

  double get totalDiscount {
    final rawTotal = cartDiscountAmount + customerGroupDiscount + loyaltyDiscountValue;
    final maxAllowed = subtotal > 0 ? subtotal : 0.0;
    return rawTotal.clamp(0.0, maxAllowed).roundToDouble();
  }

  double get exchangeSurplusCredit {
    if (!isExchangeMode) return 0.0;
    final net = subtotal - totalDiscount;
    return net < 0 ? net.abs() : 0.0;
  }

  static double _round4dp(double value) => (value * 10000.0).roundToDouble() / 10000.0;

  /// Exclusive tax total across positive cart lines (mirrors backend `PriceCart` / `TaxResolver`).
  /// Products with `taxInclusive == true` already include tax in `unitPrice`, so 0 is added on top.
  double get exclusiveTaxTotal {
    if (isExchangeMode && (subtotal - totalDiscount) <= 0) return 0.0;
    final positiveLines = cart.where((c) => !c.isExchangeReturn).toList();
    if (positiveLines.isEmpty) return 0.0;
    final posSub = positiveLines.fold<double>(0.0, (s, c) => s + c.lineTotal);
    double remOrderDisc = totalDiscount.clamp(0.0, posSub);
    double taxSum = 0.0;
    for (int i = 0; i < positiveLines.length; i++) {
      final c = positiveLines[i];
      double orderDiscShare = 0.0;
      if (remOrderDisc > 0 && posSub > 0) {
        if (i == positiveLines.length - 1) {
          orderDiscShare = remOrderDisc;
        } else {
          orderDiscShare = ((c.lineTotal / posSub) * totalDiscount).roundToDouble();
          remOrderDisc = (remOrderDisc - orderDiscShare).clamp(0.0, posSub);
        }
      }
      final taxableBase = (c.lineTotal - orderDiscShare).clamp(0.0, double.infinity);
      if (!c.product.taxInclusive && c.product.taxRate > 0) {
        taxSum += _round4dp(taxableBase * (c.product.taxRate / 100.0));
      }
    }
    return _round4dp(taxSum);
  }

  double get grandTotal =>
      _round4dp((subtotal - totalDiscount).clamp(0.0, double.infinity) + exclusiveTaxTotal);

  int get lowStockProductsCount => allProducts.where((p) => p.isLowStock).length;

  int get expiringSoonCount => allProducts.where((p) => p.hasExpiringSoonBatch).length;

  VerticalCapabilities get capabilities => VerticalConfig.getCapabilities(currentVertical);

  /// C.2: Pharmacy prescription items currently in cart
  List<CartItemModel> get prescriptionRequiredCartProducts =>
      cart.where((item) => !item.isExchangeReturn && item.product.requiresPrescription).toList();

  /// C.2: True when cart contains prescription drugs without doctor/patient metadata
  bool get hasUnfulfilledPrescriptionRequirement {
    if (prescriptionRequiredCartProducts.isEmpty) return false;
    final doc = (verticalMetadata['doctor_name'] ?? '').toString().trim();
    final patient = (verticalMetadata['patient_name'] ?? '').toString().trim();
    return doc.isEmpty || patient.isEmpty;
  }

  PosState copyWith({
    bool? isLoading,
    bool? isOnline,
    bool? isSyncingOfflineQueue,
    bool? isInitialRestoring,
    double? initialRestoreProgress,
    String? initialRestoreStep,
    bool clearInitialRestoreStep = false,
    String? activeNodeCode,
    BusinessVertical? currentVertical,
    String? posMode,
    String? orderType,
    List<ProductModel>? allProducts,
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? customers,
    List<Map<String, dynamic>>? suppliers,
    int? selectedCategoryId,
    int? selectedBrandId,
    String? searchQuery,
    List<CartItemModel>? cart,
    Map<String, dynamic>? selectedCustomer,
    bool clearCustomer = false,
    Map<String, dynamic>? selectedTable,
    bool clearTable = false,
    String? orderNotes,
    bool clearOrderNotes = false,
    Map<String, dynamic>? verticalMetadata,
    bool clearVerticalMetadata = false,
    double? cartDiscountAmount,
    bool? managerDiscountApproved,
    int? redeemedLoyaltyPoints,
    List<Map<String, dynamic>>? heldCarts,
    List<Map<String, dynamic>>? salesHistory,
    List<Map<String, dynamic>>? paymentMethods,
    List<Map<String, dynamic>>? returnReasons,
    List<Map<String, dynamic>>? brands,
    List<Map<String, dynamic>>? units,
    List<Map<String, dynamic>>? expenseCategories,
    List<Map<String, dynamic>>? customerGroups,
    List<Map<String, dynamic>>? localSyncConflicts,
    List<Map<String, dynamic>>? deadLetterItems,
    int? activeHeldSaleId,
    bool clearActiveHeldSaleId = false,
    Map<String, dynamic>? exchangeSourceSale,
    bool clearExchangeSourceSale = false,
    int? offlinePendingCount,
    String? alertMessage,
  }) {
    return PosState(
      isLoading: isLoading ?? this.isLoading,
      isOnline: isOnline ?? this.isOnline,
      isSyncingOfflineQueue: isSyncingOfflineQueue ?? this.isSyncingOfflineQueue,
      isInitialRestoring: isInitialRestoring ?? this.isInitialRestoring,
      initialRestoreProgress: initialRestoreProgress ?? this.initialRestoreProgress,
      initialRestoreStep: clearInitialRestoreStep ? null : (initialRestoreStep ?? this.initialRestoreStep),
      activeNodeCode: activeNodeCode ?? this.activeNodeCode,
      currentVertical: currentVertical ?? this.currentVertical,
      posMode: posMode ?? this.posMode,
      orderType: orderType ?? this.orderType,
      allProducts: allProducts ?? this.allProducts,
      categories: categories ?? this.categories,
      customers: customers ?? this.customers,
      suppliers: suppliers ?? this.suppliers,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      selectedBrandId: selectedBrandId ?? this.selectedBrandId,
      searchQuery: searchQuery ?? this.searchQuery,
      cart: cart ?? this.cart,
      selectedCustomer: clearCustomer ? null : (selectedCustomer ?? this.selectedCustomer),
      selectedTable: clearTable ? null : (selectedTable ?? this.selectedTable),
      orderNotes: clearOrderNotes ? null : (orderNotes ?? this.orderNotes),
      verticalMetadata: clearVerticalMetadata ? const {} : (verticalMetadata ?? this.verticalMetadata),
      cartDiscountAmount: cartDiscountAmount ?? this.cartDiscountAmount,
      managerDiscountApproved: managerDiscountApproved ?? this.managerDiscountApproved,
      redeemedLoyaltyPoints: redeemedLoyaltyPoints ?? this.redeemedLoyaltyPoints,
      heldCarts: heldCarts ?? this.heldCarts,
      salesHistory: salesHistory ?? this.salesHistory,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      returnReasons: returnReasons ?? this.returnReasons,
      brands: brands ?? this.brands,
      units: units ?? this.units,
      expenseCategories: expenseCategories ?? this.expenseCategories,
      customerGroups: customerGroups ?? this.customerGroups,
      localSyncConflicts: localSyncConflicts ?? this.localSyncConflicts,
      deadLetterItems: deadLetterItems ?? this.deadLetterItems,
      activeHeldSaleId: clearActiveHeldSaleId ? null : (activeHeldSaleId ?? this.activeHeldSaleId),
      exchangeSourceSale: clearExchangeSourceSale ? null : (exchangeSourceSale ?? this.exchangeSourceSale),
      offlinePendingCount: offlinePendingCount ?? this.offlinePendingCount,
      alertMessage: alertMessage,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isOnline,
        isSyncingOfflineQueue,
        isInitialRestoring,
        initialRestoreProgress,
        initialRestoreStep,
        activeNodeCode,
        currentVertical,
        posMode,
        orderType,
        allProducts,
        categories,
        customers,
        suppliers,
        selectedCategoryId,
        selectedBrandId,
        searchQuery,
        cart,
        selectedCustomer,
        selectedTable,
        orderNotes,
        verticalMetadata,
        cartDiscountAmount,
        managerDiscountApproved,
        redeemedLoyaltyPoints,
        heldCarts,
        salesHistory,
        paymentMethods,
        returnReasons,
        brands,
        units,
        expenseCategories,
        customerGroups,
        localSyncConflicts,
        deadLetterItems,
        activeHeldSaleId,
        exchangeSourceSale,
        offlinePendingCount,
        alertMessage,
      ];
}
