// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosCartPanelsExt on _PosCatalogScreenState {
  Widget _buildBottomCartPanel(BuildContext context, PosState state) {
    final tokens = NusaThemeTokens.of(context);
    final hasItems = state.cart.isNotEmpty;
    final String summaryPreview = !hasItems
        ? 'Pilih produk untuk mulai transaksi'
        : state.cart.length == 1
            ? state.cart.first.displayName
            : '${state.cart.first.displayName} (+${state.cart.length - 1} lainnya)';

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
        boxShadow: tokens.isDark || tokens.isHighContrast ? null : NusaThemeTokens.of(context).floatingCartShadow,
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row: Interactive Expandable Cart Summary | Diskon | Hapus
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: hasItems ? () => setState(() => _isCartExpanded = !_isCartExpanded) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasItems ? tokens.accent : tokens.bgElevated,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              IdrCurrencyFormatter.formatQty(state.totalItemsCount),
                              style: AppTheme.moneyStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: hasItems ? Colors.white : tokens.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isCartExpanded ? 'Rincian Keranjang' : summaryPreview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: hasItems ? tokens.textPrimary : tokens.textTertiary,
                              ),
                            ),
                          ),
                          if (hasItems)
                            Icon(
                              _isCartExpanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_up_rounded,
                              size: 20,
                              color: tokens.textSecondary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (hasItems) ..._buildCartActionToolbar(context, state, hasItems),
              ],
            ),

            // Animated Expandable Cart Items List (Hidden cleanly until expanded)
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: (!hasItems || !_isCartExpanded)
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 168),
                        child: _buildCartItemsListView(context, state, shrinkWrap: true),
                      ),
                    ),
            ),

            ..._buildCartCheckoutFooter(context, state, hasItems),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCartActionToolbar(BuildContext context, PosState state, bool hasItems) {
    final tokens = NusaThemeTokens.of(context);
    return [
      const SizedBox(width: 6),
      InkWell(
        onTap: hasItems ? () => _showDiscountAndHoldModal(context, state) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: state.totalDiscount > 0 ? tokens.positiveSoft : tokens.accentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            state.totalDiscount > 0
                ? 'Disc -${IdrCurrencyFormatter.formatCompact(state.totalDiscount)}'
                : '+ Diskon',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: state.totalDiscount > 0 ? tokens.positive : tokens.accent,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      InkWell(
        onTap: hasItems
            ? () {
                context.read<PosCubit>().clearCart();
                setState(() => _isCartExpanded = false);
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Icon(Icons.delete_outline_rounded, size: 18, color: tokens.danger),
        ),
      ),
    ];
  }

  List<Widget> _buildCartCheckoutFooter(BuildContext context, PosState state, bool hasItems) {
    final tokens = NusaThemeTokens.of(context);
    final hasSurplusCredit = state.isExchangeMode && state.exchangeSurplusCredit > 0;
    return [
      Divider(height: 12, color: tokens.borderSubtle),
      Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSurplusCredit ? 'Kelebihan Retur' : 'Total Tagihan',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasSurplusCredit ? tokens.accent : tokens.textSecondary,
                  ),
                ),
                NusaPriceTag(
                  amount: hasSurplusCredit ? state.exchangeSurplusCredit : state.grandTotal,
                  fontSize: 18,
                  color: hasSurplusCredit ? tokens.accent : tokens.textPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: hasItems ? () => _showDiscountAndHoldModal(context, state) : null,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: tokens.borderDefault, width: tokens.borderWidth),
              ),
              icon: const Icon(Icons.pause_rounded, size: 18),
              label: const Text('Hold', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: NusaButton(
              label: 'Bayar',
              trailingIcon: Icons.arrow_forward_rounded,
              minHeight: 48,
              onPressed: hasItems ? () => context.push('/pos/payment') : null,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildTabletSideCartPanel(BuildContext context, PosState state, double width) {
    final tokens = NusaThemeTokens.of(context);
    final hasItems = state.cart.isNotEmpty;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        border: Border(left: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
      ),
      child: SafeArea(
        top: false,
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasItems ? tokens.accent : tokens.bgElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      IdrCurrencyFormatter.formatQty(state.totalItemsCount),
                      style: AppTheme.moneyStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: hasItems ? Colors.white : tokens.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Keranjang Kasir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  if (hasItems) ..._buildCartActionToolbar(context, state, hasItems),
                ],
              ),
              Divider(height: 16, color: tokens.borderSubtle),
              Expanded(
                child: !hasItems
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_cart_outlined, size: 42, color: tokens.textTertiary),
                            const SizedBox(height: 10),
                            Text(
                              'Keranjang Masih Kosong',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ketuk produk di katalog kiri\nuntuk menambah ke nota.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: tokens.textTertiary),
                            ),
                          ],
                        ),
                      )
                    : _buildCartItemsListView(context, state, shrinkWrap: false),
              ),
              ..._buildCartCheckoutFooter(context, state, hasItems),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartItemsListView(
    BuildContext context,
    PosState state, {
    required bool shrinkWrap,
  }) {
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      itemCount: state.cart.length,
      separatorBuilder: (_, __) => Divider(height: 8, color: NusaThemeTokens.of(context).borderSubtle),
                          itemBuilder: (context, idx) {
                            final item = state.cart[idx];
                            return Row(
                              children: [
                                ProductIllustrationWidget(
                                  iconType: item.product.iconType,
                                  imageUrl: item.product.imageUrl,
                                  size: 36,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: InkWell(
                                    onTap: item.isExchangeReturn
                                        ? null
                                        : () => _showEditCartItemModal(context, idx, item),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: NusaThemeTokens.of(context).textPrimary,
                                                ),
                                              ),
                                            ),
                                            if (item.isExchangeReturn) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: NusaThemeTokens.of(context).warningSoft,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: NusaThemeTokens.of(context).warning.withOpacity(0.45),
                                                  ),
                                                ),
                                                child: Text(
                                                  'RETUR / TUKAR',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: NusaThemeTokens.of(context).warning,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (!item.isExchangeReturn &&
                                                state.capabilities.hasWholesaleMultiUnit &&
                                                item.product.unitConversions.length > 1) ...[
                                              const SizedBox(width: 6),
                                              InkWell(
                                                borderRadius: BorderRadius.circular(6),
                                                onTap: () {
                                                  showModalBottomSheet<void>(
                                                    context: context,
                                                    shape: const RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                                    ),
                                                    builder: (sheetCtx) => SafeArea(
                                                      child: Padding(
                                                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              'Pilih Satuan • ${item.displayName}',
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.w800,
                                                                color: NusaThemeTokens.of(sheetCtx).textPrimary,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 4),
                                                            Text(
                                                              'Harga & pengurangan stok otomatis mengikuti konversi satuan.',
                                                              style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(sheetCtx).textSecondary),
                                                            ),
                                                            const SizedBox(height: 12),
                                                            ...item.product.unitConversions.map((u) {
                                                              final selected = u.unitCode.toUpperCase() ==
                                                                  item.effectiveUnitCode.toUpperCase();
                                                              return Padding(
                                                                padding: const EdgeInsets.only(bottom: 8),
                                                                child: InkWell(
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  onTap: () {
                                                                    context.read<PosCubit>().changeCartItemUnit(idx, u);
                                                                    Navigator.of(sheetCtx).pop();
                                                                  },
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                      horizontal: 14,
                                                                      vertical: 12,
                                                                    ),
                                                                    decoration: BoxDecoration(
                                                                      color: selected
                                                                          ? NusaThemeTokens.of(sheetCtx).accent.withOpacity(0.08)
                                                                          : Colors.white,
                                                                      borderRadius: BorderRadius.circular(12),
                                                                      border: Border.all(
                                                                        color: selected
                                                                            ? NusaThemeTokens.of(sheetCtx).accent
                                                                            : NusaThemeTokens.of(sheetCtx).borderSubtle,
                                                                        width: selected ? 1.5 : 1,
                                                                      ),
                                                                    ),
                                                                    child: Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child: Column(
                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                            children: [
                                                                              Text(
                                                                                '${u.unitName} (${u.unitCode.toUpperCase()})',
                                                                                style: TextStyle(
                                                                                  fontSize: 13.5,
                                                                                  fontWeight: FontWeight.w800,
                                                                                  color: selected
                                                                                      ? NusaThemeTokens.of(sheetCtx).accent
                                                                                      : NusaThemeTokens.of(sheetCtx).textPrimary,
                                                                                ),
                                                                              ),
                                                                              Text(
                                                                                '1 ${u.unitCode.toUpperCase()} = ${IdrCurrencyFormatter.formatQty(u.multiplier)} ${item.product.unitCode.toUpperCase()}',
                                                                                style: TextStyle(
                                                                                  fontSize: 11.5,
                                                                                  color: NusaThemeTokens.of(sheetCtx).textSecondary,
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        Text(
                                                                          IdrCurrencyFormatter.format(u.price),
                                                                          style: TextStyle(
                                                                            fontSize: 13.5,
                                                                            fontWeight: FontWeight.w800,
                                                                            color: selected
                                                                                ? NusaThemeTokens.of(sheetCtx).accent
                                                                                : NusaThemeTokens.of(sheetCtx).textPrimary,
                                                                          ),
                                                                        ),
                                                                        if (selected) ...[
                                                                          const SizedBox(width: 8),
                                                                          Icon(
                                                                            Icons.check_circle_rounded,
                                                                            color: NusaThemeTokens.of(sheetCtx).accent,
                                                                            size: 18,
                                                                          ),
                                                                        ],
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            }),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: NusaThemeTokens.of(context).accent.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: NusaThemeTokens.of(context).accent.withOpacity(0.3),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        item.effectiveUnitCode.toUpperCase(),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w800,
                                                          color: NusaThemeTokens.of(context).accent,
                                                        ),
                                                      ),
                                                      Icon(
                                                        Icons.arrow_drop_down_rounded,
                                                        size: 14,
                                                        color: NusaThemeTokens.of(context).accent,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          '${IdrCurrencyFormatter.format(item.unitPrice)} × ${IdrCurrencyFormatter.formatQty(item.quantity)} ${item.effectiveUnitCode}'
                                          '${item.discountAmount > 0 ? ' • Disc -${IdrCurrencyFormatter.format(item.discountAmount)}' : ''}'
                                          '${item.stylistName != null && item.stylistName!.isNotEmpty ? ' • Kapster: ${item.stylistName}' : ''}'
                                          '${(item.batch ?? item.product.fefoBatch) != null ? ' • Batch: ${(item.batch ?? item.product.fefoBatch)!.batchNumber}' : ''}'
                                          '${item.notes != null && item.notes!.isNotEmpty ? ' • ${item.notes}' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: NusaThemeTokens.of(context).textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (item.isExchangeReturn)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: NusaThemeTokens.of(context).warningSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.45)),
                                    ),
                                    child: Text(
                                      '-${IdrCurrencyFormatter.format(item.lineTotal.abs())}',
                                      style: AppTheme.moneyStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: NusaThemeTokens.of(context).warning,
                                      ),
                                    ),
                                  )
                                else
                                  // Compact Ergonomic Stepper
                                  Container(
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: NusaThemeTokens.of(context).bgElevated,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => context.read<PosCubit>().decrementCartItem(idx),
                                          borderRadius: BorderRadius.circular(10),
                                          child: SizedBox(
                                            width: 34,
                                            height: 34,
                                            child: Icon(Icons.remove_rounded, size: 16, color: NusaThemeTokens.of(context).textPrimary),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Text(
                                            IdrCurrencyFormatter.formatQty(item.quantity),
                                            style: AppTheme.moneyStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: NusaThemeTokens.of(context).textPrimary,
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => context.read<PosCubit>().incrementCartItem(idx),
                                          borderRadius: BorderRadius.circular(10),
                                          child: SizedBox(
                                            width: 34,
                                            height: 34,
                                            child: Icon(Icons.add_rounded, size: 16, color: NusaThemeTokens.of(context).accent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
  }
}
