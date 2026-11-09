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
    final storeName = storeProfile['name'] ?? 'Toko Berkah Jaya';
    final number = sale['number'] ?? '#INV-1024';
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
        '_Dikirim otomatis dari NusaCommerce Mobile POS_';

    return _launchWhatsApp(phone, message);
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
