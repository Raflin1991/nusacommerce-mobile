// ignore_for_file: invalid_use_of_protected_member
part of 'shift_management_screen.dart';

extension _ShiftManagementScreenStatePart2Ext on _ShiftManagementScreenState {

  void _showThermalZReportDialog(Map<String, dynamic> zReport) {
    final session = context.read<AuthCubit>().state.session;
    final storeProfile = _offlineDb.getStoreProfile();
    String selectedWidth = _printer.paperWidth;

    final openCash = (zReport['opening_cash'] as num?)?.toDouble() ?? _openingCash;
    final cashSales = (zReport['cash_sales'] as num?)?.toDouble() ??
        (zReport['sales_total'] as num?)?.toDouble() ??
        0;
    final payIns = (zReport['pay_ins'] as num?)?.toDouble() ?? _payIns;
    final payOuts = (zReport['pay_outs'] as num?)?.toDouble() ?? _payOuts;
    final expected = (zReport['expected_cash'] as num?)?.toDouble() ?? 0;
    final counted = (zReport['counted_cash'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final tokens = NusaThemeTokens.of(ctx);
          final text = _printer.formatShiftZReportText(
            storeProfile: storeProfile,
            cashierName: session.userName,
            openingCash: openCash,
            cashSalesTotal: cashSales,
            payInTotal: payIns,
            payOutTotal: payOuts,
            expectedCash: expected,
            countedCash: counted,
            paperWidthOverride: selectedWidth,
          );
          return AlertDialog(
            title: Text('Struk Z-Report Thermal ($selectedWidth)',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NusaPillFilter(
                        label: '58mm',
                        selected: selectedWidth == '58mm',
                        onTap: () => setModalState(() {
                          selectedWidth = '58mm';
                          _printer.savePreferences(width: '58mm');
                        }),
                      ),
                      const SizedBox(width: 8),
                      NusaPillFilter(
                        label: '80mm',
                        selected: selectedWidth == '80mm',
                        onTap: () => setModalState(() {
                          selectedWidth = '80mm';
                          _printer.savePreferences(width: '80mm');
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tokens.bgElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: tokens.borderSubtle, width: tokens.borderWidth),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final ok =
                      await _printer.printReceiptText(text, openCashDrawer: false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: ok ? tokens.positive : tokens.warning,
                      content: Text(
                        ok
                            ? 'Struk Z-Report ($selectedWidth) dikirim ke printer Bluetooth!'
                            : 'Printer Bluetooth tidak terhubung. Cek Pengaturan > Printer.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.print_rounded, size: 17),
                label: const Text('Cetak Bluetooth'),
              ),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
  }


  Future<void> _closeShiftAndSendZReport() async {
    if (!_hasOpenShift) return;
    if (_countedCashCtrl.text.trim().isEmpty || !_isBlindCountLocked) {
      setState(() {
        _closeError =
            'Masukkan uang fisik di laci dan tekan "Kunci Hitungan Fisik" terlebih dahulu (Strict Blind Drop).';
      });
      return;
    }
    if (_requiresVarianceReason &&
        (_selectedVarianceReason == null || _selectedVarianceReason!.isEmpty)) {
      setState(() {
        _closeError =
            'Server mendeteksi selisih kas di luar toleransi. Pilih alasan selisih untuk menyelesaikan tutup shift.';
      });
      return;
    }

    final counted = IdrCurrencyFormatter.parse(_countedCashCtrl.text);
    final session = context.read<AuthCubit>().state.session;

    setState(() {
      _submitting = true;
      _closeError = null;
    });

    Map<String, dynamic>? closedZReport;

    try {
      if (_isLocalStandalone) {
        await _offlineDb.closeLocalShift(actualClosingCash: counted);
        final exp = _expectedCash ?? 0;
        final diff = counted - exp;
        closedZReport = {
          'shift_id': _shiftId ?? 0,
          'status': diff.abs() > 0 ? 'closed_with_variance' : 'closed',
          'variance_status':
              diff == 0 ? 'balanced' : (diff > 0 ? 'overage' : 'shortage'),
          'opening_cash': _openingCash,
          'cash_sales': _cashSales ?? 0,
          'sales_total': _cashSales ?? 0,
          'pay_ins': _payIns,
          'pay_outs': _payOuts,
          'expected_cash': exp,
          'counted_cash': counted,
          'cash_variance': diff,
          'cash_shortage': diff < 0 ? diff.abs() : 0.0,
          'cash_overage': diff > 0 ? diff : 0.0,
        };
      } else {
        final closeIdempotencyKey = const Uuid().v4();
        try {
          // Strict Blind Drop: send ONLY counted physical cash & denominations;
          // server computes authoritative expected_cash & variance.
          final res = await _repo.closeShift(
            {
              'shift_id': _shiftId,
              'closing_cash_counted': counted,
              'closing_denominations':
                  _denomCounts.map((k, v) => MapEntry(k.toString(), v)),
              if (_selectedVarianceReason != null &&
                  _selectedVarianceReason!.isNotEmpty)
                'variance_reason': _selectedVarianceReason,
              if (_varianceNotesCtrl.text.trim().isNotEmpty)
                'variance_notes': _varianceNotesCtrl.text.trim(),
            },
            options: Options(
              headers: {
                'X-Idempotency-Key': closeIdempotencyKey,
              },
            ),
          );
          final body = res.data is Map
              ? Map<String, dynamic>.from(res.data as Map)
              : <String, dynamic>{};
          final shiftData = Map<String, dynamic>.from((body['data'] as Map?) ?? {});
          final serverZ = shiftData['z_report'];
          if (serverZ is Map) {
            closedZReport = Map<String, dynamic>.from(serverZ);
          } else {
            final exp = (shiftData['expected_cash'] as num?)?.toDouble() ?? 0.0;
            final v = (shiftData['cash_variance'] as num?)?.toDouble() ?? (counted - exp);
            closedZReport = {
              'shift_id': shiftData['id'] ?? _shiftId,
              'status': shiftData['status'] ?? 'closed',
              'variance_status':
                  v == 0 ? 'balanced' : (v > 0 ? 'overage' : 'shortage'),
              'opening_cash': (shiftData['opening_cash'] as num?)?.toDouble() ?? _openingCash,
              'cash_sales': (shiftData['cash_sales'] as num?)?.toDouble() ??
                  (shiftData['sales_total'] as num?)?.toDouble() ??
                  0.0,
              'sales_total': (shiftData['sales_total'] as num?)?.toDouble() ?? 0.0,
              'pay_ins': (shiftData['pay_ins'] as num?)?.toDouble() ?? _payIns,
              'pay_outs': (shiftData['pay_outs'] as num?)?.toDouble() ?? _payOuts,
              'expected_cash': exp,
              'counted_cash': (shiftData['closing_cash_counted'] as num?)?.toDouble() ?? counted,
              'cash_variance': v,
              'cash_shortage': (shiftData['cash_shortage'] as num?)?.toDouble() ??
                  (v < 0 ? v.abs() : 0.0),
              'cash_overage': (shiftData['cash_overage'] as num?)?.toDouble() ??
                  (v > 0 ? v : 0.0),
            };
          }
        } catch (e) {
          if (!ApiClient.isNetworkOfflineError(e)) {
            if (e is DioException && e.response?.data is Map) {
              final errData = Map<String, dynamic>.from(e.response!.data as Map);
              final needsReason = errData['requires_variance_reason'] == true ||
                  errData['error_code'] == 'VarianceReasonRequired';
              if (needsReason && mounted) {
                setState(() {
                  _requiresVarianceReason = true;
                  _varianceReasons = _parseVarianceReasons(errData['variance_reasons']);
                  _selectedVarianceReason ??= _varianceReasons.first['code'];
                  _closeError = (errData['message'] ??
                          'Terjadi selisih kas di luar toleransi. Pilih alasan selisih untuk menutup shift.')
                      .toString();
                  _submitting = false;
                });
                return;
              }
            }
            if (mounted) {
              setState(() {
                _closeError = ApiClient.extractErrorMessage(e);
                _submitting = false;
              });
            }
            return;
          }
          // BUG 6 FIX: Queue shift closure for Cloud sync so Cloud closes the shift
          // cleanly upon reconnect before opening the next day's shift!
          await _offlineDb.enqueuePendingShiftClosure(
            shiftId: _shiftId,
            closingCashCounted: counted,
            closingDenominations:
                _denomCounts.map((k, v) => MapEntry(k.toString(), v)),
            varianceReason: _selectedVarianceReason,
            varianceNotes: _varianceNotesCtrl.text.trim().isNotEmpty
                ? _varianceNotesCtrl.text.trim()
                : null,
            idempotencyKey: closeIdempotencyKey,
          );
          _refreshPosPendingBadge();
          final exp = _expectedCash ?? (_openingCash + (_cashSales ?? 0) + _payIns - _payOuts);
          final diff = counted - exp;
          closedZReport = {
            'shift_id': _shiftId ?? 0,
            'status': 'closed_offline_pending',
            'is_offline_pending': true,
            'variance_status':
                diff == 0 ? 'balanced' : (diff > 0 ? 'overage' : 'shortage'),
            'opening_cash': _openingCash,
            'cash_sales': _cashSales ?? 0,
            'sales_total': _cashSales ?? 0,
            'pay_ins': _payIns,
            'pay_outs': _payOuts,
            'expected_cash': exp,
            'counted_cash': counted,
            'cash_variance': diff,
            'cash_shortage': diff < 0 ? diff.abs() : 0.0,
            'cash_overage': diff > 0 ? diff : 0.0,
          };
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: NusaThemeTokens.of(context).warning,
                content: const Text(
                  'Shift ditutup offline & masuk antrean sinkronisasi Cloud. Akan otomatis dikirim saat online.',
                ),
              ),
            );
          }
        }
      }

      final ownerPhone = session.activeStore.phone?.trim() ?? '';
      if (ownerPhone.isNotEmpty && ownerPhone != '-') {
        await WhatsAppService.sendShiftZReportToOwner(
          ownerPhone: ownerPhone,
          storeName: session.activeStore.name,
          cashierName: session.userName,
          openingCash: (closedZReport['opening_cash'] as num?)?.toDouble() ?? _openingCash,
          salesTotal: (closedZReport['cash_sales'] as num?)?.toDouble() ?? 0,
          expectedCash: (closedZReport['expected_cash'] as num?)?.toDouble() ?? 0,
          countedCash: (closedZReport['counted_cash'] as num?)?.toDouble() ?? counted,
        );
      }

      if (mounted) {
        _countedCashCtrl.clear();
        _varianceNotesCtrl.clear();
        setState(() {
          _lastClosedZReport = closedZReport;
          _isBlindCountLocked = false;
          _requiresVarianceReason = false;
          _selectedVarianceReason = null;
          _closeError = null;
        });
      }
      await _loadCurrentShift();
    } catch (e) {
      if (!mounted) return;
      setState(() => _closeError = ApiClient.extractErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }


  Widget _inlineModalErrorBox(NusaThemeTokens tokens, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.dangerSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.danger, width: tokens.borderWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: tokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: tokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildClosedZReportCard(
    NusaThemeTokens tokens,
    Map<String, dynamic> z,
  ) {
    final expected = (z['expected_cash'] as num?)?.toDouble() ?? 0;
    final counted = (z['counted_cash'] as num?)?.toDouble() ?? 0;
    final variance = (z['cash_variance'] as num?)?.toDouble() ?? (counted - expected);
    final isBalanced = variance.abs() < 0.01;

    return NusaCard(
      key: const Key('shift_z_report_card'),
      borderColor: isBalanced ? tokens.positive : tokens.danger,
      borderWidth: tokens.isHighContrast ? 2.0 : 1.4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Ringkasan Z-Report Terverifikasi Server',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              NusaBadge(
                label: isBalanced
                    ? 'BALANCE'
                    : (variance > 0 ? 'OVERAGE' : 'SHORTAGE'),
                variant: isBalanced
                    ? NusaBadgeVariant.success
                    : NusaBadgeVariant.danger,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _zRow(tokens, 'Kas Fisik Dihitung Kasir', counted),
          _zRow(tokens, 'Kas Sistem (Server Expected)', expected),
          Divider(height: 14, color: tokens.borderSubtle),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  isBalanced
                      ? 'Selisih Kas (Sesuai):'
                      : (variance > 0 ? 'Selisih Lebih:' : 'Selisih Kurang:'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              NusaPriceTag(
                amount: variance.abs(),
                prefix: variance > 0 ? '+' : (variance < 0 ? '-' : ''),
                fontSize: 15,
                color: isBalanced ? tokens.positive : tokens.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          NusaButton(
            label: 'Cetak Struk Z-Report (58mm / 80mm)',
            icon: Icons.receipt_long_rounded,
            variant: NusaButtonVariant.outline,
            minHeight: 44,
            onPressed: () => _showThermalZReportDialog(z),
          ),
        ],
      ),
    );
  }


  Widget _zRow(NusaThemeTokens tokens, String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          NusaPriceTag(amount: amount, fontSize: 13.5, color: tokens.textPrimary),
        ],
      ),
    );
  }


  Widget _shiftStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
