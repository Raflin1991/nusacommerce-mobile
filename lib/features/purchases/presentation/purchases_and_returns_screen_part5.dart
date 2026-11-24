// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_and_returns_screen.dart';

extension _PurchasesAndReturnsScreenStatePart5Ext on _PurchasesAndReturnsScreenState {

  Widget _buildPayQuickChip(
    String label,
    double amount,
    TextEditingController ctrl,
    void Function(void Function()) setModalState,
  ) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      padding: EdgeInsets.zero,
      onPressed: () {
        setModalState(() {
          ctrl.text = amount.toInt().toString();
        });
      },
    );
  }


  Widget _buildAiReorderTab() {
    if (_reorderSuggestions.isEmpty) {
      return const NusaEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Semua Stok dalam Batas Aman',
        subtitle: 'Tidak ada SKU dengan stok di bawah reorder level saat ini.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        NusaCard(
          backgroundColor: NusaThemeTokens.of(context).accentSoft,
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: NusaThemeTokens.of(context).accentDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_reorderSuggestions.length} SKU perlu kulakan ulang.',
                  style: TextStyle(fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).textPrimary),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final initial = _reorderSuggestions
                      .take(20)
                      .map((s) => {
                            'product_id': (s['product_id'] as num).toInt(),
                            'product_name': (s['name'] ?? 'Produk').toString(),
                            'sku': (s['sku'] ?? '-').toString(),
                            'unit_code': (s['unit_code'] ?? 'pcs').toString(),
                            'quantity': (s['suggested_qty'] as num?)?.toDouble() ?? 10.0,
                            'unit_cost': (s['cost_price'] as num?)?.toDouble() ?? 0.0,
                          })
                      .toList();
                  _openCreatePurchaseModal(initialLines: initial);
                },
                child: const Text('Buat PO Semua'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._reorderSuggestions.map((s) {
          final currentStock = (s['current_stock'] as num?)?.toDouble() ?? 0.0;
          final reorderLevel = (s['reorder_level'] as num?)?.toDouble() ?? 5.0;
          final suggestedQty = (s['suggested_qty'] as num?)?.toDouble() ?? 10.0;
          final costPrice = (s['cost_price'] as num?)?.toDouble() ?? 0.0;
          final unitCode = (s['unit_code'] ?? 'pcs').toString();
          final supId = (s['supplier_id'] as num?)?.toInt();
          final supName = s['supplier_name']?.toString();

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NusaCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((s['name'] ?? 'Produk').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(
                          'SKU: ${s['sku'] ?? '-'} • Sisa: ${IdrCurrencyFormatter.formatQty(currentStock)} $unitCode (Min ${IdrCurrencyFormatter.formatQty(reorderLevel)})',
                          style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).danger),
                        ),
                        if (supName != null && supName.isNotEmpty)
                          Text('Pemasok terakhir: $supName',
                              style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${IdrCurrencyFormatter.formatQty(suggestedQty)} $unitCode',
                        style: TextStyle(fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).accent),
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton(
                        onPressed: () {
                          _openCreatePurchaseModal(
                            initialSupplierId: supId,
                            initialLines: [
                              {
                                'product_id': (s['product_id'] as num).toInt(),
                                'product_name': (s['name'] ?? 'Produk').toString(),
                                'sku': (s['sku'] ?? '-').toString(),
                                'unit_code': unitCode,
                                'quantity': suggestedQty,
                                'unit_cost': costPrice,
                              }
                            ],
                          );
                        },
                        child: const Text('Pesan'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
