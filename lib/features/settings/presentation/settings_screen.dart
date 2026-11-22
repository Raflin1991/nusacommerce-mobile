import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/presentation/cloud_upgrade_sheet.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 9 — PENGATURAN SISTEM OXO.ID (TAB 5 NAVIGASI)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PrinterService _printerService = GetIt.instance<PrinterService>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final ApiClient _apiClient = GetIt.instance<ApiClient>();

  void _showSwitchStoreBranchModal(BuildContext context) {
    final session = context.read<AuthCubit>().state.session;
    final stores = session.availableStores;

    showModalBottomSheet(
      context: context,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final tokens = NusaThemeTokens.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ganti Cabang Toko Aktif',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih cabang aktif. Katalog produk dan stok otomatis disesuaikan dengan cabang ini.',
                style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
              ),
              const SizedBox(height: 14),
              if (stores.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Hanya 1 cabang aktif yang terdaftar pada akun ini.',
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                )
              else
                ...stores.map((branch) {
                  final isCurrent = branch.id == session.activeStore.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NusaCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderColor: isCurrent ? tokens.accent : tokens.borderSubtle,
                      borderWidth: isCurrent ? 1.5 : tokens.borderWidth,
                      backgroundColor: isCurrent ? tokens.accentSoft : tokens.bgElevated,
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (isCurrent) return;
                        await context.read<AuthCubit>().switchStoreBranch(branch);
                        if (context.mounted) {
                          await context.read<PosCubit>().syncWithCloud(force: true);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cabang aktif dialihkan ke ${branch.name}')),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.storefront_rounded,
                            color: isCurrent ? tokens.accent : tokens.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  branch.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                if (branch.address != null && branch.address!.isNotEmpty)
                                  Text(
                                    branch.address!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                          if (isCurrent)
                            const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  void _showServerEndpointModal(BuildContext context) {
    final urlCtrl = TextEditingController(text: _apiClient.baseUrl);
    final edgeUrlCtrl = TextEditingController(
      text: _apiClient.edgeDiscovery.getEdgeBaseUrl() ?? '',
    );
    final nodeCtrl = TextEditingController(
      text: _apiClient.edgeDiscovery.getMobileNodeCode(),
    );
    String? inlineError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
              const Text(
                'Server Cloud, OXO Edge & Kode Terminal',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kode Terminal mempartisi nomor struk offline (contoh: M01, M02, M4F9A) agar multi-perangkat kasir tidak pernah bentrok.',
                style: TextStyle(fontSize: 12.5, color: AppColors.slate600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'Endpoint REST API Cloud v1',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: edgeUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL OXO Edge LAN Cabang (Opsional)',
                  hintText: 'http://192.168.1.10/api/v1',
                  prefixIcon: Icon(Icons.router_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nodeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Kode Terminal / Partisi Nota (Anti-Bentrok)',
                  hintText: 'M01 / M02 / M7A3C',
                  prefixIcon: Icon(Icons.tablet_android_outlined),
                  counterText: '',
                ),
              ),
              if (inlineError != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                  ),
                  child: Text(
                    inlineError!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dangerDark,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final rawNode = nodeCtrl.text.trim().toUpperCase();
                    if (rawNode.isNotEmpty && !RegExp(r'^M?[A-Z0-9]{2,5}$').hasMatch(rawNode)) {
                      setModalState(() {
                        inlineError =
                            'Kode terminal harus 2–6 karakter alfanumerik (contoh: M01, M02, M4F9A).';
                      });
                      return;
                    }
                    await _apiClient.setBaseUrl(urlCtrl.text);
                    await _apiClient.edgeDiscovery.setEdgeBaseUrl(edgeUrlCtrl.text);
                    if (rawNode.isNotEmpty) {
                      await context.read<PosCubit>().updateTerminalNodeCode(rawNode);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Tersimpan • Terminal ${_apiClient.edgeDiscovery.getMobileNodeCode()} • ${_apiClient.baseUrl}',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Simpan Konfigurasi Server & Terminal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(strokeWidth: 2.5),
                              SizedBox(height: 8),
                              Text(
                                'Memindai printer Bluetooth di perangkat...',
                                style: TextStyle(fontSize: 12, color: AppColors.slate500),
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
                            backgroundColor: isConnected ? AppColors.successSoft : AppColors.primarySoft,
                            child: Icon(
                              Icons.print_rounded,
                              color: isConnected ? AppColors.successDark : AppColors.primary,
                            ),
                          ),
                          title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          subtitle: Text('MAC: ${dev.macAddress} • ${dev.paperSize}', style: const TextStyle(fontSize: 11.5)),
                          trailing: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConnected ? AppColors.success : AppColors.primary,
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
                                              backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
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
                                  backgroundColor: AppColors.successDark,
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
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
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
                                backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
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

  IconData _verticalIcon(BusinessVertical vertical) {
    switch (vertical) {
      case BusinessVertical.retail:
        return Icons.storefront_rounded;
      case BusinessVertical.restaurant:
        return Icons.restaurant_menu_rounded;
      case BusinessVertical.pharmacy:
        return Icons.local_pharmacy_outlined;
      case BusinessVertical.workshop:
        return Icons.build_circle_outlined;
      case BusinessVertical.laundry:
        return Icons.local_laundry_service_outlined;
      case BusinessVertical.salon:
        return Icons.content_cut_rounded;
    }
  }

  void _showBusinessVerticalModal(BuildContext context) {
    final currentVertical = context.read<PosCubit>().state.currentVertical;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final tokens = NusaThemeTokens.of(ctx);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mode Bisnis Toko',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sesuaikan tampilan dan alur kerja Kasir POS dengan jenis usaha Anda. Perubahan langsung aktif tanpa restart.',
                  style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
                ),
                const SizedBox(height: 16),
                ...BusinessVertical.values.map((v) {
                  final isSelected = v == currentVertical;
                  final caps = VerticalConfig.getCapabilities(v);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: NusaCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderColor: isSelected ? tokens.accent : tokens.borderSubtle,
                      borderWidth: isSelected ? 1.5 : tokens.borderWidth,
                      backgroundColor: isSelected ? tokens.accentSoft : tokens.bgElevated,
                    onTap: () async {
                      await context.read<PosCubit>().setBusinessVertical(v);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.successDark,
                            content: Text(
                              'Mode bisnis aktif diubah ke ${v.label} (${caps.posDisplayName}).',
                            ),
                          ),
                        );
                      }
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.14)
                                : AppColors.slate100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _verticalIcon(v),
                            size: 21,
                            color: isSelected ? AppColors.primary : AppColors.slate600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                v.shortDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isSelected)
                          const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
      },
    );
  }

  void _showAboutDialog(BuildContext context, PosState posState) {
    final printerName = _printerService.isWifiMode
        ? _printerService.activePrinterLabel
        : (_printerService.connectedPrinter?.name ?? 'Belum Terhubung');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storefront_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'OXO.ID Mobile',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Versi 2.0.0 Enterprise (Multi-Industry POS)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text('Mode Bisnis: ${posState.currentVertical.label}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Database Lokal: SQLite Terindeks (${posState.allProducts.length} SKU)', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Printer Thermal ESC/POS: $printerName (${_printerService.paperWidth})', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Status Cloud: ${posState.isOnline ? 'Online & Sinkron' : 'Mode Offline Aman'}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            const Text(
              'Platform Kasir POS Offline-First, Operasional Toko & 50 Laporan Bisnis oleh OXO.ID.',
              style: TextStyle(fontSize: 11.5, color: AppColors.slate500),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSyncData(BuildContext context) async {
    final syncedCount = await context.read<PosCubit>().syncOfflineTransactions();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.successDark,
          content: Text(
            syncedCount > 0
                ? '$syncedCount transaksi offline berhasil disinkronkan ke Cloud!'
                : 'Seluruh data usaha sudah 100% tersinkronisasi dengan OXO Cloud.',
          ),
        ),
      );
    }
  }

  ThemeCubit? _maybeThemeCubit(BuildContext context) {
    try {
      return context.watch<ThemeCubit>();
    } catch (_) {
      return null;
    }
  }

  void _showThemeModeModal(BuildContext context, ThemeCubit themeCubit) {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tema Tampilan CDO Warm Linen',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih tampilan paling nyaman: Warm Linen Terang, Mode Gelap, atau Kontras Tinggi Outdoor POS.',
                style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
              ),
              const SizedBox(height: 14),
              ...NusaThemeMode.values.map((mode) {
                final selected = themeCubit.state == mode;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NusaCard(
                    backgroundColor: selected ? tokens.accentSoft : tokens.bgSurface,
                    borderColor: selected ? tokens.accent : tokens.borderSubtle,
                    borderWidth: selected ? 1.6 : tokens.borderWidth,
                    onTap: () async {
                      await themeCubit.setThemeMode(mode);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Row(
                      children: [
                        Icon(mode.icon, color: selected ? tokens.accent : tokens.textPrimary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            mode.label,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          const NusaBadge(label: 'Aktif', variant: NusaBadgeVariant.primary),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final themeCubit = _maybeThemeCubit(context);
    final session = context.watch<AuthCubit>().state.session;
    final posState = context.watch<PosCubit>().state;
    final offlinePending = posState.offlinePendingCount;
    final displayName = session.userName.trim().isEmpty
        ? 'Pengguna OXO.ID'
        : session.userName.trim();
    final tenantLabel = session.isLocalTrial
        ? 'Mode Toko Mandiri (Offline Lokal)'
        : (session.tenantName.trim().isEmpty ? 'OXO.ID' : session.tenantName.trim());

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          children: [
            // 1. Authenticated Operator & Store Summary Card
            InkWell(
              onTap: () => context.push('/store-profile'),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
                  boxShadow: tokens.isDark || tokens.isHighContrast ? null : AppColors.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_rounded, size: 32, color: tokens.accentDark),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            session.userEmail.isEmpty ? session.userRole : '${session.userRole} • ${session.userEmail}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$tenantLabel • ${session.activeStore.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.accentDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: tokens.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (session.isLocalTrial) ...[
              NusaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: tokens.accentSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.cloud_upload_outlined, color: tokens.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Upgrade & Cadangkan ke OXO Cloud',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Sinkronkan seluruh produk, pelanggan, buku bon & riwayat transaksi lokal dari HP ini ke server Cloud.',
                                style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    NusaButton(
                      label: 'Hubungkan Akun Cloud & Migrasi Data',
                      icon: Icons.cloud_sync_outlined,
                      minHeight: 46,
                      onPressed: () => showCloudMigrationSheet(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 2. Operational Master Data & Branch Switcher Shortcuts
            NusaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.swap_horiz_rounded,
                    title: 'Ganti Cabang Toko Aktif',
                    subtitle: '${session.activeStore.name} (${session.availableStores.length} cabang)',
                    onTap: () => _showSwitchStoreBranchModal(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.business_center_outlined,
                    title: 'Mode Bisnis Toko',
                    subtitle: '${posState.capabilities.posDisplayName} • ${posState.currentVertical.label}',
                    onTap: () => _showBusinessVerticalModal(context),
                  ),
                  if (themeCubit != null) ...[
                    Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                    _buildSettingsTile(
                      tokens,
                      icon: tokens.mode.icon,
                      title: 'Tema Tampilan (CDO Warm Linen)',
                      subtitle: tokens.mode.label,
                      onTap: () => _showThemeModeModal(context, themeCubit),
                    ),
                  ],
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.people_outline_rounded,
                    title: 'Manajemen Pelanggan & Member',
                    subtitle: 'Data member, grup diskon, poin & limit kasbon',
                    onTap: () => context.push('/customers'),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.local_shipping_outlined,
                    title: 'Manajemen Pemasok & Stok Masuk',
                    subtitle: 'Daftar pemasok, rekening transfer & penerimaan stok',
                    onTap: () => context.push('/suppliers'),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.storefront_outlined,
                    title: 'Profil Toko & Header Struk',
                    subtitle: 'Atur nama toko, alamat, nomor telepon & footer struk',
                    onTap: () => context.push('/store-profile'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Hardware, Server API, & Sync Settings
            NusaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _buildSettingsTile(
                    tokens,
                    icon: _printerService.isWifiMode ? Icons.wifi_rounded : Icons.print_outlined,
                    title: 'Pengaturan Printer Thermal (BT / WiFi)',
                    subtitle: _printerService.isWifiMode
                        ? '${_printerService.activePrinterLabel} • Kertas ${_printerService.paperWidth}'
                        : (_printerService.savedMacAddress != null
                            ? 'Bluetooth: ${_printerService.connectedPrinter?.name ?? _printerService.savedMacAddress} (${_printerService.paperWidth})'
                            : 'Kertas ${_printerService.paperWidth} • Bluetooth, WiFi LAN 9100 & RJ-11'),
                    onTap: () => _showBluetoothPrinterModal(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.dns_outlined,
                    title: 'Server Cloud, Edge & Kode Terminal',
                    subtitle: 'Node ${posState.activeNodeCode} • ${_apiClient.baseUrl}',
                    onTap: () => _showServerEndpointModal(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.cloud_upload_outlined,
                    title: 'Sinkronisasi Data & Backup Offline',
                    subtitle: offlinePending > 0
                        ? '$offlinePending transaksi menunggu sinkronisasi Cloud'
                        : 'Seluruh transaksi dan katalog sinkron dengan Cloud',
                    onTap: () => _handleSyncData(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.help_outline_rounded,
                    title: 'Bantuan & Panduan Operasional',
                    subtitle: 'Pusat panduan fitur POS, FEFO & Buku Bon',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Pusat Bantuan OXO.ID'),
                          content: const Text(
                            'Aplikasi ini terhubung otomatis ke OXO Cloud Multi-Tenant.\n\n'
                            '• Scan Barcode mendukung EAN-13 & Timbangan Digital Prefix 20/21.\n'
                            '• Saat internet terputus, transaksi tetap tersimpan aman di memori perangkat.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti')),
                          ],
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.info_outline_rounded,
                    title: 'Tentang OXO.ID Mobile',
                    subtitle: 'Versi 2.0.0 Enterprise',
                    onTap: () => _showAboutDialog(context, posState),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 4. Outlined Red Logout Button (>= 48dp)
            NusaButton(
              label: 'Keluar Sesi (Logout)',
              icon: Icons.logout_rounded,
              variant: NusaButtonVariant.danger,
              minHeight: 50,
              onPressed: () async {
                final posCubit = context.read<PosCubit>();
                await context.read<AuthCubit>().logout();
                await posCubit.resetForLogout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    NusaThemeTokens tokens, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: tokens.textPrimary, size: 24),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: tokens.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: tokens.textSecondary,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: tokens.textTertiary),
      onTap: onTap,
    );
  }
}
