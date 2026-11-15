import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/presentation/cloud_upgrade_sheet.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 9 — PENGATURAN SISTEM NUSACOMMERCE (TAB 5 NAVIGASI)
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ganti Cabang Toko Aktif',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navyDark),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pilih cabang aktif. Katalog produk dan stok otomatis disesuaikan dengan cabang ini.',
              style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
            ),
            const SizedBox(height: 14),
            if (stores.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Hanya 1 cabang aktif yang terdaftar pada akun ini.',
                  style: TextStyle(color: AppColors.slate500),
                ),
              )
            else
              ...stores.map((branch) {
                final isCurrent = branch.id == session.activeStore.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NusaCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    borderColor: isCurrent ? AppColors.primary : AppColors.border,
                    borderWidth: isCurrent ? 1.5 : 1.0,
                    backgroundColor: isCurrent ? AppColors.primarySoft : Colors.white,
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
                          color: isCurrent ? AppColors.primary : AppColors.slate600,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                branch.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              if (branch.address != null && branch.address!.isNotEmpty)
                                Text(
                                  branch.address!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
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
      ),
    );
  }

  void _showServerEndpointModal(BuildContext context) {
    final urlCtrl = TextEditingController(text: _apiClient.baseUrl);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
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
              'Konfigurasi Server API Cloud',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ubah endpoint REST API v1 jika berpindah server atau domain lokal Laragon.',
              style: TextStyle(fontSize: 12.5, color: AppColors.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Endpoint REST API v1',
                prefixIcon: Icon(Icons.cloud_outlined),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _apiClient.setBaseUrl(urlCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Endpoint server disimpan: ${_apiClient.baseUrl}')),
                    );
                  }
                },
                child: const Text('Simpan Endpoint Server'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBluetoothPrinterModal(BuildContext context) {
    bool isScanning = true;
    bool hasInitializedScan = false;
    bool isConnecting = false;
    String selectedPrinterRole = 'kasir';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (!hasInitializedScan) {
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Pengaturan Printer Kasir (Bluetooth)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                        ),
                      ),
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
                  const Text(
                    'Pilih printer Bluetooth thermal paired (58mm/80mm) untuk disimpan & auto-reconnect saat aplikasi dibuka.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Ukuran Kertas Thermal',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
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
                    backgroundColor: AppColors.background,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          title: const Text('Auto-Cut Kertas Struk', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          subtitle: const Text('Potong otomatis setelah transaksi selesai', style: TextStyle(fontSize: 11.5)),
                          value: _printerService.autoCutPaper,
                          onChanged: (val) async {
                            await _printerService.savePreferences(autoCut: val);
                            if (ctx.mounted) setModalState(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        SwitchListTile.adaptive(
                          title: const Text('Buka Laci Otomatis (RJ-11)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          subtitle: const Text('Kirim pulse pembuka laci pada pembayaran tunai', style: TextStyle(fontSize: 11.5)),
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
                  const Text(
                    'Routing Multi-Printer (Pilih Stasiun Target)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
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
                    backgroundColor: AppColors.background,
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
                      const Text(
                        'Perangkat Bluetooth Terdeteksi (Paired)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
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
                        color: AppColors.slate100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.bluetooth_disabled_rounded, color: AppColors.slate500, size: 28),
                          SizedBox(height: 6),
                          Text(
                            'Belum ada printer Bluetooth yang ter-pair.',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pasangkan (Pair) printer thermal melalui Pengaturan Bluetooth Android lalu tekan "Pindai Ulang".',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: AppColors.slate500),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: NusaButton(
                          label: 'Test Print Struk',
                          icon: Icons.receipt_long_rounded,
                          variant: NusaButtonVariant.outline,
                          minHeight: 46,
                          onPressed: () async {
                            final previewText = _printerService.formatTestPrintReceiptText(
                              storeProfile: _offlineDb.getStoreProfile(),
                            );
                            final sentPhysical = await _printerService.printReceiptText(previewText);
                            if (context.mounted && sentPhysical) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: AppColors.successDark,
                                  content: Text('Test Print ESC/POS berhasil dicetak ke printer Bluetooth!'),
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
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
                                content: Text(
                                  ok
                                      ? 'Pulse RJ-11 berhasil membuka laci: $hexStr'
                                      : 'Printer Bluetooth belum tersambung (Pulse RJ-11: $hexStr)',
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mode Bisnis Toko',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sesuaikan tampilan dan alur kerja Kasir POS dengan jenis usaha Anda. Perubahan langsung aktif tanpa restart.',
                style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
              ),
              const SizedBox(height: 16),
              ...BusinessVertical.values.map((v) {
                final isSelected = v == currentVertical;
                final caps = VerticalConfig.getCapabilities(v);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NusaCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    borderColor: isSelected ? AppColors.primary : AppColors.border,
                    borderWidth: isSelected ? 1.5 : 1.0,
                    backgroundColor: isSelected ? AppColors.primarySoft : Colors.white,
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
      ),
    );
  }

  void _showAboutDialog(BuildContext context, PosState posState) {
    final printerName = _printerService.connectedPrinter?.name ?? 'Belum Terhubung';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storefront_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'NusaCommerce Mobile',
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
              'Arsitektur Multi-Tenant Enterprise oleh NUSA Commerce Cloud.',
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
                : 'Seluruh data usaha sudah 100% tersinkronisasi dengan NusaCommerce Cloud.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    final posState = context.watch<PosCubit>().state;
    final offlinePending = posState.offlinePendingCount;
    final displayName = session.userName.trim().isEmpty
        ? 'Pengguna NusaCommerce'
        : session.userName.trim();
    final tenantLabel = session.isLocalTrial
        ? 'Mode Toko Mandiri (Offline Lokal)'
        : (session.tenantName.trim().isEmpty ? 'NusaCommerce' : session.tenantName.trim());

    return Scaffold(
      backgroundColor: AppColors.background,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, size: 32, color: AppColors.primaryDark),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            session.userEmail.isEmpty ? session.userRole : '${session.userRole} • ${session.userEmail}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.slate500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$tenantLabel • ${session.activeStore.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
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
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.cloud_upload_outlined, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Upgrade & Cadangkan ke NusaCommerce Cloud',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Sinkronkan seluruh produk, pelanggan, buku bon & riwayat transaksi lokal dari HP ini ke server Cloud.',
                                style: TextStyle(fontSize: 12, color: AppColors.slate600),
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
                    icon: Icons.swap_horiz_rounded,
                    title: 'Ganti Cabang Toko Aktif',
                    subtitle: '${session.activeStore.name} (${session.availableStores.length} cabang)',
                    onTap: () => _showSwitchStoreBranchModal(context),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.business_center_outlined,
                    title: 'Mode Bisnis Toko',
                    subtitle: '${posState.capabilities.posDisplayName} • ${posState.currentVertical.label}',
                    onTap: () => _showBusinessVerticalModal(context),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.people_outline_rounded,
                    title: 'Manajemen Pelanggan & Member',
                    subtitle: 'Data member, grup diskon, poin & limit kasbon',
                    onTap: () => context.push('/customers'),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.local_shipping_outlined,
                    title: 'Manajemen Pemasok & Stok Masuk',
                    subtitle: 'Daftar pemasok, rekening transfer & penerimaan stok',
                    onTap: () => context.push('/suppliers'),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
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
                    icon: Icons.print_outlined,
                    title: 'Pengaturan Printer Kasir',
                    subtitle: _printerService.savedMacAddress != null
                        ? 'Tersimpan: ${_printerService.connectedPrinter?.name ?? _printerService.savedMacAddress} (${_printerService.paperWidth})'
                        : 'Kertas ${_printerService.paperWidth} • Scan Bluetooth, Test Print & RJ-11',
                    onTap: () => _showBluetoothPrinterModal(context),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.dns_outlined,
                    title: 'Konfigurasi Server API Cloud',
                    subtitle: _apiClient.baseUrl,
                    onTap: () => _showServerEndpointModal(context),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Sinkronisasi Data & Backup Offline',
                    subtitle: offlinePending > 0
                        ? '$offlinePending transaksi menunggu sinkronisasi Cloud'
                        : 'Seluruh transaksi dan katalog sinkron dengan Cloud',
                    onTap: () => _handleSyncData(context),
                  ),
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Bantuan & Panduan Operasional',
                    subtitle: 'Pusat panduan fitur POS, FEFO & Buku Bon',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Pusat Bantuan NusaCommerce'),
                          content: const Text(
                            'Aplikasi ini terhubung otomatis ke NusaCommerce Cloud Multi-Tenant.\n\n'
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
                  const Divider(height: 1, indent: 56, color: AppColors.border),
                  _buildSettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Tentang NusaCommerce Mobile',
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
                await context.read<AuthCubit>().logout();
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

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: AppColors.navyDark, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: AppColors.navyDark,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.slate500,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
      onTap: onTap,
    );
  }
}
