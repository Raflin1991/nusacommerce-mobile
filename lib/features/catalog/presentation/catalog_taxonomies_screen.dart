import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// PUSAT TAKSONOMI PRODUK & LABEL BARCODE
/// Mengelola Kategori, Merek, Satuan, dan Cetak Stiker Label Barcode Thermal.
class CatalogTaxonomiesScreen extends StatefulWidget {
  final int initialTab;

  const CatalogTaxonomiesScreen({super.key, this.initialTab = 0});

  @override
  State<CatalogTaxonomiesScreen> createState() => _CatalogTaxonomiesScreenState();
}

class _CatalogTaxonomiesScreenState extends State<CatalogTaxonomiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PrinterService _printer = GetIt.instance<PrinterService>();
  String _search = '';
  int _barcodeCopies = 1;
  bool _barcodeShowPrice = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PosCubit>().refreshTaxonomies();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showSimpleCrudModal({
    required String title,
    required String nameLabel,
    String? codeLabel,
    bool showColor = false,
    bool showDecimalToggle = false,
    Map<String, dynamic>? existing,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic> payload) onSave,
  }) {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final codeCtrl = TextEditingController(
      text: (existing?['symbol'] ?? existing?['code'] ?? '').toString(),
    );
    String selectedColor = (existing?['color'] ?? '#2563EB').toString();
    bool allowDecimal = existing?['allow_decimal'] == true;
    bool saving = false;

    const palette = ['#2563EB', '#059669', '#D97706', '#DC2626', '#7C3AED', '#0891B2'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: nameLabel,
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
              ),
              if (codeLabel != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: codeLabel,
                    prefixIcon: const Icon(Icons.short_text_rounded),
                  ),
                ),
              ],
              if (showDecimalToggle) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: allowDecimal,
                  onChanged: (v) => setModal(() => allowDecimal = v),
                  title: const Text('Izinkan Pecahan Desimal (Contoh: Kg/Liter)',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ],
              if (showColor) ...[
                const SizedBox(height: 12),
                Text('Warna Label Kategori',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: NusaThemeTokens.of(ctx).textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: palette.map((hex) {
                    final colorVal = Color(int.parse(hex.replaceFirst('#', '0xFF')));
                    final active = selectedColor == hex;
                    return InkWell(
                      onTap: () => setModal(() => selectedColor = hex),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorVal,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: active ? NusaThemeTokens.of(ctx).textPrimary : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: active ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 18),
              NusaButton(
                label: 'Simpan',
                isLoading: saving,
                icon: Icons.save_rounded,
                onPressed: saving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        setModal(() => saving = true);
                        final payload = <String, dynamic>{
                          'name': name,
                          if (codeLabel != null && codeCtrl.text.trim().isNotEmpty)
                            'symbol': codeCtrl.text.trim(),
                          if (codeLabel != null && codeCtrl.text.trim().isNotEmpty)
                            'code': codeCtrl.text.trim(),
                          if (showColor) 'color': selectedColor,
                          if (showDecimalToggle) 'allow_decimal': allowDecimal,
                        };
                        final res = await onSave(payload);
                        if (!ctx.mounted) return;
                        setModal(() => saving = false);
                        if (res['success'] == true) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('"$name" berhasil disimpan.')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text((res['message'] ?? 'Gagal menyimpan').toString()),
                              backgroundColor: NusaThemeTokens.of(ctx).danger,
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete({
    required String label,
    required Future<Map<String, dynamic>> Function() onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Data?'),
        content: Text('Apakah Anda yakin ingin menghapus "$label"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NusaThemeTokens.of(ctx).danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await onDelete();
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$label" dihapus.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((res['message'] ?? 'Gagal menghapus').toString()),
          backgroundColor: NusaThemeTokens.of(context).danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeName = context.watch<AuthCubit>().state.session.activeStore.name;
    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        title: const Text('Kategori, Merek, Satuan & Barcode'),
        actions: [
          IconButton(
            tooltip: 'Sinkronkan Taksonomi',
            onPressed: () => context.read<PosCubit>().refreshTaxonomies(),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: NusaThemeTokens.of(context).accent,
          unselectedLabelColor: NusaThemeTokens.of(context).textSecondary,
          indicatorColor: NusaThemeTokens.of(context).accent,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Kategori'),
            Tab(text: 'Merek / Brand'),
            Tab(text: 'Satuan / Unit'),
            Tab(text: 'Label Barcode'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final cubit = context.read<PosCubit>();
                if (_tabController.index == 0) {
                  _showSimpleCrudModal(
                    title: 'Tambah Kategori Produk',
                    nameLabel: 'Nama Kategori *',
                    showColor: true,
                    onSave: (p) => cubit.saveCategory(p),
                  );
                } else if (_tabController.index == 1) {
                  _showSimpleCrudModal(
                    title: 'Tambah Merek / Brand',
                    nameLabel: 'Nama Merek *',
                    onSave: (p) => cubit.saveBrand(p),
                  );
                } else {
                  _showSimpleCrudModal(
                    title: 'Tambah Satuan / Unit',
                    nameLabel: 'Nama Satuan (contoh: Kilogram, Dus) *',
                    codeLabel: 'Simbol Singkat (contoh: kg, dus)',
                    showDecimalToggle: true,
                    onSave: (p) => cubit.saveUnit(p),
                  );
                }
              },
              backgroundColor: NusaThemeTokens.of(context).accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _tabController.index == 0
                    ? 'Kategori Baru'
                    : (_tabController.index == 1 ? 'Merek Baru' : 'Satuan Baru'),
              ),
            ),
      body: BlocBuilder<PosCubit, PosState>(
        builder: (context, state) {
          final cats = state.categories
              .where((c) => (c['id'] as num?)?.toInt() != 0 && c['name'] != 'Semua')
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: KATEGORI
              cats.isEmpty
                  ? const NusaEmptyState(
                      icon: Icons.category_outlined,
                      title: 'Belum Ada Kategori',
                      subtitle: 'Tambahkan kategori untuk mengelompokkan katalog kasir POS.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: cats.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final cat = cats[idx];
                        final id = (cat['id'] as num?)?.toInt() ?? 0;
                        final hex = (cat['color'] ?? '#2563EB').toString();
                        final dotColor = Color(
                          int.tryParse(hex.replaceFirst('#', '0xFF')) ?? 0xFF2563EB,
                        );
                        final count = (cat['products_count'] as num?)?.toInt() ??
                            state.allProducts.where((p) => p.categoryId == id).length;

                        return NusaCard(
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat['name'].toString(),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      '$count produk terdaftar',
                                      style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: NusaThemeTokens.of(context).accent),
                                onPressed: () => _showSimpleCrudModal(
                                  title: 'Edit Kategori',
                                  nameLabel: 'Nama Kategori *',
                                  showColor: true,
                                  existing: cat,
                                  onSave: (p) => context.read<PosCubit>().saveCategory(p, id: id),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: NusaThemeTokens.of(context).danger),
                                onPressed: () => _confirmDelete(
                                  label: cat['name'].toString(),
                                  onDelete: () => context.read<PosCubit>().deleteCategory(id),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

              // TAB 2: MEREK / BRAND
              state.brands.isEmpty
                  ? const NusaEmptyState(
                      icon: Icons.verified_outlined,
                      title: 'Belum Ada Merek',
                      subtitle: 'Tambahkan merek produk agar mudah dicari dan dianalisis per brand.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: state.brands.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final brand = state.brands[idx];
                        final id = (brand['id'] as num?)?.toInt() ?? 0;
                        return NusaCard(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: NusaThemeTokens.of(context).accentSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.verified_rounded, color: NusaThemeTokens.of(context).accent, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  brand['name'].toString(),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: NusaThemeTokens.of(context).accent),
                                onPressed: () => _showSimpleCrudModal(
                                  title: 'Edit Merek',
                                  nameLabel: 'Nama Merek *',
                                  existing: brand,
                                  onSave: (p) => context.read<PosCubit>().saveBrand(p, id: id),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: NusaThemeTokens.of(context).danger),
                                onPressed: () => _confirmDelete(
                                  label: brand['name'].toString(),
                                  onDelete: () => context.read<PosCubit>().deleteBrand(id),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

              // TAB 3: SATUAN / UNIT
              state.units.isEmpty
                  ? const NusaEmptyState(
                      icon: Icons.straighten_rounded,
                      title: 'Belum Ada Satuan',
                      subtitle: 'Tambahkan satuan seperti pcs, dus, pack, botol, kg, atau meter.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: state.units.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final unit = state.units[idx];
                        final id = (unit['id'] as num?)?.toInt() ?? 0;
                        final sym = (unit['symbol'] ?? unit['code'] ?? 'pcs').toString();
                        final dec = unit['allow_decimal'] == true;
                        return NusaCard(
                          child: Row(
                            children: [
                              NusaBadge(label: sym.toUpperCase(), variant: NusaBadgeVariant.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      unit['name'].toString(),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      dec ? 'Mendukung qty desimal / timbangan' : 'Qty bilangan bulat',
                                      style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: NusaThemeTokens.of(context).accent),
                                onPressed: () => _showSimpleCrudModal(
                                  title: 'Edit Satuan',
                                  nameLabel: 'Nama Satuan *',
                                  codeLabel: 'Simbol Singkat',
                                  showDecimalToggle: true,
                                  existing: unit,
                                  onSave: (p) => context.read<PosCubit>().saveUnit(p, id: id),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: NusaThemeTokens.of(context).danger),
                                onPressed: () => _confirmDelete(
                                  label: unit['name'].toString(),
                                  onDelete: () => context.read<PosCubit>().deleteUnit(id),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

              // TAB 4: CETAK LABEL BARCODE THERMAL
              _buildBarcodeLabelTab(state.allProducts, storeName),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBarcodeLabelTab(List<ProductModel> products, String storeName) {
    final filtered = products.where((p) {
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  hintText: 'Cari produk untuk cetak label harga / barcode...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 10),
              NusaCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: NusaThemeTokens.of(context).accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          const Text('Jumlah Salinan:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(width: 8),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: _barcodeCopies > 1
                                ? () => setState(() => _barcodeCopies--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('$_barcodeCopies', style: AppTheme.moneyStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: _barcodeCopies < 50
                                ? () => setState(() => _barcodeCopies++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Harga', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Switch(
                          value: _barcodeShowPrice,
                          onChanged: (v) => setState(() => _barcodeShowPrice = v),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final p = filtered[idx];
              final code = p.barcode.isNotEmpty ? p.barcode : p.sku;
              return NusaCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          const SizedBox(height: 3),
                          Text(
                            'Kode: ${code.isNotEmpty ? code : "-"} • SKU: ${p.sku}',
                            style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            IdrCurrencyFormatter.format(p.sellingPrice),
                            style: AppTheme.moneyStyle(fontSize: 14, color: NusaThemeTokens.of(context).accent),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final preview = _printer.formatBarcodeLabelText(
                          storeName: storeName,
                          productName: p.name,
                          sku: p.sku,
                          barcode: p.barcode,
                          price: p.sellingPrice,
                          showPrice: _barcodeShowPrice,
                        );
                        final ok = await _printer.printBarcodeLabel(
                          storeName: storeName,
                          productName: p.name,
                          sku: p.sku,
                          barcode: p.barcode,
                          price: p.sellingPrice,
                          copies: _barcodeCopies,
                          showPrice: _barcodeShowPrice,
                        );
                        if (!context.mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(ok
                                ? 'Label Terkirim ($_barcodeCopies x)'
                                : 'Preview Label Barcode (Printer Offline)'),
                            content: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: NusaThemeTokens.of(ctx).bgElevated,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                preview,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Tutup'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.print_rounded, size: 17),
                      label: const Text('Cetak'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
