import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../bloc/auth_cubit.dart';

/// Multi-Tenant Cloud Login Screen (Subdomain Toko, Email Kasir/Owner, Password)
class LoginScreen extends StatefulWidget {
  final ApiClient apiClient;

  const LoginScreen({super.key, required this.apiClient});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _tenantController = TextEditingController(text: 'manunggal');
  final _emailController = TextEditingController(text: 'direktur@manunggal.co.id');
  final _passwordController = TextEditingController(text: 'Manunggal2026!');
  bool _obscurePassword = true;

  @override
  void dispose() {
    _tenantController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithPreset({
    required String tenant,
    required String email,
    required String password,
  }) async {
    setState(() {
      _tenantController.text = tenant;
      _emailController.text = email;
      _passwordController.text = password;
    });
    await _submitLogin();
  }

  Future<void> _submitLogin() async {
    if (_tenantController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subdomain tenant, email, dan kata sandi wajib diisi.')),
      );
      return;
    }

    final success = await context.read<AuthCubit>().login(
          tenantDomain: _tenantController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
    if (success && mounted) {
      await context.read<PosCubit>().syncWithCloud(force: true);
      if (mounted) {
        context.go('/home');
      }
    }
  }

  void _showStandaloneTrialOnboardingSheet() {
    final storeNameCtrl = TextEditingController(text: 'Toko Saya');
    final openingCashCtrl = TextEditingController(text: '100000');
    BusinessVertical selectedVertical = BusinessVertical.retail;
    bool isStarting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Buka Toko Mandiri (Tanpa Login)',
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '100% gratis & tersimpan lokal di HP/Tablet. Siap jualan dalam 10 detik.',
                            style: TextStyle(fontSize: 12, color: AppColors.slate600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '1. Nama Usaha / Toko',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: storeNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Warung Maju Jaya / Kopi Senja',
                    prefixIcon: Icon(Icons.store_mall_directory_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '2. Pilih Jenis Usaha Anda',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: BusinessVertical.values.map((v) {
                    final selected = selectedVertical == v;
                    return InkWell(
                      onTap: () => setSheetState(() => selectedVertical = v),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary.withOpacity(0.1) : AppColors.slate100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? AppColors.primary : AppColors.border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _verticalIcon(v),
                              size: 16,
                              color: selected ? AppColors.primary : AppColors.slate600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              v.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                color: selected ? AppColors.primary : AppColors.navyDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                const Text(
                  '3. Modal Kas Awal Laci (Rp)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: openingCashCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: '100000',
                    prefixText: 'Rp ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isStarting
                        ? null
                        : () async {
                            setSheetState(() => isStarting = true);
                            final cleanCashStr = openingCashCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                            final openingCash = double.tryParse(cleanCashStr) ?? 100000.0;
                            final storeName = storeNameCtrl.text.trim().isEmpty
                                ? 'Toko Saya'
                                : storeNameCtrl.text.trim();

                            final authCubit = context.read<AuthCubit>();
                            final posCubit = context.read<PosCubit>();
                            await authCubit.startLocalTrialSession(
                              storeName: storeName,
                              businessVertical: selectedVertical.key,
                              openingCash: openingCash,
                            );
                            await posCubit.setBusinessVertical(selectedVertical);
                            await posCubit.initializeCatalog(seedDefaultCart: false);

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              context.go('/home');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: isStarting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.rocket_launch_rounded, size: 19),
                    label: Text(
                      isStarting ? 'Menyiapkan Toko...' : 'Buka Kasir Sekarang',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _verticalIcon(BusinessVertical vertical) {
    switch (vertical) {
      case BusinessVertical.retail:
        return Icons.shopping_basket_rounded;
      case BusinessVertical.restaurant:
        return Icons.restaurant_rounded;
      case BusinessVertical.pharmacy:
        return Icons.local_pharmacy_rounded;
      case BusinessVertical.workshop:
        return Icons.build_rounded;
      case BusinessVertical.laundry:
        return Icons.local_laundry_service_rounded;
      case BusinessVertical.salon:
        return Icons.content_cut_rounded;
    }
  }

  void _showServerUrlModal() {
    final urlCtrl = TextEditingController(text: widget.apiClient.baseUrl);
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
              'Konfigurasi URL Server Cloud',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gunakan http://10.0.2.2:8000/api/v1 untuk Android Emulator atau domain Laragon/Cloud Anda.',
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
                  await widget.apiClient.setBaseUrl(urlCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Server API disimpan: ${widget.apiClient.baseUrl}')),
                    );
                  }
                },
                child: const Text('Simpan Endpoint Cloud'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiHost = Uri.tryParse(widget.apiClient.baseUrl)?.host ?? widget.apiClient.baseUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Info Aplikasi NusaCommerce',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Masuk NusaCommerce'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ActionChip(
              avatar: const Icon(Icons.dns_outlined, size: 15, color: AppColors.primary),
              label: Text(
                apiHost.isEmpty ? 'Server API' : apiHost,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              backgroundColor: AppColors.primarySoft,
              side: const BorderSide(color: AppColors.primaryLight),
              onPressed: _showServerUrlModal,
            ),
          ),
        ],
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.executiveNavyGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white24),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'NC',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NusaCommerce Cloud & POS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Kasir POS Retail, Inventaris FEFO, Pemasok, Buku Bon & Laporan Owner.',
                              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (state.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            state.errorMessage!,
                            style: const TextStyle(
                              color: AppColors.dangerDark,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Subdomain / Kode Toko',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _tenantController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'Contoh: manunggal',
                          prefixIcon: Icon(Icons.domain_rounded, color: AppColors.primary),
                          suffixText: '.nusco.id',
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Email Pengguna (Owner / Kasir)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: 'direktur@tokoanda.co.id',
                          prefixIcon: Icon(Icons.email_outlined, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Kata Sandi',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => state.isLoading ? null : _submitLogin(),
                        decoration: InputDecoration(
                          hintText: 'Masukkan kata sandi',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: state.isLoading ? null : _submitLogin,
                          icon: state.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Icon(Icons.login_rounded, size: 20),
                          label: Text(
                            state.isLoading ? 'Menghubungkan Toko...' : 'Masuk & Sinkronkan Toko',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.success.withOpacity(0.10),
                        AppColors.primary.withOpacity(0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.success.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.rocket_launch_rounded, color: AppColors.success, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Belum Punya Akun Cloud?',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyDark,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Mulai jualan 100% mandiri & offline di HP/Tablet tanpa perlu login.',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.slate600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: state.isLoading ? null : _showStandaloneTrialOnboardingSheet,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.storefront_rounded, size: 19),
                          label: const Text(
                            'Mulai Coba Gratis / Mode Toko Mandiri',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt_rounded, size: 17, color: AppColors.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'Akses Cepat Akun UAT / Demo (1-Ketuk Masuk)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: state.isLoading
                                  ? null
                                  : () => _loginWithPreset(
                                        tenant: 'manunggal',
                                        email: 'direktur@manunggal.co.id',
                                        password: 'Manunggal2026!',
                                      ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                side: const BorderSide(color: AppColors.primaryLight),
                                backgroundColor: AppColors.primarySoft,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Direktur (Owner)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'manunggal • direktur@',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: AppColors.slate600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: state.isLoading
                                  ? null
                                  : () => _loginWithPreset(
                                        tenant: 'manunggal',
                                        email: 'kasir.siti@manunggal.co.id',
                                        password: 'Manunggal2026!',
                                      ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                side: const BorderSide(color: AppColors.successSoft),
                                backgroundColor: AppColors.successSoft.withOpacity(0.55),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kasir Siti (POS)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.successDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'manunggal • kasir.siti@',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: AppColors.slate600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
