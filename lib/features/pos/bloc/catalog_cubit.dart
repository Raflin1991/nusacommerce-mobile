import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/repositories/product_repository.dart';
import '../models/pos_models.dart';
import 'pos_cubit.dart';

class CatalogState extends Equatable {
  final bool isLoading;
  final List<ProductModel> allProducts;
  final List<ProductModel> filteredProducts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> brands;
  final List<Map<String, dynamic>> units;
  final int selectedCategoryId;
  final int selectedBrandId;
  final String searchQuery;
  final int lowStockCount;
  final int expiringSoonCount;

  const CatalogState({
    this.isLoading = false,
    this.allProducts = const [],
    this.filteredProducts = const [],
    this.categories = const [],
    this.brands = const [],
    this.units = const [],
    this.selectedCategoryId = 0,
    this.selectedBrandId = 0,
    this.searchQuery = '',
    this.lowStockCount = 0,
    this.expiringSoonCount = 0,
  });

  factory CatalogState.fromPosState(PosState s) {
    return CatalogState(
      isLoading: s.isLoading,
      allProducts: s.allProducts,
      filteredProducts: s.filteredProducts,
      categories: s.posCategories,
      brands: s.posBrands,
      units: s.units,
      selectedCategoryId: s.selectedCategoryId,
      selectedBrandId: s.selectedBrandId,
      searchQuery: s.searchQuery,
      lowStockCount: s.lowStockProductsCount,
      expiringSoonCount: s.expiringSoonCount,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        allProducts,
        filteredProducts,
        categories,
        brands,
        units,
        selectedCategoryId,
        selectedBrandId,
        searchQuery,
        lowStockCount,
        expiringSoonCount,
      ];
}

/// Focused Domain Cubit for POS Product Catalog, Indexed FTS5 Search,
/// Category/Brand Filtering, and Multi-Warehouse Stock Queries.
class CatalogCubit extends Cubit<CatalogState> {
  final PosCubit _posCubit;
  final ProductRepository _productRepository;
  StreamSubscription<PosState>? _posSub;

  CatalogCubit({
    required PosCubit posCubit,
    required ProductRepository productRepository,
  })  : _posCubit = posCubit,
        _productRepository = productRepository,
        super(CatalogState.fromPosState(posCubit.state)) {
    _posSub = _posCubit.stream.listen((next) {
      if (!isClosed) emit(CatalogState.fromPosState(next));
    });
  }

  ProductRepository get repository => _productRepository;

  void selectCategory(int categoryId) => _posCubit.selectCategory(categoryId);

  void selectBrand(int brandId) => _posCubit.selectBrand(brandId);

  void updateSearchQuery(String query) => _posCubit.updateSearchQuery(query);

  Future<List<ProductModel>> searchFast(String query) => _posCubit.searchProductsFast(query);

  Future<({bool fromCloud, List<Map<String, dynamic>> results, String? error})>
      fetchWarehouseStock({int? productId, String query = ''}) {
    return _posCubit.fetchWarehouseStock(productId: productId, query: query);
  }

  Future<void> refreshTaxonomies() => _posCubit.refreshTaxonomies();

  @override
  Future<void> close() async {
    await _posSub?.cancel();
    return super.close();
  }
}
