import 'package:url_launcher/url_launcher.dart';
import '../utils/currency_formatter.dart';

/// 1-Click WhatsApp Receipt & Buku Bon Debt Reminder Gateway
class WhatsAppService {
  WhatsAppService._();

  static String normalizePhone(String rawPhone) {
    var digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    } else if (digits.startsWith('8')) {
      digits = '62$digits';
    }
    if (digits.isEmpty) {
      digits = '6281234567890';
    }
    return digits;
  }

  /// Launch WhatsApp with formatted digital POS receipt
  static Future<bool> sendDigitalReceipt({
    required String customerPhone,
    required Map<String, dynamic> storeProfile,
    required Map<String, dynamic> sale,
  }) async {
    final phone = normalizePhone(customerPhone);
    final storeName = storeProfile['name'] ?? 'OXO.ID POS';
    final number = sale['number'] ?? '#INV-0001';
    final dt = sale['sale_datetime'] ?? 'Hari Ini';
    final grandTotal = (sale['grand_total'] as num?) ?? 0;
    final paid = (sale['paid_total'] as num?) ?? grandTotal;
    final change = (sale['change_returned'] as num?) ?? 0;
    final balanceDue = (sale['balance_due'] as num?) ?? 0;
    final items = (sale['items'] as List<dynamic>? ?? []);

    final sb = StringBuffer();
    sb.writeln('🧾 *STRUK DIGITAL — ${storeName.toString().toUpperCase()}*');
    sb.writeln('No Nota: *$number*');
    sb.writeln('Waktu: $dt');
    sb.writeln('--------------------------------');

    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final name = item['product_name'] ?? 'Barang';
      final qty = (item['quantity'] as num?) ?? 1;
      final lineTotal = (item['line_total'] as num?) ?? 0;
      sb.writeln('• $name (${IdrCurrencyFormatter.formatQty(qty)}x) = *${IdrCurrencyFormatter.format(lineTotal)}*');
    }

    sb.writeln('--------------------------------');
    sb.writeln('Total Tagihan: *${IdrCurrencyFormatter.format(grandTotal)}*');
    sb.writeln('Jumlah Bayar: ${IdrCurrencyFormatter.format(paid)}');
    if (balanceDue > 0) {
      sb.writeln('Status: *KASBON / PIUTANG (${IdrCurrencyFormatter.format(balanceDue)})*');
    } else {
      sb.writeln('Kembalian: ${IdrCurrencyFormatter.format(change)}');
      sb.writeln('Status: *LUNAS ✅*');
    }
    sb.writeln('\nTerima kasih telah berbelanja di *$storeName* 🙏');

    return _launchWhatsApp(phone, sb.toString());
  }

  /// Launch WhatsApp with polite Buku Bon debt reminder
  static Future<bool> sendDebtReminder({
    required String customerName,
    required String customerPhone,
    required String invoiceNumber,
    required num balanceDue,
    required String storeName,
  }) async {
    final phone = normalizePhone(customerPhone);
    final message = 'Halo Kak *$customerName* 👋,\n\n'
        'Kami dari *$storeName* ingin mengingatkan dengan hormat terkait catatan bon/tagihan nota *$invoiceNumber* '
        'sebesar *${IdrCurrencyFormatter.format(balanceDue)}*.\n\n'
        'Pembayaran dapat dilakukan secara tunai di toko atau transfer/QRIS. Terima kasih banyak atas kerja samanya 🙏';

    return _launchWhatsApp(phone, message);
  }

  /// Launch WhatsApp with Shift Z-Report summary to Store Owner
  static Future<bool> sendShiftZReportToOwner({
    required String ownerPhone,
    required String storeName,
    required String cashierName,
    required num openingCash,
    required num salesTotal,
    required num expectedCash,
    required num countedCash,
  }) async {
    final phone = normalizePhone(ownerPhone);
    final variance = countedCash - expectedCash;
    final message = '📊 *LAPORAN TUTUP SHIFT (Z-REPORT)*\n'
        'Toko: *$storeName*\n'
        'Kasir: *$cashierName*\n'
        '--------------------------------\n'
        '• Modal Awal Laci: ${IdrCurrencyFormatter.format(openingCash)}\n'
        '• Total Penjualan Shift: *${IdrCurrencyFormatter.format(salesTotal)}*\n'
        '• Kas Seharusnya di Laci: ${IdrCurrencyFormatter.format(expectedCash)}\n'
        '• Uang Fisik Dihitung: *${IdrCurrencyFormatter.format(countedCash)}*\n'
        '• Selisih Kas: *${IdrCurrencyFormatter.format(variance)}*\n'
        '--------------------------------\n'
        '_Dikirim otomatis dari OXO.ID Mobile POS_';

    return _launchWhatsApp(phone, message);
  }

  /// Launch WhatsApp with Executive Owner Business Report (SAK EMKM + Anti-Fraud)
  static Future<bool> sendExecutiveReportToOwner({
    required String ownerPhone,
    required String storeName,
    required String periodLabel,
    required String branchLabel,
    required num netSales,
    required num grossProfit,
    required num expenses,
    required num netProfit,
    required num netMarginPct,
    required int transactionsCount,
    required int voidCount,
    required int refundCount,
    required int varianceCount,
  }) async {
    final phone = normalizePhone(ownerPhone);
    final message = '📈 *LAPORAN EKSEKUTIF OWNER — ${storeName.toUpperCase()}*\n'
        'Periode: *$periodLabel* | Cabang: *$branchLabel*\n'
        '--------------------------------\n'
        '• Omzet Bersih: *${IdrCurrencyFormatter.format(netSales)}* ($transactionsCount Trx)\n'
        '• Laba Kotor (Gross): ${IdrCurrencyFormatter.format(grossProfit)}\n'
        '• Biaya Operasional: ${IdrCurrencyFormatter.format(expenses)}\n'
        '• Laba Bersih (Net): *${IdrCurrencyFormatter.format(netProfit)}* (${netMarginPct.toStringAsFixed(1)}%)\n'
        '--------------------------------\n'
        '🛡️ *Radar Anti-Fraud*\n'
        '• Transaksi Void: $voidCount | Retur: $refundCount\n'
        '• Selisih Kas Shift: $varianceCount peringatan\n'
        '--------------------------------\n'
        '_Dikirim otomatis dari OXO.ID Mobile_';

    return _launchWhatsApp(phone, message);
  }

  /// Launch WhatsApp with Installment / Settlement Kwitansi (Bukti Pelunasan Piutang/Hutang)
  static Future<bool> sendSettlementReceipt({
    required String partyName,
    required String phone,
    required String invoiceNumber,
    required num paidAmount,
    required num remainingBalance,
    required String paymentMethod,
    required String storeName,
    bool isReceivable = true,
  }) async {
    final normalized = normalizePhone(phone);
    final statusLabel = remainingBalance <= 0
        ? '*LUNAS ✅*'
        : 'Sisa Tagihan: *${IdrCurrencyFormatter.format(remainingBalance)}*';
    final docTitle = isReceivable ? 'KWITANSI PEMBAYARAN PIUTANG' : 'BUKTI PEMBAYARAN HUTANG';
    final message = '🧾 *$docTitle*\n'
        'Toko: *$storeName*\n'
        '--------------------------------\n'
        'Kepada: *$partyName*\n'
        'No. Nota: *$invoiceNumber*\n'
        'Metode: $paymentMethod\n'
        'Nominal Dibayar: *${IdrCurrencyFormatter.format(paidAmount)}*\n'
        'Status: $statusLabel\n'
        '--------------------------------\n'
        'Terima kasih atas pembayarannya 🙏';

    return _launchWhatsApp(normalized, message);
  }

  static Future<bool> sendCustomMessage({
    required String phone,
    required String text,
  }) async {
    return _launchWhatsApp(normalizePhone(phone), text);
  }

  /// Opens WhatsApp share sheet with pre-formatted report/message ready to send
  /// to any management group or contact.
  static Future<bool> shareToAnyChat({required String text}) async {
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encoded');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _launchWhatsApp(String phone, String text) async {
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/$phone?text=$encoded');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
