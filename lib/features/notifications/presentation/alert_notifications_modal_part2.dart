// ignore_for_file: invalid_use_of_protected_member
part of 'alert_notifications_modal.dart';

extension _OperationalRadarSheetStatePart2Ext on _OperationalRadarSheetState {

  Widget _buildDeadLetterSection(List<Map<String, dynamic>> items) {
    return _buildSectionCard(
      title: 'Dead-Letter Queue / Gagal Sinkron (${items.length})',
      subtitle: 'Payload piutang, biaya, produk, atau tutup shift yang ditolak server dikarantina agar antrean lain tidak macet',
      icon: Icons.report_problem_outlined,
      accentColor: NusaThemeTokens.of(context).warning,
      softBgColor: NusaThemeTokens.of(context).warningSoft,
      child: Column(
        children: [
          if (_conflictInlineError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NusaThemeTokens.of(context).danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.4)),
              ),
              child: Text(
                _conflictInlineError!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: NusaThemeTokens.of(context).danger,
                ),
              ),
            ),
          if (_conflictInlineSuccess != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: NusaThemeTokens.of(context).positive.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.35)),
              ),
              child: Text(
                _conflictInlineSuccess!,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: NusaThemeTokens.of(context).positive,
                ),
              ),
            ),
          ...items.take(10).map((item) {
            final id = (item['id'] ?? '').toString();
            final title = (item['reference_label'] ?? item['title'] ?? item['entity_type'] ?? 'Payload Offline').toString();
            final entityType = (item['entity_type'] ?? '').toString();
            final errCode = (item['error_code'] ?? '').toString();
            final errMsg = (item['error_message'] ?? 'Ditolak oleh server').toString();
            final httpStatus = (item['http_status'] as num?)?.toInt() ?? 0;
            final busy = _processingConflictUuids.contains('dlq-$id');

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: NusaThemeTokens.of(context).bgPage,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NusaThemeTokens.of(context).warning.withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: NusaThemeTokens.of(context).textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: NusaThemeTokens.of(context).warning.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          httpStatus > 0 ? 'HTTP $httpStatus' : entityType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: NusaThemeTokens.of(context).warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    errMsg,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: NusaThemeTokens.of(context).danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            foregroundColor: NusaThemeTokens.of(context).danger,
                            side: BorderSide(color: NusaThemeTokens.of(context).danger.withOpacity(0.45)),
                          ),
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() {
                                    _processingConflictUuids.add('dlq-$id');
                                    _conflictInlineError = null;
                                    _conflictInlineSuccess = null;
                                  });
                                  await context.read<PosCubit>().discardDeadLetterItem(id);
                                  if (!mounted) return;
                                  setState(() {
                                    _processingConflictUuids.remove('dlq-$id');
                                    _conflictInlineSuccess = 'Item "$title" dibuang dari antrean.';
                                  });
                                },
                          child: const Text(
                            'Hapus dari Antrean',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            backgroundColor: NusaThemeTokens.of(context).accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() {
                                    _processingConflictUuids.add('dlq-$id');
                                    _conflictInlineError = null;
                                    _conflictInlineSuccess = null;
                                  });
                                  Map<String, dynamic>? overrides;
                                  if (entityType == 'shift_closure' &&
                                      errCode == 'VarianceReasonRequired') {
                                    overrides = {
                                      'variance_reason': 'miscount',
                                      'variance_notes': 'Rekonsiliasi selisih shift offline',
                                    };
                                  }
                                  final res = await context.read<PosCubit>().retryDeadLetterItem(
                                        id,
                                        payloadOverrides: overrides,
                                      );
                                  if (!mounted) return;
                                  setState(() {
                                    _processingConflictUuids.remove('dlq-$id');
                                    if (res.success) {
                                      _conflictInlineSuccess =
                                          'Item "$title" berhasil dikirim ulang ke Cloud.';
                                    } else {
                                      _conflictInlineError =
                                          res.errorMessage ?? 'Masih ditolak server.';
                                    }
                                  });
                                },
                          child: Text(
                            busy ? 'Mengirim...' : 'Coba Kirim Ulang',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }


  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color softBgColor,
    required Widget child,
  }) {
    final tokens = NusaThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: softBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }


  Widget _buildSafePill(String label) {
    final tokens = NusaThemeTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.positiveSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: tokens.positive),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.positive,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildVoidAndDiscountSection(List<Map<String, dynamic>> items) {
    final totalVoids = items.length + widget.voidCountFromServer;
    final hasAlert = totalVoids > 0;
    return _buildSectionCard(
      title: 'Radar Void & Diskon > Rp 50.000',
      subtitle: 'Audit transaksi batal dan potongan harga besar hari ini',
      icon: Icons.gpp_maybe_rounded,
      accentColor: hasAlert ? NusaThemeTokens.of(context).danger : NusaThemeTokens.of(context).positive,
      softBgColor: hasAlert ? NusaThemeTokens.of(context).danger.withOpacity(0.1) : NusaThemeTokens.of(context).positiveSoft,
      child: !hasAlert
          ? _buildSafePill('Aman • Tidak ada void atau diskon > Rp 50.000 hari ini')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.voidCountFromServer > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Server Audit Watch mendeteksi ${widget.voidCountFromServer} transaksi void.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: NusaThemeTokens.of(context).danger,
                      ),
                    ),
                  ),
                ...items.take(5).map((sale) {
                  final inv = (sale['number'] ?? sale['invoice_number'] ?? sale['code'] ?? 'NOTA').toString();
                  final status = (sale['status'] ?? '').toString().toUpperCase();
                  final discount = ((sale['discount_total'] ??
                          sale['discount_amount'] ??
                          sale['discount'] ??
                          0) as num)
                      .toDouble();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: NusaThemeTokens.of(context).bgPage,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            inv,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: NusaThemeTokens.of(context).textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          status == 'VOID'
                              ? 'STATUS VOID'
                              : 'Diskon ${IdrCurrencyFormatter.format(discount)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: NusaThemeTokens.of(context).danger,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }


  Widget _buildCashVarianceSection(BuildContext context) {
    final hasVariance = widget.varianceShiftsCount > 0;
    return _buildSectionCard(
      title: 'Radar Selisih Kasir (Shift Variance)',
      subtitle: 'Pantau perbedaan kas fisik laci dengan catatan sistem',
      icon: Icons.point_of_sale_rounded,
      accentColor: hasVariance ? NusaThemeTokens.of(context).warning : NusaThemeTokens.of(context).positive,
      softBgColor: hasVariance ? NusaThemeTokens.of(context).warningSoft : NusaThemeTokens.of(context).positiveSoft,
      child: !hasVariance
          ? _buildSafePill('Aman • Tidak ditemukan shift dengan selisih kas')
          : Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.varianceShiftsCount} shift ditutup dengan selisih kas laci.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: NusaThemeTokens.of(context).warning,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/shifts');
                  },
                  child: const Text('Buka Shift & Kas'),
                ),
              ],
            ),
    );
  }


  Widget _buildInventoryAndFefoSection(List<ProductModel> items) {
    final hasAlert = items.isNotEmpty;
    return _buildSectionCard(
      title: 'Radar Stok Menipis & FEFO (< 30 Hari)',
      subtitle: 'Barang mendekati stok minimum atau tanggal kedaluwarsa',
      icon: Icons.inventory_2_rounded,
      accentColor: hasAlert ? NusaThemeTokens.of(context).warning : NusaThemeTokens.of(context).positive,
      softBgColor: hasAlert ? NusaThemeTokens.of(context).warningSoft : NusaThemeTokens.of(context).positiveSoft,
      child: !hasAlert
          ? _buildSafePill('Aman • Stok produk & tanggal kedaluwarsa terkendali')
          : Column(
              children: items.take(8).map((p) {
                final badgeLabel = p.hasExpiringSoonBatch
                    ? 'FEFO < 30 Hari'
                    : 'Stok Menipis';
                final badgeColor =
                    p.hasExpiringSoonBatch ? NusaThemeTokens.of(context).danger : NusaThemeTokens.of(context).warning;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(context).bgPage,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: NusaThemeTokens.of(context).textPrimary,
                              ),
                            ),
                            Text(
                              'SKU: ${p.sku.isEmpty ? '-' : p.sku} • Sisa ${IdrCurrencyFormatter.formatQty(p.stock)} ${p.unitCode}',
                              style: TextStyle(
                                fontSize: 11,
                                color: NusaThemeTokens.of(context).textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }


  Widget _buildReceivablesSection(BuildContext context) {
    final hasOverdue = widget.overdueReceivables.isNotEmpty;
    return _buildSectionCard(
      title: 'Radar Piutang Jatuh Tempo',
      subtitle: 'Kirim pengingat tagihan WhatsApp langsung ke pelanggan',
      icon: Icons.receipt_long_rounded,
      accentColor: hasOverdue ? NusaThemeTokens.of(context).danger : NusaThemeTokens.of(context).positive,
      softBgColor: hasOverdue ? NusaThemeTokens.of(context).danger.withOpacity(0.1) : NusaThemeTokens.of(context).positiveSoft,
      child: !hasOverdue
          ? _buildSafePill('Aman • Tidak ada piutang jatuh tempo tertunggak')
          : Column(
              children: widget.overdueReceivables.take(6).map((item) {
                final customer = (item['customer'] as Map?) ?? const {};
                final customerName = (item['customer_name'] ??
                        customer['name'] ??
                        'Pelanggan')
                    .toString();
                final phone = (item['customer_phone'] ??
                        item['phone'] ??
                        customer['phone'] ??
                        '')
                    .toString();
                final invoiceNumber = (item['invoice_number'] ??
                        item['reference'] ??
                        item['code'] ??
                        'BON')
                    .toString();
                final dueDate =
                    (item['due_date'] ?? item['maturity_date'] ?? '-').toString();
                final balance = ((item['balance_due'] ??
                        item['remaining_amount'] ??
                        item['amount'] ??
                        0) as num)
                    .toDouble();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(context).bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              customerName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: NusaThemeTokens.of(context).textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            IdrCurrencyFormatter.format(balance),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: NusaThemeTokens.of(context).danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nota: $invoiceNumber • Jatuh Tempo: $dueDate',
                        style: TextStyle(
                          fontSize: 11,
                          color: NusaThemeTokens.of(context).textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await WhatsAppService.sendDebtReminder(
                                customerName: customerName,
                                customerPhone: phone,
                                invoiceNumber: invoiceNumber,
                                balanceDue: balance,
                                storeName: widget.storeName,
                              );
                              if (mounted) {
                                setState(() {
                                  _conflictInlineError = null;
                                  _conflictInlineSuccess = 'Membuka WhatsApp tagihan untuk $customerName.';
                                });
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _conflictInlineSuccess = null;
                                  _conflictInlineError = 'Gagal membuka WhatsApp: $e';
                                });
                              }
                            }
                          },
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text('Kirim Tagihan WA'),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
