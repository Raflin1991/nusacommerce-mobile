import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/currency_formatter.dart';

/// Direct Bluetooth Thermal Printer (ESC/POS 58mm & 80mm, Sunmi, iMin)
/// Powered by `print_bluetooth_thermal` with auto-reconnect MAC persistence,
/// ESC/POS byte stream generation, and RJ-11 cash drawer kick pulses.
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
  static const String _keyMac = 'nusa_paired_printer_mac_v4';
  static const String _keyName = 'nusa_paired_printer_v4';
  static const String _keyPaperWidth = 'nusa_printer_paper_width_v4';
  static const String _keyAutoCut = 'nusa_printer_auto_cut_v4';
  static const String _keyAutoDrawer = 'nusa_printer_auto_drawer_v4';

  SharedPreferences? _prefs;

  BluetoothPrinterDevice? connectedPrinter;
  String? savedMacAddress;
  String? savedPrinterName;
  String paperWidth = '58mm';
  bool autoCutPaper = true;
  bool autoOpenCashDrawer = true;
  bool isScanning = false;

  List<BluetoothPrinterDevice> discoveredDevices = [];

  /// Initialize printer preferences and auto-reconnect previously saved MAC address.
  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    savedMacAddress = prefs.getString(_keyMac);
    savedPrinterName = prefs.getString(_keyName);
    paperWidth = prefs.getString(_keyPaperWidth) ?? '58mm';
    autoCutPaper = prefs.getBool(_keyAutoCut) ?? true;
    autoOpenCashDrawer = prefs.getBool(_keyAutoDrawer) ?? true;

    if (savedMacAddress != null && savedMacAddress!.isNotEmpty) {
      connectedPrinter = BluetoothPrinterDevice(
        name: savedPrinterName ?? 'Printer Kasir ($savedMacAddress)',
        macAddress: savedMacAddress!,
        paperSize: paperWidth,
      );
      if (!kIsWeb) {
        try {
          final connected = await PrintBluetoothThermal.connectionStatus;
          if (!connected) {
            await PrintBluetoothThermal.connect(macPrinterAddress: savedMacAddress!);
          }
        } catch (_) {
          // Non-fatal: device may be turned off during startup; printBytes will auto-retry later.
        }
      }
    }
  }

  Future<void> savePreferences({
    String? width,
    bool? autoCut,
    bool? autoDrawer,
  }) async {
    if (width != null) {
      paperWidth = width;
      await _prefs?.setString(_keyPaperWidth, width);
    }
    if (autoCut != null) {
      autoCutPaper = autoCut;
      await _prefs?.setBool(_keyAutoCut, autoCut);
    }
    if (autoDrawer != null) {
      autoOpenCashDrawer = autoDrawer;
      await _prefs?.setBool(_keyAutoDrawer, autoDrawer);
    }
  }

  /// Real Bluetooth Connection Status via `PrintBluetoothThermal.connectionStatus`
  Future<bool> get isConnected async {
    if (kIsWeb) return connectedPrinter != null;
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (_) {
      return false;
    }
  }

  /// Request Android Bluetooth permissions and scan paired thermal printers physically.
  Future<List<BluetoothPrinterDevice>> scanBluetoothDevices() async {
    isScanning = true;
    try {
      if (kIsWeb) {
        discoveredDevices = [];
        return discoveredDevices;
      }

      try {
        await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.bluetooth,
          Permission.locationWhenInUse,
        ].request();
      } catch (_) {}

      final paired = await PrintBluetoothThermal.pairedBluetooths;
      discoveredDevices = paired.map((info) {
        final lowerName = info.name.toLowerCase();
        final guessedWidth = (lowerName.contains('80') ||
                lowerName.contains('tm-t8') ||
                lowerName.contains('t82'))
            ? '80mm'
            : paperWidth;
        final builtIn = lowerName.contains('inner') ||
            lowerName.contains('sunmi') ||
            lowerName.contains('imin');
        return BluetoothPrinterDevice(
          name: info.name.trim().isEmpty ? 'Printer Bluetooth' : info.name.trim(),
          macAddress: info.macAdress,
          paperSize: guessedWidth,
          isBuiltInHandheld: builtIn,
        );
      }).toList();

      return discoveredDevices;
    } catch (_) {
      discoveredDevices = [];
      return discoveredDevices;
    } finally {
      isScanning = false;
    }
  }

  /// Connect physically to a Bluetooth thermal printer by MAC address and persist it for auto-reconnect.
  Future<bool> connectToDevice(
    String macAddress, {
    String? deviceName,
    String? paperSize,
  }) async {
    final cleanMac = macAddress.trim();
    if (cleanMac.isEmpty) return false;

    try {
      bool ok = false;
      if (!kIsWeb) {
        ok = await PrintBluetoothThermal.connect(macPrinterAddress: cleanMac);
      }

      if (ok) {
        savedMacAddress = cleanMac;
        savedPrinterName = deviceName ?? savedPrinterName ?? 'Printer ($cleanMac)';
        if (paperSize != null) {
          paperWidth = paperSize;
          await _prefs?.setString(_keyPaperWidth, paperSize);
        }
        await _prefs?.setString(_keyMac, cleanMac);
        await _prefs?.setString(_keyName, savedPrinterName!);

        connectedPrinter = BluetoothPrinterDevice(
          name: savedPrinterName!,
          macAddress: cleanMac,
          paperSize: paperWidth,
        );
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Keep synchronous device metadata setter for local selection state.
  void connectDevice(BluetoothPrinterDevice device) {
    connectedPrinter = device;
    savedMacAddress = device.macAddress;
    savedPrinterName = device.name;
    paperWidth = device.paperSize;
    _prefs?.setString(_keyMac, device.macAddress);
    _prefs?.setString(_keyName, device.name);
    _prefs?.setString(_keyPaperWidth, device.paperSize);
  }

  Future<void> disconnectDevice({bool forgetSavedMac = false}) async {
    connectedPrinter = null;
    if (!kIsWeb) {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
    }
    if (forgetSavedMac) {
      savedMacAddress = null;
      savedPrinterName = null;
      await _prefs?.remove(_keyMac);
      await _prefs?.remove(_keyName);
    }
  }

  void disconnect() {
    connectedPrinter = null;
    if (!kIsWeb) {
      try {
        PrintBluetoothThermal.disconnect;
      } catch (_) {}
    }
  }

  /// Send raw ESC/POS bytes to connected physical printer (with auto-reconnect to `savedMacAddress`).
  Future<bool> printBytes(List<int> bytes) async {
    if (kIsWeb || bytes.isEmpty) return false;
    try {
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected && savedMacAddress != null && savedMacAddress!.isNotEmpty) {
        connected = await PrintBluetoothThermal.connect(macPrinterAddress: savedMacAddress!);
      }
      if (!connected) return false;
      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {
      return false;
    }
  }

  /// Encode formatted thermal receipt text into ESC/POS bytes and print physically.
  Future<bool> printReceiptText(
    String text, {
    bool? cutPaper,
    bool? openCashDrawer,
  }) async {
    final bytes = buildEscPosBytesFromText(
      text,
      cutPaper: cutPaper ?? autoCutPaper,
      openCashDrawer: openCashDrawer ?? false,
    );
    return await printBytes(bytes);
  }

  /// Send RJ-11 Pin 2 Cash Drawer Kick Pulse `[0x1B, 0x70, 0x00, 0x19, 0xFA]`.
  Future<bool> kickCashDrawer() async {
    return await printBytes(buildCashDrawerKickBytes());
  }

  /// Build ESC/POS raw byte payload from formatted receipt text (supports 58mm & 80mm thermal printers).
  List<int> buildEscPosBytesFromText(
    String text, {
    bool cutPaper = true,
    bool openCashDrawer = false,
  }) {
    final bytes = <int>[];
    // ESC @ (Initialize Printer)
    bytes.addAll([0x1B, 0x40]);
    // ESC t 0 (Select character code table PC437)
    bytes.addAll([0x1B, 0x74, 0x00]);

    // Encode text lines into printable ASCII/UTF-8 safe bytes
    final normalized = text.replaceAll('•', '-').replaceAll('×', 'x');
    bytes.addAll(utf8.encode('$normalized\n\n\n'));

    // Optional Partial Paper Cut (GS V 66 0)
    if (cutPaper) {
      bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    }

    // Optional RJ-11 Cash Drawer Kick Pulse
    if (openCashDrawer) {
      bytes.addAll(buildCashDrawerKickBytes());
    }

    return bytes;
  }

  /// ESC/POS Standard Cash Drawer Kick Pulse Command (Pin 2 / RJ-11)
  Uint8List buildCashDrawerKickBytes() {
    return Uint8List.fromList([0x1B, 0x70, 0x00, 0x19, 0xFA]);
  }

  /// Build ESC/POS Test Print Slip
  String formatTestPrintReceiptText({
    required Map<String, dynamic> storeProfile,
    String? paperWidthOverride,
  }) {
    final activeWidth = paperWidthOverride ?? paperWidth;
    final width = activeWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final doubleDivider = '=' * width;
    final storeName = (storeProfile['name'] ?? 'NUSACOMMERCE POS').toString().toUpperCase();
    final deviceLabel = connectedPrinter?.name ?? 'Printer ($activeWidth)';
    final macLabel = connectedPrinter?.macAddress ?? savedMacAddress ?? '-';

    return [
      doubleDivider,
      storeName,
      'UJI CETAK PRINTER THERMAL',
      doubleDivider,
      'Perangkat : $deviceLabel',
      'Alamat MAC: $macLabel',
      'Lebar     : $activeWidth ($width kolom)',
      'Auto-Cut  : ${autoCutPaper ? 'AKTIF' : 'NONAKTIF'}',
      'Laci RJ-11: ${autoOpenCashDrawer ? 'AKTIF' : 'MANUAL'}',
      divider,
      '1234567890' * (width ~/ 10),
      'Uji Angka :         Rp 150.000',
      'Status    : PRINTER SIAP PAKAI',
      doubleDivider,
    ].join('\n');
  }

  /// Build formatted text & ESC/POS byte stream for a Customer Sale Receipt
  String formatThermalReceiptText({
    required Map<String, dynamic> storeProfile,
    required Map<String, dynamic> sale,
    String? paperWidthOverride,
  }) {
    final activeWidth = paperWidthOverride ?? paperWidth;
    final width = activeWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final doubleDivider = '=' * width;

    final storeName = (storeProfile['name'] ?? 'NusaCommerce POS').toString().toUpperCase();
    final storeAddress = (storeProfile['address'] ?? '-').toString();
    final storePhone = (storeProfile['phone'] ?? '-').toString();
    final footer = (storeProfile['receipt_footer'] ?? 'Terima kasih atas kunjungan Anda!').toString();

    final number = (sale['number'] ?? '#INV-0001').toString();
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
    if (sale['notes'] != null && sale['notes'].toString().trim().isNotEmpty) {
      sb.writeln('Catatan: ${sale['notes'].toString().trim()}');
    }
    sb.writeln(divider);

    for (final rawItem in items) {
      final item = Map<String, dynamic>.from(rawItem as Map);
      final name = (item['product_name'] ?? 'Produk').toString();
      final qty = (item['quantity'] as num?) ?? 1;
      final unitCode = (item['unit_code'] ?? '').toString().trim();
      final price = (item['unit_price'] as num?) ?? 0;
      final lineTotal = (item['line_total'] as num?) ?? (qty * price);

      sb.writeln(name);
      final qtySuffix = unitCode.isNotEmpty ? ' $unitCode' : '';
      sb.writeln(
        _leftRight(
          '  ${IdrCurrencyFormatter.formatQty(qty)}$qtySuffix x ${IdrCurrencyFormatter.format(price, withSymbol: false)}',
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
    final serviceCharge = (sale['service_charge_amount'] as num?) ?? 0;
    final grandTotal = (sale['grand_total'] as num?) ?? subtotal;
    final storeCreditAmount = (sale['store_credit_amount'] as num?) ?? 0;
    final paid = (sale['paid_total'] as num?) ?? grandTotal;
    final change = (sale['change_returned'] as num?) ?? 0;
    final balanceDue = (sale['balance_due'] as num?) ?? 0;
    final dueDate = sale['due_date']?.toString();

    sb.writeln(_leftRight('Subtotal', IdrCurrencyFormatter.format(subtotal), width));
    if (discount > 0) {
      sb.writeln(_leftRight('Diskon', '-${IdrCurrencyFormatter.format(discount)}', width));
    }
    if (tax > 0) {
      sb.writeln(_leftRight('PPN / Pajak', IdrCurrencyFormatter.format(tax), width));
    }
    if (serviceCharge > 0) {
      sb.writeln(_leftRight('Service Charge', IdrCurrencyFormatter.format(serviceCharge), width));
    }
    sb.writeln(doubleDivider);
    sb.writeln(_leftRight('TOTAL TAGIHAN', IdrCurrencyFormatter.format(grandTotal), width));
    if (storeCreditAmount > 0) {
      sb.writeln(_leftRight('Potong Saldo Deposit', IdrCurrencyFormatter.format(storeCreditAmount), width));
    }
    if (balanceDue > 0) {
      sb.writeln(_leftRight('Uang Muka (DP)', IdrCurrencyFormatter.format(paid), width));
      sb.writeln(_leftRight('SISA TAGIHAN (KASBON)', IdrCurrencyFormatter.format(balanceDue), width));
      if (dueDate != null && dueDate.trim().isNotEmpty) {
        sb.writeln(_leftRight('Jatuh Tempo', dueDate.trim(), width));
      }
    } else {
      sb.writeln(_leftRight('Bayar ($methods)', IdrCurrencyFormatter.format(paid), width));
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

  /// Build Thermal Shift Z-Report text (58mm / 80mm) for Closing Shift
  String formatShiftZReportText({
    required Map<String, dynamic> storeProfile,
    required String cashierName,
    required num openingCash,
    required num cashSalesTotal,
    required num payInTotal,
    required num payOutTotal,
    required num expectedCash,
    required num countedCash,
    String? notes,
    String? paperWidthOverride,
  }) {
    final activeWidth = paperWidthOverride ?? paperWidth;
    final width = activeWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final doubleDivider = '=' * width;
    final storeName = (storeProfile['name'] ?? 'NusaCommerce POS').toString().toUpperCase();
    final variance = countedCash - expectedCash;

    final sb = StringBuffer();
    sb.writeln(_center('*** Z-REPORT TUTUP SHIFT ***', width));
    sb.writeln(_center(storeName, width));
    sb.writeln(doubleDivider);
    sb.writeln('Kasir : $cashierName');
    sb.writeln('Lebar : $activeWidth');
    sb.writeln(divider);
    sb.writeln(_leftRight('Modal Awal', IdrCurrencyFormatter.format(openingCash), width));
    sb.writeln(_leftRight('Penjualan Tunai', IdrCurrencyFormatter.format(cashSalesTotal), width));
    sb.writeln(_leftRight('Kas Masuk (Pay-In)', IdrCurrencyFormatter.format(payInTotal), width));
    sb.writeln(_leftRight('Kas Keluar (Pay-Out)', IdrCurrencyFormatter.format(payOutTotal), width));
    sb.writeln(divider);
    sb.writeln(_leftRight('Kas Sistem', IdrCurrencyFormatter.format(expectedCash), width));
    sb.writeln(_leftRight('Uang Fisik', IdrCurrencyFormatter.format(countedCash), width));
    sb.writeln(_leftRight('Selisih Kas', IdrCurrencyFormatter.format(variance), width));
    if (notes != null && notes.trim().isNotEmpty) {
      sb.writeln(divider);
      sb.writeln('Catatan: ${notes.trim()}');
    }
    sb.writeln(doubleDivider);
    sb.writeln(_center('Powered by NusaCommerce Cloud', width));
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
