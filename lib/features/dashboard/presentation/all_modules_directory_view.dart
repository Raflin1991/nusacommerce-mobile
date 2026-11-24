import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/cascade_entitlement_teaser.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';

part 'all_modules_directory_view_part1.dart';
part 'all_modules_directory_view_part2.dart';

/// Hub "Semua Menu" — Pusat direktori modul ERP & POS OXORA (Strict RBAC + CDO Warm Linen).
/// Hanya menampilkan modul yang diizinkan oleh hak akses peran (RBAC) pengguna.
class AllModulesDirectoryView extends StatefulWidget {
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSwitchTab;

  const AllModulesDirectoryView({
    super.key,
    required this.onOpenDrawer,
    required this.onSwitchTab,
  });

  @override
  State<AllModulesDirectoryView> createState() => _AllModulesDirectoryViewState();
}


class _AllModulesDirectoryViewState extends State<AllModulesDirectoryView> {
  final TextEditingController _searchCtrl = TextEditingController();

  String _searchQuery = '';


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final authState = context.watch<AuthCubit>().state;
    final session = authState.session;
    final hasFullCatalogAccess = MobileWorkspaceResolver.canSwitchWorkspaces(session) ||
        (!authState.isAuthenticated &&
            session.userId == 0 &&
            session.userRole.trim().isEmpty &&
            session.permissions.isEmpty);
    final onlineGated = session.isModuleGated('online_store');

    final categories = _buildCategories(
      context,
      tokens: tokens,
      session: session,
      hasFullCatalogAccess: hasFullCatalogAccess,
      onlineGated: onlineGated,
      currentTier: session.tier,
    );

    final totalVisibleModules =
        categories.fold<int>(0, (sum, cat) => sum + cat.items.length);

    final q = _searchQuery.trim().toLowerCase();
    final filteredCategories = <_ModuleCategory>[];
    for (final cat in categories) {
      if (q.isEmpty) {
        filteredCategories.add(cat);
      } else {
        final matchedItems = cat.items.where((item) {
          return item.title.toLowerCase().contains(q) ||
              item.subtitle.toLowerCase().contains(q) ||
              cat.title.toLowerCase().contains(q) ||
              (item.secondaryActionLabel?.toLowerCase().contains(q) ?? false);
        }).toList();
        if (matchedItems.isNotEmpty) {
          filteredCategories.add(cat.copyWithItems(matchedItems));
        }
      }
    }

    return Scaffold(
      backgroundColor: tokens.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            _buildStickyHeader(
              context,
              tokens,
              totalVisibleModules: totalVisibleModules,
              hasFullCatalogAccess: hasFullCatalogAccess,
            ),
            Expanded(
              child: filteredCategories.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: tokens.textTertiary),
                            const SizedBox(height: 10),
                            Text(
                              'Modul tidak ditemukan',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tidak ada fitur yang cocok dengan "$_searchQuery".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Text('Reset Pencarian', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      itemCount: filteredCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) => _buildCategoryCard(tokens, filteredCategories[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


class _ModuleCategory {
  final String title;
  final Color accentColor;
  final List<_ModuleEntry> items;

  const _ModuleCategory({
    required this.title,
    required this.accentColor,
    required this.items,
  });

  _ModuleCategory copyWithItems(List<_ModuleEntry> newItems) {
    return _ModuleCategory(
      title: title,
      accentColor: accentColor,
      items: newItems,
    );
  }
}


class _ModuleEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isGated;
  final String requiredTier;
  final String? badge;
  final bool fullSpan;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryTap;

  const _ModuleEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isGated = false,
    this.requiredTier = 'PRO',
    this.badge,
    this.fullSpan = false,
    this.secondaryActionLabel,
    this.onSecondaryTap,
  });
}
