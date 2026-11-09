import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/widgets/product_illustration_widget.dart';

/// LAYAR 10 — PROFIL TOKO SCREEN
/// Matches 1:1 with Bottom-Right Screen (Screen 9) of `Papan Konsep UI KasirKu Modern-1.png`
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

  @override
  void initState() {
    super.initState();
    final profile = widget.offlineDb.getStoreProfile();
    _nameController = TextEditingController(text: (profile['name'] ?? 'Toko Berkah Jaya').toString());
    _addressController = TextEditingController(text: (profile['address'] ?? 'Jl. Melati No. 12, Jakarta').toString());
    _phoneController = TextEditingController(text: (profile['phone'] ?? '0812 3456 7890').toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    await widget.offlineDb.saveStoreProfile({
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(),
      'receipt_footer': 'Terima kasih telah berbelanja di ${_nameController.text.trim()}!',
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Profil Toko'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 3D Store Banner Illustration with Blue Camera Badge (Persis Mockup Screen 9)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Store3DIllustrationWidget(height: 150, showChartBadge: false),
                    Positioned(
                      right: 26,
                      bottom: 4,
                      child: InkWell(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kamera / Galeri foto toko siap dipilih.')),
                          );
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 19),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Form Inputs Card: Nama Toko, Alamat, Telepon, Logo Toko (Persis Mockup Screen 9)
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
                      'Nama Toko',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate500, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Alamat',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate500, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _addressController,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Telepon',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate500, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Logo Toko',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate500, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 32),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Logo struk thermal diperbarui.')),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: const Text(
                            'Ubah',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navyDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // 3. Full-Width Blue Button: "Simpan Perubahan" (Persis Mockup Screen 9)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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
