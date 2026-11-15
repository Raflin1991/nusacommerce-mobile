import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/business_vertical_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../bloc/auth_cubit.dart';

/// Multi-Tenant Cloud & Day-0 Standalone Login Screen
class LoginScreen extends StatefulWidget {
  final ApiClient apiClient;

  const LoginScreen({super.key, required this.apiClient});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginEntryMode { cloud, standalone }

class _LoginScreenState extends State<LoginScreen> {
  final _tenantController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _storeNameController = TextEditingController(text: 'Toko Saya');
  final _openingCashController = TextEditingController(text: '100000');

  _LoginEntryMode _entryMode = _LoginEntryMode.cloud;
  BusinessVertical _selectedVertical = BusinessVertical.retail;
  bool _obscurePassword = true;
  bool _startingStandalone = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill only last non-trial cloud subdomain if user previously logged into one,
    // never hardcoding another tenant's email or password by default.
    final lastSlug = widget.apiClient.getTenantSlug();
    if (lastSlug != null &&
        lastSlug.trim().isNotEmpty &&
        lastSlug.trim().toLowerCase() != 'local-trial') {
      _tenantController.text = lastSlug.trim();
    }
  }

  @override
  void dispose() {
    _tenantController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _storeNameController.dispose();
    _openingCashController.dispose();
    super.dispose();
  }

  String _normalizeTenantInput(String raw) {
    var clean = raw.trim().toLowerCase();
    clean = clean.replaceFirst(RegExp(r'^https?://'), '');
    if (clean.contains('/')) {
      clean = clean.split('/').first;
    }
    if (clean.contains('.')) {
      clean = clean.split('.').first;
    }
    return clean;
  }

  Future<void> _loginWithPreset({
    required String tenant,
    required String email,
    required String password,
  }) async {
    setState(() {
      _entryMode = _LoginEntryMode.cloud;
      _tenantController.text = tenant;
      _emailController.text = email;
      _passwordController.text = password;
    });
    await _submitLogin();
  }

