// ignore_for_file: invalid_use_of_protected_member
part of 'debt_book_screen.dart';

extension _DebtBookScreenStatePart2Ext on _DebtBookScreenState {

  void _showAddExpenseModal() {
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    int? selectedCatId = _expenseCategories.isNotEmpty ? (_expenseCategories.first['id'] as num?)?.toInt() : null;
    bool isSaving = false;
    String? modalError;
    final idempotencyKey = const Uuid().v4();
    const presetLabels = [
      'Listrik',
      'Air',
      'Gaji Harian Kasir',
      'Kantong Kresek',
      'Konsumsi',
      'Transport',
      'Perawatan Toko',
    ];

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catat Biaya Operasional Toko',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'Kategori Cepat:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(mCtx).textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presetLabels.map((preset) {
                    return NusaPillFilter(
                      label: preset,
                      selected: descCtrl.text.trim() == preset,
                      onTap: () {
                        if (isSaving) return;
                        descCtrl.text = preset;
                        setModalState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (_expenseCategories.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: selectedCatId,
                    decoration: const InputDecoration(labelText: 'Pos Biaya Akuntansi'),
                    items: _expenseCategories
                        .map((c) => DropdownMenuItem<int>(
                              value: (c['id'] as num).toInt(),
                              child: Text((c['name'] ?? 'Operasional').toString()),
                            ))
                        .toList(),
                    onChanged: isSaving ? null : (v) => setModalState(() => selectedCatId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: descCtrl,
                  enabled: !isSaving,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan Biaya / Pengeluaran *',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amtCtrl,
                  enabled: !isSaving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nominal Pengeluaran (Rp) *',
                    prefixIcon: Icon(Icons.payments_outlined),
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
                    onPressed: isSaving
                        ? null
                        : () async {
                            final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                            final desc = descCtrl.text.trim();
                            if (amt <= 0 || desc.isEmpty) {
                              setModalState(() => modalError = 'Lengkapi keterangan dan nominal (> 0).');
                              return;
                            }
                            setModalState(() {
                              isSaving = true;
                              modalError = null;
                            });
                            final chosenCatName = _expenseCategories
                                .firstWhere(
                                  (c) => (c['id'] as num?)?.toInt() == selectedCatId,
                                  orElse: () => {'name': 'Operasional Toko'},
                                )['name']
                                .toString();

                            Future<void> saveOfflineExpenseAndFinish() async {
                              await _offlineDb.addLocalExpense(
                                category: chosenCatName,
                                categoryId: selectedCatId,
                                amount: amt,
                                description: desc,
                                paymentMethod: 'Tunai',
                                localUuid: idempotencyKey,
                                isSynced: false,
                              );
                              _refreshPosPendingBadge();
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor:
                                      _isLocalStandalone ? NusaThemeTokens.of(mCtx).positive : NusaThemeTokens.of(mCtx).warning,
                                  content: Text(
                                    _isLocalStandalone
                                        ? 'Biaya operasional dicatat secara lokal!'
                                        : 'Biaya disimpan offline & akan otomatis disinkronkan ke Cloud saat online.',
                                  ),
                                ),
                              );
                            }

                            try {
                              if (_isLocalStandalone || !(await _connectivity.checkOnline())) {
                                await saveOfflineExpenseAndFinish();
                                return;
                              }
                              await _repo.createExpense(
                                {
                                  'category_id': selectedCatId,
                                  'amount': amt,
                                  'description': desc,
                                },
                                options: Options(
                                  headers: {
                                    'X-Idempotency-Key': idempotencyKey,
                                  },
                                ),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                            } catch (e) {
                              if (ApiClient.isNetworkOfflineError(e)) {
                                await saveOfflineExpenseAndFinish();
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
                        : const Text('Simpan Biaya Operasional'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
