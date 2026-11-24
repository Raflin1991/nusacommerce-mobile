// ignore_for_file: invalid_use_of_protected_member
part of 'login_screen.dart';

extension _LoginScreenStatePart3Ext on _LoginScreenState {
  Widget _buildExistingStandaloneStoreCard(OfflineDatabase db) {
    final tokens = NusaThemeTokens.of(context);
    final profile = db.getSavedStoreProfile() ?? db.getStoreProfile();
    final storeName = (profile['name'] ?? 'Toko Saya').toString();
    final address = (profile['address'] ?? 'Mode Toko Mandiri (Offline Lokal)').toString();
    final verticalKey = (profile['business_vertical'] ?? db.getSavedBusinessVertical() ?? 'retail').toString();
    final vertical = VerticalConfig.parse(verticalKey);
    final productsCount = db.getCachedProducts().length;
    final salesCount = db.getLocalSalesHistory().length;
    final heldCount = db.getHeldSales().length;
    final hasPin = (profile['cashier_pin_hash'] ?? '').toString().trim().isNotEmpty;

    return Container(
      key: const Key('existing_standalone_store_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        boxShadow: tokens.isDark || tokens.isHighContrast ? null : NusaThemeTokens.of(context).cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.accent.withOpacity(0.28)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tokens.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.accent.withOpacity(0.25)),
                  ),
                  child: Icon(_verticalIcon(vertical), color: tokens.accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOKO OFFLINE TERSIMPAN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: tokens.accentDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${vertical.label} • $address',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSavedStatPill(tokens, Icons.inventory_2_outlined, '$productsCount Produk'),
              const SizedBox(width: 8),
              _buildSavedStatPill(tokens, Icons.receipt_long_outlined, '$salesCount Nota'),
              if (heldCount > 0) ...[
                const SizedBox(width: 8),
                _buildSavedStatPill(tokens, Icons.pause_circle_outline_rounded, '$heldCount Tahan'),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: NusaThemeTokens.of(context).positiveSoft.withOpacity(0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NusaThemeTokens.of(context).positive.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 17, color: NusaThemeTokens.of(context).positive),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Database lokal SQLite aman tersimpan permanen. Langsung buka kasir untuk melanjutkan operasional.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: NusaThemeTokens.of(context).textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasPin) ...[
            const SizedBox(height: 14),
            Text(
              'Masukkan PIN Kasir',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _standalonePinController,
              keyboardType: TextInputType.number,
              obscureText: _obscurePin,
              maxLength: 6,
              onChanged: (_) {
                if (_standaloneError != null) {
                  setState(() => _standaloneError = null);
                }
              },
              onSubmitted: (_) => _startingStandalone ? null : _resumeStandaloneStore(),
              decoration: InputDecoration(
                hintText: 'Masukkan 4–6 digit PIN kasir',
                counterText: '',
                prefixIcon: Icon(Icons.pin_outlined, color: tokens.accent),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
              ),
            ),
          ],
          if (_standaloneError != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(_standaloneError!),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('resume_standalone_store_button'),
              onPressed: _startingStandalone ? null : _resumeStandaloneStore,
              style: ElevatedButton.styleFrom(
                backgroundColor: NusaThemeTokens.of(context).positive,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _startingStandalone
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(hasPin ? Icons.lock_open_rounded : Icons.point_of_sale_rounded, size: 20),
              label: Text(
                _startingStandalone
                    ? 'Membuka Kasir...'
                    : (hasPin ? 'Masuk PIN & Buka Kasir' : 'Buka Kasir Toko Ini'),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Untuk menghapus seluruh data lokal & membuat toko baru, gunakan menu Pengaturan → Reset Pabrik.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }


  Widget _buildSavedStatPill(NusaThemeTokens tokens, IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: tokens.accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
