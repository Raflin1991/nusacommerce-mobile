// ignore_for_file: invalid_use_of_protected_member
part of 'login_screen.dart';

extension _LoginScreenStatePart2Ext on _LoginScreenState {

  Widget _buildCloudLoginSection(AuthState state) {
    final tokens = NusaThemeTokens.of(context);
    final previewSlug = _normalizeTenantInput(_tenantController.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
            boxShadow: tokens.isDark || tokens.isHighContrast ? null : NusaThemeTokens.of(context).cardShadow,
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Subdomain / Kode Toko',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    if (previewSlug.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$previewSlug.oxora.id',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tokens.accentDark,
                          ),
                        ),
                      ),
                    ],
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
                        Icon(Icons.storefront_rounded, color: NusaThemeTokens.of(context).accent),
                    suffixText: '.oxora.id',
                    suffixIcon: _tenantController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Bersihkan',
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: NusaThemeTokens.of(context).textTertiary),
                            onPressed: () {
                              _tenantController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Email Pengguna (Owner / Kasir)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: NusaThemeTokens.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'owner@tokoanda.co.id',
                    prefixIcon:
                        Icon(Icons.email_outlined, color: NusaThemeTokens.of(context).accent),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Kata Sandi',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: NusaThemeTokens.of(context).textPrimary,
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
                    prefixIcon: Icon(Icons.lock_outline_rounded,
                        color: NusaThemeTokens.of(context).accent),
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
                  NusaThemeTokens.of(context).positive.withOpacity(0.10),
                  NusaThemeTokens.of(context).accent.withOpacity(0.06),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(context).positive.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.rocket_launch_rounded,
                      color: NusaThemeTokens.of(context).positive, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Belum punya akun Cloud?',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: NusaThemeTokens.of(context).textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Mulai Coba Gratis Mode Toko Mandiri tanpa login',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: NusaThemeTokens.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 15, color: NusaThemeTokens.of(context).positive),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Compact UAT Quick Demo Access
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: tokens.accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Coba Akun Demo Server (1-Ketuk Masuk)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
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
                        side: BorderSide(color: NusaThemeTokens.of(context).accentSoft),
                        backgroundColor: NusaThemeTokens.of(context).accentSoft,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.admin_panel_settings_outlined,
                              size: 15, color: NusaThemeTokens.of(context).accentDark),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Owner Manunggal',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: NusaThemeTokens.of(context).accentDark,
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
                        side: BorderSide(color: NusaThemeTokens.of(context).positiveSoft),
                        backgroundColor: NusaThemeTokens.of(context).positiveSoft.withOpacity(0.55),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.point_of_sale_rounded,
                              size: 15, color: NusaThemeTokens.of(context).positive),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Kasir Siti',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: NusaThemeTokens.of(context).positive,
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
    final db = _offlineDb;
    if (db != null && db.hasExistingStandaloneStore) {
      return _buildExistingStandaloneStoreCard(db);
    }

    const cashPresets = ['50000', '100000', '200000', '500000'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
        boxShadow: NusaThemeTokens.of(context).cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NusaThemeTokens.of(context).positiveSoft.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.offline_bolt_rounded,
                    color: NusaThemeTokens.of(context).positive, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Data stok, nota, utang-piutang & laporan tersimpan 100% di perangkat ini dan tetap aman jika nanti naik ke Cloud.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: NusaThemeTokens.of(context).textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '1. Nama Usaha / Toko',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: NusaThemeTokens.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _storeNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Contoh: Warung Maju Jaya / Kopi Senja',
              prefixIcon: Icon(Icons.store_mall_directory_outlined,
                  color: NusaThemeTokens.of(context).positive),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '2. Pilih Jenis Usaha',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: NusaThemeTokens.of(context).textPrimary,
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
                    color: selected ? NusaThemeTokens.of(context).accentSoft : NusaThemeTokens.of(context).bgPage,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? NusaThemeTokens.of(context).accent : NusaThemeTokens.of(context).borderSubtle,
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
                              ? NusaThemeTokens.of(context).accent.withOpacity(0.14)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _verticalIcon(v),
                          size: 17,
                          color: selected
                              ? NusaThemeTokens.of(context).accent
                              : NusaThemeTokens.of(context).textSecondary,
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
                                    ? NusaThemeTokens.of(context).accentDark
                                    : NusaThemeTokens.of(context).textPrimary,
                              ),
                            ),
                            Text(
                              _verticalSubtitle(v),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: NusaThemeTokens.of(context).textSecondary,
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
          Text(
            '3. Modal Kas Awal Laci (Rp)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: NusaThemeTokens.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _openingCashController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '100000',
              prefixText: 'Rp ',
              prefixIcon:
                  Icon(Icons.payments_outlined, color: NusaThemeTokens.of(context).positive),
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
                        ? NusaThemeTokens.of(context).positiveSoft
                        : NusaThemeTokens.of(context).bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active ? NusaThemeTokens.of(context).positive : NusaThemeTokens.of(context).borderSubtle,
                    ),
                  ),
                  child: Text(
                    shortLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? NusaThemeTokens.of(context).positive
                          : NusaThemeTokens.of(context).textSecondary,
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
                backgroundColor: NusaThemeTokens.of(context).positive,
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
