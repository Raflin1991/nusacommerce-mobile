// ignore_for_file: invalid_use_of_protected_member
part of 'all_modules_directory_view.dart';

extension _AllModulesDirectoryViewStatePart1Ext on _AllModulesDirectoryViewState {

  Widget _buildStickyHeader(
    BuildContext context,
    NusaThemeTokens tokens, {
    required int totalVisibleModules,
    required bool hasFullCatalogAccess,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: widget.onOpenDrawer,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: tokens.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                  ),
                  child: Icon(Icons.menu_rounded, size: 20, color: tokens.textPrimary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pusat Modul & Fitur Toko',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Modul terfilter sesuai hak akses peran Anda',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35),
                    width: tokens.borderWidth,
                  ),
                ),
                child: Text(
                  hasFullCatalogAccess ? '100% Lengkap' : '$totalVisibleModules Modul',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.accentDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (value) => setState(() => _searchQuery = value),
            style: TextStyle(fontSize: 13, color: tokens.textPrimary),
            decoration: InputDecoration(
              hintText: 'Cari modul, fitur, atau laporan...',
              hintStyle: TextStyle(fontSize: 13, color: tokens.textTertiary),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: tokens.textTertiary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, size: 18, color: tokens.textSecondary),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: tokens.bgElevated,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: tokens.accent, width: tokens.isHighContrast ? 2.0 : 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCategoryCard(NusaThemeTokens tokens, _ModuleCategory category) {
    final fullSpanItems = category.items.where((i) => i.fullSpan).toList();
    final gridItems = category.items.where((i) => !i.fullSpan).toList();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : (width < 340 ? 1 : 2);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        boxShadow: tokens.isDark || tokens.isHighContrast ? null : NusaThemeTokens.of(context).cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: category.accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${category.items.length} Modul',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < gridItems.length; i += columns) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 8),
                  Expanded(
                    child: i + col < gridItems.length
                        ? _buildModuleTile(tokens, gridItems[i + col], category.accentColor)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
          for (final wideItem in fullSpanItems) ...[
            if (gridItems.isNotEmpty || wideItem != fullSpanItems.first) const SizedBox(height: 8),
            _buildModuleTile(tokens, wideItem, category.accentColor),
          ],
        ],
      ),
    );
  }


  Widget _buildModuleTile(NusaThemeTokens tokens, _ModuleEntry item, Color categoryAccent) {
    return Material(
      color: item.isGated ? tokens.warningSoft : tokens.bgElevated,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.isGated
                  ? tokens.warning.withOpacity(tokens.isHighContrast ? 1.0 : 0.45)
                  : tokens.borderSubtle,
              width: tokens.borderWidth,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: categoryAccent.withOpacity(tokens.isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 18, color: categoryAccent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (item.isGated) ...[
                          const SizedBox(width: 4),
                          CascadeCrownBadge(requiredTier: item.requiredTier),
                        ] else if (item.badge != null) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: categoryAccent.withOpacity(tokens.isDark ? 0.22 : 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.badge!,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: categoryAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.secondaryActionLabel != null && item.onSecondaryTap != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: item.onSecondaryTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: categoryAccent.withOpacity(tokens.isHighContrast ? 1.0 : 0.5),
                        width: tokens.borderWidth,
                      ),
                    ),
                    child: Text(
                      item.secondaryActionLabel!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: categoryAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
