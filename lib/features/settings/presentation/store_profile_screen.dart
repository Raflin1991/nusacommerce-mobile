import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../auth/bloc/auth_cubit.dart';

/// LAYAR 10 — PROFIL TOKO & HEADER STRUK OXORA
class StoreProfileScreen extends StatefulWidget {
  final OfflineDatabase offlineDb;

  const StoreProfileScreen({super.key, required this.offlineDb});

  @override
  State<StoreProfileScreen> createState() => _StoreProfileScreenState();
}

class _StoreProfileScreenState extends State<StoreProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _footerController;

  @override
  void initState() {
    super.initState();
    final session = context.read<AuthCubit>().state.session;
    final profile = widget.offlineDb.getStoreProfile();

    final storedName = (profile['name'] ?? '').toString().trim();
    final storedAddress = (profile['address'] ?? '').toString().trim();
    final storedPhone = (profile['phone'] ?? '').toString().trim();
    final storedFooter = (profile['receipt_footer'] ?? '').toString().trim();

    final fallbackName = session.tenantName.trim().isNotEmpty
        ? session.tenantName.trim()
        : (session.activeStore.name.trim().isNotEmpty ? session.activeStore.name.trim() : 'OXORA POS');
    final fallbackAddress = (session.activeStore.address ?? '').trim().isNotEmpty
        ? session.activeStore.address!.trim()
        : '-';
    final fallbackPhone = (session.activeStore.phone ?? '').trim().isNotEmpty
        ? session.activeStore.phone!.trim()
        : '-';

    _nameController = TextEditingController(
      text: (storedName.isEmpty || storedName == 'NusaCommerce POS' || storedName == 'OXO.ID POS' || storedName == 'OXORA POS') ? fallbackName : storedName,
    );
    _addressController = TextEditingController(
      text: (storedAddress.isEmpty || storedAddress == '-') ? fallbackAddress : storedAddress,
    );
    _phoneController = TextEditingController(
      text: (storedPhone.isEmpty || storedPhone == '-') ? fallbackPhone : storedPhone,
    );
    _footerController = TextEditingController(
      text: storedFooter.isNotEmpty
          ? storedFooter
          : 'Terima kasih telah berbelanja di ${_nameController.text.trim()}!',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final session = context.read<AuthCubit>().state.session;
    final footerText = _footerController.text.trim();
    await widget.offlineDb.saveStoreProfile({
      'name': _nameController.text.trim(),
      'branch': session.activeStore.name,
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(),
      'receipt_footer': footerText.isNotEmpty
          ? footerText
          : 'Terima kasih telah berbelanja di ${_nameController.text.trim()}!',
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.successDark,
          content: Text('Profil Toko berhasil disimpan dan disinkronkan ke header struk!'),
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;

    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Profil Toko & Struk'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Structured Enterprise Store Header Preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppColors.executiveNavyGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.activeStore.name.isEmpty ? 'Cabang Aktif' : session.activeStore.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Kode: ${session.activeStore.code} • Header Struk Thermal & WhatsApp',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Form Inputs Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nama Toko (Header Struk)',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate600, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Alamat Cabang',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate600, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _addressController,
                      maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Nomor Telepon / WhatsApp Toko',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate600, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Footer Struk Kasir',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate600, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _footerController,
                      maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      decoration: const InputDecoration(
                        hintText: 'Pesan ucapan / syarat penukaran di bagian bawah struk',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // 3. Full-Width Blue Button: "Simpan Perubahan"
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Simpan Perubahan',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
