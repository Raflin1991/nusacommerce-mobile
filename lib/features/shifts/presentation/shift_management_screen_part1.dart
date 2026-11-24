// ignore_for_file: invalid_use_of_protected_member
part of 'shift_management_screen.dart';

extension _ShiftManagementScreenStatePart1Ext on _ShiftManagementScreenState {

  void _refreshPosPendingBadge() {
    if (!mounted) return;
    try {
      context.read<PosCubit>().refreshOfflinePendingState();
    } catch (_) {}
  }


  void _updateDenom(int denom, int delta) {
    if (_isBlindCountLocked) return;
    setState(() {
      final current = _denomCounts[denom] ?? 0;
      _denomCounts[denom] = (current + delta).clamp(0, 9999);
      final total = _denomCounts.entries.fold<double>(
        0.0,
        (sum, e) => sum + (e.key * e.value),
      );
      _countedCashCtrl.text = IdrCurrencyFormatter.format(total);
    });
  }


  void _resetDenoms() {
    if (_isBlindCountLocked) return;
    setState(() {
      for (final key in _denomCounts.keys) {
        _denomCounts[key] = 0;
      }
      _countedCashCtrl.clear();
    });
  }


  List<Map<String, String>> _parseVarianceReasons(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      final parsed = <Map<String, String>>[];
      for (final item in raw) {
        if (item is Map) {
          final code = (item['code'] ?? '').toString().trim();
          final name = (item['name'] ?? code).toString().trim();
          if (code.isNotEmpty) {
            parsed.add({'code': code, 'name': name});
          }
        }
      }
      if (parsed.isNotEmpty) return parsed;
    }
    return _varianceReasons;
  }


  void _applyLocalShiftState(Map<String, dynamic>? localShift) {
    if (!mounted) return;
    if (localShift != null) {
      final rawEntries = (localShift['entries'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _hasOpenShift = true;
        _blindDropEnforced = false;
        _canViewExpectedCash = true;
        _shiftId = (localShift['id'] as num?)?.toInt();
        _terminalLabel = 'Kasir Mandiri Lokal';
        _openingCash = (localShift['opening_cash'] as num?)?.toDouble() ?? 0.0;
        _cashSales = (localShift['cash_sales'] as num?)?.toDouble() ?? 0.0;
        _expectedCash = (localShift['expected_cash'] as num?)?.toDouble() ?? 0.0;
        _payIns = (localShift['cash_in'] as num?)?.toDouble() ?? 0.0;
        _payOuts = (localShift['cash_out'] as num?)?.toDouble() ?? 0.0;
        _salesCount = (localShift['sales_count'] as num?)?.toInt() ?? 0;
        _drawerEntries = rawEntries;
        _terminals = [];
        _isBlindCountLocked = false;
        _requiresVarianceReason = false;
        _closeError = null;
        _error = null;
        _loading = false;
      });
    } else {
      setState(() {
        _hasOpenShift = false;
        _shiftId = null;
        _terminalLabel = 'Kasir Mandiri Lokal';
        _openingCash = 0;
        _cashSales = null;
        _expectedCash = null;
        _payIns = 0;
        _payOuts = 0;
        _salesCount = 0;
        _drawerEntries = [];
        _terminals = [];
        _isBlindCountLocked = false;
        _requiresVarianceReason = false;
        _closeError = null;
        _error = null;
        _loading = false;
      });
    }
  }


  Future<void> _loadCurrentShift() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isLocalStandalone) {
      _applyLocalShiftState(_offlineDb.getCurrentLocalShift());
      return;
    }

    try {
      // BUG 6 FIX: Flush any queued offline shift closures (and preceding offline sales)
      // BEFORE querying Cloud shift status so Cloud closes the old shift automatically.
      if (_offlineDb.pendingShiftClosuresCount > 0) {
        await _offlineDb.syncOfflineQueue(_api);
        _refreshPosPendingBadge();
      }

      final res = await _repo.fetchCurrentShift();
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final hasShift = data['has_open_shift'] == true && data['shift'] != null;
      final terms = (data['terminals'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final reasons = _parseVarianceReasons(data['variance_reasons']);
      final topBlind = data['blind_drop_enforced'] == true;
      final topCanView = data['can_view_expected_cash'] == true;

      if (hasShift) {
        final s = Map<String, dynamic>.from(data['shift'] as Map);
        final term = s['terminal'] as Map?;
        final entries = (s['entries'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final rawExpected = s['expected_cash'];
        final rawCashSales = s['cash_sales'] ?? s['sales_total'];
        final blindDrop = s['blind_drop_enforced'] == true ||
            (topBlind && rawExpected == null);
        final canView = s['can_view_expected_cash'] == true ||
            (topCanView && rawExpected != null);

        if (!mounted) return;
        setState(() {
          _hasOpenShift = true;
          _blindDropEnforced = blindDrop;
          _canViewExpectedCash = canView && rawExpected != null;
          _shiftId = (s['id'] as num?)?.toInt();
          _terminalLabel = (term?['name'] ?? 'POS').toString();
          _openingCash = (s['opening_cash'] as num?)?.toDouble() ?? 0;
          _cashSales =
              canView && rawCashSales is num ? rawCashSales.toDouble() : null;
          _expectedCash =
              canView && rawExpected is num ? rawExpected.toDouble() : null;
          _payIns = (s['pay_ins'] as num?)?.toDouble() ?? 0;
          _payOuts = (s['pay_outs'] as num?)?.toDouble() ?? 0;
          _salesCount = (s['sales_count'] as num?)?.toInt() ?? 0;
          _drawerEntries = entries;
          _terminals = terms;
          _varianceReasons = reasons;
          _isBlindCountLocked = false;
          _requiresVarianceReason = false;
          _closeError = null;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasOpenShift = false;
          _blindDropEnforced = topBlind;
          _canViewExpectedCash = topCanView;
          _shiftId = null;
          _terminals = terms;
          _varianceReasons = reasons;
          _drawerEntries = [];
          _openingCash = 0;
          _cashSales = null;
          _expectedCash = null;
          _payIns = 0;
          _payOuts = 0;
          _salesCount = 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (!ApiClient.isNetworkOfflineError(e)) {
        if (!mounted) return;
        setState(() {
          _error = ApiClient.extractErrorMessage(e);
          _loading = false;
        });
        return;
      }
      final localShift = _offlineDb.getCurrentLocalShift();
      final localId = (localShift?['id'] as num?)?.toInt();
      if (_offlineDb.hasPendingClosureForShift(localId ?? _shiftId)) {
        _applyLocalShiftState(null);
      } else {
        _applyLocalShiftState(localShift);
      }
    }
  }


  Future<void> _showOpenShiftDialog() async {
    final openCtrl = TextEditingController(text: '500000');
    int? selectedTerminalId = _terminals.isNotEmpty
        ? (_terminals.first['id'] as num?)?.toInt()
        : null;
    String? modalError;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setModalState) {
          final tokens = NusaThemeTokens.of(dCtx);
          return AlertDialog(
            title: const Text('Buka Shift Kasir',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_terminals.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedTerminalId,
                      decoration:
                          const InputDecoration(labelText: 'Terminal Kasir'),
                      items: _terminals
                          .map((t) => DropdownMenuItem<int>(
                                value: (t['id'] as num).toInt(),
                                child: Text((t['name'] ?? 'Terminal').toString()),
                              ))
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => setModalState(() => selectedTerminalId = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: openCtrl,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setModalState(() => modalError = null),
                    decoration: const InputDecoration(
                        labelText: 'Modal Awal Kasir (Rp)'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in const [
                        ('Rp 200rb', '200000'),
                        ('Rp 300rb', '300000'),
                        ('Rp 500rb', '500000'),
                        ('Rp 1 Jt', '1000000'),
                      ])
                        NusaPillFilter(
                          label: preset.$1,
                          selected: IdrCurrencyFormatter.parse(openCtrl.text) ==
                              double.parse(preset.$2),
                          onTap: () => setModalState(() {
                            openCtrl.text = preset.$2;
                            modalError = null;
                          }),
                        ),
                    ],
                  ),
                  if (modalError != null) ...[
                    const SizedBox(height: 12),
                    _inlineModalErrorBox(tokens, modalError!),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final opening =
                            IdrCurrencyFormatter.parse(openCtrl.text);
                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });
                        try {
                          if (_isLocalStandalone) {
                            await _offlineDb.openLocalShift(
                              openingCash: opening,
                              cashierName:
                                  context.read<AuthCubit>().state.session.userName,
                            );
                          } else {
                            // BUG 6 FIX: Automatically flush pending offline shift closures
                            // (and preceding offline sales) to Cloud BEFORE opening a new shift!
                            if (_offlineDb.pendingShiftClosuresCount > 0) {
                              await _offlineDb.syncOfflineQueue(_api);
                              _refreshPosPendingBadge();
                              final rejectedClosure = _offlineDb
                                  .getDeadLetterItems()
                                  .where((d) => d['entity_type'] == 'shift_closure')
                                  .firstOrNull;
                              if (rejectedClosure != null) {
                                setModalState(() {
                                  saving = false;
                                  modalError =
                                      'Penutupan shift sebelumnya ditolak server (${rejectedClosure['error_message'] ?? 'butuh alasan selisih'}). Selesaikan di Antrean Sinkronisasi / Notifikasi terlebih dahulu.';
                                });
                                return;
                              }
                            }
                            await _repo.openShift(
                              {
                                'opening_cash': opening,
                                if (selectedTerminalId != null)
                                  'terminal_id': selectedTerminalId,
                              },
                              options: Options(
                                headers: {
                                  'X-Idempotency-Key': const Uuid().v4(),
                                },
                              ),
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadCurrentShift();
                        } catch (e) {
                          if (!ApiClient.isNetworkOfflineError(e)) {
                            setModalState(() {
                              saving = false;
                              modalError = ApiClient.extractErrorMessage(e);
                            });
                            return;
                          }
                          await _offlineDb.openLocalShift(
                            openingCash: opening,
                            cashierName:
                                context.read<AuthCubit>().state.session.userName,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadCurrentShift();
                        }
                      },
                child: Text(saving ? 'Membuka...' : 'Buka Shift'),
              ),
            ],
          );
        },
      ),
    );
  }


  void _showAddCashEntryModal(String type) {
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final isIn = type == 'pay_in';
    String? modalError;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (mCtx, setModalState) {
          final tokens = NusaThemeTokens.of(mCtx);
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(mCtx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIn
                      ? 'Catat Kas Masuk Laci (Pay-In)'
                      : 'Catat Kas Keluar Laci (Pay-Out)',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Nominal Uang Tunai (Rp)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: isIn
                        ? 'Keterangan (misal: Tambah receh modal)'
                        : 'Alasan (misal: Beli es batu / galon)',
                  ),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  _inlineModalErrorBox(tokens, modalError!),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isIn ? tokens.positive : tokens.danger,
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            final amt = IdrCurrencyFormatter.parse(amtCtrl.text);
                            if (amt <= 0 || reasonCtrl.text.trim().isEmpty) {
                              setModalState(() => modalError =
                                  'Isi nominal (> Rp 0) dan alasan mutasi kas.');
                              return;
                            }
                            setModalState(() {
                              saving = true;
                              modalError = null;
                            });
                            try {
                              if (_isLocalStandalone) {
                                await _offlineDb.addLocalShiftCashEntry(
                                  type: type,
                                  amount: amt,
                                  reason: reasonCtrl.text.trim(),
                                );
                              } else {
                                await _repo.addShiftCashEntry(
                                  {
                                    'shift_id': _shiftId,
                                    'type': type,
                                    'amount': amt,
                                    'reason': reasonCtrl.text.trim(),
                                  },
                                );
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadCurrentShift();
                            } catch (e) {
                              if (!ApiClient.isNetworkOfflineError(e)) {
                                setModalState(() {
                                  saving = false;
                                  modalError = ApiClient.extractErrorMessage(e);
                                });
                                return;
                              }
                              await _offlineDb.addLocalShiftCashEntry(
                                type: type,
                                amount: amt,
                                reason: reasonCtrl.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadCurrentShift();
                            }
                          },
                    child: Text(saving
                        ? 'Menyimpan...'
                        : (isIn ? 'Simpan Kas Masuk' : 'Simpan Kas Keluar')),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }


  Future<void> _recordNoSaleDrawerOpen() async {
    if (!_hasOpenShift || _submitting) return;
    final reasonCtrl =
        TextEditingController(text: 'Tukar uang kembalian / cek fisik laci');
    String? modalError;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (mCtx, setModalState) {
          final tokens = NusaThemeTokens.of(mCtx);
          return AlertDialog(
            title: const Text('Buka Laci Tanpa Transaksi (No-Sale)',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: reasonCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Alasan Buka Laci (Audit Anti-Fraud)',
                  ),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  _inlineModalErrorBox(tokens, modalError!),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dCtx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final reasonText = reasonCtrl.text.trim().isEmpty
                            ? 'Buka laci manual (No-Sale)'
                            : reasonCtrl.text.trim();
                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });
                        try {
                          if (_isLocalStandalone) {
                            await _offlineDb.addLocalShiftCashEntry(
                              type: 'drawer_open_no_sale',
                              amount: 0,
                              reason: reasonText,
                            );
                          } else {
                            await _repo.addShiftCashEntry(
                              {
                                'shift_id': _shiftId,
                                'type': 'drawer_open_no_sale',
                                'amount': 0,
                                'reason': reasonText,
                              },
                            );
                          }
                        } catch (e) {
                          if (!ApiClient.isNetworkOfflineError(e)) {
                            setModalState(() {
                              saving = false;
                              modalError = ApiClient.extractErrorMessage(e);
                            });
                            return;
                          }
                          await _offlineDb.addLocalShiftCashEntry(
                            type: 'drawer_open_no_sale',
                            amount: 0,
                            reason: reasonText,
                          );
                        }
                        if (dCtx.mounted) Navigator.pop(dCtx);
                        final kicked = await _printer.kickCashDrawer();
                        await _loadCurrentShift();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor:
                                  kicked ? NusaThemeTokens.of(context).positive : null,
                              content: Text(
                                kicked
                                    ? 'Laci kasir RJ-11 dibuka via Bluetooth & kejadian No-Sale dicatat untuk audit.'
                                    : 'Kejadian No-Sale dicatat untuk audit.',
                              ),
                            ),
                          );
                        }
                      },
                child: Text(saving ? 'Memproses...' : 'Kirim Pulse & Buka'),
              ),
            ],
          );
        },
      ),
    );
  }
}
