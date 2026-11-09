import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';

/// Offline-First Local Database Engine (Isar-equivalent collection manager)
/// Persists Products, Customers, Offline Sale Queue (UUIDv4 idempotent),
/// and Store Profile locally on smartphone / handheld POS storage.
class OfflineDatabase {
  final SharedPreferences _prefs;

  static const String _keyCachedProducts = 'nusa_local_products_v2';
  static const String _keyCachedCategories = 'nusa_local_categories_v2';
  static const String _keyCachedCustomers = 'nusa_local_customers_v2';
  static const String _keyOfflineSalesQueue = 'nusa_offline_sales_queue_v2';
  static const String _keyCompletedSalesHistory = 'nusa_local_sales_history_v2';
  static const String _keyStoreProfile = 'nusa_store_profile_v2';
  static const String _keyPairedPrinter = 'nusa_paired_printer_v2';

  OfflineDatabase(this._prefs);

  // ===========================================================================
  // 1. LOCAL PRODUCT CATALOG CACHE
  // ===========================================================================
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    await _prefs.setString(_keyCachedProducts, jsonEncode(products));
  }

  List<Map<String, dynamic>> getCachedProducts() {
    final raw = _prefs.getString(_keyCachedProducts);
    if (raw == null || raw.isEmpty) return _defaultSeedProducts();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return _defaultSeedProducts();
    }
  }

  Future<void> updateLocalProductStock(int productId, double newStock) async {
    final products = getCachedProducts();
    for (final p in products) {
      if (p['id'] == productId) {
        p['stock'] = newStock;
        p['is_low_stock'] = newStock <= ((p['reorder_level'] as num?)?.toDouble() ?? 5.0);
        break;
      }
    }
    await cacheProducts(products);
  }

  Future<void> addOrUpdateLocalProduct(Map<String, dynamic> product) async {
    final products = getCachedProducts();
    final idx = products.indexWhere((p) => p['id'] == product['id']);
    if (idx >= 0) {
      products[idx] = product;
    } else {
      products.insert(0, product);
    }
    await cacheProducts(products);
  }

  // ===========================================================================
  // 2. CATEGORIES CACHE
  // ===========================================================================
  Future<void> cacheCategories(List<Map<String, dynamic>> categories) async {
    await _prefs.setString(_keyCachedCategories, jsonEncode(categories));
  }

  List<Map<String, dynamic>> getCachedCategories() {
    final raw = _prefs.getString(_keyCachedCategories);
    if (raw == null || raw.isEmpty) {
      return [
        {'id': 0, 'name': 'Semua', 'color': '#2563EB', 'products_count': 8},
        {'id': 1, 'name': 'Minuman', 'color': '#0EA5E9', 'products_count': 3},
        {'id': 2, 'name': 'Snack', 'color': '#F59E0B', 'products_count': 3},
        {'id': 3, 'name': 'Sembako', 'color': '#10B981', 'products_count': 1},
        {'id': 4, 'name': 'Pulsa', 'color': '#8B5CF6', 'products_count': 1},
      ];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // ===========================================================================
  // 3. CUSTOMERS & BUKU BON CACHE
  // ===========================================================================
  Future<void> cacheCustomers(List<Map<String, dynamic>> customers) async {
    await _prefs.setString(_keyCachedCustomers, jsonEncode(customers));
  }

  List<Map<String, dynamic>> getCachedCustomers() {
    final raw = _prefs.getString(_keyCachedCustomers);
    if (raw == null || raw.isEmpty) {
      return [
        {
          'id': 1,
          'code': 'CUST-001',
          'name': 'Budi Santoso (Warung Berkah)',
          'phone': '081234567890',
          'whatsapp_phone': '081234567890',
          'group_name': 'Grosir VIP',
          'default_discount_percent': 5.0,
          'credit_limit': 2000000.0,
          'outstanding_balance': 320000.0,
          'available_credit': 1680000.0,
          'loyalty_points': 240,
        },
        {
          'id': 2,
          'code': 'CUST-002',
          'name': 'Siti Rahmawati',
          'phone': '081398765432',
          'whatsapp_phone': '081398765432',
          'group_name': 'Member Reguler',
          'default_discount_percent': 0.0,
          'credit_limit': 1000000.0,
          'outstanding_balance': 150000.0,
          'available_credit': 850000.0,
          'loyalty_points': 85,
        },
        {
          'id': 3,
          'code': 'CUST-003',
          'name': 'Hendra Wijaya',
          'phone': '085711223344',
          'whatsapp_phone': '085711223344',
          'group_name': 'Umum',
          'default_discount_percent': 0.0,
          'credit_limit': 500000.0,
          'outstanding_balance': 0.0,
          'available_credit': 500000.0,
          'loyalty_points': 40,
        },
      ];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // ===========================================================================
  // 4. OFFLINE SALE QUEUE (IDEMPOTENT SYNC ENGINE)
  // ===========================================================================
  List<Map<String, dynamic>> getOfflineSalesQueue() {
    final raw = _prefs.getString(_keyOfflineSalesQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> enqueueOfflineSale(Map<String, dynamic> salePayload) async {
    final queue = getOfflineSalesQueue();
    queue.add({
      ...salePayload,
      'queued_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });
    await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(queue));
  }

  /// Flush pending offline sales to NusaCommerce Cloud POST /api/v1/pos/checkout
  Future<int> syncOfflineQueue(ApiClient apiClient) async {
    final queue = getOfflineSalesQueue();
    if (queue.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    int syncedCount = 0;

    for (final payload in queue) {
      try {
        await apiClient.dio.post(ApiEndpoints.checkout, data: payload);
        syncedCount++;
      } catch (_) {
        remaining.add(payload);
      }
    }

    await _prefs.setString(_keyOfflineSalesQueue, jsonEncode(remaining));
    return syncedCount;
  }

  // ===========================================================================
  // 5. LOCAL COMPLETED SALES HISTORY (Matches Mockup Screen 5)
  // ===========================================================================
  List<Map<String, dynamic>> getLocalSalesHistory() {
    final raw = _prefs.getString(_keyCompletedSalesHistory);
    if (raw == null || raw.isEmpty) return _defaultSeedSalesHistory();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return _defaultSeedSalesHistory();
    }
  }

  Future<void> saveSaleToLocalHistory(Map<String, dynamic> saleReceipt) async {
    final history = getLocalSalesHistory();
    history.removeWhere((s) => s['number'] == saleReceipt['number']);
    history.insert(0, saleReceipt);
    await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(history));
  }

  Future<void> updateLocalSaleStatus(int saleId, String status, {String? voidReason}) async {
    final history = getLocalSalesHistory();
    for (final s in history) {
      if (s['id'] == saleId) {
        s['status'] = status;
        if (voidReason != null) s['void_reason'] = voidReason;
      }
    }
    await _prefs.setString(_keyCompletedSalesHistory, jsonEncode(history));
  }

  // ===========================================================================
  // 6. STORE PROFILE & PAIRED BLUETOOTH PRINTER
  // ===========================================================================
  Map<String, dynamic> getStoreProfile() {
    final raw = _prefs.getString(_keyStoreProfile);
    if (raw == null || raw.isEmpty) {
      return {
        'name': 'Toko Berkah Jaya',
        'branch': 'Cabang Kemang',
        'address': 'Jl. Melati No. 12, Jakarta',
        'phone': '0812 3456 7890',
        'receipt_footer': 'Terima kasih telah berbelanja di Toko Berkah Jaya!',
        'paper_size': '58mm',
      };
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {'name': 'Toko Berkah Jaya', 'address': 'Jl. Melati No. 12, Jakarta', 'phone': '0812 3456 7890'};
    }
  }

  Future<void> saveStoreProfile(Map<String, dynamic> profile) async {
    await _prefs.setString(_keyStoreProfile, jsonEncode(profile));
  }

  String? getPairedPrinterName() => _prefs.getString(_keyPairedPrinter);

  Future<void> setPairedPrinterName(String? name) async {
    if (name == null) {
      await _prefs.remove(_keyPairedPrinter);
    } else {
      await _prefs.setString(_keyPairedPrinter, name);
    }
  }

  // ===========================================================================
  // DEFAULT REALISTIC SEED DATA (Matches Mockup KasirKu 1:1)
  // ===========================================================================
  List<Map<String, dynamic>> _defaultSeedProducts() {
    return [
      {
        'id': 101,
        'name': 'Air Mineral 600ml',
        'sku': 'MIN-001',
        'barcode': '8992752011001',
        'type': 'standard',
        'selling_price': 5000.0,
        'cost_price': 3200.0,
        'stock': 48.0,
        'unit_code': 'pcs',
        'category_id': 1,
        'category_name': 'Minuman',
        'is_low_stock': false,
        'shelf_location': 'Rak A1 • Baris 1',
        'icon_type': 'water',
        'batches': [
          {'id': 1, 'batch_number': 'BATCH-2027A', 'expiry_date': '2027-08-15', 'quantity': 48.0, 'is_expired': false}
        ],
      },
      {
        'id': 102,
        'name': 'Teh Botol Sosro',
        'sku': 'MIN-002',
        'barcode': '8992752011002',
        'type': 'standard',
        'selling_price': 6000.0,
        'cost_price': 4100.0,
        'stock': 36.0,
        'unit_code': 'btl',
        'category_id': 1,
        'category_name': 'Minuman',
        'is_low_stock': false,
        'shelf_location': 'Cooler B1 • Baris 2',
        'icon_type': 'tea',
        'batches': [
          {'id': 2, 'batch_number': 'BATCH-2027B', 'expiry_date': '2027-05-20', 'quantity': 36.0, 'is_expired': false}
        ],
      },
      {
        'id': 103,
        'name': 'Indomie Goreng',
        'sku': 'SNK-001',
        'barcode': '8992752011003',
        'type': 'standard',
        'selling_price': 3500.0,
        'cost_price': 2850.0,
        'stock': 25.0,
        'reorder_level': 30.0,
        'unit_code': 'pcs',
        'category_id': 2,
        'category_name': 'Snack',
        'is_low_stock': true,
        'shelf_location': 'Rak C2 • Baris 3',
        'icon_type': 'noodle',
        'batches': [
          {'id': 3, 'batch_number': 'FEFO-NOV26', 'expiry_date': '2026-11-28', 'quantity': 25.0, 'is_expired': false}
        ],
      },
      {
        'id': 104,
        'name': 'Roti Tawar Kupas',
        'sku': 'SNK-002',
        'barcode': '8992752011004',
        'type': 'variable',
        'selling_price': 12000.0,
        'cost_price': 8500.0,
        'stock': 50.0,
        'unit_code': 'bks',
        'category_id': 2,
        'category_name': 'Snack',
        'is_low_stock': false,
        'shelf_location': 'Rak Roti A2',
        'icon_type': 'bread',
        'variants': [
          {'id': 201, 'name': 'Original Klasik', 'sku': 'ROT-ORI', 'selling_price': 12000.0, 'stock': 30.0},
          {'id': 202, 'name': 'Gandum Utuh (Wheat)', 'sku': 'ROT-WHT', 'selling_price': 15000.0, 'stock': 12.0},
          {'id': 203, 'name': 'Pandan Wangi', 'sku': 'ROT-PDN', 'selling_price': 13500.0, 'stock': 8.0},
        ],
      },
      {
        'id': 105,
        'name': 'Biskuit Roma Kelapa',
        'sku': 'SNK-003',
        'barcode': '8992752011005',
        'type': 'standard',
        'selling_price': 10000.0,
        'cost_price': 7400.0,
        'stock': 100.0,
        'unit_code': 'bks',
        'category_id': 2,
        'category_name': 'Snack',
        'is_low_stock': false,
        'shelf_location': 'Rak C1 • Baris 1',
        'icon_type': 'biscuit',
      },
      {
        'id': 106,
        'name': 'Susu UHT Full Cream',
        'sku': 'MIN-003',
        'barcode': '8992752011006',
        'type': 'variable',
        'selling_price': 8000.0,
        'cost_price': 5900.0,
        'stock': 42.0,
        'unit_code': 'ktk',
        'category_id': 1,
        'category_name': 'Minuman',
        'is_low_stock': false,
        'shelf_location': 'Cooler B2 • Baris 1',
        'icon_type': 'milk',
        'variants': [
          {'id': 204, 'name': 'Full Cream 250ml', 'sku': 'UHT-FC250', 'selling_price': 8000.0, 'stock': 24.0},
          {'id': 205, 'name': 'Cokelat 250ml', 'sku': 'UHT-CK250', 'selling_price': 8000.0, 'stock': 18.0},
          {'id': 206, 'name': 'Family Pack 1 Liter', 'sku': 'UHT-1000', 'selling_price': 21000.0, 'stock': 10.0},
        ],
      },
      {
        'id': 107,
        'name': 'Beras Ramos Curah (Timbang)',
        'sku': 'SMB-001',
        'barcode': '2010007010009',
        'scale_plu': '10007',
        'sold_by_weight': true,
        'type': 'standard',
        'selling_price': 14500.0,
        'cost_price': 12200.0,
        'stock': 4.0,
        'reorder_level': 10.0,
        'unit_code': 'kg',
        'category_id': 3,
        'category_name': 'Sembako',
        'is_low_stock': true,
        'shelf_location': 'Gudang Depan D1',
        'icon_type': 'rice',
      },
      {
        'id': 108,
        'name': 'Token Listrik PLN 50.000',
        'sku': 'DIG-001',
        'barcode': '8992752099001',
        'type': 'digital',
        'digital_target_label': 'ID Pelanggan / Nomor Meter PLN',
        'selling_price': 52500.0,
        'cost_price': 50100.0,
        'stock': 999.0,
        'unit_code': 'vcr',
        'category_id': 4,
        'category_name': 'Pulsa',
        'is_low_stock': false,
        'shelf_location': 'Produk Digital Cloud',
        'icon_type': 'digital',
      },
    ];
  }

  List<Map<String, dynamic>> _defaultSeedSalesHistory() {
    return [
      {
        'id': 1024,
        'number': '#INV-1024',
        'sale_datetime': '31 Okt 2026 • 15:30',
        'grand_total': 17000.0,
        'subtotal': 17000.0,
        'discount_total': 0.0,
        'tax_total': 0.0,
        'paid_total': 20000.0,
        'change_returned': 3000.0,
        'balance_due': 0.0,
        'status': 'completed',
        'payment_methods': ['Tunai'],
        'customer': {'id': 1, 'name': 'Pelanggan Umum', 'phone': '081234567890'},
        'items': [
          {'product_id': 101, 'product_name': 'Air Mineral 600ml', 'quantity': 1, 'unit_price': 5000.0, 'line_total': 5000.0},
          {'product_id': 102, 'product_name': 'Teh Botol Sosro', 'quantity': 2, 'unit_price': 6000.0, 'line_total': 12000.0},
        ],
      },
      {
        'id': 1023,
        'number': '#INV-1023',
        'sale_datetime': '31 Okt 2026 • 14:20',
        'grand_total': 48000.0,
        'subtotal': 48000.0,
        'discount_total': 0.0,
        'tax_total': 0.0,
        'paid_total': 48000.0,
        'change_returned': 0.0,
        'balance_due': 0.0,
        'status': 'completed',
        'payment_methods': ['QRIS'],
        'customer': {'id': 2, 'name': 'Siti Rahmawati', 'phone': '081398765432'},
        'items': [
          {'product_id': 104, 'product_name': 'Roti Tawar Kupas', 'quantity': 2, 'unit_price': 12000.0, 'line_total': 24000.0},
          {'product_id': 106, 'product_name': 'Susu UHT Full Cream', 'quantity': 3, 'unit_price': 8000.0, 'line_total': 24000.0},
        ],
      },
      {
        'id': 1022,
        'number': '#INV-1022',
        'sale_datetime': '31 Okt 2026 • 13:10',
        'grand_total': 25000.0,
        'subtotal': 25000.0,
        'discount_total': 0.0,
        'tax_total': 0.0,
        'paid_total': 25000.0,
        'change_returned': 0.0,
        'balance_due': 0.0,
        'status': 'completed',
        'payment_methods': ['Tunai'],
        'customer': {'id': 1, 'name': 'Budi Santoso', 'phone': '081234567890'},
        'items': [
          {'product_id': 105, 'product_name': 'Biskuit Roma Kelapa', 'quantity': 2, 'unit_price': 10000.0, 'line_total': 20000.0},
          {'product_id': 101, 'product_name': 'Air Mineral 600ml', 'quantity': 1, 'unit_price': 5000.0, 'line_total': 5000.0},
        ],
      },
      {
        'id': 1021,
        'number': '#INV-1021',
        'sale_datetime': '31 Okt 2026 • 12:50',
        'grand_total': 120000.0,
        'subtotal': 120000.0,
        'discount_total': 0.0,
        'tax_total': 0.0,
        'paid_total': 120000.0,
        'change_returned': 0.0,
        'balance_due': 0.0,
        'status': 'completed',
        'payment_methods': ['Transfer Bank'],
        'customer': {'id': 3, 'name': 'Hendra Wijaya', 'phone': '085711223344'},
        'items': [
          {'product_id': 105, 'product_name': 'Biskuit Roma Kelapa', 'quantity': 12, 'unit_price': 10000.0, 'line_total': 120000.0},
        ],
      },
      {
        'id': 1020,
        'number': '#INV-1020',
        'sale_datetime': '31 Okt 2026 • 11:30',
        'grand_total': 75000.0,
        'subtotal': 75000.0,
        'discount_total': 0.0,
        'tax_total': 0.0,
        'paid_total': 75000.0,
        'change_returned': 0.0,
        'balance_due': 0.0,
        'status': 'completed',
        'payment_methods': ['Kartu Debit'],
        'customer': {'id': 1, 'name': 'Pelanggan Umum', 'phone': '081234567890'},
        'items': [
          {'product_id': 102, 'product_name': 'Teh Botol Sosro', 'quantity': 5, 'unit_price': 6000.0, 'line_total': 30000.0},
          {'product_id': 103, 'product_name': 'Indomie Goreng', 'quantity': 10, 'unit_price': 3500.0, 'line_total': 35000.0},
          {'product_id': 105, 'product_name': 'Biskuit Roma Kelapa', 'quantity': 1, 'unit_price': 10000.0, 'line_total': 10000.0},
        ],
      },
    ];
  }
}
