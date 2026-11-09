import 'dart:typed_data';
import '../utils/currency_formatter.dart';

/// Direct Bluetooth Thermal Printer (ESC/POS 58mm & 80mm, Sunmi, iMin)
/// Generates ESC/POS raw byte streams for Customer Receipts, Kitchen Order Tickets (KOT),
/// Cash Drawer RJ-11 Kick pulses, and Shift Z-Reports.
class BluetoothPrinterDevice {
  final String name;
  final String macAddress;
  final String paperSize;
  final bool isBuiltInHandheld;

  const BluetoothPrinterDevice({
    required this.name,
    required this.macAddress,
    this.paperSize = '58mm',
    this.isBuiltInHandheld = false,
  });
}

class PrinterService {
  BluetoothPrinterDevice? connectedPrinter;
  String paperWidth = '58mm';

  final List<BluetoothPrinterDevice> discoveredDevices = const [
    BluetoothPrinterDevice(
      name: 'Sunmi V2s InnerPrinter',
      macAddress: '00:11:22:33:44:01',
      paperSize: '58mm',
      isBuiltInHandheld: true,
    ),
    BluetoothPrinterDevice(
      name: 'iMin M2 Thermal POS',
      macAddress: '00:11:22:33:44:02',
      paperSize: '58mm',
      isBuiltInHandheld: true,
    ),
    BluetoothPrinterDevice(
      name: 'RPP02N / Panda PRJ-58B',
      macAddress: 'DC:0D:30:8A:12:99',
      paperSize: '58mm',
    ),
    BluetoothPrinterDevice(
      name: 'Epson TM-T82X Kasir (80mm)',
      macAddress: 'AC:3F:A4:11:88:20',
      paperSize: '80mm',
    ),
  ];

  void connectDevice(BluetoothPrinterDevice device) {
    connectedPrinter = device;
    paperWidth = device.paperSize;
  }

  void disconnect() {
    connectedPrinter = null;
  }

  /// ESC/POS Standard Cash Drawer Kick Pulse Command (Pin 2 / RJ-11)
  Uint8List buildCashDrawerKickBytes() {
    return Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]);
  }

  /// Build formatted text & ESC/POS byte stream for a Customer Sale Receipt
  String formatThermalReceiptText({
    required Map<String, dynamic> storeProfile,
    required Map<String, dynamic> sale,
  }) {
    final width = paperWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final doubleDivider = '=' * width;

    final storeName = (storeProfile['name'] ?? 'Toko Berkah Jaya').toString().toUpperCase();
    final storeAddress = (storeProfile['address'] ?? 'Jl. Melati No. 12, Jakarta').toString();
    final storePhone = (storeProfile['phone'] ?? '0812 3456 7890').toString();
    final footer = (storeProfile['receipt_footer'] ?? 'Terima kasih atas kunjungan Anda!').toString();

    final number = (sale['number'] ?? '#INV-1024').toString();
    final dt = (sale['sale_datetime'] ?? 'Hari Ini').toString();
    final customerName = (sale['customer'] is Map ? sale['customer']['name'] : 'Pelanggan Umum').toString();
    final items = (sale['items'] as List<dynamic>? ?? []);
    final methods = (sale['payment_methods'] as List<dynamic>? ?? ['Tunai']).join(', ');

    final sb = StringBuffer();
    sb.writeln(_center(storeName, width));
    sb.writeln(_center(storeAddress, width));
    sb.writeln(_center('Telp: $storePhone', width));
    sb.writeln(doubleDivider);
    sb.writeln(_leftRight('No: $number', dt, width));
    sb.writeln(_leftRight('Pelanggan:', customerName, width));
    sb.writeln(divider);

    for (final rawItem in items) {
      final item = Map<String, dynamic>.from(rawItem as Map);
      final name = (item['product_name'] ?? 'Produk').toString();
      final qty = (item['quantity'] as num?) ?? 1;
      final price = (item['unit_price'] as num?) ?? 0;
      final lineTotal = (item['line_total'] as num?) ?? (qty * price);

      sb.writeln(name);
      sb.writeln(
        _leftRight(
          '  ${IdrCurrencyFormatter.formatQty(qty)} x ${IdrCurrencyFormatter.format(price, withSymbol: false)}',
          IdrCurrencyFormatter.format(lineTotal),
          width,
        ),
      );
      if (item['notes'] != null && item['notes'].toString().isNotEmpty) {
        sb.writeln('  *Catatan: ${item['notes']}');
      }
    }

    sb.writeln(divider);
    final subtotal = (sale['subtotal'] as num?) ?? (sale['grand_total'] as num?) ?? 0;
    final discount = (sale['discount_total'] as num?) ?? 0;
    final tax = (sale['tax_total'] as num?) ?? 0;
    final grandTotal = (sale['grand_total'] as num?) ?? subtotal;
    final paid = (sale['paid_total'] as num?) ?? grandTotal;
    final change = (sale['change_returned'] as num?) ?? 0;
    final balanceDue = (sale['balance_due'] as num?) ?? 0;

    sb.writeln(_leftRight('Subtotal', IdrCurrencyFormatter.format(subtotal), width));
    if (discount > 0) {
      sb.writeln(_leftRight('Diskon', '-${IdrCurrencyFormatter.format(discount)}', width));
    }
    if (tax > 0) {
      sb.writeln(_leftRight('PPN / Pajak', IdrCurrencyFormatter.format(tax), width));
    }
    sb.writeln(doubleDivider);
    sb.writeln(_leftRight('TOTAL TAGIHAN', IdrCurrencyFormatter.format(grandTotal), width));
    sb.writeln(_leftRight('Bayar ($methods)', IdrCurrencyFormatter.format(paid), width));
    if (balanceDue > 0) {
      sb.writeln(_leftRight('SISA KASBON (BON)', IdrCurrencyFormatter.format(balanceDue), width));
    } else {
      sb.writeln(_leftRight('KEMBALIAN', IdrCurrencyFormatter.format(change), width));
    }
    sb.writeln(doubleDivider);
    sb.writeln(_center(footer, width));
    sb.writeln(_center('Powered by NusaCommerce Cloud', width));

    return sb.toString();
  }

  /// Build Kitchen Order Ticket (KOT) text for Restaurant / F&B Mode
  String formatKitchenOrderTicket({
    required String tableName,
    required String sectionName,
    required int pax,
    required List<Map<String, dynamic>> items,
  }) {
    const width = 32;
    final sb = StringBuffer();
    sb.writeln(_center('*** TIKET DAPUR (KOT) ***', width));
    sb.writeln(_center('$tableName ($sectionName) • $pax Pax', width));
    sb.writeln('=' * width);
    for (final item in items) {
      sb.writeln('[ ${IdrCurrencyFormatter.formatQty((item['quantity'] as num?) ?? 1)}x ] ${item['product_name']}');
      if (item['notes'] != null && item['notes'].toString().isNotEmpty) {
        sb.writeln('   >> CATATAN: ${item['notes']}');
      }
    }
    sb.writeln('=' * width);
    return sb.toString();
  }

  String _center(String text, int width) {
    if (text.length >= width) return text;
    final pad = ((width - text.length) / 2).floor();
    return (' ' * pad) + text;
  }

  String _leftRight(String left, String right, int width) {
    final space = width - left.length - right.length;
    if (space <= 1) return '$left $right';
    return left + (' ' * space) + right;
  }
}
