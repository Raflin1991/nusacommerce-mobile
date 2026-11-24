// ignore_for_file: invalid_use_of_protected_member
part of 'payment_checkout_screen.dart';

extension _PaymentCheckoutScreenStatePart2Ext on _PaymentCheckoutScreenState {

  Future<void> _submitPayment(double grandTotal) async {
    final posCubit = context.read<PosCubit>();
    if (_isSubmitting || posCubit.isCheckoutInProgress) return;
    setState(() {
      _isSubmitting = true;
      _checkoutError = null;
      _checkoutErrorCode = null;
    });

    try {
      final rxWarning = posCubit.validatePrescriptionRequirements();
      if (rxWarning != null) {
        PosFeedback.onGuardBlocked();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: NusaThemeTokens.of(context).danger,
            content: Text(rxWarning),
          ),
        );
        return;
      }

      final posState = posCubit.state;
      final availableMethods = posState.paymentMethods;
      final appliedStoreCredit = _appliedStoreCredit(grandTotal);
      final netDue = _netTotalAfterStoreCredit(grandTotal);

      final paymentsList = <Map<String, dynamic>>[];
      final methodNames = <String>[];
      double paidTotal = 0.0;
      double changeReturned = 0.0;
      double balanceDue = 0.0;
      String? dueDateStr;

      if (appliedStoreCredit > 0) {
        methodNames.add('Saldo Deposit (${IdrCurrencyFormatter.format(appliedStoreCredit)})');
      }

