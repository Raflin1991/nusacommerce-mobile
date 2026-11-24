import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/edge_discovery_service.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../../core/widgets/shift_inactivity_lock_guard.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/presentation/cloud_upgrade_sheet.dart';
import '../../pos/bloc/pos_cubit.dart';

part 'settings_screen_part1.dart';
part 'settings_screen_part2.dart';
part 'settings_screen_part3.dart';
part 'settings_screen_part4.dart';

/// LAYAR 9 — PENGATURAN SISTEM OXORA (TAB 5 NAVIGASI)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}


class _SettingsScreenState extends State<SettingsScreen> {
  final PrinterService _printerService = GetIt.instance<PrinterService>();

  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  final ApiClient _apiClient = GetIt.instance<ApiClient>();


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final themeCubit = _maybeThemeCubit(context);
    final session = context.watch<AuthCubit>().state.session;
    final posState = context.watch<PosCubit>().state;
    final offlinePending = posState.offlinePendingCount;
    final displayName = session.userName.trim().isEmpty
        ? 'Pengguna OXORA'
        : session.userName.trim();
    final tenantLabel = session.isLocalTrial
        ? 'Mode Toko Mandiri (Offline Lokal)'
        : (session.tenantName.trim().isEmpty ? 'OXORA' : session.tenantName.trim());

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
                  boxShadow: tokens.isDark || tokens.isHighContrast ? null : NusaThemeTokens.of(context).cardShadow,
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
                                'Upgrade & Cadangkan ke OXORA Cloud',
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
                    subtitle:
                        'Node ${posState.activeNodeCode} • ${_tierShortLabel(_apiClient.edgeDiscovery.currentTier)} • Lease: ${_apiClient.lastLeaseState ?? 'aktif'}',
                    onTap: () => _showServerEndpointModal(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.lock_clock_outlined,
                    title: 'Auto-Lock Layar Kasir Saat Idle',
                    subtitle: _idleLockSubtitle(),
                    onTap: () => _showInactivityLockModal(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.cloud_upload_outlined,
                    title: 'Sinkronisasi Data & Backup Offline',
                    subtitle: offlinePending > 0
                        ? '$offlinePending item offline menunggu sinkronisasi Cloud'
                        : 'Seluruh transaksi, piutang, biaya & shift sinkron dengan Cloud',
                    onTap: () => _handleSyncData(context),
                  ),
                  Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                  _buildSettingsTile(
                    tokens,
                    icon: Icons.report_problem_outlined,
                    title: 'Dead-Letter Queue (Gagal Sinkron)',
                    subtitle: posState.deadLetterItems.isNotEmpty
                        ? '${posState.deadLetterItems.length} payload ditolak server perlu ditinjau'
                        : 'Antrean bersih • Tidak ada payload ditolak server',
                    onTap: () => _showDeadLetterQueueModal(context),
                  ),
                  if (session.isLocalTrial) ...[
                    Divider(height: 1, indent: 56, color: tokens.borderSubtle),
                    _buildSettingsTile(
                      tokens,
                      icon: Icons.pin_outlined,
                      title: 'PIN Kasir Offline (Opsional)',
                      subtitle: context.read<AuthCubit>().hasStandalonePin
                          ? 'PIN Aktif • Diminta saat masuk kembali ke toko offline'
                          : 'Belum diatur • Klik untuk kunci akses kasir offline dengan PIN',
                      onTap: () => _showOfflinePinModal(context),
                    ),
                  ],
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
                          title: const Text('Pusat Bantuan OXORA'),
                          content: const Text(
                            'Aplikasi ini terhubung otomatis ke OXORA Cloud Multi-Tenant.\n\n'
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
                    title: 'Tentang OXORA Mobile',
                    subtitle: 'Versi 2.0.0 Enterprise',
                    onTap: () => _showAboutDialog(context, posState),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3b. Danger Zone — Explicit Factory Reset (BUG 1 Guard: ONLY place wiping SQLite!)
            NusaCard(
              padding: EdgeInsets.zero,
              borderColor: tokens.danger.withOpacity(0.35),
              child: ListTile(
                key: const Key('factory_reset_database_tile'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tokens.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.delete_forever_rounded, color: tokens.danger, size: 22),
                ),
                title: Text(
                  'Reset Pabrik / Hapus Seluruh Database',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: tokens.danger,
                  ),
                ),
                subtitle: Text(
                  'Hapus permanen seluruh produk, nota tahan, transaksi & profil toko lokal dari perangkat ini.',
                  style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: tokens.danger),
                onTap: () => _showFactoryResetDialog(context),
              ),
            ),
            const SizedBox(height: 18),

            // 4. Outlined Red Logout Button (>= 48dp) — Safe Session Lock (NEVER wipes offline data!)
            NusaButton(
              label: session.isLocalTrial
                  ? 'Keluar Sesi Kasir (Data Toko Tetap Aman)'
                  : 'Keluar Sesi (Logout)',
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
}
