// ignore_for_file: invalid_use_of_protected_member
part of 'mobile_report_detail_screen.dart';

extension _MobileReportDetailScreenStatePart1Ext on _MobileReportDetailScreenState {

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final authSession = context.read<AuthCubit>().state.session;
    try {
      final result = await _repo.fetchReport(
        definition: widget.definition,
        periodKey: _periodKey,
        customStart: _customStart,
        customEnd: _customEnd,
        storeScope: _storeScope,
        storeLabel: _storeLabel,
        isLocalTrial: authSession.isLocalTrial,
      );
      if (!mounted) return;
      setState(() {
        _payload = result;
        _loading = false;
      });
    } on MobileReportApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }


  Future<void> _selectPeriod(String key) async {
    if (key == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: now,
        initialDateRange: _customStart != null && _customEnd != null
            ? DateTimeRange(start: _customStart!, end: _customEnd!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 6)),
                end: now,
              ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _periodKey = 'custom';
        _customStart = picked.start;
        _customEnd = picked.end;
      });
      await _loadReport();
      return;
    }

    setState(() {
      _periodKey = key;
      _customStart = null;
      _customEnd = null;
    });
    await _loadReport();
  }


  void _openStorePicker() {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih Cakupan Cabang',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: Icon(Icons.domain_rounded, color: tokens.accent),
                title: Text(
                  'Semua Cabang',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                trailing: _storeScope == 'all'
                    ? Icon(Icons.check_circle_rounded, color: tokens.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _storeScope = 'all';
                    _storeLabel = 'Semua Cabang';
                  });
                  _loadReport();
                },
              ),
              for (final s in widget.availableStores)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(
                    Icons.storefront_rounded,
                    color: tokens.textSecondary,
                  ),
                  title: Text(
                    (s['name'] ?? s['store_name'] ?? 'Cabang').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  trailing: _storeScope == (s['id'] ?? s['store_id']).toString()
                      ? Icon(Icons.check_circle_rounded, color: tokens.accent)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _storeScope = (s['id'] ?? s['store_id']).toString();
                      _storeLabel =
                          (s['name'] ?? s['store_name'] ?? 'Cabang').toString();
                    });
                    _loadReport();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }


  Future<void> _shareWhatsApp() async {
    final payload = _payload;
    if (payload == null) return;
    final text = payload.whatsappSummary.trim().isNotEmpty
        ? payload.whatsappSummary
        : MobileReportRepository.buildWhatsAppSummary(
            definition: widget.definition,
            storeLabel: payload.storeLabel,
            periodLabel: payload.periodLabel,
            kpis: payload.kpis,
            items: payload.items,
            isOfflineData: payload.isOfflineData,
            lastSyncLabel: payload.lastSyncLabel,
          );

    await Clipboard.setData(ClipboardData(text: text));
    final opened = await WhatsAppService.shareToAnyChat(text: text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Ringkasan laporan siap dikirim ke WhatsApp (juga disalin ke clipboard).'
              : 'Teks laporan WhatsApp telah disalin ke clipboard.',
        ),
        backgroundColor: NusaThemeTokens.of(context).whatsapp,
      ),
    );
  }


  void _openExportSheet() {
    final payload = _payload;
    if (payload == null) return;
    final tokens = NusaThemeTokens.of(context);
    final isLocalTrial = context.read<AuthCubit>().state.session.isLocalTrial;

    String? sheetError;
    String? sheetSuccess;
    bool busy = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: tokens.borderDefault,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Bagikan & Ekspor Laporan',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${payload.title} • ${payload.periodLabel}',
                  style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                ),
                const SizedBox(height: 14),
                if (sheetError != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tokens.danger.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: tokens.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sheetError!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (sheetSuccess != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.positiveSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: tokens.positive.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: tokens.positive, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sheetSuccess!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.positive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildExportActionTile(
                  tokens: tokens,
                  icon: Icons.chat_rounded,
                  iconColor: NusaThemeTokens.of(ctx).whatsapp,
                  title: 'Kirim Ringkasan via WhatsApp (1-Klik)',
                  subtitle: 'Teks rapi berformat emoji & total Rupiah siap kirim ke grup toko',
                  busy: busy,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _shareWhatsApp();
                  },
                ),
                const SizedBox(height: 8),
                _buildExportActionTile(
                  tokens: tokens,
                  icon: Icons.picture_as_pdf_rounded,
                  iconColor: NusaThemeTokens.of(ctx).danger,
                  title: 'Ekspor PDF Ringkas (A4)',
                  subtitle: payload.isOfflineData || isLocalTrial
                      ? 'Perlu koneksi Cloud untuk render PDF A4 resmi'
                      : 'Unduh PDF resmi berlogo OXORA dari server Cloud',
                  busy: busy,
                  onTap: () async {
                    if (payload.isOfflineData || isLocalTrial) {
                      setModalState(() {
                        sheetError =
                            'Ekspor PDF A4 memerlukan koneksi Cloud. Gunakan ekspor CSV atau bagikan via WhatsApp saat offline.';
                        sheetSuccess = null;
                      });
                      return;
                    }
                    setModalState(() {
                      busy = true;
                      sheetError = null;
                      sheetSuccess = null;
                    });
                    try {
                      final res = await _repo.downloadServerPdf(
                        definition: widget.definition,
                        periodKey: _periodKey,
                        customStart: _customStart,
                        customEnd: _customEnd,
                        storeScope: _storeScope,
                      );
                      setModalState(() {
                        busy = false;
                        sheetSuccess = res.filePath != null
                            ? 'PDF berhasil disimpan (${(res.byteLength / 1024).toStringAsFixed(1)} KB): ${res.filePath}'
                            : 'PDF berhasil diunduh (${res.filename}, ${(res.byteLength / 1024).toStringAsFixed(1)} KB).';
                      });
                    } catch (e) {
                      setModalState(() {
                        busy = false;
                        sheetError = ApiClient.extractErrorMessage(e);
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                _buildExportActionTile(
                  tokens: tokens,
                  icon: Icons.table_view_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'Ekspor CSV / Excel (Aman Formula)',
                  subtitle: 'Simpan file .csv (UTF-8 BOM) & salin isi ke clipboard',
                  busy: busy,
                  onTap: () async {
                    setModalState(() {
                      busy = true;
                      sheetError = null;
                      sheetSuccess = null;
                    });
                    try {
                      final res = await _repo.exportCsvFile(payload);
                      if (res.textContent != null) {
                        await Clipboard.setData(
                          ClipboardData(text: res.textContent!),
                        );
                      }
                      setModalState(() {
                        busy = false;
                        sheetSuccess = res.filePath != null
                            ? 'CSV tersimpan di ${res.filePath} & disalin ke clipboard.'
                            : 'Data CSV (${res.filename}) berhasil disalin ke clipboard.';
                      });
                    } catch (e) {
                      setModalState(() {
                        busy = false;
                        sheetError = 'Gagal membuat file CSV: $e';
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildExportActionTile({
    required NusaThemeTokens tokens,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tokens.textTertiary),
          ],
        ),
      ),
    );
  }
}
