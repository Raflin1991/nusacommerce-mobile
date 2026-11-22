import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// MODUL HRD, DIREKTORI KARYAWAN & PRESENSI CABANG (Live API Bound)
class HrAttendanceScreen extends StatefulWidget {
  const HrAttendanceScreen({super.key});

  @override
  State<HrAttendanceScreen> createState() => _HrAttendanceScreenState();
}

class _HrAttendanceScreenState extends State<HrAttendanceScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();

  bool _loading = true;
  bool _clockSubmitting = false;
  String? _error;
  int? _selectedStoreFilter;

  int _totalEmployees = 0;
  int _presentToday = 0;
  int _lateToday = 0;
  int _onLeaveToday = 0;

  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _selectedStoreFilter = context.read<AuthCubit>().state.session.activeStore.id;
    if (_isLocalStandalone) {
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadHrData();
      });
    }
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  Future<void> _loadHrData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_isLocalStandalone) {
      setState(() {
        _loading = false;
      });
      return;
    }

    try {
      final params = <String, dynamic>{};
      if (_selectedStoreFilter != null && _selectedStoreFilter! > 0) {
        params['store_id'] = _selectedStoreFilter;
      }

      final results = await Future.wait([
        _api.dio.get(ApiEndpoints.hrSummary, queryParameters: params),
        _api.dio.get(ApiEndpoints.hrEmployees, queryParameters: params),
      ]);

      final sumData = Map<String, dynamic>.from((results[0].data?['data'] as Map?) ?? {});
      final rawStores = (sumData['stores'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawEmps = (results[1].data?['data'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _stores = rawStores;
        _employees = rawEmps;
        _totalEmployees = (sumData['total_employees'] as num?)?.toInt() ?? rawEmps.length;
        _presentToday = (sumData['present_today'] as num?)?.toInt() ?? 0;
        _lateToday = (sumData['late_today'] as num?)?.toInt() ?? 0;
        _onLeaveToday = (sumData['on_leave_today'] as num?)?.toInt() ?? 0;
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

  Future<void> _submitClock({
    required String action,
    int? employeeId,
    String? employeeName,
  }) async {
    if (_clockSubmitting) return;
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          action == 'clock_in' ? 'Konfirmasi Clock-In' : 'Konfirmasi Clock-Out',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              employeeName != null
                  ? 'Catat ${action == 'clock_in' ? 'masuk kerja' : 'pulang'} untuk $employeeName?'
                  : 'Catat ${action == 'clock_in' ? 'masuk kerja (Clock-In)' : 'pulang kerja (Clock-Out)'} akun Anda saat ini?',
              style: const TextStyle(fontSize: 13.5, color: AppColors.slate700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan Shift / Kehadiran (Opsional)',
                hintText: 'Contoh: Shift Pagi Tablet Kasir 1',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action == 'clock_in' ? 'Clock-In Sekarang' : 'Clock-Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clockSubmitting = true);
    try {
      final res = await _api.dio.post(ApiEndpoints.hrClock, data: {
        'action': action,
        if (employeeId != null) 'employee_id': employeeId,
        if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
      });
      final msg = (res.data?['message'] ?? 'Presensi berhasil dicatat.').toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.successDark, content: Text(msg)),
      );
      await _loadHrData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(ApiClient.extractErrorMessage(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _clockSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final kpiColumns = width >= 840 ? 4 : 2;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        title: const Text('HRD, Tim & Presensi'),
        actions: [
          IconButton(
            onPressed: _loadHrData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLocalStandalone
          ? const NusaEmptyState(
              icon: Icons.badge_outlined,
              title: 'HRD & Absensi Terhubung Cloud',
              subtitle:
                  'Fitur absensi karyawan, rekap kehadiran harian, dan manajemen staf multi-cabang aktif saat login ke akun Cloud Enterprise.',
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_rounded, size: 48, color: tokens.danger),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: tokens.textPrimary)),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _loadHrData,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHrData,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          // Quick Self Clock-In / Clock-Out Bar (360dp phone & tablet safe)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: tokens.heroGradientColors),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.14),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Presensi Cepat Operator',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14.5,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Catat jam masuk & pulang langsung ke HR Cloud',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: _clockSubmitting
                                          ? null
                                          : () => _submitClock(action: 'clock_in'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: tokens.positive,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Clock-In'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _clockSubmitting
                                          ? null
                                          : () => _submitClock(action: 'clock_out'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.white54),
                                      ),
                                      child: const Text('Clock-Out'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          if (_stores.length > 1) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: NusaPillFilter(
                                      label: 'Semua Cabang',
                                      selected: _selectedStoreFilter == null,
                                      onTap: () {
                                        setState(() => _selectedStoreFilter = null);
                                        _loadHrData();
                                      },
                                    ),
                                  ),
                                  ..._stores.map((s) {
                                    final sid = (s['id'] as num?)?.toInt();
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: NusaPillFilter(
                                        label: (s['name'] ?? 'Cabang').toString(),
                                        selected: _selectedStoreFilter == sid,
                                        onTap: () {
                                          setState(() => _selectedStoreFilter = sid);
                                          _loadHrData();
                                        },
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          GridView.count(
                            crossAxisCount: kpiColumns,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: width >= 840 ? 1.85 : 1.7,
                            children: [
                              _kpiTile(tokens, 'Total Staf Aktif', '$_totalEmployees Orang', tokens.accent),
                              _kpiTile(tokens, 'Hadir Hari Ini', '$_presentToday Orang', tokens.positive),
                              _kpiTile(tokens, 'Terlambat', '$_lateToday Orang', tokens.warning),
                              _kpiTile(tokens, 'Cuti / Izin', '$_onLeaveToday Orang', tokens.textSecondary),
                            ],
                          ),
                          const SizedBox(height: 18),

                          Text(
                            'Direktori Karyawan (${_employees.length})',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_employees.isEmpty)
                            const NusaEmptyState(
                              icon: Icons.people_outline_rounded,
                              title: 'Belum Ada Data Karyawan',
                              subtitle: 'Tambahkan data karyawan pada cabang ini melalui portal Web Admin Cloud.',
                            )
                          else
                            ..._employees.map((emp) {
                              final id = (emp['id'] as num?)?.toInt() ?? 0;
                              final name = (emp['full_name'] ?? emp['name'] ?? 'Karyawan').toString();
                              final title = (emp['job_title'] ?? 'Staf Toko').toString();
                              final dept = (emp['department'] ?? '-').toString();
                              final storeName = ((emp['store'] as Map?)?['name'] ?? '-').toString();
                              final todayStatus = emp['today_status']?.toString();
                              final clockIn = emp['today_clock_in']?.toString();
                              final clockOut = emp['today_clock_out']?.toString();

                              NusaBadgeVariant badgeVar = NusaBadgeVariant.neutral;
                              String statusLabel = 'BELUM ABSEN';
                              if (todayStatus == 'late') {
                                badgeVar = NusaBadgeVariant.warning;
                                statusLabel = 'TERLAMBAT ($clockIn)';
                              } else if (todayStatus == 'present') {
                                badgeVar = clockOut != null ? NusaBadgeVariant.primary : NusaBadgeVariant.success;
                                statusLabel = clockOut != null
                                    ? 'PULANG ($clockIn-$clockOut)'
                                    : 'HADIR ($clockIn)';
                              }

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: NusaCard(
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: tokens.accentSoft,
                                        child: Text(
                                          name.isNotEmpty ? name[0].toUpperCase() : 'K',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: tokens.accentDark,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: tokens.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              '$title • $dept • $storeName',
                                              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                                            ),
                                            const SizedBox(height: 6),
                                            NusaBadge(label: statusLabel, variant: badgeVar),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        onSelected: (action) => _submitClock(
                                          action: action,
                                          employeeId: id,
                                          employeeName: name,
                                        ),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'clock_in', child: Text('Catat Clock-In')),
                                          PopupMenuItem(value: 'clock_out', child: Text('Catat Clock-Out')),
                                        ],
                                      ),
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

  Widget _kpiTile(NusaThemeTokens tokens, String label, String value, Color accent) {
    return NusaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.textSecondary),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
