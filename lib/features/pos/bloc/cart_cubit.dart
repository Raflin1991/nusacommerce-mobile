import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/repositories/sale_repository.dart';
import '../models/pos_models.dart';
import 'pos_cubit.dart';

class CartState extends Equatable {
  final List<CartItemModel> items;
  final String posMode;
  final String orderType;
  final Map<String, dynamic>? selectedCustomer;
  final Map<String, dynamic>? selectedTable;
  final String? orderNotes;
  final double subtotal;
  final double totalDiscount;
  final double exclusiveTaxTotal;
  final double grandTotal;
  final double totalItemsCount;
  final int redeemedLoyaltyPoints;
  final bool isExchangeMode;
  final List<Map<String, dynamic>> heldCarts;

  const CartState({
    this.items = const [],
    this.posMode = 'retail',
    this.orderType = 'retail',
    this.selectedCustomer,
    this.selectedTable,
    this.orderNotes,
    this.subtotal = 0.0,
    this.totalDiscount = 0.0,
    this.exclusiveTaxTotal = 0.0,
    this.grandTotal = 0.0,
    this.totalItemsCount = 0.0,
    this.redeemedLoyaltyPoints = 0,
    this.isExchangeMode = false,
    this.heldCarts = const [],
  });

  factory CartState.fromPosState(PosState s) {
    return CartState(
      items: s.cart,
      posMode: s.posMode,
      orderType: s.orderType,
      selectedCustomer: s.selectedCustomer,
      selectedTable: s.selectedTable,
      orderNotes: s.orderNotes,
      subtotal: s.subtotal,
      totalDiscount: s.totalDiscount,
      exclusiveTaxTotal: s.exclusiveTaxTotal,
      grandTotal: s.grandTotal,
      totalItemsCount: s.totalItemsCount,
      redeemedLoyaltyPoints: s.redeemedLoyaltyPoints,
      isExchangeMode: s.isExchangeMode,
      heldCarts: s.heldCarts,
    );
  }

  @override
  List<Object?> get props => [
        items,
        posMode,
        orderType,
        selectedCustomer,
        selectedTable,
        orderNotes,
        subtotal,
        totalDiscount,
        exclusiveTaxTotal,
        grandTotal,
        totalItemsCount,
        redeemedLoyaltyPoints,
        isExchangeMode,
        heldCarts,
      ];
}

/// Focused Domain Cubit for Active POS Cart, Barcode Wedge, Discounts, Loyalty,
/// Hold/Recall Bills, and Supervisor PIN Verification.
class CartCubit extends Cubit<CartState> {
  final PosCubit _posCubit;
  final SaleRepository _saleRepository;
  StreamSubscription<PosState>? _posSub;

  CartCubit({
    required PosCubit posCubit,
    required SaleRepository saleRepository,
  })  : _posCubit = posCubit,
        _saleRepository = saleRepository,
        super(CartState.fromPosState(posCubit.state)) {
    _posSub = _posCubit.stream.listen((next) {
      if (!isClosed) emit(CartState.fromPosState(next));
    });
  }

  SaleRepository get repository => _saleRepository;

  void addProduct(
    ProductModel product, {
    ProductVariantModel? variant,
    double quantity = 1.0,
    String? notes,
    String? digitalTargetValue,
  }) {
    _posCubit.addToCart(
      product,
      variant: variant,
      quantity: quantity,
      notes: notes,
      digitalTargetValue: digitalTargetValue,
    );
  }

  bool scanBarcode(String rawCode) => _posCubit.handleBarcodeScanned(rawCode);

  void incrementItem(int index) => _posCubit.incrementCartItem(index);

  void decrementItem(int index) => _posCubit.decrementCartItem(index);

  void removeItem(int index) => _posCubit.removeCartItem(index);

  void clearCart() => _posCubit.clearCart();

  void selectCustomer(Map<String, dynamic>? customer) => _posCubit.selectCustomer(customer);

  void selectTable(Map<String, dynamic>? table) => _posCubit.selectRestaurantTable(table);

  void setOrderType(String orderType) => _posCubit.setOrderType(orderType);

  void setOrderNotes(String? notes) => _posCubit.setOrderNotes(notes);

  bool applyCartDiscount(double discountAmount) => _posCubit.applyCartDiscount(discountAmount);

  void setRedeemedLoyaltyPoints(int points) => _posCubit.setRedeemedLoyaltyPoints(points);

  Future<void> holdCart(String label) => _posCubit.holdCurrentCart(label);

  void resumeHeldCart(int index, {bool autoParkActiveCart = true}) {
    _posCubit.resumeHeldCart(index, autoParkActiveCart: autoParkActiveCart);
  }

  Future<bool> verifySupervisorPin(String pin, {String? action}) {
    return _posCubit.verifyManagerPin(pin, action: action ?? 'pos_override');
  }

  @override
  Future<void> close() async {
    await _posSub?.cancel();
    return super.close();
  }
}
