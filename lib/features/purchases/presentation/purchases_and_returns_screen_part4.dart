// ignore_for_file: invalid_use_of_protected_member
part of 'purchases_and_returns_screen.dart';

extension _PurchasesAndReturnsScreenStatePart4Ext on _PurchasesAndReturnsScreenState {

  void _openPurchaseDetailModal(Map<String, dynamic> po) {
    final tokens = NusaThemeTokens.of(context);
    final total = (po['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paid = (po['paid_total'] as num?)?.toDouble() ?? 0.0;
    final balance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
    final isTempo = balance > 0.5;
    final poNumber = (po['number'] ?? po['purchase_number'] ?? '-').toString();
    final supplierName = (po['supplier_name'] ?? 'Pemasok Umum').toString();
    final purchaseDate = (po['purchase_date'] ?? '').toString().split('T').first;
    final dueDate = (po['due_date'] ?? '').toString().split('T').first;
    final invoiceNumber = (po['supplier_invoice_number'] ?? '').toString();
    final notes = (po['notes'] ?? '').toString();
    final status = (po['status'] ?? '').toString().toLowerCase();
    final isDraft = status == 'draft' || status == 'submitted' || status == 'approved';
    final isReceived = status == 'received' || status == 'partially_received' || status == 'partially_paid' || status == 'paid';
    final isFullyReturned = po['is_fully_returned'] == true || (isReceived && ((po['total_returnable_qty'] as num?)?.toDouble() ?? 1.0) <= 0.0001 && po['is_returnable'] == false);

    String detailBadgeLabel;
    NusaBadgeVariant detailBadgeVariant;
    if (isDraft) {
      detailBadgeLabel = status == 'draft' ? 'DRAF PO (BELUM DITERIMA)' : 'DIPESAN (MENUNGGU KIRIM)';
      detailBadgeVariant = NusaBadgeVariant.neutral;
    } else if (status == 'partially_received') {
      detailBadgeLabel = 'DITERIMA SEBAGIAN (PARSIAL)';
      detailBadgeVariant = NusaBadgeVariant.warning;
    } else if (status == 'cancelled') {
      detailBadgeLabel = 'DIBATALKAN';
      detailBadgeVariant = NusaBadgeVariant.danger;
    } else if (isFullyReturned) {
      detailBadgeLabel = 'SEMUA BARANG DIRETUR';
      detailBadgeVariant = NusaBadgeVariant.neutral;
    } else if (isTempo) {
      detailBadgeLabel = 'TEMPO / HUTANG';
      detailBadgeVariant = NusaBadgeVariant.warning;
    } else {
      detailBadgeLabel = 'DITERIMA • LUNAS';
      detailBadgeVariant = NusaBadgeVariant.success;
    }

    final items = (po['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poNumber,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pemasok: $supplierName',
                          style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  NusaBadge(
                    label: detailBadgeLabel,
                    variant: detailBadgeVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Ringkasan Finansial Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDraft
                      ? tokens.bgPage
                      : (isTempo ? NusaThemeTokens.of(ctx).warningSoft : NusaThemeTokens.of(ctx).positiveSoft),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDraft
                        ? tokens.borderDefault
                        : (isTempo
                            ? NusaThemeTokens.of(ctx).warning.withOpacity(0.3)
                            : NusaThemeTokens.of(ctx).positive.withOpacity(0.3)),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Nilai PO', style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(ctx).textPrimary)),
                        Text(
                          IdrCurrencyFormatter.format(total),
                          style: AppTheme.moneyStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sudah Dibayar', style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(ctx).textPrimary)),
                        Text(
                          IdrCurrencyFormatter.format(paid),
                          style: AppTheme.moneyStyle(
                            fontSize: 13.5,
                            color: NusaThemeTokens.of(ctx).positive,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isDraft
                              ? 'Status Tagihan'
                              : (isTempo ? 'Sisa Hutang Tempo' : 'Status Pelunasan'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isDraft
                                ? tokens.textSecondary
                                : (isTempo ? NusaThemeTokens.of(ctx).danger : NusaThemeTokens.of(ctx).positive),
                          ),
                        ),
                        Text(
                          isDraft
                              ? 'Belum Ditagihkan (Draft)'
                              : (isTempo ? IdrCurrencyFormatter.format(balance) : 'LUNAS'),
                          style: AppTheme.moneyStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDraft
                                ? tokens.textSecondary
                                : (isTempo ? NusaThemeTokens.of(ctx).danger : NusaThemeTokens.of(ctx).positive),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Detail Transaksi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.bgPage,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.borderDefault),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      'Status Barang',
                      isDraft
                          ? 'Belum Masuk Toko (Draft / Dipesan)'
                          : 'Barang Fisik Diterima di Toko',
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow('Tanggal Pembelian', purchaseDate.isNotEmpty ? purchaseDate : '-'),
                    if (isTempo && dueDate.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('Jatuh Tempo', dueDate),
                    ],
                    if (invoiceNumber.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('No. Faktur Pemasok', invoiceNumber),
                    ],
                    if ((po['delivery_note_number'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('No. Surat Jalan (DO)', po['delivery_note_number'].toString()),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildDetailRow('Catatan', notes),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Rincian Barang
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Rincian Barang Dipesan',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${items.length} Barang',
                    style: TextStyle(fontSize: 12.5, color: tokens.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tokens.bgPage,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      'Rincian barang per item tidak tersedia dalam cache ringkas.',
                      style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
                    ),
                  ),
                )
              else
                ...items.map((it) {
                  final name = (it['product_name'] ?? 'Barang').toString();
                  final sku = (it['sku'] ?? '-').toString();
                  final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
                  final cost = (it['unit_cost'] as num?)?.toDouble() ?? 0.0;
                  final lineTotal = (it['line_total'] as num?)?.toDouble() ?? (qty * cost);
                  final qtyStr = qty.truncateToDouble() == qty ? qty.toInt().toString() : qty.toStringAsFixed(1);
                  final retQty = (it['returned_quantity'] as num?)?.toDouble() ?? 0.0;
                  final recQty = (it['received_quantity'] as num?)?.toDouble() ?? (isReceived && status != 'partially_received' ? qty : 0.0);
                  final unrecQty = (it['unreceived_quantity'] as num?)?.toDouble() ?? (qty - recQty).clamp(0.0, double.infinity);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.bgPage,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.borderDefault),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'SKU: $sku • Dipesan: $qtyStr unit x ${IdrCurrencyFormatter.format(cost)}'
                                '${isReceived ? " • Diterima: ${IdrCurrencyFormatter.formatQty(recQty)}" : ""}'
                                '${unrecQty > 0.0001 && isReceived ? " • Sisa Belum: ${IdrCurrencyFormatter.formatQty(unrecQty)}" : ""}'
                                '${retQty > 0 ? " • Diretur: ${IdrCurrencyFormatter.formatQty(retQty)}" : ""}',
                                style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          IdrCurrencyFormatter.format(lineTotal),
                          style: AppTheme.moneyStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 20),
              // Action Buttons di Detail Modal
              if (po['can_receive'] == true || isDraft || status == 'partially_received') ...[
                NusaButton(
                  label: status == 'partially_received'
                      ? 'Terima Sisa Barang (GRN)'
                      : 'Konfirmasi Penerimaan Barang (GRN)',
                  icon: Icons.inventory_rounded,
                  variant: NusaButtonVariant.primary,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openReceivePurchaseModal(po);
                  },
                ),
                const SizedBox(height: 10),
              ],
              if (isReceived && isTempo) ...[
                NusaButton(
                  label: 'Bayar Tagihan PO (${IdrCurrencyFormatter.format(balance)})',
                  icon: Icons.payment_rounded,
                  variant: NusaButtonVariant.primary,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openPayPurchaseModal(po);
                  },
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  if (isReceived && !isFullyReturned) ...[
                    Expanded(
                      child: NusaButton(
                        label: 'Retur PO',
                        icon: Icons.assignment_return_outlined,
                        variant: NusaButtonVariant.outline,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openReturnPurchaseModal(po);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: NusaButton(
                      label: 'Tutup',
                      variant: NusaButtonVariant.ghost,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }


  void _openPayPurchaseModal(Map<String, dynamic> po) {
    final tokens = NusaThemeTokens.of(context);
    final purchaseId = (po['id'] as num?)?.toInt() ?? 0;
    final poNumber = (po['number'] ?? po['purchase_number'] ?? 'PO-$purchaseId').toString();
    final supplierName = (po['supplier_name'] ?? 'Pemasok Umum').toString();
    final currentBalance = (po['balance_due'] as num?)?.toDouble() ?? 0.0;
    final isLocalItem = _isLocalStandalone || po['is_local'] == true;

    final methods = _getPaymentMethods();
    int? selectedMethodId = methods.isNotEmpty ? (methods.first['id'] as num?)?.toInt() : 1;
    String selectedMethodName = methods.isNotEmpty ? (methods.first['name'] ?? 'Tunai').toString() : 'Tunai';

    final amountCtrl = TextEditingController(text: currentBalance.toInt().toString());
    final notesCtrl = TextEditingController();
    bool paying = false;
    String? payError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) => Padding(
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
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.payment_rounded, color: tokens.accent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bayar Tagihan PO',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '$poNumber • $supplierName',
                          style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Card Sisa Tagihan
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NusaThemeTokens.of(mCtx).dangerSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NusaThemeTokens.of(mCtx).danger.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sisa Hutang Tagihan:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NusaThemeTokens.of(mCtx).textPrimary),
                    ),
                    Text(
                      IdrCurrencyFormatter.format(currentBalance),
                      style: AppTheme.moneyStyle(fontSize: 15, color: NusaThemeTokens.of(mCtx).danger, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Input Nominal
              const Text(
                'Nominal Pembayaran (Rp)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: 'Rp ',
                  hintText: '0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              // Quick Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildPayQuickChip('25%', currentBalance * 0.25, amountCtrl, setModalState),
                    const SizedBox(width: 6),
                    _buildPayQuickChip('50%', currentBalance * 0.50, amountCtrl, setModalState),
                    const SizedBox(width: 6),
                    _buildPayQuickChip('75%', currentBalance * 0.75, amountCtrl, setModalState),
                    const SizedBox(width: 6),
                    _buildPayQuickChip('Lunas (100%)', currentBalance, amountCtrl, setModalState),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Metode Pembayaran
              const Text(
                'Sumber Dana / Metode Pembayaran',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: selectedMethodId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: methods.map((m) {
                  final id = (m['id'] as num).toInt();
                  final name = (m['name'] ?? 'Metode').toString();
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setModalState(() {
                      selectedMethodId = val;
                      final match = methods.firstWhere(
                        (e) => (e['id'] as num).toInt() == val,
                        orElse: () => {'name': 'Tunai'},
                      );
                      selectedMethodName = (match['name'] ?? 'Tunai').toString();
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // Catatan / Referensi
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Catatan / Referensi Transfer (Opsional)',
                  hintText: 'Misal: Transfer via BCA / Mandiri',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              if (payError != null) ...[
                const SizedBox(height: 10),
                Text(
                  payError!,
                  style: TextStyle(color: NusaThemeTokens.of(mCtx).danger, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 18),
              NusaButton(
                label: 'Konfirmasi Pembayaran PO',
                isLoading: paying,
                variant: NusaButtonVariant.success,
                icon: Icons.check_circle_rounded,
                onPressed: paying
                    ? null
                    : () async {
                        final paidAmount = IdrCurrencyFormatter.parse(amountCtrl.text);
                        if (paidAmount <= 0) {
                          setModalState(() => payError = 'Masukkan nominal pembayaran yang valid (> 0).');
                          return;
                        }
                        if (paidAmount > currentBalance + 1.0) {
                          setModalState(() => payError = 'Nominal bayar tidak boleh melebihi sisa hutang.');
                          return;
                        }

                        setModalState(() {
                          paying = true;
                          payError = null;
                        });

                        try {
                          final isOnline = !_isLocalStandalone && (await _connectivity.checkOnline());
                          bool cloudSuccess = false;

                          if (isOnline && !isLocalItem && purchaseId > 0) {
                            try {
                              await _repo.payPayable(
                                purchaseId,
                                {
                                  'payment_method_id': selectedMethodId ?? 1,
                                  'amount': paidAmount,
                                  'reference': notesCtrl.text.trim().isNotEmpty
                                      ? notesCtrl.text.trim()
                                      : 'Bayar PO $poNumber',
                                  'notes': notesCtrl.text.trim(),
                                },
                              );
                              cloudSuccess = true;
                            } catch (e) {
                              if (!ApiClient.isNetworkOfflineError(e)) {
                                final errMsg = ApiClient.extractErrorMessage(e);
                                setModalState(() {
                                  paying = false;
                                  payError = errMsg;
                                });
                                return;
                              }
                            }
                          }

                          if (!cloudSuccess) {
                            await _offlineDb.payLocalPayable(
                              payableId: purchaseId,
                              amount: paidAmount,
                              paymentMethod: selectedMethodName,
                              invoiceNumber: poNumber,
                            );
                          }

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          await _loadData();

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: NusaThemeTokens.of(mCtx).positive,
                                content: Text(
                                  'Pembayaran $poNumber sebesar ${IdrCurrencyFormatter.format(paidAmount)} berhasil dicatat!',
                                ),
                              ),
                            );
                          }
                        } catch (err) {
                          setModalState(() {
                            paying = false;
                            payError = err.toString();
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(context).textSecondary)),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
