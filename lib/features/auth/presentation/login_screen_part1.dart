// ignore_for_file: invalid_use_of_protected_member
part of 'login_screen.dart';

extension _LoginScreenStatePart1Ext on _LoginScreenState {

  OfflineDatabase? get _offlineDb {
    try {
      return context.read<AuthCubit>().offlineDb;
    } catch (_) {
      return null;
    }
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

    final success = await authCubit.login(
      tenantDomain: normalizedTenant,
      email: email,
      password: password,
    );
    // MainNavigationShell reactively detects AuthState.sessionRevision changes and triggers
    // clean local reset + full paginated SQLite master data restore with a live progress banner.
    if (success && mounted) {
      context.go('/home');
    }
  }


  Future<void> _resumeStandaloneStore() async {
    if (_startingStandalone) return;
    setState(() {
      _startingStandalone = true;
      _standaloneError = null;
    });
    try {
      final authCubit = context.read<AuthCubit>();
      final ok = await authCubit.resumeLocalTrialSession(
        pin: _standalonePinController.text.trim(),
      );
      if (!ok) {
        if (mounted) {
          setState(() {
            _standaloneError =
                authCubit.state.errorMessage ?? 'Gagal membuka toko offline. Periksa PIN Anda.';
          });
        }
        return;
      }

      try {
        final posCubit = context.read<PosCubit>();
        await posCubit.initializeCatalog(seedDefaultCart: false, awaitCloudSync: false);
      } catch (_) {}

      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) {
        setState(() => _startingStandalone = false);
      }
    }
  }


  Future<void> _startStandaloneStore() async {
    if (_startingStandalone) return;
    setState(() {
      _startingStandalone = true;
      _standaloneError = null;
    });
    try {
      final cleanCashStr =
          _openingCashController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final openingCash = double.tryParse(cleanCashStr) ?? 100000.0;
      final storeName = _storeNameController.text.trim().isEmpty
          ? 'Toko Saya'
          : _storeNameController.text.trim();

      final authCubit = context.read<AuthCubit>();
      PosCubit? posCubit;
      try {
        posCubit = context.read<PosCubit>();
      } catch (_) {}

      await posCubit?.resetForLogout();
      await authCubit.startLocalTrialSession(
        storeName: storeName,
        businessVertical: _selectedVertical.key,
        openingCash: openingCash,
      );
      await posCubit?.setBusinessVertical(_selectedVertical);
      await posCubit?.initializeCatalog(seedDefaultCart: false);

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
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
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
                  color: tokens.borderDefault,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Konfigurasi Server API Cloud',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: tokens.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Pilih preset server atau masukkan URL kustom:',
              style: TextStyle(fontSize: 12.5, color: tokens.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.cloud_done_outlined, size: 16),
                  label: const Text('Cloud VPS', style: TextStyle(fontSize: 12)),
                  onPressed: () => urlCtrl.text = ApiEndpoints.vpsServerUrl,
                ),
                ActionChip(
                  avatar: const Icon(Icons.laptop_outlined, size: 16),
                  label: const Text('Lokal Laragon', style: TextStyle(fontSize: 12)),
                  onPressed: () => urlCtrl.text = ApiEndpoints.laragonDomainUrl,
                ),
                ActionChip(
                  avatar: const Icon(Icons.phone_android_outlined, size: 16),
                  label: const Text('Emulator (10.0.2.2)', style: TextStyle(fontSize: 12)),
                  onPressed: () => urlCtrl.text = 'http://10.0.2.2/api/v1',
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Endpoint REST API v1',
                hintText: 'https://oxora.test/api/v1',
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


  String _formatServerChipLabel(String rawHost) {
    final cleaned = rawHost.trim().toLowerCase();
    if (cleaned.isEmpty ||
        cleaned.contains('nusacommerce') ||
        cleaned == '43.159.49.77' ||
        cleaned == 'localhost' ||
        cleaned == '127.0.0.1') {
      return 'oxora.id';
    }
    return rawHost.trim();
  }


  Widget _buildBrandHeader() {
    final tokens = NusaThemeTokens.of(context);
    final isDark = tokens.isDark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            isDark
                ? 'assets/images/oxora_wordmark_dark.png'
                : 'assets/images/oxora_wordmark_light.png',
            height: 44,
            fit: BoxFit.contain,
            semanticLabel: 'OXORA',
          ),
          const SizedBox(height: 12),
          Text(
            _entryMode == _LoginEntryMode.cloud
                ? 'Masuk ke server toko Anda untuk\nsinkronisasi multi-cabang real-time'
                : 'Siap jualan 100% di HP/Tablet tanpa perlu\ninternet, login, atau server.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? tokens.textSecondary : const Color(0xFF1E293B),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildModeSwitcher() {
    final tokens = NusaThemeTokens.of(context);
    final isDark = tokens.isDark;
    final isCloud = _entryMode == _LoginEntryMode.cloud;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? tokens.bgElevated : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? tokens.borderSubtle : const Color(0xFFE2E8F0),
          width: tokens.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTabButton(
              icon: Icons.storefront_rounded,
              label: 'Akun Cloud Toko',
              selected: isCloud,
              accentColor: const Color(0xFF0052FF),
              onTap: () => setState(() => _entryMode = _LoginEntryMode.cloud),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ModeTabButton(
              icon: Icons.store_mall_directory_rounded,
              label: 'Toko Mandiri (Offline)',
              selected: !isCloud,
              accentColor: NusaThemeTokens.of(context).positive,
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
        color: NusaThemeTokens.of(context).dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NusaThemeTokens.of(context).danger.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: NusaThemeTokens.of(context).danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: NusaThemeTokens.of(context).danger,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
