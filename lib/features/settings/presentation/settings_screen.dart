import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/printer_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 9 — PENGATURAN SISTEM (TAB 5 NAVIGASI)
/// Matches 1:1 with Screen 8 of `Papan Konsep UI KasirKu Modern-1.png`
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PrinterService _printerService = PrinterService();

  void _showBluetoothPrinterModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pengaturan Aplikasi & Printer Thermal Bluetooth',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hubungkan printer ESC/POS 58mm/80mm atau printer internal Sunmi / iMin.',
                style: TextStyle(fontSize: 12.5, color: AppColors.slate500),
              ),
              const SizedBox(height: 14),
              ..._printerService.discoveredDevices.map((dev) {
                final isConnected = _printerService.connectedPrinter?.macAddress == dev.macAddress;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isConnected ? AppColors.successSoft : AppColors.primarySoft,
                    child: Icon(
                      Icons.print_rounded,
                      color: isConnected ? AppColors.successDark : AppColors.primary,
                    ),
                  ),
                  title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('MAC: ${dev.macAddress} • Kertas: ${dev.paperSize}'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConnected ? AppColors.success : AppColors.primary,
                    ),
                    onPressed: () {
                      setModalState(() => _printerService.connectDevice(dev));
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Terhubung ke printer ${dev.name} (${dev.paperSize})')),
                      );
                    },
                    child: Text(isConnected ? 'Terhubung' : 'Hubungkan'),
                  ),
                );
              }),
            ],
          ),
        ),
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
    final offlinePending = context.watch<PosCubit>().state.offlinePendingCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          children: [
            // 1. User Profile Card ("Raflin Abdul / Pemilik Usaha" Persis Mockup Screen 8)
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
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, size: 34, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.userName.contains(' ') ? session.userName : '${session.userName} Abdul',
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            session.userRole,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.slate500,
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

            // 2. Settings Menu List Card (Persis Mockup Screen 8)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.storefront_outlined,
                    title: 'Profil Toko',
                    subtitle: 'Atur informasi toko',
                    onTap: () => context.push('/store-profile'),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingsTile(
                    icon: Icons.settings_outlined,
                    title: 'Pengaturan Aplikasi',
                    subtitle: _printerService.connectedPrinter != null
                        ? 'Printer: ${_printerService.connectedPrinter!.name}'
                        : 'Bahasa, tema, notifikasi & printer Bluetooth',
                    onTap: () => _showBluetoothPrinterModal(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingsTile(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Data & Backup',
                    subtitle: offlinePending > 0
                        ? '$offlinePending transaksi menunggu sinkronisasi Cloud'
                        : 'Cadangkan data usaha',
                    onTap: () => _handleSyncData(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingsTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Bantuan & Panduan',
                    subtitle: 'Pusat bantuan & FAQ',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Pusat Bantuan NusaCommerce'),
                          content: const Text(
                            'Aplikasi ini terhubung otomatis ke NusaCommerce Cloud Multi-Tenant.\n\n'
                            '• Scan Barcode mendukung EAN-13 & Timbangan Digital Prefix 20/21.\n'
                            '• Saat internet terputus, transaksi tetap tersimpan aman di memori HP.',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mengerti')),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildSettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'Tentang Aplikasi',
                    subtitle: 'Versi 1.0.0',
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 3. Outlined Red Logout Button ("[🚪 Keluar]" Persis Mockup Screen 8)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await context.read<AuthCubit>().logout();
                  if (context.mounted) {
                    context.go('/');
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.5),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.danger),
                label: const Text(
                  'Keluar',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                  ),
                ),
              ),
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
