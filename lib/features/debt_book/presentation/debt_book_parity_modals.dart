part of 'debt_book_screen.dart';

extension _DebtBookParityModalsExt on _DebtBookScreenState {
  void _showSettlementReceiptDialog({
    required bool isReceivable,
    required String partyName,
    required String phone,
    required String invoiceNumber,
    required double paidAmount,
    required double remainingBalance,
    required String paymentMethod,
  }) {
    final store = context.read<AuthCubit>().state.session.activeStore;
    final receiptText = _printer.formatSettlementReceipt(
      storeProfile: store.toJson(),
      type: isReceivable ? 'receivable' : 'payable',
      partyName: partyName,
      invoiceNumber: invoiceNumber,
      paidAmount: paidAmount,
      remainingBalance: remainingBalance,
      paymentMethod: paymentMethod,
      paidAt: DateTime.now().toIso8601String(),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isReceivable ? 'Kwitansi Piutang Tercatat' : 'Bukti Bayar Hutang Tercatat'),
        content: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.slate100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              receiptText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            ),
          ),
        ),
        actions: [
          if (phone.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                WhatsAppService.sendSettlementReceipt(
                  partyName: partyName,
                  phone: phone,
                  invoiceNumber: invoiceNumber,
                  paidAmount: paidAmount,
                  remainingBalance: remainingBalance,
                  paymentMethod: paymentMethod,
                  storeName: store.name,
                  isReceivable: isReceivable,
                );
              },
              icon: const Icon(Icons.chat_rounded, color: AppColors.successDark),
              label: const Text('Kirim WA'),
            ),
          FilledButton.icon(
            onPressed: () async {
              final ok = await _printer.printReceiptText(receiptText);
              if (ctx.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Kwitansi dikirim ke printer thermal.'
                        : 'Printer thermal belum terhubung.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.print_rounded, size: 17),
            label: const Text('Cetak'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _showInstallmentHistoryModal({
    required bool isReceivable,
    required Map<String, dynamic> invoice,
    required String partyName,
  }) async {
    final id = isReceivable
        ? ((invoice['sale_id'] as num?)?.toInt() ?? (invoice['id'] as num?)?.toInt() ?? 0)
        : ((invoice['purchase_id'] as num?)?.toInt() ?? (invoice['id'] as num?)?.toInt() ?? 0);
    var logs = (invoice['payments'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!_isLocalStandalone && id > 0) {
      try {
        final endpoint = isReceivable
            ? ApiEndpoints.receivablePayments(id)
            : ApiEndpoints.payablePayments(id);
        final res = await _api.dio.get(endpoint);
        final raw = res.data['data'] as List<dynamic>?;
        if (raw != null && raw.isNotEmpty) {
          logs = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Riwayat Cicilan • ${invoice['number'] ?? '-'}',
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            Text(partyName, style: const TextStyle(fontSize: 13, color: AppColors.slate600)),
            const SizedBox(height: 12),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('Belum ada riwayat cicilan untuk nota ini.',
                      style: TextStyle(color: AppColors.slate500)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final l = logs[idx];
                    final amt = (l['amount'] as num?)?.toDouble() ?? 0.0;
                    final method = (l['method_name'] ?? l['payment_method_name'] ?? 'Tunai').toString();
                    final date = (l['paid_at'] ?? l['payment_date'] ?? '-').toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(IdrCurrencyFormatter.format(amt),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.successDark)),
                      subtitle: Text('$method • $date'),
                      trailing: IconButton(
                        icon: const Icon(Icons.print_outlined, color: AppColors.primary),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showSettlementReceiptDialog(
                            isReceivable: isReceivable,
                            partyName: partyName,
                            phone: (invoice['customer']?['phone'] ?? invoice['supplier']?['phone'] ?? '').toString(),
                            invoiceNumber: (invoice['number'] ?? '-').toString(),
                            paidAmount: amt,
                            remainingBalance: (invoice['balance_due'] as num?)?.toDouble() ?? 0.0,
                            paymentMethod: method,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBatchSettlementModal({required bool isReceivable}) {
    final list = isReceivable ? _receivables : _payables;
    final Set<int> selectedIds = {};
    int? selectedMethodId =
        _paymentMethods.isNotEmpty ? (_paymentMethods.first['id'] as num?)?.toInt() : 1;
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          double totalSelected = 0;
          for (final item in list) {
            final id = isReceivable
                ? ((item['sale_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0)
                : ((item['purchase_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0);
            if (selectedIds.contains(id)) {
              totalSelected += (item['balance_due'] as num?)?.toDouble() ?? 0.0;
            }
          }

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isReceivable ? 'Pelunasan Gabungan Piutang' : 'Pelunasan Gabungan Hutang',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (_paymentMethods.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedMethodId,
                      decoration: const InputDecoration(labelText: 'Metode Pembayaran'),
                      items: _paymentMethods
                          .map((pm) => DropdownMenuItem<int>(
                                value: (pm['id'] as num).toInt(),
                                child: Text((pm['name'] ?? 'Tunai').toString()),
                              ))
                          .toList(),
                      onChanged: (v) => setModal(() => selectedMethodId = v),
                    ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, idx) {
                        final item = list[idx];
                        final id = isReceivable
                            ? ((item['sale_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0)
                            : ((item['purchase_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0);
                        final due = (item['balance_due'] as num?)?.toDouble() ?? 0.0;
                        final name = isReceivable
                            ? (item['customer']?['name'] ?? 'Pelanggan').toString()
                            : (item['supplier']?['name'] ?? 'Supplier').toString();
                        final checked = selectedIds.contains(id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setModal(() {
                              if (v == true) {
                                selectedIds.add(id);
                              } else {
                                selectedIds.remove(id);
                              }
                            });
                          },
                          title: Text('${item['number']} • $name',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          subtitle: Text('Sisa: ${IdrCurrencyFormatter.format(due)}'),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Dilunasi:', style: TextStyle(fontWeight: FontWeight.w700)),
                      NusaPriceTag(amount: totalSelected, fontSize: 17, color: AppColors.successDark),
                    ],
                  ),
                  if (modalError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              modalError!,
                              style: const TextStyle(
                                color: AppColors.dangerDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  NusaButton(
                    label: 'Lunasi ${selectedIds.length} Nota Terpilih',
                    variant: NusaButtonVariant.success,
                    isLoading: saving,
                    onPressed: (saving || selectedIds.isEmpty)
                        ? null
                        : () async {
                            setModal(() {
                              saving = true;
                              modalError = null;
                            });
                            final methodName = _methodNameById(selectedMethodId);
                            bool cloudOk = false;
                            if (!_isLocalStandalone && (await _connectivity.checkOnline())) {
                              try {
                                final endpoint = isReceivable
                                    ? ApiEndpoints.batchPayReceivables
                                    : ApiEndpoints.batchPayPayables;
                                final selectedRows = list.where((e) {
                                  final id = isReceivable
                                      ? ((e['sale_id'] as num?)?.toInt() ?? (e['id'] as num?)?.toInt() ?? 0)
                                      : ((e['purchase_id'] as num?)?.toInt() ?? (e['id'] as num?)?.toInt() ?? 0);
                                  return selectedIds.contains(id);
                                }).toList();

                                // Group selected invoices by party (customer_id or supplier_id) so each request
                                // satisfies backend batch-pay contract ({customer_id/supplier_id, payment_method_id, amount, allocations}).
                                final grouped = <int, List<Map<String, dynamic>>>{};
                                for (final row in selectedRows) {
                                  final partyId = isReceivable
                                      ? (((row['customer'] is Map ? row['customer']['id'] : null) ??
                                              row['customer_id']) as num?)
                                          ?.toInt() ??
                                          0
                                      : (((row['supplier'] is Map ? row['supplier']['id'] : null) ??
                                              row['supplier_id']) as num?)
                                          ?.toInt() ??
                                          0;
                                  grouped.putIfAbsent(partyId, () => []).add(row);
                                }

                                for (final entry in grouped.entries) {
                                  if (entry.key <= 0) continue;
                                  final rows = entry.value;
                                  final groupTotal = rows.fold<double>(
                                    0.0,
                                    (s, r) => s + ((r['balance_due'] as num?)?.toDouble() ?? 0.0),
                                  );
                                  if (groupTotal <= 0) continue;
                                  await _api.dio.post(
                                    endpoint,
                                    data: {
                                      if (isReceivable) 'customer_id': entry.key else 'supplier_id': entry.key,
                                      'payment_method_id': selectedMethodId ?? 1,
                                      'amount': groupTotal,
                                      'allocations': rows.map((e) {
                                        final due = (e['balance_due'] as num?)?.toDouble() ?? 0.0;
                                        return isReceivable
                                            ? {'sale_id': e['sale_id'] ?? e['id'], 'amount': due}
                                            : {'purchase_id': e['purchase_id'] ?? e['id'], 'amount': due};
                                      }).toList(),
                                    },
                                    options: Options(
                                      headers: {
                                        'X-Idempotency-Key': const Uuid().v4(),
                                      },
                                    ),
                                  );
                                }
                                cloudOk = grouped.keys.any((k) => k > 0);
                              } catch (e) {
                                if (!ApiClient.isNetworkOfflineError(e)) {
                                  if (!ctx.mounted) return;
                                  setModal(() {
                                    saving = false;
                                    modalError = ApiClient.extractErrorMessage(e);
                                  });
                                  return;
                                }
                              }
                            }
                            if (!cloudOk) {
                              for (final id in selectedIds) {
                                final match = list.where((e) {
                                  final eid = isReceivable
                                      ? ((e['sale_id'] as num?)?.toInt() ?? (e['id'] as num?)?.toInt() ?? 0)
                                      : ((e['purchase_id'] as num?)?.toInt() ?? (e['id'] as num?)?.toInt() ?? 0);
                                  return eid == id;
                                }).firstOrNull;
                                final due = (match?['balance_due'] as num?)?.toDouble() ?? 0.0;
                                if (due > 0) {
                                  if (isReceivable) {
                                    final custId =
                                        ((match?['customer'] is Map ? match!['customer']['id'] : null) ??
                                                match?['customer_id']) as num?;
                                    await _offlineDb.payLocalReceivable(
                                      saleId: id,
                                      saleLocalUuid: match?['local_uuid']?.toString(),
                                      amount: due,
                                      paymentMethod: methodName,
                                      paymentMethodId: selectedMethodId ?? 1,
                                      invoiceNumber: match?['number']?.toString(),
                                      customerName: (match?['customer']?['name'] ??
                                              match?['customer_name'] ??
                                              'Pelanggan')
                                          .toString(),
                                      customerId: custId?.toInt(),
                                      enqueueForCloudSync: !_isLocalStandalone,
                                    );
                                  } else {
                                    await _offlineDb.payLocalPayable(
                                      payableId: id,
                                      amount: due,
                                      paymentMethod: methodName,
                                    );
                                  }
                                }
                              }
                              _refreshPosPendingBadge();
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadData();
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showExpenseCategoriesManager() {
    final posCubit = context.read<PosCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Kelola Kategori Biaya',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                  FilledButton.icon(
                    onPressed: () {
                      final ctrl = TextEditingController();
                      showDialog(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Kategori Biaya Baru'),
                          content: TextField(
                            controller: ctrl,
                            autofocus: true,
                            decoration: const InputDecoration(labelText: 'Nama Kategori'),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Batal')),
                            FilledButton(
                              onPressed: () async {
                                final nm = ctrl.text.trim();
                                if (nm.isEmpty) return;
                                await posCubit.saveExpenseCategory({'name': nm});
                                if (dCtx.mounted) Navigator.pop(dCtx);
                                await _loadData();
                                setModal(() {});
                              },
                              child: const Text('Simpan'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _expenseCategories.length,
                  itemBuilder: (_, idx) {
                    final cat = _expenseCategories[idx];
                    final id = (cat['id'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      title: Text(cat['name'].toString()),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                        onPressed: () async {
                          await posCubit.deleteExpenseCategory(id);
                          await _loadData();
                          setModal(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditExpenseModal(Map<String, dynamic> exp) {
    final id = (exp['id'] as num?)?.toInt() ?? 0;
    final descCtrl = TextEditingController(text: (exp['description'] ?? '').toString());
    final amtCtrl = TextEditingController(
      text: ((exp['amount'] as num?)?.toDouble() ?? 0).toInt().toString(),
    );
    final catName = (exp['category']?['name'] ?? exp['category_name'] ?? 'Operasional Toko').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Biaya Operasional'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Keterangan')),
            const SizedBox(height: 10),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
              if (amt <= 0 || descCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              if (!_isLocalStandalone && (await _connectivity.checkOnline())) {
                try {
                  await _api.dio.put(ApiEndpoints.expenseDetail(id), data: {
                    'description': descCtrl.text.trim(),
                    'amount': amt,
                  });
                } catch (_) {}
              } else {
                await _offlineDb.updateLocalExpense(
                  id,
                  category: catName,
                  amount: amt,
                  description: descCtrl.text.trim(),
                );
              }
              await _loadData();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteExpense(Map<String, dynamic> exp) async {
    final id = (exp['id'] as num?)?.toInt() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Biaya?'),
        content: Text('Yakin hapus catatan "${exp['description']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_isLocalStandalone && (await _connectivity.checkOnline())) {
      try {
        await _api.dio.delete(ApiEndpoints.expenseDetail(id));
      } catch (_) {}
    } else {
      await _offlineDb.deleteLocalExpense(id);
    }
    await _loadData();
  }
}