      if (_isKasbonMode) {
        if (_selectedCustomer == null) {
          PosFeedback.onGuardBlocked();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: NusaThemeTokens.of(context).danger,
              content: Text('Pilih pelanggan terlebih dahulu untuk transaksi Kasbon.'),
            ),
          );
          return;
        }
        final kasbonCalc = _buildKasbonCalculation(grandTotal);
        if (kasbonCalc.validationError != null || !kasbonCalc.isWithinCreditLimit) {
          PosFeedback.onGuardBlocked();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: NusaThemeTokens.of(context).danger,
              content: Text(kasbonCalc.validationError ?? 'Melebihi plafon kredit pelanggan!'),
            ),
          );
          return;
        }

        paidTotal = kasbonCalc.downPayment;
        balanceDue = kasbonCalc.balanceDue;
        dueDateStr = DateFormat('yyyy-MM-dd').format(_kasbonDueDate);

        if (kasbonCalc.downPayment > 0) {
          final dpLabel = _labelForCode(_kasbonDpMethod);
          paymentsList.add({
            'payment_method_id': _resolvePaymentMethodId(availableMethods, _kasbonDpMethod),
            'amount': kasbonCalc.downPayment,
            'tendered_amount': kasbonCalc.downPayment,
            'reference': 'DP-$dpLabel',
          });
          methodNames.add('DP $dpLabel (${IdrCurrencyFormatter.format(kasbonCalc.downPayment)})');
        }
        methodNames.add('Kasbon (${IdrCurrencyFormatter.format(balanceDue)})');
      } else if (_isSplitPayment) {
        final validation = _buildMultiTenderValidation(grandTotal);
        if (!validation.isValidCheckout) {
          PosFeedback.onGuardBlocked();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: NusaThemeTokens.of(context).danger,
              content: Text(
                validation.remainingDue > 0
                    ? 'Multi-Tender masih kurang ${IdrCurrencyFormatter.format(validation.remainingDue)}!'
                    : 'Kelebihan bayar non-tunai tidak diperbolehkan!',
              ),
            ),
          );
          return;
        }

        paidTotal = validation.tendersTotal;
        changeReturned = validation.cashChangeReturned;
        for (int i = 0; i < _splitLines.length; i++) {
          final line = _splitLines[i];
          if (line.amount <= 0) continue;
          final recordedAmount = i < validation.effectiveRecordedAmounts.length
              ? validation.effectiveRecordedAmounts[i]
              : line.amount;
          final label = line.subType.isNotEmpty
              ? '${line.methodLabel} (${line.subType})'
              : line.methodLabel;
          final ref = line.referenceController.text.trim().isNotEmpty
              ? line.referenceController.text.trim()
              : '$label-SPLIT';
          paymentsList.add({
            'payment_method_id': _resolvePaymentMethodId(availableMethods, line.methodCode),
            'amount': recordedAmount,
            'tendered_amount': line.amount,
            if (line.methodCode != 'cash') 'reference': ref,
          });
          methodNames.add('$label (${IdrCurrencyFormatter.format(recordedAmount)})');
        }
      } else {
        if (netDue <= 0.5) {
          paidTotal = 0.0;
          changeReturned = 0.0;
          if (posState.isExchangeMode && posState.exchangeSurplusCredit > 0) {
            methodNames.add(
              _refundSurplusToStoreCredit && (_selectedCustomer?['id'] as num?) != null
                  ? 'Tukar Barang (Simpan Deposit)'
                  : 'Tukar Barang (Kembali Tunai)',
            );
          } else if (posState.isExchangeMode) {
            methodNames.add('Tukar Barang (Impas)');
          }
        } else {
          final rawPaid = _paidAmount;
          if (rawPaid < netDue - 0.5) {
            PosFeedback.onGuardBlocked();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: NusaThemeTokens.of(context).danger,
                content: Text('Jumlah bayar kurang dari Sisa Tagihan!'),
              ),
            );
            return;
          }
          paidTotal = rawPaid;
          changeReturned = (rawPaid - netDue).clamp(0.0, double.infinity);

          String resolvedName = _selectedMethodName;
          if (_selectedMethodCode == 'qris') resolvedName = 'QRIS $_qrisType';
          if (_selectedMethodCode == 'transfer') resolvedName = 'Transfer $_selectedBank';
          if (_selectedMethodCode == 'card') resolvedName = 'EDC $_edcCardType';

          paymentsList.add({
            'payment_method_id': _resolvePaymentMethodId(availableMethods, _selectedMethodCode),
            'amount': netDue,
            'tendered_amount': rawPaid,
            'reference': _referenceController.text.trim().isNotEmpty
                ? _referenceController.text.trim()
                : resolvedName,
          });
          methodNames.add(resolvedName);
        }
      }

      _pendingIdempotencyKey ??= const Uuid().v4();

      final receipt = await posCubit.completeCheckout(
        payments: paymentsList,
        paymentMethodNames: methodNames.isEmpty ? ['Tunai'] : methodNames,
        paidTotal: paidTotal,
        changeReturned: changeReturned,
        balanceDue: balanceDue,
        storeCreditAmount: appliedStoreCredit,
        grandTotalOverride: _splitOverrideGrandTotal,
        overrideHeldSaleId: _splitChildHeldSaleId,
        refundSurplusToStoreCredit: _refundSurplusToStoreCredit,
        splitItemIndices: _splitItemIndices,
        dueDate: dueDateStr,
        idempotencyKey: _pendingIdempotencyKey,
      );

      _pendingIdempotencyKey = null;

      final enrichedReceipt = Map<String, dynamic>.from(receipt);
      if (_splitServiceCharge > 0) {
        enrichedReceipt['service_charge_amount'] = _splitServiceCharge;
      }
      if (_splitTaxTotal > 0) {
        enrichedReceipt['tax_total'] = _splitTaxTotal;
      }

      final hasCashComponent = PrinterService.shouldKickCashDrawer(
        payments: paymentsList,
        paymentMethods: methodNames,
        isKasbonZeroDp: _isKasbonMode && paidTotal <= 0,
        isReprint: false,
      );
      enrichedReceipt['has_cash_payment'] = hasCashComponent;

      // Phase 3.1: Non-blocking multi-printer KOT & Bar routing when configured
      if (GetIt.instance.isRegistered<PrinterService>()) {
        final printer = GetIt.instance<PrinterService>();
        final hasStationPrinters =
            (printer.printerDapurMac != null && printer.printerDapurMac!.isNotEmpty) ||
                (printer.printerBarMac != null && printer.printerBarMac!.isNotEmpty);
        if (hasStationPrinters || posState.capabilities.hasKitchenOrderTicket) {
          unawaited(
            printer.routeOrderTicketsAndReceipt(
              sale: enrichedReceipt,
              store: widget.offlineDb.getStoreProfile(),
              openCashDrawer: hasCashComponent && printer.autoOpenCashDrawer,
              printReceipt: false,
            ),
          );
        }
      }

      if (mounted) {
        context.pushReplacement('/pos/receipt', extra: enrichedReceipt);
      }
    } on CheckoutServerException catch (e) {
      if (mounted) {
        PosFeedback.onGuardBlocked();
        setState(() {
          _checkoutError = e.message;
          _checkoutErrorCode = e.errorCode;
        });
      }
    } catch (e) {
      if (mounted) {
        PosFeedback.onGuardBlocked();
        setState(() {
          _checkoutError = 'Gagal memproses transaksi: $e';
          _checkoutErrorCode = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }


  /// Phase 3.3: Dynamic QRIS In-App Polling Timer (5-minute countdown + 3s status polling)
  void _showDynamicQrisPollingModal(
    BuildContext rootContext, {
    required double netDue,
    required double grandTotal,
  }) {
    int remainingSeconds = 300; // 5 menit
    int pollCount = 0;
    String statusText = 'Menunggu pembayaran pelanggan...';
    Timer? countdownTimer;
    Timer? pollTimer;
    bool timersStarted = false;

    showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: NusaThemeTokens.of(rootContext).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final tokens = NusaThemeTokens.of(modalCtx);
          if (!timersStarted) {
            timersStarted = true;
            countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!modalCtx.mounted) return;
              if (remainingSeconds <= 1) {
                countdownTimer?.cancel();
                pollTimer?.cancel();
                setModalState(() {
                  remainingSeconds = 0;
                  statusText = 'QRIS kedaluwarsa (5 menit). Generate ulang QRIS atau verifikasi manual.';
                });
              } else {
                setModalState(() => remainingSeconds--);
              }
            });
            pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
              if (!modalCtx.mounted || remainingSeconds <= 0) return;
              setModalState(() {
                pollCount++;
                statusText = 'Memeriksa status gateway QRIS (Pengecekan ke-$pollCount)...';
              });
            });
          }

          final mm = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
          final ss = (remainingSeconds % 60).toString().padLeft(2, '0');

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'QRIS Dinamis OXORA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      NusaBadge(
                        label: 'Sisa Waktu $mm:$ss',
                        variant: remainingSeconds > 60
                            ? NusaBadgeVariant.primary
                            : NusaBadgeVariant.danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NusaPriceTag(amount: netDue, fontSize: 22, color: tokens.accent),
                  const SizedBox(height: 12),
                  // QR Code itself stays on crisp white scan canvas for camera readability
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: tokens.borderDefault, width: 1.5),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 148, color: Color(0xFF1C1917)),
                        SizedBox(height: 6),
                        Text(
                          'QRIS STANDAR PEMBAYARAN NASIONAL (GPN / BI)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            statusText,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(modalCtx).accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  NusaButton(
                    label: 'Verifikasi Manual (Pelanggan Sudah Sukses)',
                    icon: Icons.verified_rounded,
                    variant: NusaButtonVariant.success,
                    minHeight: 50,
                    onPressed: () {
                      countdownTimer?.cancel();
                      pollTimer?.cancel();
                      Navigator.pop(modalCtx);
                      setState(() {
                        _selectedMethodCode = 'qris';
                        _selectedMethodName = 'QRIS $_qrisType';
                        _qrisType = 'Dinamis';
                        _amountPaidController.text = IdrCurrencyFormatter.format(netDue);
                      });
                      _submitPayment(grandTotal);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      countdownTimer?.cancel();
      pollTimer?.cancel();
    });
  }


  Future<void> _pickKasbonDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _kasbonDueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _kasbonDueDate = picked);
    }
  }
}