  Future<void> _submitLogin() async {
    final normalizedTenant = _normalizeTenantInput(_tenantController.text);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (normalizedTenant.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subdomain toko, email, dan kata sandi wajib diisi.'),
        ),
      );
      return;
    }

    final authCubit = context.read<AuthCubit>();
    final posCubit = context.read<PosCubit>();

    final success = await authCubit.login(
      tenantDomain: normalizedTenant,
      email: email,
      password: password,
    );
    if (success && mounted) {
      await posCubit.resetForLogout();
      await posCubit.initializeCatalog(seedDefaultCart: false);
      await posCubit.syncWithCloud(force: true);
      if (mounted) {
        context.go('/home');
      }
    }
  }

  Future<void> _startStandaloneStore() async {
    if (_startingStandalone) return;
    setState(() => _startingStandalone = true);
    try {
      final cleanCashStr =
          _openingCashController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final openingCash = double.tryParse(cleanCashStr) ?? 100000.0;
      final storeName = _storeNameController.text.trim().isEmpty
          ? 'Toko Saya'
          : _storeNameController.text.trim();

      final authCubit = context.read<AuthCubit>();
      final posCubit = context.read<PosCubit>();

      await posCubit.resetForLogout();
      await authCubit.startLocalTrialSession(
        storeName: storeName,
        businessVertical: _selectedVertical.key,
        openingCash: openingCash,
      );
      await posCubit.setBusinessVertical(_selectedVertical);
      await posCubit.initializeCatalog(seedDefaultCart: false);

      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) {
        setState(() => _startingStandalone = false);
      }
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
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Konfigurasi Server API Cloud',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gunakan URL domain Laragon/Cloud Anda atau http://10.0.2.2:8000/api/v1 untuk Android Emulator.',
              style: TextStyle(fontSize: 12.5, color: AppColors.slate600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Endpoint REST API v1',
                hintText: 'https://nusacommerce.test/api/v1',
                prefixIcon: Icon(Icons.cloud_outlined),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  await widget.apiClient.setBaseUrl(urlCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Server API disimpan: ${widget.apiClient.baseUrl}'),
                      ),
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

  String _verticalSubtitle(BusinessVertical vertical) {
    switch (vertical) {
      case BusinessVertical.retail:
        return 'Barcode, Stok & Bon';
      case BusinessVertical.restaurant:
        return 'Meja, Takeaway & Dapur';
      case BusinessVertical.pharmacy:
        return 'Resep & Batch FEFO';
      case BusinessVertical.workshop:
        return 'Nopol, Mekanik & Jasa';
      case BusinessVertical.laundry:
        return 'Kiloan & Status Order';
      case BusinessVertical.salon:
        return 'Stylist & Layanan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiHost = Uri.tryParse(widget.apiClient.baseUrl)?.host ??
        widget.apiClient.baseUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Info NusaCommerce',
          icon: const Icon(Icons.info_outline_rounded, color: AppColors.navyDark),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text(
          'Masuk NusaCommerce',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.navyDark,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: _showServerUrlModal,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.primaryLight),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dns_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      apiHost.isEmpty ? 'Server API' : apiHost,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBrandHeader(),
                      const SizedBox(height: 12),
                      _buildModeSwitcher(),
                      const SizedBox(height: 12),
                      if (state.errorMessage != null &&
                          _entryMode == _LoginEntryMode.cloud) ...[
                        _buildErrorBanner(state.errorMessage!),
                        const SizedBox(height: 12),
                      ],
                      if (_entryMode == _LoginEntryMode.cloud)
                        _buildCloudLoginSection(state)
                      else
                        _buildStandaloneSetupSection(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.executiveNavyGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          NusaBrandLogo(
            size: 50,
            borderRadius: 14,
            padding: const EdgeInsets.all(7),
            borderColor: Colors.white.withOpacity(0.28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NusaCommerce POS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _entryMode == _LoginEntryMode.cloud
                      ? 'Masuk ke server toko Anda untuk sinkronisasi multi-cabang real-time.'
                      : 'Siap jualan 100% di HP/Tablet tanpa perlu internet, login, atau server.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSwitcher() {
    final isCloud = _entryMode == _LoginEntryMode.cloud;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.slate100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTabButton(
              icon: Icons.cloud_done_outlined,
              label: 'Akun Cloud Toko',
              selected: isCloud,
              accentColor: AppColors.primary,
              onTap: () => setState(() => _entryMode = _LoginEntryMode.cloud),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeTabButton(
              icon: Icons.storefront_rounded,
              label: 'Toko Mandiri (Gratis)',
              badge: 'Offline',
              selected: !isCloud,
              accentColor: AppColors.successDark,
              onTap: () =>
                  setState(() => _entryMode = _LoginEntryMode.standalone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.dangerDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.dangerDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudLoginSection(AuthState state) {
    final previewSlug = _normalizeTenantInput(_tenantController.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow,
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Subdomain / Kode Toko',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.navyDark,
                      ),
                    ),
                    if (previewSlug.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$previewSlug.nusco.id',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _tenantController,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Contoh: warungmaju',
                    prefixIcon:
                        const Icon(Icons.domain_rounded, color: AppColors.primary),
                    suffixText: '.nusco.id',
                    suffixIcon: _tenantController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Bersihkan',
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: AppColors.slate400),
                            onPressed: () {
                              _tenantController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Email Pengguna (Owner / Kasir)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'owner@tokoanda.co.id',
                    prefixIcon:
                        Icon(Icons.email_outlined, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Kata Sandi',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => state.isLoading ? null : _submitLogin(),
                  decoration: InputDecoration(
                    hintText: 'Masukkan kata sandi',
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.primary),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Tampilkan sandi'
                          : 'Sembunyikan sandi',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: state.isLoading ? null : _submitLogin,
                    icon: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Icon(Icons.login_rounded, size: 20),
                    label: Text(
                      state.isLoading
                          ? 'Menghubungkan Toko...'
                          : 'Masuk & Sinkronkan Toko',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Prominent 1-Tap Switch CTA to Day-0 Standalone Trial
        InkWell(
          onTap: () => setState(() => _entryMode = _LoginEntryMode.standalone),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.success.withOpacity(0.10),
                  AppColors.primary.withOpacity(0.06),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.success.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.rocket_launch_rounded,
                      color: AppColors.successDark, size: 19),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Belum punya akun Cloud?',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyDark,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Mulai Coba Gratis Mode Toko Mandiri tanpa login',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.slate600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 15, color: AppColors.successDark),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Compact UAT Quick Demo Access
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: AppColors.primary),
                  SizedBox(width: 5),
                  Text(
                    'Coba Akun Demo Server (1-Ketuk Masuk)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        side: const BorderSide(color: AppColors.primaryLight),
                        backgroundColor: AppColors.primarySoft,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.admin_panel_settings_outlined,
                              size: 15, color: AppColors.primaryDark),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Owner Manunggal',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        side: const BorderSide(color: AppColors.successSoft),
                        backgroundColor: AppColors.successSoft.withOpacity(0.55),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.point_of_sale_rounded,
                              size: 15, color: AppColors.successDark),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Kasir Siti',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.successDark,
                              ),
                            ),
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
    );
  }

  Widget _buildStandaloneSetupSection() {
    const cashPresets = ['50000', '100000', '200000', '500000'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successSoft.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.offline_bolt_rounded,
                    color: AppColors.successDark, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Data stok, nota, utang-piutang & laporan tersimpan 100% di perangkat ini dan tetap aman jika nanti naik ke Cloud.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navyDark,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '1. Nama Usaha / Toko',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _storeNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Contoh: Warung Maju Jaya / Kopi Senja',
              prefixIcon: Icon(Icons.store_mall_directory_outlined,
                  color: AppColors.successDark),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '2. Pilih Jenis Usaha',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.35,
            children: BusinessVertical.values.map((v) {
              final selected = _selectedVertical == v;
              return InkWell(
                onTap: () => setState(() => _selectedVertical = v),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primarySoft : AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withOpacity(0.14)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _verticalIcon(v),
                          size: 17,
                          color: selected
                              ? AppColors.primary
                              : AppColors.slate600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              v.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: selected
                                    ? AppColors.primaryDark
                                    : AppColors.navyDark,
                              ),
                            ),
                            Text(
                              _verticalSubtitle(v),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            '3. Modal Kas Awal Laci (Rp)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _openingCashController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '100000',
              prefixText: 'Rp ',
              prefixIcon:
                  Icon(Icons.payments_outlined, color: AppColors.successDark),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cashPresets.map((amount) {
              final cleanCurrent = _openingCashController.text
                  .replaceAll(RegExp(r'[^0-9]'), '');
              final active = cleanCurrent == amount;
              final shortLabel = 'Rp ${int.parse(amount) ~/ 1000}rb';
              return InkWell(
                onTap: () =>
                    setState(() => _openingCashController.text = amount),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.successSoft
                        : AppColors.slate100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? AppColors.success : AppColors.border,
                    ),
                  ),
                  child: Text(
                    shortLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? AppColors.successDark
                          : AppColors.slate600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _startingStandalone ? null : _startStandaloneStore,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: _startingStandalone
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch_rounded, size: 20),
              label: Text(
                _startingStandalone
                    ? 'Menyiapkan Toko...'
                    : 'Buka Kasir Toko Mandiri Sekarang',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.icon,
    required this.label,
    this.badge,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected ? AppColors.cardShadow : null,
          border: selected
              ? Border.all(color: accentColor.withOpacity(0.28))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? accentColor : AppColors.slate500,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.navyDark : AppColors.slate600,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.successDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
