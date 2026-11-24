part of 'offline_database.dart';

extension OfflineDatabaseVerticalSeedsExt on OfflineDatabase {
  // ===========================================================================
  // 7. STANDALONE TRIAL SEEDING (6 VERTICAL TEMPLATES)
  // ===========================================================================
  Future<List<Map<String, dynamic>>> seedVerticalSampleProductsIfEmpty(
    String verticalCode, {
    bool forceReseed = false,
  }) async {
    final existing = getCachedProducts();
    final hasLeakedCloudProducts = existing.any((p) {
      final id = (p['id'] as num?)?.toInt() ?? 0;
      return p['is_local_only'] != true && id > 0 && id < 1000000000;
    });
    if (!forceReseed && existing.isNotEmpty && !hasLeakedCloudProducts) {
      return existing;
    }
    if (hasLeakedCloudProducts || forceReseed) {
      final prevIdentity = getActiveTenantIdentity();
      final prevVertical = getSavedBusinessVertical();
      final prevProfile = _prefs.getString(OfflineDatabase._keyStoreProfile);
      await clearTenantCache();
      if (prevIdentity != null && prevIdentity.startsWith('local-trial')) {
        await setActiveTenantIdentity(prevIdentity);
      }
      if (prevVertical != null && prevVertical.isNotEmpty) {
        await setSavedBusinessVertical(prevVertical);
      }
      if (prevProfile != null && prevProfile.isNotEmpty) {
        await _prefs.setString(OfflineDatabase._keyStoreProfile, prevProfile);
      }
    }

    final code = verticalCode.trim().toLowerCase();
    final List<Map<String, dynamic>> samples;

    switch (code) {
      case 'restaurant':
      case 'fnb':
      case 'cafe':
        samples = [
          {
            'id': -101,
            'name': 'Kopi Susu Gula Aren',
            'sku': 'FNB-001',
            'barcode': '899000100101',
            'type': 'standard',
            'selling_price': 18000.0,
            'cost_price': 8500.0,
            'stock': 50.0,
            'reorder_level': 10.0,
            'unit_code': 'cup',
            'category_id': 1,
            'category_name': 'Minuman',
            'icon_type': 'coffee',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Americano Iced',
            'sku': 'FNB-002',
            'barcode': '899000100102',
            'type': 'standard',
            'selling_price': 15000.0,
            'cost_price': 6000.0,
            'stock': 50.0,
            'reorder_level': 10.0,
            'unit_code': 'cup',
            'category_id': 1,
            'category_name': 'Minuman',
            'icon_type': 'coffee',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Nasi Goreng Spesial',
            'sku': 'FNB-003',
            'barcode': '899000100103',
            'type': 'standard',
            'selling_price': 25000.0,
            'cost_price': 13000.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'porsi',
            'category_id': 2,
            'category_name': 'Makanan Berat',
            'icon_type': 'food',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Ayam Geprek Sambal Matah',
            'sku': 'FNB-004',
            'barcode': '899000100104',
            'type': 'standard',
            'selling_price': 22000.0,
            'cost_price': 12000.0,
            'stock': 35.0,
            'reorder_level': 5.0,
            'unit_code': 'porsi',
            'category_id': 2,
            'category_name': 'Makanan Berat',
            'icon_type': 'food',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Kentang Goreng Crispy',
            'sku': 'FNB-005',
            'barcode': '899000100105',
            'type': 'standard',
            'selling_price': 14000.0,
            'cost_price': 6500.0,
            'stock': 40.0,
            'reorder_level': 8.0,
            'unit_code': 'porsi',
            'category_id': 3,
            'category_name': 'Snack',
            'icon_type': 'food',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Es Teh Manis Jumbo',
            'sku': 'FNB-006',
            'barcode': '899000100106',
            'type': 'standard',
            'selling_price': 7000.0,
            'cost_price': 2000.0,
            'stock': 80.0,
            'reorder_level': 10.0,
            'unit_code': 'gelas',
            'category_id': 1,
            'category_name': 'Minuman',
            'icon_type': 'drink',
            'is_local_only': true,
          },
        ];
        break;

      case 'pharmacy':
      case 'apotek':
        samples = [
          {
            'id': -101,
            'name': 'Paracetamol 500mg',
            'sku': 'APT-001',
            'barcode': '899000200101',
            'type': 'standard',
            'selling_price': 8000.0,
            'cost_price': 4500.0,
            'stock': 60.0,
            'reorder_level': 10.0,
            'unit_code': 'strip',
            'category_id': 1,
            'category_name': 'Obat Bebas',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Vitamin C 1000mg',
            'sku': 'APT-002',
            'barcode': '899000200102',
            'type': 'standard',
            'selling_price': 25000.0,
            'cost_price': 17000.0,
            'stock': 40.0,
            'reorder_level': 8.0,
            'unit_code': 'tube',
            'category_id': 2,
            'category_name': 'Vitamin',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Antasida Doen Sirup',
            'sku': 'APT-003',
            'barcode': '899000200103',
            'type': 'standard',
            'selling_price': 18500.0,
            'cost_price': 12500.0,
            'stock': 25.0,
            'reorder_level': 5.0,
            'unit_code': 'btl',
            'category_id': 1,
            'category_name': 'Obat Bebas',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Amoxicillin 500mg',
            'sku': 'APT-004',
            'barcode': '899000200104',
            'type': 'standard',
            'selling_price': 15000.0,
            'cost_price': 9000.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'strip',
            'category_id': 3,
            'category_name': 'Obat Resep',
            'requires_prescription': true,
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Masker Medis 3-Ply (Box 50)',
            'sku': 'APT-005',
            'barcode': '899000200105',
            'type': 'standard',
            'selling_price': 28000.0,
            'cost_price': 18000.0,
            'stock': 20.0,
            'reorder_level': 5.0,
            'unit_code': 'box',
            'category_id': 4,
            'category_name': 'Alkes',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Minyak Kayu Putih 60ml',
            'sku': 'APT-006',
            'barcode': '899000200106',
            'type': 'standard',
            'selling_price': 24000.0,
            'cost_price': 16500.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'btl',
            'category_id': 2,
            'category_name': 'Vitamin & Herbal',
            'icon_type': 'pharmacy',
            'is_local_only': true,
          },
        ];
        break;

      case 'workshop':
      case 'bengkel':
        samples = [
          {
            'id': -101,
            'name': 'Oli Mesin MPX2 0.8L',
            'sku': 'BKL-001',
            'barcode': '899000300101',
            'type': 'standard',
            'selling_price': 58000.0,
            'cost_price': 44000.0,
            'stock': 30.0,
            'reorder_level': 6.0,
            'unit_code': 'btl',
            'category_id': 1,
            'category_name': 'Oli & Pelumas',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Jasa Servis Tune-Up Ringan',
            'sku': 'BKL-002',
            'barcode': '899000300102',
            'type': 'service',
            'selling_price': 45000.0,
            'cost_price': 10000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'jasa',
            'category_id': 2,
            'category_name': 'Jasa Bengkel',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Kampas Rem Depan Matic',
            'sku': 'BKL-003',
            'barcode': '899000300103',
            'type': 'standard',
            'selling_price': 42000.0,
            'cost_price': 26000.0,
            'stock': 20.0,
            'reorder_level': 4.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Sparepart',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Busi Standar Beat / Vario',
            'sku': 'BKL-004',
            'barcode': '899000300104',
            'type': 'standard',
            'selling_price': 22000.0,
            'cost_price': 13000.0,
            'stock': 35.0,
            'reorder_level': 5.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Sparepart',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Oli Gardan Matic 120ml',
            'sku': 'BKL-005',
            'barcode': '899000300105',
            'type': 'standard',
            'selling_price': 18000.0,
            'cost_price': 11000.0,
            'stock': 40.0,
            'reorder_level': 8.0,
            'unit_code': 'pcs',
            'category_id': 1,
            'category_name': 'Oli & Pelumas',
            'icon_type': 'service',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Jasa Tambal Ban Tubeless',
            'sku': 'BKL-006',
            'barcode': '899000300106',
            'type': 'service',
            'selling_price': 20000.0,
            'cost_price': 3000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'jasa',
            'category_id': 2,
            'category_name': 'Jasa Bengkel',
            'icon_type': 'service',
            'is_local_only': true,
          },
        ];
        break;

      case 'laundry':
        samples = [
          {
            'id': -101,
            'name': 'Cuci Komplit Reguler (2 Hari)',
            'sku': 'LND-001',
            'barcode': '899000400101',
            'type': 'service',
            'selling_price': 7000.0,
            'cost_price': 2500.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'kg',
            'sold_by_weight': true,
            'category_id': 1,
            'category_name': 'Kiloan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Cuci Express Kilat (6 Jam)',
            'sku': 'LND-002',
            'barcode': '899000400102',
            'type': 'service',
            'selling_price': 14000.0,
            'cost_price': 4000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'kg',
            'sold_by_weight': true,
            'category_id': 1,
            'category_name': 'Kiloan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Setrika Uap Saja',
            'sku': 'LND-003',
            'barcode': '899000400103',
            'type': 'service',
            'selling_price': 5000.0,
            'cost_price': 1500.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'kg',
            'sold_by_weight': true,
            'category_id': 1,
            'category_name': 'Kiloan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Cuci Bedcover Besar',
            'sku': 'LND-004',
            'barcode': '899000400104',
            'type': 'service',
            'selling_price': 35000.0,
            'cost_price': 10000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'pcs',
            'category_id': 2,
            'category_name': 'Satuan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Cuci Sepatu Deep Clean',
            'sku': 'LND-005',
            'barcode': '899000400105',
            'type': 'service',
            'selling_price': 30000.0,
            'cost_price': 7000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'psg',
            'category_id': 2,
            'category_name': 'Satuan',
            'icon_type': 'laundry',
            'is_local_only': true,
          },
        ];
        break;

      case 'salon':
      case 'barbershop':
        samples = [
          {
            'id': -101,
            'name': 'Potong Rambut + Cuci',
            'sku': 'SLN-001',
            'barcode': '899000500101',
            'type': 'service',
            'selling_price': 40000.0,
            'cost_price': 8000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 1,
            'category_name': 'Haircut',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Creambath Aromatherapy',
            'sku': 'SLN-002',
            'barcode': '899000500102',
            'type': 'service',
            'selling_price': 65000.0,
            'cost_price': 18000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 2,
            'category_name': 'Perawatan',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Shaving & Beard Trim',
            'sku': 'SLN-003',
            'barcode': '899000500103',
            'type': 'service',
            'selling_price': 25000.0,
            'cost_price': 5000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 1,
            'category_name': 'Haircut',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Pomade Waterbased Premium',
            'sku': 'SLN-004',
            'barcode': '899000500104',
            'type': 'standard',
            'selling_price': 75000.0,
            'cost_price': 48000.0,
            'stock': 20.0,
            'reorder_level': 4.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Produk Rambut',
            'icon_type': 'salon',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Hair Coloring Natural',
            'sku': 'SLN-005',
            'barcode': '899000500105',
            'type': 'service',
            'selling_price': 120000.0,
            'cost_price': 42000.0,
            'stock': 999.0,
            'reorder_level': 0.0,
            'unit_code': 'sesi',
            'category_id': 2,
            'category_name': 'Perawatan',
            'icon_type': 'salon',
            'is_local_only': true,
          },
        ];
        break;

      case 'retail':
      default:
        samples = [
          {
            'id': -101,
            'name': 'Indomie Goreng Original',
            'sku': 'RTL-001',
            'barcode': '899000000101',
            'type': 'standard',
            'selling_price': 3500.0,
            'cost_price': 2700.0,
            'stock': 80.0,
            'reorder_level': 12.0,
            'unit_code': 'pcs',
            'category_id': 1,
            'category_name': 'Sembako',
            'icon_type': 'retail',
            'is_local_only': true,
          },
          {
            'id': -102,
            'name': 'Aqua Botol 600ml',
            'sku': 'RTL-002',
            'barcode': '899000000102',
            'type': 'standard',
            'selling_price': 4000.0,
            'cost_price': 2500.0,
            'stock': 60.0,
            'reorder_level': 12.0,
            'unit_code': 'btl',
            'category_id': 2,
            'category_name': 'Minuman',
            'icon_type': 'drink',
            'is_local_only': true,
          },
          {
            'id': -103,
            'name': 'Beras Pandan Wangi 5kg',
            'sku': 'RTL-003',
            'barcode': '899000000103',
            'type': 'standard',
            'selling_price': 74000.0,
            'cost_price': 64000.0,
            'stock': 20.0,
            'reorder_level': 4.0,
            'unit_code': 'sak',
            'category_id': 1,
            'category_name': 'Sembako',
            'icon_type': 'retail',
            'is_local_only': true,
          },
          {
            'id': -104,
            'name': 'Minyak Goreng Pouch 1L',
            'sku': 'RTL-004',
            'barcode': '899000000104',
            'type': 'standard',
            'selling_price': 18500.0,
            'cost_price': 15500.0,
            'stock': 35.0,
            'reorder_level': 6.0,
            'unit_code': 'pcs',
            'category_id': 1,
            'category_name': 'Sembako',
            'icon_type': 'retail',
            'is_local_only': true,
          },
          {
            'id': -105,
            'name': 'Kopi Kapal Api Mix 165g',
            'sku': 'RTL-005',
            'barcode': '899000000105',
            'type': 'standard',
            'selling_price': 16000.0,
            'cost_price': 12500.0,
            'stock': 30.0,
            'reorder_level': 5.0,
            'unit_code': 'pak',
            'category_id': 2,
            'category_name': 'Minuman',
            'icon_type': 'coffee',
            'is_local_only': true,
          },
          {
            'id': -106,
            'name': 'Sabun Cuci Piring 750ml',
            'sku': 'RTL-006',
            'barcode': '899000000106',
            'type': 'standard',
            'selling_price': 15000.0,
            'cost_price': 11200.0,
            'stock': 25.0,
            'reorder_level': 5.0,
            'unit_code': 'pcs',
            'category_id': 3,
            'category_name': 'Kebersihan',
            'icon_type': 'retail',
            'is_local_only': true,
          },
        ];
        break;
    }

    await cacheProducts(samples);

    final cats = <int, Map<String, dynamic>>{
      0: {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': samples.length},
    };
    for (final s in samples) {
      final cid = (s['category_id'] as num?)?.toInt() ?? 1;
      final cname = (s['category_name'] ?? 'Umum').toString();
      if (!cats.containsKey(cid)) {
        cats[cid] = {'id': cid, 'name': cname, 'color': '#2563EB', 'products_count': 1};
      } else {
        cats[cid]!['products_count'] = ((cats[cid]!['products_count'] as int?) ?? 0) + 1;
      }
    }
    await cacheCategories(cats.values.toList());

    if (getCachedCustomers().isEmpty) {
      await cacheCustomers([
        {
          'id': -201,
          'name': 'Pelanggan Langganan',
          'phone': '081234567890',
          'outstanding_balance': 0.0,
          'store_credit_balance': 0.0,
          'points_balance': 0,
          'is_local_only': true,
        },
      ]);
    }
    if (getCachedSuppliers().isEmpty) {
      await cacheSuppliers([
        {
          'id': -301,
          'name': 'Supplier Utama',
          'phone': '081200001111',
          'address': 'Pusat Grosir Setempat',
          'is_local_only': true,
        },
      ]);
    }
    return samples;
  }

}
