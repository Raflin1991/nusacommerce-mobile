// ignore_for_file: invalid_use_of_protected_member
part of 'settings_screen.dart';

extension _SettingsScreenStatePart2Ext on _SettingsScreenState {

  void _showBluetoothPrinterModal(BuildContext context) {
    bool isScanning = !_printerService.isWifiMode;
    bool hasInitializedScan = _printerService.isWifiMode;
    bool isConnecting = false;
    bool isTestingWifi = false;
    String selectedPrinterRole = 'kasir';
    String selectedMode = _printerService.connectionMode == 'wifi' ? 'wifi' : 'bluetooth';
    final wifiIpCtrl = TextEditingController(text: _printerService.wifiPrinterIp ?? '');
    final wifiPortCtrl = TextEditingController(text: '${_printerService.wifiPrinterPort}');
    String? wifiInlineError;
    String? wifiInlineSuccess;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final tokens = NusaThemeTokens.of(ctx);
          if (selectedMode == 'bluetooth' && !hasInitializedScan) {
            hasInitializedScan = true;
            _printerService.scanBluetoothDevices().then((_) {
              if (ctx.mounted) {
                setModalState(() => isScanning = false);
              }
            });
          }

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Pengaturan Printer Thermal (Bluetooth / WiFi)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (selectedMode == 'bluetooth')
                        TextButton.icon(
                          onPressed: isScanning
                              ? null
                              : () async {
                                  setModalState(() => isScanning = true);
                                  await _printerService.scanBluetoothDevices();
                                  if (ctx.mounted) setModalState(() => isScanning = false);
                                },
                          icon: isScanning
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.bluetooth_searching_rounded, size: 18),
                          label: Text(isScanning ? 'Memindai...' : 'Pindai Ulang'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedMode == 'wifi'
                        ? 'Cetak langsung ke printer thermal LAN/WiFi melalui soket TCP RAW (port standar 9100) dalam jaringan lokal toko.'
                        : 'Pilih printer Bluetooth thermal paired (58mm/80mm) untuk disimpan & auto-reconnect saat aplikasi dibuka.',
                    style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mode Koneksi Printer',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      NusaPillFilter(
                        label: 'Bluetooth',
                        icon: Icons.bluetooth_rounded,
                        selected: selectedMode == 'bluetooth',
                        onTap: () async {
                          await _printerService.savePreferences(mode: 'bluetooth');
                          if (ctx.mounted) {
                            setModalState(() {
                              selectedMode = 'bluetooth';
                              wifiInlineError = null;
                              wifiInlineSuccess = null;
                              if (!hasInitializedScan) {
                                isScanning = true;
                              }
                            });
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                      NusaPillFilter(
                        label: 'WiFi / LAN (TCP 9100)',
                        icon: Icons.wifi_rounded,
                        selected: selectedMode == 'wifi',
                        onTap: () async {
                          await _printerService.savePreferences(mode: 'wifi');
                          if (ctx.mounted) {
                            setModalState(() {
                              selectedMode = 'wifi';
                              wifiInlineError = null;
                              wifiInlineSuccess = null;
                            });
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ukuran Kertas Thermal',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      NusaPillFilter(
                        label: '58mm (Struk Kecil)',
                        selected: _printerService.paperWidth == '58mm',
                        onTap: () async {
                          await _printerService.savePreferences(width: '58mm');
                          if (ctx.mounted) setModalState(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      NusaPillFilter(
                        label: '80mm (Lebar Desktop)',
                        selected: _printerService.paperWidth == '80mm',
                        onTap: () async {
                          await _printerService.savePreferences(width: '80mm');
                          if (ctx.mounted) setModalState(() {});
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  NusaCard(
                    padding: EdgeInsets.zero,
                    backgroundColor: tokens.bgElevated,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          title: Text(
                            'Auto-Cut Kertas Struk',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Potong otomatis setelah transaksi selesai',
                            style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                          ),
                          value: _printerService.autoCutPaper,
                          onChanged: (val) async {
                            await _printerService.savePreferences(autoCut: val);
                            if (ctx.mounted) setModalState(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                        Divider(height: 1, color: tokens.borderSubtle),
                        SwitchListTile.adaptive(
                          title: Text(
                            'Buka Laci Otomatis (RJ-11)',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Kirim pulse pembuka laci pada pembayaran tunai',
                            style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                          ),
                          value: _printerService.autoOpenCashDrawer,
                          onChanged: (val) async {
                            await _printerService.savePreferences(autoDrawer: val);
                            if (ctx.mounted) setModalState(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (selectedMode == 'wifi') ...[
                    Text(
                      'Alamat IP & Port Printer Thermal LAN/WiFi',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: wifiIpCtrl,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Alamat IP / Host Printer',
                              hintText: '192.168.1.100',
                              prefixIcon: Icon(Icons.router_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: wifiPortCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Port TCP',
                              hintText: '9100',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (wifiInlineError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: tokens.dangerSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.danger.withOpacity(0.5)),
                        ),
                        child: Text(
                          wifiInlineError!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.danger,
                          ),
                        ),
                      ),
                    ],
                    if (wifiInlineSuccess != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: tokens.positiveSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.positive.withOpacity(0.5)),
                        ),
                        child: Text(
                          wifiInlineSuccess!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.positive,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: NusaButton(
                        label: isTestingWifi ? 'Menyimpan...' : 'Simpan Printer WiFi Aktif',
                        icon: Icons.wifi_rounded,
                        minHeight: 46,
                        onPressed: isTestingWifi
                            ? null
                            : () async {
                                final ip = wifiIpCtrl.text.trim();
                                final port = int.tryParse(wifiPortCtrl.text.trim());
                                final validHost = RegExp(r'^[A-Za-z0-9.\-]{3,64}$').hasMatch(ip);
                                if (ip.isEmpty || !validHost) {
                                  setModalState(() {
                                    wifiInlineError =
                                        'Masukkan alamat IP LAN yang valid (contoh: 192.168.1.100).';
                                    wifiInlineSuccess = null;
                                  });
                                  return;
                                }
                                if (port == null || port < 1 || port > 65535) {
                                  setModalState(() {
                                    wifiInlineError =
                                        'Port TCP harus berupa angka antara 1 sampai 65535 (standar ESC/POS: 9100).';
                                    wifiInlineSuccess = null;
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isTestingWifi = true;
                                  wifiInlineError = null;
                                  wifiInlineSuccess = null;
                                });
                                await _printerService.saveWifiPrinter(
                                  ipAddress: ip,
                                  port: port,
                                  activateWifiMode: true,
                                );
                                if (ctx.mounted) {
                                  setModalState(() {
                                    isTestingWifi = false;
                                    wifiInlineSuccess =
                                        'Printer WiFi LAN $ip:$port aktif untuk seluruh pencetakan struk POS.';
                                  });
                                }
                                if (mounted) setState(() {});
                              },
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Routing Multi-Printer (Pilih Stasiun Target)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        NusaPillFilter(
                          label: 'Kasir (Struk)',
                          selected: selectedPrinterRole == 'kasir',
                          onTap: () => setModalState(() => selectedPrinterRole = 'kasir'),
                        ),
                        NusaPillFilter(
                          label: 'Dapur (KOT Makanan)',
                          selected: selectedPrinterRole == 'dapur',
                          onTap: () => setModalState(() => selectedPrinterRole = 'dapur'),
                        ),
                        NusaPillFilter(
                          label: 'Bar (Minuman)',
                          selected: selectedPrinterRole == 'bar',
                          onTap: () => setModalState(() => selectedPrinterRole = 'bar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    NusaCard(
                      padding: const EdgeInsets.all(10),
                      backgroundColor: tokens.bgElevated,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• Kasir (Struk): ${_printerService.printerKasirName ?? 'Belum diatur'} (${_printerService.printerKasirMac ?? '-'})',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '• Dapur (KOT): ${_printerService.printerDapurName ?? 'Belum diatur'} (${_printerService.printerDapurMac ?? '-'})',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '• Bar (Minuman): ${_printerService.printerBarName ?? 'Belum diatur'} (${_printerService.printerBarMac ?? '-'})',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Perangkat Bluetooth Terdeteksi (Paired)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (_printerService.savedMacAddress != null)
                          NusaBadge(
                            label: 'Auto-Reconnect: ${_printerService.savedMacAddress}',
                            variant: NusaBadgeVariant.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isScanning)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(strokeWidth: 2.5),
                              SizedBox(height: 8),
                              Text(
                                'Memindai printer Bluetooth di perangkat...',
                                style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(ctx).textSecondary),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_printerService.discoveredDevices.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: tokens.bgElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.bluetooth_disabled_rounded, color: tokens.textTertiary, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              'Belum ada printer Bluetooth yang ter-pair.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pasangkan (Pair) printer thermal melalui Pengaturan Bluetooth Android lalu tekan "Pindai Ulang".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._printerService.discoveredDevices.map((dev) {
                        final activeMacForRole = selectedPrinterRole == 'dapur'
                            ? _printerService.printerDapurMac
                            : selectedPrinterRole == 'bar'
                                ? _printerService.printerBarMac
                                : (_printerService.printerKasirMac ?? _printerService.savedMacAddress);
                        final isConnected = activeMacForRole == dev.macAddress;
                        final roleLabel = selectedPrinterRole == 'dapur'
                            ? 'Dapur (KOT Makanan)'
                            : selectedPrinterRole == 'bar'
                                ? 'Bar (Minuman)'
                                : 'Kasir (Struk)';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: isConnected ? NusaThemeTokens.of(ctx).positiveSoft : NusaThemeTokens.of(ctx).accentSoft,
                            child: Icon(
                              Icons.print_rounded,
                              color: isConnected ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).accent,
                            ),
                          ),
                          title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          subtitle: Text('MAC: ${dev.macAddress} • ${dev.paperSize}', style: const TextStyle(fontSize: 11.5)),
                          trailing: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConnected ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).accent,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: isConnecting
                                  ? null
                                  : () async {
                                      setModalState(() => isConnecting = true);
                                      if (isConnected) {
                                        if (selectedPrinterRole == 'kasir') {
                                          await _printerService.disconnectDevice(forgetSavedMac: true);
                                        }
                                        await _printerService.clearPrinterRole(selectedPrinterRole);
                                        if (ctx.mounted) setModalState(() => isConnecting = false);
                                        if (mounted) setState(() {});
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Printer ${dev.name} dilepas dari $roleLabel.')),
                                          );
                                        }
                                      } else {
                                        await _printerService.savePreferences(mode: 'bluetooth');
                                        await _printerService.assignPrinterRole(selectedPrinterRole, dev);
                                        bool ok = true;
                                        if (selectedPrinterRole == 'kasir') {
                                          ok = await _printerService.connectToDevice(
                                            dev.macAddress,
                                            deviceName: dev.name,
                                            paperSize: dev.paperSize,
                                          );
                                        }
                                        if (ctx.mounted) setModalState(() => isConnecting = false);
                                        if (mounted) setState(() {});
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              backgroundColor: ok ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).warning,
                                              content: Text(
                                                ok
                                                    ? '${dev.name} ditetapkan sebagai Printer $roleLabel (${dev.macAddress})'
                                                    : 'Disimpan sebagai Printer $roleLabel, namun koneksi Bluetooth gagal. Pastikan printer menyala.',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                              child: Text(isConnected ? 'Terpasang' : 'Set $selectedPrinterRole'),
                            ),
                          ),
                        );
                      }),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: NusaButton(
                          label: selectedMode == 'wifi' ? 'Tes Cetak WiFi' : 'Test Print Struk',
                          icon: Icons.receipt_long_rounded,
                          variant: NusaButtonVariant.outline,
                          minHeight: 46,
                          onPressed: () async {
                            final previewText = _printerService.formatTestPrintReceiptText(
                              storeProfile: _offlineDb.getStoreProfile(),
                            );
                            final sentPhysical = await _printerService.printReceiptText(previewText);
                            if (ctx.mounted && selectedMode == 'wifi') {
                              setModalState(() {
                                if (sentPhysical) {
                                  wifiInlineSuccess =
                                      'Test Print ESC/POS berhasil dikirim ke ${_printerService.activePrinterLabel}.';
                                  wifiInlineError = null;
                                } else {
                                  wifiInlineError =
                                      'Gagal menghubungi printer WiFi (${_printerService.activePrinterLabel}). Pastikan IP & WiFi lokal satu jaringan.';
                                  wifiInlineSuccess = null;
                                }
                              });
                            } else if (context.mounted && sentPhysical) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(ctx).positive,
                                  content: Text(
                                    'Test Print ESC/POS berhasil dicetak ke ${_printerService.activePrinterLabel}!',
                                  ),
                                ),
                              );
                            }
                            if (!ctx.mounted) return;
                            showDialog(
                              context: ctx,
                              builder: (pCtx) => AlertDialog(
                                title: Text(
                                  'Test Print (${_printerService.paperWidth})',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                content: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: NusaThemeTokens.of(pCtx).bgPage,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: NusaThemeTokens.of(pCtx).borderSubtle),
                                  ),
                                  child: Text(
                                    previewText,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                  ),
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(pCtx),
                                    child: const Text('Tutup'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NusaButton(
                          label: 'Uji Laci RJ-11',
                          icon: Icons.point_of_sale_rounded,
                          minHeight: 46,
                          onPressed: () async {
                            final ok = await _printerService.kickCashDrawer();
                            final kick = _printerService.buildCashDrawerKickBytes();
                            final hexStr = kick.map((b) => '0x${b.toRadixString(16).toUpperCase()}').join(' ');
                            if (ctx.mounted && selectedMode == 'wifi') {
                              setModalState(() {
                                if (ok) {
                                  wifiInlineSuccess = 'Pulse RJ-11 berhasil membuka laci via WiFi: $hexStr';
                                  wifiInlineError = null;
                                } else {
                                  wifiInlineError = 'Printer WiFi belum terjangkau untuk pulse RJ-11 ($hexStr).';
                                  wifiInlineSuccess = null;
                                }
                              });
                              return;
                            }
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: ok ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).warning,
                                content: Text(
                                  ok
                                      ? 'Pulse RJ-11 berhasil membuka laci: $hexStr'
                                      : 'Printer belum tersambung (Pulse RJ-11: $hexStr)',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
