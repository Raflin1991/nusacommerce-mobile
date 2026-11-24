// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosProductCardsExt on _PosCatalogScreenState {
  Widget _buildPosProductCard(BuildContext context, PosState state, ProductModel product) {
    final tokens = NusaThemeTokens.of(context);
    final inCartQty = _productQtyInCart(state, product.id);
    final hasInCart = inCartQty > 0;
    final outOfStock = product.stock <= 0;
    final cartIdx = hasInCart ? state.cart.lastIndexWhere((c) => c.product.id == product.id) : -1;

    final String stockLabel = product.isServiceOrNonStockItem || !product.trackStock
        ? 'Jasa / Non-Stok'
        : 'Stok ${IdrCurrencyFormatter.formatQty(product.stock)}';
    final String stockMeta = product.sku.isNotEmpty
        ? '${product.sku} • $stockLabel'
        : '$stockLabel ${product.unitCode}';

    return Material(
      color: tokens.bgSurface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onProductTapped(context, product),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasInCart ? tokens.accent : tokens.borderSubtle,
              width: hasInCart ? (tokens.isHighContrast ? 2.2 : 1.6) : tokens.borderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. High-Clarity Product Showcase Frame (108dp gives generous typography room)
              SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  children: [
                    ProductIllustrationWidget(
                      iconType: product.iconType,
                      imageUrl: product.imageUrl,
                      width: double.infinity,
                      height: 108,
                      showBorder: false,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      backgroundColor: tokens.bgSurface,
                      padding: const EdgeInsets.all(6),
                      fit: BoxFit.contain,
                    ),
                    // Top-Left Active Cart Counter Pill
                    if (hasInCart)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '×${IdrCurrencyFormatter.formatQty(inCartQty)}',
                            style: AppTheme.moneyStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // Top-Right Quick Undo (-1) when in cart OR Variant / Weight Pill
                    if (hasInCart && cartIdx >= 0)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: tokens.bgSurface.withOpacity(0.95),
                          shape: CircleBorder(
                            side: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => context.read<PosCubit>().decrementCartItem(cartIdx),
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(
                                Icons.remove_rounded,
                                size: 16,
                                color: tokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (product.type == 'variable' || product.soldByWeight)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tokens.accent.withOpacity(0.25)),
                          ),
                          child: Text(
                            product.soldByWeight ? 'KG' : '${product.variants.length} Varian',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ),
                    // Bottom-Left Wholesale Tier Badge (Grosir Bertingkat)
                    if (product.volumeTiers.isNotEmpty)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: NusaThemeTokens.of(context).positiveSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.35)),
                          ),
                          child: Text(
                            'Grosir',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: NusaThemeTokens.of(context).positive,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
              // 2. Structured Typography & Action Footer (Zero Vertical Clipping, Zero Price Ellipsis)
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: hasInCart ? tokens.accentSoft.withOpacity(tokens.isDark ? 0.45 : 0.35) : tokens.bgSurface,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                          height: 1.22,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stockMeta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: outOfStock && product.trackStock && !product.isServiceOrNonStockItem
                                    ? tokens.danger
                                    : (product.isLowStock && product.trackStock ? tokens.warning : tokens.textSecondary),
                              ),
                            ),
                          ),
                          if (product.otherWarehousesStock > 0) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _showWarehouseStockSheet(context, initialProduct: product),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: NusaThemeTokens.of(context).warningSoft,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.35)),
                                ),
                                child: Text(
                                  '+Gdg ${IdrCurrencyFormatter.formatQty(product.otherWarehousesStock)}',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: NusaThemeTokens.of(context).warning,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: NusaPriceTag(
                              amount: product.sellingPrice,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                              fitWidth: true,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: hasInCart ? tokens.positive : tokens.accentSoft,
                              borderRadius: BorderRadius.circular(9),
                              border: hasInCart
                                  ? null
                                  : Border.all(color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.3)),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              color: hasInCart ? Colors.white : tokens.accent,
                              size: 19,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosProductListTile(BuildContext context, PosState state, ProductModel product) {
    final tokens = NusaThemeTokens.of(context);
    final inCartQty = _productQtyInCart(state, product.id);
    final hasInCart = inCartQty > 0;
    final outOfStock = product.stock <= 0;

    return NusaCard(
      padding: const EdgeInsets.all(10),
      borderColor: hasInCart ? tokens.accent : tokens.borderSubtle,
      borderWidth: hasInCart ? (tokens.isHighContrast ? 2.2 : 1.5) : tokens.borderWidth,
      backgroundColor: hasInCart ? tokens.accentSoft.withOpacity(tokens.isDark ? 0.35 : 0.25) : tokens.bgSurface,
      onTap: () => _onProductTapped(context, product),
      child: Row(
        children: [
          ProductIllustrationWidget(
            iconType: product.iconType,
            imageUrl: product.imageUrl,
            size: 64,
            fit: BoxFit.contain,
            padding: const EdgeInsets.all(4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (product.volumeTiers.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const NusaBadge(
                        label: 'Grosir',
                        variant: NusaBadgeVariant.success,
                      ),
                    ],
                    if (hasInCart) ...[
                      const SizedBox(width: 6),
                      NusaBadge(
                        label: '×${IdrCurrencyFormatter.formatQty(inCartQty)}',
                        variant: NusaBadgeVariant.primary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'SKU: ${product.sku} • Stok: ${IdrCurrencyFormatter.formatQty(product.stock)} ${product.unitCode}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: outOfStock
                        ? tokens.danger
                        : (product.isLowStock ? tokens.warning : tokens.textSecondary),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: NusaPriceTag(
                        amount: product.sellingPrice,
                        fontSize: 15,
                        color: tokens.textPrimary,
                        fitWidth: true,
                      ),
                    ),
                    if (product.otherWarehousesStock > 0) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _showWarehouseStockSheet(context, initialProduct: product),
                        borderRadius: BorderRadius.circular(6),
                        child: NusaBadge(
                          label: '+Gudang ${IdrCurrencyFormatter.formatQty(product.otherWarehousesStock)}',
                          variant: NusaBadgeVariant.warning,
                        ),
                      ),
                    ],
                    if (product.type == 'variable') ...[
                      const SizedBox(width: 8),
                      NusaBadge(
                        label: '${product.variants.length} Varian',
                        variant: NusaBadgeVariant.neutral,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: hasInCart ? tokens.positive : tokens.accentSoft,
              borderRadius: BorderRadius.circular(11),
              border: hasInCart ? null : Border.all(color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.3)),
            ),
            child: Icon(
              Icons.add_rounded,
              color: hasInCart ? Colors.white : tokens.accent,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}
