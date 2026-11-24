import 'package:flutter/material.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../auth/models/auth_session_model.dart';

part 'mobile_report_models.dart';

class MobileReportCatalog {
  MobileReportCatalog._();

  static const MobileReportDefinition oversoldAuditDefinition = MobileReportDefinition(
    id: 'oversold',
    categoryCode: 'inventory_stock',
    title: 'Barang Terjual Minus (Oversold)',
    subtitle: 'Audit SKU bersaldo stok negatif yang perlu rekonsiliasi segera',
    icon: Icons.remove_shopping_cart_outlined,
    permissions: ['products.view', 'reports.view_inventory', 'reports.view_financial'],
    keywords: ['minus', 'negatif', 'oversold', 'selisih', 'stok'],
    dateMode: 'snapshot',
    supportsOfflineLocal: true,
  );

  /// All 50 Cloud-parity reports grouped into 8 intuitive mobile business-cycle categories.
  static const List<MobileReportCategory> categories = [
    // 1. PENJUALAN & MARGIN (11 Laporan)
    MobileReportCategory(
      code: 'sales_margin',
      title: 'Penjualan & Margin',
      shortTitle: 'Penjualan',
      subtitle: 'Omzet, laba per nota, produk, kategori, saluran & jam sibuk',
      icon: Icons.trending_up_rounded,
      accentColor: Color(0xFFEA580C),
      reports: [
        MobileReportDefinition(
          id: 'sales-report',
          categoryCode: 'sales_margin',
          title: 'Ringkasan Penjualan',
          subtitle: 'Total omzet harian, transaksi, diskon, pajak & kas masuk',
          icon: Icons.bar_chart_rounded,
          permissions: ['reports.view_financial', 'reports.view_sales'],
          keywords: ['omzet', 'sales', 'summary', 'penjualan', 'harian'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'bill-wise-profit',
          categoryCode: 'sales_margin',
          title: 'Laba per Faktur (Nota)',
          subtitle: 'Laba kotor, HPP & margin persentase tiap nomor struk',
          icon: Icons.receipt_long_rounded,
          permissions: ['reports.view_financial', 'reports.view_sales'],
          keywords: ['profit', 'margin', 'faktur', 'nota', 'struk', 'hpp'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'sales-by-product',
          categoryCode: 'sales_margin',
          title: 'Penjualan per Produk',
          subtitle: 'Volume terjual, omzet, HPP & margin per item barang',
          icon: Icons.inventory_2_outlined,
          permissions: ['reports.view_financial', 'reports.view_sales'],
          keywords: ['produk', 'terlaris', 'sku', 'top product', 'item'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'sales-by-category',
          categoryCode: 'sales_margin',
          title: 'Penjualan per Kategori',
          subtitle: 'Analisis kontribusi omzet & volume per departemen produk',
          icon: Icons.category_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['kategori', 'category', 'departemen'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'sales-by-brand',
          categoryCode: 'sales_margin',
          title: 'Penjualan per Brand / Merek',
          subtitle: 'Peringkat omzet, qty & profitabilitas per merek dagang',
          icon: Icons.local_offer_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['brand', 'merek', 'merk'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'sales-by-channel',
          categoryCode: 'sales_margin',
          title: 'Penjualan per Saluran',
          subtitle: 'Perbandingan omzet Kasir POS, Toko Online & WhatsApp',
          icon: Icons.hub_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['saluran', 'channel', 'online', 'pos', 'whatsapp', 'omnichannel'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'sales-by-cashier',
          categoryCode: 'sales_margin',
          title: 'Penjualan per Kasir',
          subtitle: 'Produktivitas transaksi, omzet & diskon per staf kasir',
          icon: Icons.person_outline_rounded,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['kasir', 'cashier', 'staf', 'pegawai'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'sales-by-payment-method',
          categoryCode: 'sales_margin',
          title: 'Analisis Metode Pembayaran',
          subtitle: 'Rekonsiliasi Tunai, QRIS, EDC, Transfer Bank & Kasbon',
          icon: Icons.credit_card_rounded,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['pembayaran', 'qris', 'tunai', 'edc', 'transfer', 'payment'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'hourly-sales',
          categoryCode: 'sales_margin',
          title: 'Jam Sibuk Penjualan (Hourly Rush)',
          subtitle: 'Pola jam ramai transaksi untuk optimasi jadwal shift',
          icon: Icons.schedule_rounded,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['jam', 'sibuk', 'hourly', 'rush', 'heatmap'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'basket-size',
          categoryCode: 'sales_margin',
          title: 'Ukuran Keranjang Belanja (AOV)',
          subtitle: 'Rata-rata nilai belanja & distribusi nominal per struk',
          icon: Icons.shopping_basket_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['aov', 'basket', 'keranjang', 'rata-rata'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'quotation-pipeline',
          categoryCode: 'sales_margin',
          title: 'Pipeline Penawaran B2B',
          subtitle: 'Nilai penawaran terbuka, Win Rate & konversi ke faktur',
          icon: Icons.request_quote_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['quotation', 'penawaran', 'b2b', 'pipeline'],
          isNew: true,
        ),
      ],
    ),

    // 2. STOK & INVENTARIS TOKO (9 Laporan + Oversold audit)
    MobileReportCategory(
      code: 'inventory_stock',
      title: 'Stok & Inventaris Toko',
      shortTitle: 'Stok',
      subtitle: 'Stok kritis, oversold, batch FEFO, valuasi aset & mutasi gudang',
      icon: Icons.warehouse_outlined,
      accentColor: Color(0xFFD97706),
      reports: [
        MobileReportDefinition(
          id: 'low-stock',
          categoryCode: 'inventory_stock',
          title: 'Peringatan Stok Kritis & Minus',
          subtitle: 'Barang di bawah batas aman reorder, habis & oversold',
          icon: Icons.warning_amber_rounded,
          permissions: ['products.view', 'reports.view_inventory'],
          keywords: ['low stock', 'kritis', 'menipis', 'habis', 'oversold', 'minus', 'reorder'],
          dateMode: 'snapshot',
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'batch-expiry-risk',
          categoryCode: 'inventory_stock',
          title: 'Risiko Kedaluwarsa Batch (FEFO)',
          subtitle: 'Nilai aset kedaluwarsa & kritis 0-30-60-90 hari',
          icon: Icons.event_busy_outlined,
          permissions: ['reports.view_inventory', 'reports.view_financial'],
          keywords: ['expired', 'kedaluwarsa', 'batch', 'fefo', 'lot'],
          dateMode: 'as_of',
          supportsOfflineLocal: true,
          isNew: true,
        ),
        MobileReportDefinition(
          id: 'fast-dead-stock',
          categoryCode: 'inventory_stock',
          title: 'Fast Moving vs Dead Stock',
          subtitle: 'Perputaran cepat vs modal mengendap tidak terjual',
          icon: Icons.autorenew_rounded,
          permissions: ['reports.view_inventory', 'reports.view_financial'],
          keywords: ['fast', 'dead', 'moving', 'mengendap', 'perputaran'],
          dateMode: 'snapshot',
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'inventory-valuation',
          categoryCode: 'inventory_stock',
          title: 'Valuasi Nilai Aset Stok',
          subtitle: 'Total modal aset stok (WAC/HPP) & potensi nilai jual',
          icon: Icons.pie_chart_outline_rounded,
          permissions: ['reports.view_inventory', 'reports.view_financial'],
          keywords: ['valuasi', 'aset', 'persediaan', 'modal', 'stok'],
          dateMode: 'snapshot',
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'stock-opname-loss',
          categoryCode: 'inventory_stock',
          title: 'Kerugian Selisih Opname (Stock Loss)',
          subtitle: 'Nominal rupiah shrinkage & kehilangan stok hasil opname',
          icon: Icons.report_problem_outlined,
          permissions: ['reports.view_inventory', 'reports.view_financial'],
          keywords: ['opname', 'selisih', 'loss', 'hilang', 'shrinkage'],
        ),
        MobileReportDefinition(
          id: 'stock-transfers',
          categoryCode: 'inventory_stock',
          title: 'Audit Mutasi Antar Cabang',
          subtitle: 'Nilai barang in-transit & selisih terima transfer gudang',
          icon: Icons.local_shipping_outlined,
          permissions: ['reports.view_inventory', 'reports.view_financial'],
          keywords: ['transfer', 'cabang', 'transit', 'mutasi', 'gudang'],
          isNew: true,
        ),
        MobileReportDefinition(
          id: 'stock-movements',
          categoryCode: 'inventory_stock',
          title: 'Riwayat Mutasi Kartu Stok',
          subtitle: 'Audit kronologis keluar/masuk stok per SKU',
          icon: Icons.swap_vert_rounded,
          permissions: ['products.view', 'reports.view_inventory'],
          keywords: ['kartu stok', 'mutasi', 'movement', 'keluar', 'masuk'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'stock-adjustments',
          categoryCode: 'inventory_stock',
          title: 'Penyesuaian Stok (Opname)',
          subtitle: 'Histori dokumen koreksi & penyesuaian fisik gudang',
          icon: Icons.tune_rounded,
          permissions: ['products.view', 'reports.view_inventory'],
          keywords: ['penyesuaian', 'adjustment', 'koreksi', 'rusak'],
        ),
        MobileReportDefinition(
          id: 'batches',
          categoryCode: 'inventory_stock',
          title: 'Daftar Batch & Lot Aktif',
          subtitle: 'Pelacakan operasional nomor lot & tanggal kedaluwarsa',
          icon: Icons.qr_code_2_rounded,
          permissions: ['products.view', 'reports.view_inventory'],
          keywords: ['batch', 'lot', 'ed', 'expiry'],
          dateMode: 'snapshot',
          supportsOfflineLocal: true,
        ),
      ],
    ),

    // 3. PELANGGAN & CRM (6 Laporan)
    MobileReportCategory(
      code: 'customers_crm',
      title: 'Pelanggan & CRM',
      shortTitle: 'Pelanggan',
      subtitle: 'Top pelanggan, segmentasi RFM, churn WA, buku & umur piutang',
      icon: Icons.groups_outlined,
      accentColor: Color(0xFF0D9488),
      reports: [
        MobileReportDefinition(
          id: 'top-customers',
          categoryCode: 'customers_crm',
          title: 'Pelanggan Terbaik (Top Customers)',
          subtitle: 'Peringkat pembeli paling loyal & total nilai belanja',
          icon: Icons.emoji_events_outlined,
          permissions: ['reports.view_customers', 'reports.view_financial'],
          keywords: ['pelanggan', 'top', 'terbaik', 'vip', 'member'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'customer-rfm',
          categoryCode: 'customers_crm',
          title: 'Segmentasi Loyalitas (RFM)',
          subtitle: 'Klasifikasi Champions, Loyal, Potential & At Risk',
          icon: Icons.stars_outlined,
          permissions: ['reports.view_customers', 'reports.view_sales', 'reports.view_financial'],
          keywords: ['rfm', 'segmentasi', 'loyalitas', 'champion'],
          dateMode: 'snapshot',
        ),
        MobileReportDefinition(
          id: 'inactive-customers',
          categoryCode: 'customers_crm',
          title: 'Pelanggan Tidak Aktif (Churn Risk)',
          subtitle: 'Tidak belanja >30 hari siap follow-up 1-klik WhatsApp',
          icon: Icons.person_off_outlined,
          permissions: ['reports.view_customers', 'reports.view_sales', 'reports.view_financial'],
          keywords: ['pasif', 'churn', 'tidak aktif', 'follow up', 'wa'],
          dateMode: 'snapshot',
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'customer-ledger',
          categoryCode: 'customers_crm',
          title: 'Buku Pembantu Piutang Pelanggan',
          subtitle: 'Rekening koran mutasi tagihan & pelunasan per pelanggan',
          icon: Icons.menu_book_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['ledger', 'buku pembantu', 'piutang', 'bon', 'kasbon'],
        ),
        MobileReportDefinition(
          id: 'aged-receivables',
          categoryCode: 'customers_crm',
          title: 'Analisis Umur Piutang (Aging AR)',
          subtitle: 'Faktur bon pelanggan jatuh tempo 30, 60, 90+ hari',
          icon: Icons.hourglass_bottom_rounded,
          permissions: ['reports.view_financial'],
          keywords: ['aging', 'umur piutang', 'jatuh tempo', 'ar', 'kasbon'],
          dateMode: 'as_of',
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'loyalty-points',
          categoryCode: 'customers_crm',
          title: 'Saldo Poin Loyalitas Member',
          subtitle: 'Poin didapat, ditukar & estimasi kewajiban reward',
          icon: Icons.loyalty_outlined,
          permissions: ['reports.view_customers', 'reports.view_financial'],
          keywords: ['poin', 'loyalty', 'reward', 'member'],
        ),
      ],
    ),

    // 4. PEMBELIAN & PEMASOK (AP) (5 Laporan)
    MobileReportCategory(
      code: 'procurement_ap',
      title: 'Pembelian & Pemasok (AP)',
      shortTitle: 'Pembelian',
      subtitle: 'Pengadaan PO, retur & GRN, pemasok terbesar & umur hutang',
      icon: Icons.shopping_cart_checkout_rounded,
      accentColor: Color(0xFF059669),
      reports: [
        MobileReportDefinition(
          id: 'purchases-report',
          categoryCode: 'procurement_ap',
          title: 'Ringkasan Pengadaan (PO)',
          subtitle: 'Total belanja pembelian supplier & status pelunasan',
          icon: Icons.shopping_bag_outlined,
          permissions: ['reports.view_suppliers', 'reports.view_financial', 'purchases.view'],
          keywords: ['pembelian', 'po', 'pengadaan', 'kulakan'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'purchase-returns',
          categoryCode: 'procurement_ap',
          title: 'Retur Beli & Audit GRN',
          subtitle: 'Rasio retur pemasok, bukti terima fisik GRN & klaim AP',
          icon: Icons.assignment_return_outlined,
          permissions: ['reports.view_suppliers', 'reports.view_financial'],
          keywords: ['retur beli', 'grn', 'terima barang', 'klaim'],
          isNew: true,
        ),
        MobileReportDefinition(
          id: 'top-suppliers',
          categoryCode: 'procurement_ap',
          title: 'Pemasok Terbesar (Top Suppliers)',
          subtitle: 'Peringkat volume & nominal pembelian per vendor',
          icon: Icons.business_outlined,
          permissions: ['reports.view_suppliers', 'reports.view_financial'],
          keywords: ['supplier', 'pemasok', 'vendor', 'terbesar'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'supplier-ledger',
          categoryCode: 'procurement_ap',
          title: 'Buku Pembantu Hutang Supplier',
          subtitle: 'Rekening koran mutasi hutang & pembayaran per pemasok',
          icon: Icons.list_alt_rounded,
          permissions: ['reports.view_financial', 'purchases.view'],
          keywords: ['hutang', 'supplier ledger', 'rekening koran', 'ap'],
        ),
        MobileReportDefinition(
          id: 'aged-payables',
          categoryCode: 'procurement_ap',
          title: 'Analisis Umur Hutang (Aging AP)',
          subtitle: 'Tagihan pemasok jatuh tempo 30, 60, 90+ hari',
          icon: Icons.event_note_outlined,
          permissions: ['reports.view_financial'],
          keywords: ['aging', 'umur hutang', 'ap', 'jatuh tempo'],
          dateMode: 'as_of',
          supportsOfflineLocal: true,
        ),
      ],
    ),

    // 5. KAS, BIAYA & PERBANKAN (3 Laporan)
    MobileReportCategory(
      code: 'cash_banking',
      title: 'Kas, Biaya & Perbankan',
      shortTitle: 'Kas & Bank',
      subtitle: 'Pengeluaran operasional, arus kas riil & kliring EDC/QRIS 1136',
      icon: Icons.account_balance_wallet_outlined,
      accentColor: Color(0xFF0284C7),
      reports: [
        MobileReportDefinition(
          id: 'expenses-report',
          categoryCode: 'cash_banking',
          title: 'Ringkasan Biaya Operasional',
          subtitle: 'Rincian beban toko per kategori di luar HPP barang',
          icon: Icons.money_off_csred_outlined,
          permissions: ['reports.view_financial', 'expenses.view'],
          keywords: ['biaya', 'expense', 'pengeluaran', 'operasional'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'cash-flow',
          categoryCode: 'cash_banking',
          title: 'Arus Kas Masuk & Keluar',
          subtitle: 'Mutasi kas operasi, investasi, pendanaan & saldo akhir',
          icon: Icons.compare_arrows_rounded,
          permissions: ['reports.view_financial'],
          keywords: ['arus kas', 'cash flow', 'kas masuk', 'kas keluar'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'bank-settlement-reconciliation',
          categoryCode: 'cash_banking',
          title: 'Rekonsiliasi EDC/QRIS & Bank (1136)',
          subtitle: 'Dana non-tunai belum cair, settlement & potongan MDR',
          icon: Icons.account_balance_outlined,
          permissions: ['reports.view_financial', 'accounting.bank_reconciliation'],
          keywords: ['kliring', '1136', 'settlement', 'mdr', 'qris', 'edc', 'bank'],
          isNew: true,
        ),
      ],
    ),

    // 6. PERFORMA TOKO, SHIFT & RESTO (5 Laporan)
    MobileReportCategory(
      code: 'store_shift_fnb',
      title: 'Performa Toko, Shift & Resto',
      shortTitle: 'Cabang & Shift',
      subtitle: 'Komparasi cabang, Z-Report shift kasir, performa F&B & rasio SDM',
      icon: Icons.storefront_outlined,
      accentColor: Color(0xFF7C3AED),
      reports: [
        MobileReportDefinition(
          id: 'store-comparison',
          categoryCode: 'store_shift_fnb',
          title: 'Perbandingan Lintas Cabang',
          subtitle: 'Benchmark omzet, transaksi & margin antar gerai/toko',
          icon: Icons.leaderboard_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['cabang', 'store', 'komparasi', 'benchmark', 'toko'],
        ),
        MobileReportDefinition(
          id: 'shifts-by-cashier',
          categoryCode: 'store_shift_fnb',
          title: 'Arsip Shift Kasir (Z-Report)',
          subtitle: 'Laporan buka/tutup kas, produktivitas & selisih laci',
          icon: Icons.lock_clock_outlined,
          permissions: ['reports.view_employees', 'reports.view_financial'],
          keywords: ['shift', 'z-report', 'tutup kasir', 'laci', 'selisih'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'table-turnover',
          categoryCode: 'store_shift_fnb',
          title: 'Perputaran Meja Resto (F&B)',
          subtitle: 'Turnover rate, okupansi meja & omzet per kursi dine-in',
          icon: Icons.table_restaurant_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['meja', 'table', 'turnover', 'restoran', 'fnb'],
        ),
        MobileReportDefinition(
          id: 'menu-engineering',
          categoryCode: 'store_shift_fnb',
          title: 'Menu Engineering Matrix (F&B)',
          subtitle: 'Kuadran menu Stars, Plowhorses, Puzzles & Dogs',
          icon: Icons.restaurant_menu_rounded,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['menu', 'engineering', 'stars', 'dogs', 'restoran'],
        ),
        MobileReportDefinition(
          id: 'payroll-cost',
          categoryCode: 'store_shift_fnb',
          title: 'Rasio Biaya SDM & Payroll',
          subtitle: 'Ringkasan beban gaji bruto & rasio SDM terhadap omzet',
          icon: Icons.badge_outlined,
          permissions: ['reports.view_employees', 'reports.view_financial', 'hr.payroll_view'],
          keywords: ['payroll', 'gaji', 'sdm', 'rasio', 'bpjs'],
          isNew: true,
        ),
      ],
    ),

    // 7. AUDIT & PENGAWASAN KASIR (4 Laporan)
    MobileReportCategory(
      code: 'cashier_audit',
      title: 'Audit & Pengawasan Kasir',
      shortTitle: 'Audit',
      subtitle: 'Anti-fraud void/refund, diskon kasir, KOT void & approval kontrol',
      icon: Icons.shield_outlined,
      accentColor: Color(0xFFDC2626),
      reports: [
        MobileReportDefinition(
          id: 'void-refund-audit',
          categoryCode: 'cashier_audit',
          title: 'Audit Pembatalan (Void & Refund)',
          subtitle: 'Pelacakan nota batal, retur & otorisasi supervisor',
          icon: Icons.cancel_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['void', 'refund', 'batal', 'retur', 'fraud'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'discounts',
          categoryCode: 'cashier_audit',
          title: 'Audit Diskon & Promosi Kasir',
          subtitle: 'Total potongan harga, alasan & persetujuan manajer',
          icon: Icons.discount_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['diskon', 'promo', 'potongan', 'audit'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'kot-void-audit',
          categoryCode: 'cashier_audit',
          title: 'Audit KOT Void Dapur (F&B)',
          subtitle: 'Pesanan dapur dibatalkan & pemantauan food waste',
          icon: Icons.no_meals_outlined,
          permissions: ['reports.view_sales', 'reports.view_financial'],
          keywords: ['kot', 'dapur', 'void', 'waste', 'resto'],
        ),
        MobileReportDefinition(
          id: 'governance-audit',
          categoryCode: 'cashier_audit',
          title: 'Log Aktivitas & Kontrol Approval',
          subtitle: 'Maker-Checker SLA, laci no-sale, gagal GL & konflik',
          icon: Icons.verified_user_outlined,
          permissions: ['reports.view_financial', 'approvals.view'],
          keywords: ['governance', 'approval', 'no-sale', 'laci', 'log', 'keamanan'],
          isNew: true,
        ),
      ],
    ),

    // 8. PAJAK & RINGKASAN FINANSIAL (7 Laporan)
    MobileReportCategory(
      code: 'tax_financial',
      title: 'Pajak & Ringkasan Finansial',
      shortTitle: 'Pajak & SAK',
      subtitle: 'PPN/PB1, PPh CoreTax, Laba Rugi, Neraca, Buku Besar & Aset Tetap',
      icon: Icons.account_balance_rounded,
      accentColor: Color(0xFF475569),
      reports: [
        MobileReportDefinition(
          id: 'tax-summary',
          categoryCode: 'tax_financial',
          title: 'Ringkasan Pajak PPN & PB1',
          subtitle: 'PPN Keluaran vs Masukan & posisi SPT Masa bulanan',
          icon: Icons.receipt_outlined,
          permissions: ['reports.view_tax', 'reports.view_financial'],
          keywords: ['ppn', 'pb1', 'pajak', 'tax', 'faktur', 'spt'],
        ),
        MobileReportDefinition(
          id: 'withholding-tax',
          categoryCode: 'tax_financial',
          title: 'Pajak Penghasilan (PPh 21/23/UMKM)',
          subtitle: 'Subledger PPh 21 TER, PPh Final 0,5% & status setor',
          icon: Icons.gavel_outlined,
          permissions: ['reports.view_tax', 'reports.view_financial'],
          keywords: ['pph', 'umkm', 'withholding', 'coretax', 'pajak'],
          isNew: true,
        ),
        MobileReportDefinition(
          id: 'profit-and-loss',
          categoryCode: 'tax_financial',
          title: 'Laba Rugi (Kotor vs Bersih)',
          subtitle: 'Pendapatan, HPP, beban operasional & laba bersih SAK',
          icon: Icons.analytics_outlined,
          permissions: ['reports.view_financial'],
          keywords: ['laba rugi', 'pnl', 'profit', 'loss', 'bersih', 'kotor'],
          supportsOfflineLocal: true,
        ),
        MobileReportDefinition(
          id: 'balance-sheet',
          categoryCode: 'tax_financial',
          title: 'Posisi Keuangan (Neraca)',
          subtitle: 'Posisi aset lancar/tetap, liabilitas & ekuitas usaha',
          icon: Icons.balance_outlined,
          permissions: ['reports.view_financial'],
          keywords: ['neraca', 'balance sheet', 'aset', 'ekuitas', 'liabilitas'],
          dateMode: 'as_of',
        ),
        MobileReportDefinition(
          id: 'trial-balance',
          categoryCode: 'tax_financial',
          title: 'Neraca Saldo (Trial Balance)',
          subtitle: 'Keseimbangan saldo debit & kredit seluruh akun COA',
          icon: Icons.calculate_outlined,
          permissions: ['reports.view_financial'],
          keywords: ['neraca saldo', 'trial balance', 'debit', 'kredit', 'coa'],
          dateMode: 'as_of',
        ),
        MobileReportDefinition(
          id: 'general-ledger',
          categoryCode: 'tax_financial',
          title: 'Buku Besar Akun (General Ledger)',
          subtitle: 'Mutasi jurnal terperinci & saldo berjalan per akun COA',
          icon: Icons.library_books_outlined,
          permissions: ['reports.view_financial'],
          keywords: ['buku besar', 'general ledger', 'gl', 'jurnal', 'coa'],
        ),
        MobileReportDefinition(
          id: 'fixed-assets-register',
          categoryCode: 'tax_financial',
          title: 'Daftar Aset Tetap & Depresiasi',
          subtitle: 'Harga perolehan, akumulasi penyusutan & nilai buku NBV',
          icon: Icons.precision_manufacturing_outlined,
          permissions: ['reports.view_financial', 'assets.view'],
          keywords: ['aset tetap', 'depresiasi', 'penyusutan', 'nbv', 'asset'],
          dateMode: 'as_of',
          isNew: true,
        ),
      ],
    ),
  ];

  static int get totalReportCount =>
      categories.fold<int>(0, (sum, cat) => sum + cat.reports.length);

  static List<MobileReportDefinition> get allReports =>
      categories.expand((c) => c.reports).toList(growable: false);

  static MobileReportDefinition? findById(String reportId) {
    if (reportId == 'oversold') return oversoldAuditDefinition;
    for (final cat in categories) {
      for (final r in cat.reports) {
        if (r.id == reportId) return r;
      }
    }
    return null;
  }

  static MobileReportCategory? categoryForCode(String code) {
    for (final cat in categories) {
      if (cat.code == code) return cat;
    }
    return null;
  }

  /// Filter categories according to active user's RBAC permissions.
  static List<MobileReportCategory> visibleCategoriesFor(AuthSessionModel session) {
    final result = <MobileReportCategory>[];
    for (final cat in categories) {
      final visible = cat.reports.where((r) {
        if (session.isOwner || session.isLocalTrial) return true;
        return MobileWorkspaceResolver.hasAnyPermission(session, r.permissions);
      }).toList();
      if (visible.isNotEmpty) {
        result.add(cat.copyWithReports(visible));
      }
    }
    return result;
  }
}

