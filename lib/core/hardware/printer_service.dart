import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/currency_formatter.dart';
import 'wifi_printer_transport.dart';

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
  static const String _keyKasirMac = 'nusa_printer_kasir_mac_v4';
  static const String _keyKasirName = 'nusa_printer_kasir_name_v4';
  static const String _keyDapurMac = 'nusa_printer_dapur_mac_v4';
  static const String _keyDapurName = 'nusa_printer_dapur_name_v4';
  static const String _keyBarMac = 'nusa_printer_bar_mac_v4';
  static const String _keyBarName = 'nusa_printer_bar_name_v4';
  static const String _keyPaperWidth = 'nusa_printer_paper_width_v4';
  static const String _keyAutoCut = 'nusa_printer_auto_cut_v4';
  static const String _keyAutoDrawer = 'nusa_printer_auto_drawer_v4';
  static const String _keyConnectionMode = 'nusa_printer_conn_mode_v4';
  static const String _keyWifiIp = 'nusa_printer_wifi_ip_v4';
  static const String _keyWifiPort = 'nusa_printer_wifi_port_v4';

  SharedPreferences? _prefs;

  BluetoothPrinterDevice? connectedPrinter;
  String? savedMacAddress;
  String? savedPrinterName;
  String? printerKasirMac;
  String? printerKasirName;
  String? printerDapurMac;
  String? printerDapurName;
  String? printerBarMac;
  String? printerBarName;
  String paperWidth = '58mm';
  bool autoCutPaper = true;
  bool autoOpenCashDrawer = true;
  String connectionMode = 'bluetooth'; // 'bluetooth' | 'wifi'
  String? wifiPrinterIp;
  int wifiPrinterPort = 9100;
  bool isScanning = false;

  bool get isWifiMode =>
      connectionMode == 'wifi' &&
      wifiPrinterIp != null &&
      wifiPrinterIp!.trim().isNotEmpty;

  String get activePrinterLabel {
    if (isWifiMode) {
      return 'WiFi LAN ($wifiPrinterIp:$wifiPrinterPort)';
    }
    return connectedPrinter?.name ?? savedPrinterName ?? 'Printer Bluetooth';
  }

  List<BluetoothPrinterDevice> discoveredDevices = [];

  /// Initialize printer preferences and auto-reconnect previously saved MAC address.
  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    savedMacAddress = prefs.getString(_keyMac);
    savedPrinterName = prefs.getString(_keyName);
    printerKasirMac = prefs.getString(_keyKasirMac) ?? savedMacAddress;
    printerKasirName = prefs.getString(_keyKasirName) ?? savedPrinterName;
    printerDapurMac = prefs.getString(_keyDapurMac);
    printerDapurName = prefs.getString(_keyDapurName);
    printerBarMac = prefs.getString(_keyBarMac);
    printerBarName = prefs.getString(_keyBarName);
    paperWidth = prefs.getString(_keyPaperWidth) ?? '58mm';
    autoCutPaper = prefs.getBool(_keyAutoCut) ?? true;
    autoOpenCashDrawer = prefs.getBool(_keyAutoDrawer) ?? true;
    connectionMode = prefs.getString(_keyConnectionMode) ?? 'bluetooth';
    wifiPrinterIp = prefs.getString(_keyWifiIp);
    wifiPrinterPort = prefs.getInt(_keyWifiPort) ?? 9100;

    if (savedMacAddress != null && savedMacAddress!.isNotEmpty) {
      connectedPrinter = BluetoothPrinterDevice(
        name: savedPrinterName ?? 'Printer Kasir ($savedMacAddress)',
        macAddress: savedMacAddress!,
        paperSize: paperWidth,
      );
      // Non-blocking background reconnect: never freeze app startup for 5-15s
      // if the thermal Bluetooth printer is turned off or out of range.
      if (!kIsWeb) {
        unawaited(_reconnectSavedPrinterSilently(savedMacAddress!));
      }
    }
  }

  Future<void> _reconnectSavedPrinterSilently(String mac) async {
    try {
      final connected = await PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!connected) {
        await PrintBluetoothThermal.connect(macPrinterAddress: mac)
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
      }
    } catch (_) {
      // Non-fatal: printBytes will auto-retry with strict timeout when printing.
    }
  }

  Future<void> savePreferences({
    String? width,
    bool? autoCut,
    bool? autoDrawer,
    String? mode,
    String? wifiIp,
    int? wifiPort,
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
    if (mode != null && (mode == 'bluetooth' || mode == 'wifi')) {
      connectionMode = mode;
      await _prefs?.setString(_keyConnectionMode, mode);
    }
    if (wifiIp != null) {
      final clean = wifiIp.trim();
      wifiPrinterIp = clean.isEmpty ? null : clean;
      if (clean.isEmpty) {
        await _prefs?.remove(_keyWifiIp);
      } else {
        await _prefs?.setString(_keyWifiIp, clean);
      }
    }
    if (wifiPort != null && wifiPort > 0 && wifiPort <= 65535) {
      wifiPrinterPort = wifiPort;
      await _prefs?.setInt(_keyWifiPort, wifiPort);
    }
  }

  Future<void> saveWifiPrinter({
    required String ipAddress,
    int port = 9100,
    bool activateWifiMode = true,
  }) async {
    await savePreferences(
      wifiIp: ipAddress,
      wifiPort: port,
      mode: activateWifiMode ? 'wifi' : null,
    );
  }

  /// Real Bluetooth Connection Status via `PrintBluetoothThermal.connectionStatus`
  Future<bool> get isConnected async {
    if (kIsWeb) return connectedPrinter != null;
    try {
      return await PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
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
        ok = await PrintBluetoothThermal.connect(macPrinterAddress: cleanMac)
            .timeout(const Duration(seconds: 5), onTimeout: () => false);
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

  /// Send raw ESC/POS bytes to connected physical printer (WiFi/LAN TCP 9100 or Bluetooth,
  /// with strict timeout + auto-reconnect).
  Future<bool> printBytes(List<int> bytes) async {
    if (kIsWeb || bytes.isEmpty) return false;
    if (isWifiMode) {
      final sentWifi = await sendEscPosOverTcp(
        host: wifiPrinterIp!,
        port: wifiPrinterPort,
        bytes: bytes,
      );
      if (sentWifi) return true;
      // If Bluetooth MAC also configured, allow seamless fallback
      if (savedMacAddress == null || savedMacAddress!.isEmpty) {
        return false;
      }
    }
    try {
      bool connected = await PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!connected && savedMacAddress != null && savedMacAddress!.isNotEmpty) {
        connected = await PrintBluetoothThermal.connect(macPrinterAddress: savedMacAddress!)
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
      }
      if (!connected) return false;
      return await PrintBluetoothThermal.writeBytes(bytes)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
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

  /// Phase 3.1: Assign a Bluetooth thermal printer device to a specific station role
  /// (`'kasir'` = customer receipt, `'dapur'` = kitchen KOT food, `'bar'` = beverage ticket).
  Future<void> assignPrinterRole(String role, BluetoothPrinterDevice device) async {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'dapur') {
      printerDapurMac = device.macAddress;
      printerDapurName = device.name;
      await _prefs?.setString(_keyDapurMac, device.macAddress);
      await _prefs?.setString(_keyDapurName, device.name);
    } else if (normalized == 'bar') {
      printerBarMac = device.macAddress;
      printerBarName = device.name;
      await _prefs?.setString(_keyBarMac, device.macAddress);
      await _prefs?.setString(_keyBarName, device.name);
    } else {
      printerKasirMac = device.macAddress;
      printerKasirName = device.name;
      savedMacAddress = device.macAddress;
      savedPrinterName = device.name;
      connectedPrinter = device;
      await _prefs?.setString(_keyKasirMac, device.macAddress);
      await _prefs?.setString(_keyKasirName, device.name);
      await _prefs?.setString(_keyMac, device.macAddress);
      await _prefs?.setString(_keyName, device.name);
    }
  }

  Future<void> clearPrinterRole(String role) async {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'dapur') {
      printerDapurMac = null;
      printerDapurName = null;
      await _prefs?.remove(_keyDapurMac);
      await _prefs?.remove(_keyDapurName);
    } else if (normalized == 'bar') {
      printerBarMac = null;
      printerBarName = null;
      await _prefs?.remove(_keyBarMac);
      await _prefs?.remove(_keyBarName);
    } else {
      printerKasirMac = null;
      printerKasirName = null;
      await _prefs?.remove(_keyKasirMac);
      await _prefs?.remove(_keyKasirName);
    }
  }

  /// Print raw receipt/ticket text directly to the MAC address mapped to `role`.
  Future<bool> printToRole(
    String role,
    String text, {
    bool openCashDrawer = false,
  }) async {
    final normalized = role.trim().toLowerCase();
    final targetMac = normalized == 'dapur'
        ? printerDapurMac
        : normalized == 'bar'
            ? printerBarMac
            : (printerKasirMac ?? savedMacAddress);

    if (kIsWeb || targetMac == null || targetMac.trim().isEmpty) {
      return false;
    }

    final bytes = buildEscPosBytesFromText(
      text,
      cutPaper: autoCutPaper,
      openCashDrawer: normalized == 'kasir' ? openCashDrawer : false,
    );

    try {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: targetMac)
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
      if (!ok) return false;
      return await PrintBluetoothThermal.writeBytes(bytes)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  /// Phase 3.1: Multi-printer ESC/POS routing for F&B & Retail.
  /// Routes drink items to Bar printer (`printerBarMac`), food items to Kitchen KOT printer (`printerDapurMac`),
  /// and customer receipt to Cashier printer (`printerKasirMac`).
  Future<Map<String, bool>> routeOrderTicketsAndReceipt({
    required Map<String, dynamic> sale,
    required Map<String, dynamic> store,
    bool openCashDrawer = false,
    bool printReceipt = true,
  }) async {
    final results = <String, bool>{
      'kasir': false,
      'dapur': false,
      'bar': false,
    };

    final items = (sale['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    bool isDrinkItem(Map<String, dynamic> item) {
      final cat = (item['category_name'] ?? '').toString().toLowerCase();
      final name = (item['product_name'] ?? '').toString().toLowerCase();
      const drinkKeywords = [
        'minuman',
        'beverage',
        'drink',
        'kopi',
        'coffee',
        'teh',
        'tea',
        'jus',
        'juice',
        'latte',
        'matcha',
        'boba',
        'bar',
        'es ',
        'ice ',
      ];
      return drinkKeywords.any((kw) => cat.contains(kw) || name.contains(kw));
    }

    final barItems = items.where(isDrinkItem).toList();
    final kitchenItems = items.where((item) => !isDrinkItem(item)).toList();

    final tableName = (sale['table_name'] ?? 'Order Counter').toString();
    final sectionName = (sale['order_type'] ?? 'POS').toString();
    final pax = (sale['pax'] as num?)?.toInt() ?? 1;

    if (barItems.isNotEmpty && printerBarMac != null && printerBarMac!.isNotEmpty) {
      final barText = formatKitchenOrderTicket(
        tableName: '$tableName [BAR]',
        sectionName: sectionName,
        pax: pax,
        items: barItems,
      );
      results['bar'] = await printToRole('bar', barText);
    }

    if (kitchenItems.isNotEmpty && printerDapurMac != null && printerDapurMac!.isNotEmpty) {
      final kitchenText = formatKitchenOrderTicket(
        tableName: '$tableName [DAPUR]',
        sectionName: sectionName,
        pax: pax,
        items: kitchenItems,
      );
      results['dapur'] = await printToRole('dapur', kitchenText);
    }

    if (printReceipt) {
      final receiptText = formatThermalReceiptText(
        storeProfile: store,
        sale: sale,
      );
      results['kasir'] = await printToRole(
        'kasir',
        receiptText,
        openCashDrawer: openCashDrawer,
      );
    }

    return results;
  }

  /// Phase 2.2: Strict anti-fraud cash drawer kick guard.
  /// Returns `true` ONLY IF there is a positive Cash/Tunai payment component and it is NOT a reprint or 0-DP kasbon.
  static bool shouldKickCashDrawer({
    List<dynamic>? payments,
    List<dynamic>? paymentMethods,
    bool isKasbonZeroDp = false,
    bool isReprint = false,
  }) {
    if (isReprint || isKasbonZeroDp) return false;

    bool isCashLabel(String raw) {
      final lower = raw.trim().toLowerCase();
      return lower == 'cash' ||
          lower.contains('tunai') ||
          lower.contains('uang cash');
    }

    if (payments != null && payments.isNotEmpty) {
      for (final raw in payments) {
        if (raw is Map) {
          final amount = (raw['amount'] as num?)?.toDouble() ?? 0;
          final methodLabel = (raw['method'] ?? raw['method_code'] ?? raw['name'] ?? '').toString();
          if (amount > 0 && isCashLabel(methodLabel)) {
            return true;
          }
        }
      }
      return false;
    }

    if (paymentMethods != null && paymentMethods.isNotEmpty) {
      return paymentMethods.any((m) => isCashLabel(m.toString()));
    }

    return false;
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
    final storeName = (storeProfile['name'] ?? 'OXORA POS').toString().toUpperCase();
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

  /// Alias for `formatThermalReceiptText` supporting reprint watermark & multi-vertical metadata.
  String formatReceiptText({
    required Map<String, dynamic> storeProfile,
    required Map<String, dynamic> sale,
    String? paperWidthOverride,
    bool isReprint = false,
    int reprintCount = 1,
  }) {
    return formatThermalReceiptText(
      storeProfile: storeProfile,
      sale: sale,
      paperWidthOverride: paperWidthOverride,
      isReprint: isReprint,
      reprintCount: reprintCount,
    );
  }

  /// Build formatted text & ESC/POS byte stream for a Customer Sale Receipt
  String formatThermalReceiptText({
    required Map<String, dynamic> storeProfile,
    required Map<String, dynamic> sale,
    String? paperWidthOverride,
    bool isReprint = false,
    int reprintCount = 1,
  }) {
    final activeWidth = paperWidthOverride ?? paperWidth;
    final width = activeWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final doubleDivider = '=' * width;

    final storeName = (storeProfile['name'] ?? 'OXORA POS').toString().toUpperCase();
    final storeAddress = (storeProfile['address'] ?? '-').toString();
    final storePhone = (storeProfile['phone'] ?? '-').toString();
    final footer = (storeProfile['receipt_footer'] ?? 'Terima kasih atas kunjungan Anda!').toString();

    final number = (sale['number'] ?? '#INV-0001').toString();
    final dt = (sale['sale_datetime'] ?? 'Hari Ini').toString();
    final customerName = (sale['customer'] is Map ? sale['customer']['name'] : 'Pelanggan Umum').toString();
    final cashierName = (sale['cashier_name'] ?? sale['cashier'] ?? 'Kasir POS').toString();
    final items = (sale['items'] as List<dynamic>? ?? []);
    final methods = (sale['payment_methods'] as List<dynamic>? ?? ['Tunai']).join(', ');

    final effectiveReprint = isReprint || sale['is_reprint'] == true;
    final effectiveReprintCount =
        (sale['reprint_count'] as num?)?.toInt() ?? reprintCount;

    final sb = StringBuffer();
    if (effectiveReprint) {
      final now = DateTime.now();
      final dd = now.day.toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final yyyy = now.year.toString();
      final hh = now.hour.toString().padLeft(2, '0');
      final min = now.minute.toString().padLeft(2, '0');
      sb.writeln(doubleDivider);
      sb.writeln(_center('*** SALINAN / REPRINT KE-$effectiveReprintCount ***', width));
      sb.writeln('Tgl/Jam Cetak: $dd-$mm-$yyyy $hh:$min');
      sb.writeln('Kasir: $cashierName');
      sb.writeln(doubleDivider);
    }

    sb.writeln(_center(storeName, width));
    sb.writeln(_center(storeAddress, width));
    sb.writeln(_center('Telp: $storePhone', width));
    sb.writeln(doubleDivider);
    sb.writeln(_leftRight('No: $number', dt, width));
    sb.writeln(_leftRight('Pelanggan:', customerName, width));
    if (sale['notes'] != null && sale['notes'].toString().trim().isNotEmpty) {
      sb.writeln('Catatan: ${sale['notes'].toString().trim()}');
    }

    // Phase 4: Vertical-specific metadata (Workshop, Pharmacy, Laundry, Salon)
    final vMeta = sale['vertical_metadata'] is Map
        ? Map<String, dynamic>.from(sale['vertical_metadata'] as Map)
        : const <String, dynamic>{};
    if (vMeta.isNotEmpty) {
      final nopol = (vMeta['nopol'] ?? vMeta['plate_number'] ?? '').toString().trim();
      final kendaraan = (vMeta['vehicle_model'] ?? vMeta['kendaraan'] ?? '').toString().trim();
      final km = (vMeta['kilometer'] ?? vMeta['km'] ?? '').toString().trim();
      final mekanik = (vMeta['mechanic_name'] ?? vMeta['mekanik'] ?? '').toString().trim();
      if (nopol.isNotEmpty) sb.writeln('No. Polisi: $nopol');
      if (kendaraan.isNotEmpty) sb.writeln('Kendaraan: $kendaraan');
      if (km.isNotEmpty) sb.writeln('Kilometer (KM): $km');
      if (mekanik.isNotEmpty) sb.writeln('Mekanik: $mekanik');

      final doctor = (vMeta['doctor_name'] ?? '').toString().trim();
      final sip = (vMeta['doctor_sip'] ?? '').toString().trim();
      final patient = (vMeta['patient_name'] ?? '').toString().trim();
      final rxNo = (vMeta['prescription_number'] ?? '').toString().trim();
      if (doctor.isNotEmpty) sb.writeln('Dokter: $doctor');
      if (sip.isNotEmpty) sb.writeln('No. SIP: $sip');
      if (patient.isNotEmpty) sb.writeln('Pasien: $patient');
      if (rxNo.isNotEmpty) sb.writeln('No. Resep: $rxNo');

      final rack = (vMeta['rack_number'] ?? '').toString().trim();
      final estReady = (vMeta['estimated_ready_at'] ?? '').toString().trim();
      if (rack.isNotEmpty) sb.writeln('No. Rak: $rack');
      if (estReady.isNotEmpty) sb.writeln('Estimasi Selesai: $estReady');

      final leadStylist = (vMeta['stylist_name'] ?? '').toString().trim();
      if (leadStylist.isNotEmpty) sb.writeln('Kapster/Terapis: $leadStylist');
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
      final batchNo = (item['batch_number'] ?? '').toString().trim();
      final expiryDate = (item['expiry_date'] ?? '').toString().trim();
      if (batchNo.isNotEmpty || expiryDate.isNotEmpty) {
        final batchLabel = batchNo.isNotEmpty ? 'Batch: $batchNo' : '';
        final edLabel = expiryDate.isNotEmpty ? 'ED: $expiryDate' : '';
        final sep = (batchLabel.isNotEmpty && edLabel.isNotEmpty) ? ' | ' : '';
        sb.writeln('  $batchLabel$sep$edLabel');
      }
      final stylist = (item['stylist_name'] ?? '').toString().trim();
      if (stylist.isNotEmpty) {
        sb.writeln('  Kapster/Terapis: $stylist');
      }
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
    sb.writeln(_center('Powered by OXORA Cloud', width));

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
    final storeName = (storeProfile['name'] ?? 'OXORA POS').toString().toUpperCase();
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
    sb.writeln(_center('Powered by OXORA Cloud', width));
    return sb.toString();
  }

  /// Build Thermal Installment / Debt Settlement Receipt (Kwitansi Pelunasan)
  String formatSettlementReceipt({
    required Map<String, dynamic> storeProfile,
    required String type, // 'receivable' or 'payable'
    required String partyName,
    required String invoiceNumber,
    required num paidAmount,
    required num remainingBalance,
    required String paymentMethod,
    String? paidAt,
    String? notes,
    String? paperWidthOverride,
  }) {
    final activeWidth = paperWidthOverride ?? paperWidth;
    final width = activeWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final doubleDivider = '=' * width;
    final storeName = (storeProfile['name'] ?? 'OXORA POS').toString().toUpperCase();
    final isReceivable = type == 'receivable';
    final title = isReceivable ? '*** KWITANSI PIUTANG ***' : '*** BUKTI BAYAR HUTANG ***';
    final statusText = remainingBalance <= 0 ? 'LUNAS' : 'CICILAN / SEBAGIAN';

    final sb = StringBuffer();
    sb.writeln(_center(title, width));
    sb.writeln(_center(storeName, width));
    sb.writeln(doubleDivider);
    sb.writeln(_leftRight('No. Nota', invoiceNumber, width));
    sb.writeln(_leftRight(isReceivable ? 'Pelanggan' : 'Pemasok', partyName, width));
    if (paidAt != null && paidAt.isNotEmpty) {
      sb.writeln(_leftRight('Tanggal', paidAt.length > 16 ? paidAt.substring(0, 16) : paidAt, width));
    }
    sb.writeln(_leftRight('Metode', paymentMethod, width));
    sb.writeln(divider);
    sb.writeln(_leftRight('Nominal Bayar', IdrCurrencyFormatter.format(paidAmount), width));
    sb.writeln(_leftRight('Sisa Tagihan', IdrCurrencyFormatter.format(remainingBalance), width));
    sb.writeln(_leftRight('Status', statusText, width));
    if (notes != null && notes.trim().isNotEmpty) {
      sb.writeln(divider);
      sb.writeln('Catatan: ${notes.trim()}');
    }
    sb.writeln(doubleDivider);
    sb.writeln(_center('Terima kasih', width));
    return sb.toString();
  }

  /// Build Barcode / Price Tag Label Sticker text for Thermal Printer
  String formatBarcodeLabelText({
    required String storeName,
    required String productName,
    required String sku,
    required String barcode,
    required num price,
    bool showPrice = true,
    String? paperWidthOverride,
  }) {
    final activeWidth = paperWidthOverride ?? paperWidth;
    final width = activeWidth == '80mm' ? 46 : 32;
    final divider = '-' * width;
    final sb = StringBuffer();
    sb.writeln(_center(storeName.toUpperCase(), width));
    sb.writeln(divider);
    sb.writeln(_center(productName, width));
    if (showPrice) {
      sb.writeln(_center(IdrCurrencyFormatter.format(price), width));
    }
    final code = barcode.trim().isNotEmpty ? barcode.trim() : sku.trim();
    sb.writeln(_center('|| ||| |||| ||| ||', width));
    sb.writeln(_center(code.isNotEmpty ? code : '-', width));
    if (sku.trim().isNotEmpty && sku.trim() != code) {
      sb.writeln(_center('SKU: ${sku.trim()}', width));
    }
    sb.writeln(divider);
    return sb.toString();
  }

  /// Print N copies of a Barcode / Price Label to connected Bluetooth printer
  Future<bool> printBarcodeLabel({
    required String storeName,
    required String productName,
    required String sku,
    required String barcode,
    required num price,
    int copies = 1,
    bool showPrice = true,
  }) async {
    final text = formatBarcodeLabelText(
      storeName: storeName,
      productName: productName,
      sku: sku,
      barcode: barcode,
      price: price,
      showPrice: showPrice,
    );
    final safeCopies = copies.clamp(1, 50);
    bool allOk = true;
    for (int i = 0; i < safeCopies; i++) {
      final ok = await printReceiptText(text, openCashDrawer: false);
      if (!ok) allOk = false;
    }
    return allOk;
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
