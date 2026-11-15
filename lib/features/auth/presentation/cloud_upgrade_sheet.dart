import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../bloc/auth_cubit.dart';

/// 1-Click Cloud Connect & Local-to-Cloud Data Migration Sheet for Day-0 Standalone Stores
Future<bool?> showCloudMigrationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _CloudMigrationSheetBody(),
  );
}

class _CloudMigrationSheetBody extends StatefulWidget {
  const _CloudMigrationSheetBody();

  @override
  State<_CloudMigrationSheetBody> createState() => _CloudMigrationSheetBodyState();
}

class _CloudMigrationSheetBodyState extends State<_CloudMigrationSheetBody> {
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();
  final TextEditingController _tenantCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _submitting = false;
  bool _obscurePassword = true;
  String? _localError;

  @override
  void dispose() {
    _tenantCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subdomain = _tenantCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (subdomain.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _localError = 'Subdomain toko, email, dan password wajib diisi.');
      return;
    }

    setState(() {
      _submitting = true;
      _localError = null;
    });

    final authCubit = context.read<AuthCubit>();
    final posCubit = context.read<PosCubit>();
    final messenger = ScaffoldMessenger.of(context);

    final loggedIn = await authCubit.login(
      tenantDomain: subdomain,
      email: email,
      password: password,
    );

    if (!mounted) return;

    if (!loggedIn) {
      setState(() {
        _submitting = false;
        _localError = authCubit.state.errorMessage ??
            'Gagal terhubung ke NusaCommerce Cloud. Data lokal Anda tetap aman di perangkat.';
      });
      return;
    }

    final stats = await posCubit.migrateLocalStandaloneDataToCloud();
    if (!mounted) return;

    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppColors.successDark,
        duration: const Duration(seconds: 5),
        content: Text(
          'Migrasi Cloud berhasil! '
          '${stats['products'] ?? 0} produk, '
          '${stats['customers'] ?? 0} pelanggan, '
          '${stats['suppliers'] ?? 0} pemasok, '
          '${stats['sales'] ?? 0} transaksi & '
          '${stats['expenses'] ?? 0} biaya tersinkron ke Cloud.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsCount = _offlineDb.getCachedProducts().length;
    final customersCount = _offlineDb.getCachedCustomers().length;
    final suppliersCount = _offlineDb.getCachedSuppliers().length;
    final salesCount = _offlineDb.getLocalSalesHistory().length;
    final expensesCount = _offlineDb.getLocalExpenses().length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
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
                          'Hubungkan ke NusaCommerce Cloud',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Migrasi 1-klik: seluruh data lokal HP Anda diunggah aman ke server Cloud.',
                          style: TextStyle(fontSize: 12, color: AppColors.slate600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ringkasan Data Siap Migrasi:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$productsCount Produk • $customersCount Pelanggan • $suppliersCount Pemasok • $salesCount Nota • $expensesCount Biaya',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.slate700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_localError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                  ),
                  child: Text(
                    _localError!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.dangerDark,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _tenantCtrl,
                enabled: !_submitting,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Subdomain Toko Cloud *',
                  hintText: 'contoh: warungmaju (untuk warungmaju.nusco.id)',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailCtrl,
                enabled: !_submitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email Akun NusaCommerce *',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordCtrl,
                enabled: !_submitting,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _submit(),
                decoration: InputDecoration(
                  labelText: 'Password *',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              NusaButton(
                label: 'Hubungkan & Migrasikan Data Sekarang',
                icon: Icons.cloud_sync_rounded,
                isLoading: _submitting,
                minHeight: 50,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
