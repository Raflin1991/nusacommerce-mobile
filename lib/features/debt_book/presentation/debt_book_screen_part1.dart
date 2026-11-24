// ignore_for_file: invalid_use_of_protected_member
part of 'debt_book_screen.dart';

extension _DebtBookScreenStatePart1Ext on _DebtBookScreenState {

  String _methodNameById(int? id) {
    final found = _paymentMethods.firstWhere(
      (m) => (m['id'] as num?)?.toInt() == id,
      orElse: () => {'name': 'Tunai'},
    );
    return (found['name'] ?? 'Tunai').toString();
  }


  void _refreshPosPendingBadge() {
    if (!mounted) return;
    try {
      context.read<PosCubit>().refreshOfflinePendingState();
    } catch (_) {}
  }


  void _applyLocalDebtBookData() {
    final localRec = _offlineDb.getLocalReceivables();
    final cachedCloudRec = _offlineDb
        .getCachedCloudReceivables()
        .where((r) => ((r['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .toList();
    final mergedRec = <Map<String, dynamic>>[...localRec];
    final existingKeys = mergedRec
        .map((r) => '${r['sale_id'] ?? r['id'] ?? ''}|${r['number'] ?? ''}')
        .toSet();
    for (final cloudItem in cachedCloudRec) {
      final key = '${cloudItem['sale_id'] ?? cloudItem['id'] ?? ''}|${cloudItem['number'] ?? ''}';
      if (!existingKeys.contains(key)) {
        mergedRec.add(cloudItem);
        existingKeys.add(key);
      }
    }

    final localPay = _offlineDb
        .getLocalPayables()
        .where((p) => ((p['balance_due'] as num?)?.toDouble() ?? 0.0) > 0.5)
        .toList();
    final localExp = _offlineDb.getLocalExpenses();

    final recTotal = mergedRec.fold<double>(
      0.0,
      (sum, item) => sum + ((item['balance_due'] as num?)?.toDouble() ?? 0.0),
    );
    final payTotal = localPay.fold<double>(
      0.0,
      (sum, item) => sum + ((item['balance_due'] as num?)?.toDouble() ?? 0.0),
    );

    if (!mounted) return;
    setState(() {
      _totalReceivables = recTotal;
      _receivables = mergedRec;
      _totalPayables = payTotal;
      _payables = localPay;
      _expenses = localExp;
      final cachedExpCats = _offlineDb.getCachedExpenseCategories();
      _expenseCategories = cachedExpCats.isNotEmpty
          ? cachedExpCats
          : List<Map<String, dynamic>>.from(_defaultOfflineExpenseCategories);
      if (_paymentMethods.isEmpty) {
        _paymentMethods = List<Map<String, dynamic>>.from(_defaultOfflinePaymentMethods);
      }
      _error = null;
      _loading = false;
    });
  }


  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isLocalStandalone || !(await _connectivity.checkOnline())) {
      _applyLocalDebtBookData();
      return;
    }

    try {
      final results = await Future.wait([
        _repo.fetchReceivables(),
        _repo.fetchPayables(),
        _repo.fetchExpenses(),
        _repo.fetchPaymentMethods(),
      ]);

      final recData = Map<String, dynamic>.from((results[0].data['data'] as Map?) ?? {});
      final recSummary = Map<String, dynamic>.from((recData['summary'] as Map?) ?? {});
      final invoices = (recData['invoices'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Cache authoritative Cloud receivables locally so offline installment payments stay available
      await _offlineDb.cacheCloudReceivables(invoices);

      final payData = Map<String, dynamic>.from((results[1].data['data'] as Map?) ?? {});
      final paySummary = Map<String, dynamic>.from((payData['summary'] as Map?) ?? {});
      final payInvoices = (payData['invoices'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final expData = Map<String, dynamic>.from((results[2].data['data'] as Map?) ?? {});
      final exps = (expData['expenses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final cats = (expData['categories'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (cats.isNotEmpty) {
        await _offlineDb.cacheExpenseCategories(cats);
      }

      // Include any unsynced local expenses at the top until Cloud sync completes
      final unsyncedLocalExps = _offlineDb.getUnsyncedLocalExpenses();
      final mergedExps = <Map<String, dynamic>>[
        ...unsyncedLocalExps,
        ...exps,
      ];

      final methods = (results[3].data['data'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _totalReceivables = (recSummary['total_receivables'] as num?)?.toDouble() ?? 0;
        _receivables = invoices;
        _totalPayables = (paySummary['total_payables'] as num?)?.toDouble() ?? 0;
        _payables = payInvoices;
        _expenses = mergedExps;
        _expenseCategories = cats;
        _paymentMethods = methods;
        _loading = false;
      });
    } catch (e) {
      if (_isLocalStandalone ||
          _offlineDb.getLocalSalesHistory().isNotEmpty ||
          _offlineDb.getCachedCloudReceivables().isNotEmpty ||
          _offlineDb.getLocalPayables().isNotEmpty ||
          _offlineDb.getLocalExpenses().isNotEmpty) {
        _applyLocalDebtBookData();
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }


  void _showPayInstallmentModal(int index) {
    final item = _receivables[index];
    final currentDue = (item['balance_due'] as num?)?.toDouble() ?? 0;
    final customerName = (item['customer']?['name'] ?? item['customer_name'] ?? 'Pelanggan').toString();
    final customerId = ((item['customer'] is Map ? item['customer']['id'] : null) ??
            item['customer_id']) as num?;
    final saleId = (item['sale_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0;
    final saleLocalUuid = item['local_uuid']?.toString();
    final isLocalOnlySale = _isLocalStandalone || item['is_local'] == true || saleId > 1000000000;
    final amountCtrl = TextEditingController(text: currentDue.toStringAsFixed(0));
    int? selectedMethodId = _paymentMethods.isNotEmpty ? (_paymentMethods.first['id'] as num?)?.toInt() : 1;
    bool isSaving = false;
    String? modalError;
    final idempotencyKey = const Uuid().v4();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
              Text(
                'Catat Pembayaran Bon — $customerName',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Nota ${item['number']} • Sisa Tagihan: ${IdrCurrencyFormatter.format(currentDue)}',
                style: TextStyle(color: NusaThemeTokens.of(mCtx).textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
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
                  onChanged: isSaving ? null : (v) => setModalState(() => selectedMethodId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                enabled: !isSaving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nominal Dibayar (Rp)',
                  prefixIcon: Icon(Icons.payments_rounded, color: NusaThemeTokens.of(mCtx).positive),
                ),
              ),
              if (modalError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(mCtx).dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NusaThemeTokens.of(mCtx).danger.withOpacity(0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: NusaThemeTokens.of(mCtx).danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          modalError!,
                          style: TextStyle(
                            color: NusaThemeTokens.of(mCtx).danger,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: NusaThemeTokens.of(mCtx).positive),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final paid = IdrCurrencyFormatter.parse(amountCtrl.text);
                          if (paid <= 0 || selectedMethodId == null) {
                            setModalState(() => modalError = 'Masukkan nominal pembayaran yang valid (> 0).');
                            return;
                          }
                          setModalState(() {
                            isSaving = true;
                            modalError = null;
                          });

                          final methodName = _methodNameById(selectedMethodId);
                          final invNo = (item['number'] ?? 'BON-$saleId').toString();
                          final custPhone =
                              (item['customer']?['phone'] ?? item['customer_phone'] ?? '').toString();
                          final remain = (currentDue - paid).clamp(0.0, double.infinity);

                          Future<void> saveOfflineAndFinish() async {
                            await _offlineDb.payLocalReceivable(
                              saleId: saleId,
                              saleLocalUuid: saleLocalUuid,
                              amount: paid,
                              paymentMethod: methodName,
                              paymentMethodId: selectedMethodId ?? 1,
                              invoiceNumber: invNo,
                              customerName: customerName,
                              customerId: customerId?.toInt(),
                              enqueueForCloudSync: !_isLocalStandalone,
                              idempotencyKey: idempotencyKey,
                            );
                            _refreshPosPendingBadge();
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadData();
                            if (!mounted) return;
                            if (!_isLocalStandalone) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(mCtx).warning,
                                  content: Text(
                                    'Pelunasan piutang disimpan offline & masuk antrean sinkronisasi Cloud.',
                                  ),
                                ),
                              );
                            }
                            _showSettlementReceiptDialog(
                              isReceivable: true,
                              partyName: customerName,
                              phone: custPhone,
                              invoiceNumber: invNo,
                              paidAmount: paid,
                              remainingBalance: remain,
                              paymentMethod: methodName,
                            );
                          }

                          try {
                            if (isLocalOnlySale || !(await _connectivity.checkOnline())) {
                              await saveOfflineAndFinish();
                              return;
                            }
                            await _repo.payReceivable(
                              saleId,
                              {
                                'payment_method_id': selectedMethodId,
                                'amount': paid,
                              },
                              options: Options(
                                headers: {
                                  'X-Idempotency-Key': idempotencyKey,
                                },
                              ),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadData();
                            if (!mounted) return;
                            _showSettlementReceiptDialog(
                              isReceivable: true,
                              partyName: customerName,
                              phone: custPhone,
                              invoiceNumber: invNo,
                              paidAmount: paid,
                              remainingBalance: remain,
                              paymentMethod: methodName,
                            );
                          } catch (e) {
                            if (ApiClient.isNetworkOfflineError(e)) {
                              await saveOfflineAndFinish();
                              return;
                            }
                            if (!ctx.mounted) return;
                            setModalState(() {
                              isSaving = false;
                              modalError = ApiClient.extractErrorMessage(e);
                            });
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Simpan Pembayaran Piutang'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _showPaySupplierModal(int index) {
    final item = _payables[index];
    final currentDue = (item['balance_due'] as num?)?.toDouble() ?? 0;
    final supplierName = (item['supplier']?['name'] ?? item['supplier']?['business_name'] ?? 'Supplier').toString();
    final bankName = (item['supplier']?['bank_name'] ?? '-').toString();
    final bankAcc = (item['supplier']?['bank_account_number'] ?? '-').toString();
    final bankHolder = (item['supplier']?['bank_account_holder'] ?? '-').toString();
    final purchaseId = (item['purchase_id'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0;
    final isLocalItem = _isLocalStandalone || item['is_local'] == true;

    final amountCtrl = TextEditingController(text: currentDue.toInt().toString());
    final notesCtrl = TextEditingController();
    int? selectedMethodId = _paymentMethods.isNotEmpty
        ? (_paymentMethods.first['id'] as num).toInt()
        : 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
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
              Text(
                'Bayar Faktur Hutang — $supplierName',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Faktur: ${item['number']} • Sisa Hutang: ${IdrCurrencyFormatter.format(currentDue)}',
                style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(mCtx).textSecondary),
              ),
              if (bankName != '-' || bankAcc != '-') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(mCtx).accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_rounded, color: NusaThemeTokens.of(mCtx).accent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rekening Supplier: $bankName $bankAcc',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: NusaThemeTokens.of(mCtx).textPrimary),
                            ),
                            if (bankHolder != '-')
                              Text(
                                'a.n. $bankHolder',
                                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(mCtx).textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_paymentMethods.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: selectedMethodId,
                  decoration: const InputDecoration(labelText: 'Sumber Rekening / Metode Bayar'),
                  items: _paymentMethods
                      .map((m) => DropdownMenuItem<int>(
                            value: (m['id'] as num).toInt(),
                            child: Text((m['name'] ?? 'Transfer Bank').toString()),
                          ))
                      .toList(),
                  onChanged: (v) => setModalState(() => selectedMethodId = v),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nominal Dibayar (Rp)',
                  prefixIcon: Icon(Icons.payments_rounded, color: NusaThemeTokens.of(mCtx).accent),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Keterangan / Nomor Referensi Transfer',
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final paid = IdrCurrencyFormatter.parse(amountCtrl.text);
                    if (paid <= 0 || selectedMethodId == null) return;
                    final methodName = _methodNameById(selectedMethodId);
                    Navigator.pop(ctx);
                    try {
                      final invNo = (item['number'] ?? 'PO-$purchaseId').toString();
                      final suppPhone = (item['supplier']?['phone'] ?? '').toString();
                      final remain = (currentDue - paid).clamp(0.0, double.infinity);
                      if (isLocalItem || !(await _connectivity.checkOnline())) {
                        await _offlineDb.payLocalPayable(
                          payableId: purchaseId,
                          amount: paid,
                          paymentMethod: methodName,
                        );
                        await _loadData();
                        if (!mounted) return;
                        _showSettlementReceiptDialog(
                          isReceivable: false,
                          partyName: supplierName,
                          phone: suppPhone,
                          invoiceNumber: invNo,
                          paidAmount: paid,
                          remainingBalance: remain,
                          paymentMethod: methodName,
                        );
                        return;
                      }
                      await _repo.payPayable(
                        purchaseId,
                        {
                          'payment_method_id': selectedMethodId,
                          'amount': paid,
                          'reference': notesCtrl.text.trim(),
                        },
                      );
                      await _loadData();
                      if (!mounted) return;
                      _showSettlementReceiptDialog(
                        isReceivable: false,
                        partyName: supplierName,
                        phone: suppPhone,
                        invoiceNumber: invNo,
                        paidAmount: paid,
                        remainingBalance: remain,
                        paymentMethod: methodName,
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
                      );
                    }
                  },
                  child: const Text('Simpan Pembayaran Hutang'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
