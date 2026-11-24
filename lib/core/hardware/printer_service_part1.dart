// ignore_for_file: invalid_use_of_protected_member
part of 'printer_service.dart';

extension PrinterServicePart1Ext on PrinterService {

  String get activePrinterLabel {
    if (isWifiMode) {
      return 'WiFi LAN ($wifiPrinterIp:$wifiPrinterPort)';
    }
    return connectedPrinter?.name ?? savedPrinterName ?? 'Printer Bluetooth';
  }


  /// Initialize printer preferences and auto-reconnect previously saved MAC address.
  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
    savedMacAddress = prefs.getString(PrinterService._keyMac);
    savedPrinterName = prefs.getString(PrinterService._keyName);
    printerKasirMac = prefs.getString(PrinterService._keyKasirMac) ?? savedMacAddress;
    printerKasirName = prefs.getString(PrinterService._keyKasirName) ?? savedPrinterName;
    printerDapurMac = prefs.getString(PrinterService._keyDapurMac);
    printerDapurName = prefs.getString(PrinterService._keyDapurName);
    printerBarMac = prefs.getString(PrinterService._keyBarMac);
    printerBarName = prefs.getString(PrinterService._keyBarName);
    paperWidth = prefs.getString(PrinterService._keyPaperWidth) ?? '58mm';
    autoCutPaper = prefs.getBool(PrinterService._keyAutoCut) ?? true;
    autoOpenCashDrawer = prefs.getBool(PrinterService._keyAutoDrawer) ?? true;
    connectionMode = prefs.getString(PrinterService._keyConnectionMode) ?? 'bluetooth';
    wifiPrinterIp = prefs.getString(PrinterService._keyWifiIp);
    wifiPrinterPort = prefs.getInt(PrinterService._keyWifiPort) ?? 9100;

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
      await _prefs?.setString(PrinterService._keyPaperWidth, width);
    }
    if (autoCut != null) {
      autoCutPaper = autoCut;
      await _prefs?.setBool(PrinterService._keyAutoCut, autoCut);
    }
    if (autoDrawer != null) {
      autoOpenCashDrawer = autoDrawer;
      await _prefs?.setBool(PrinterService._keyAutoDrawer, autoDrawer);
    }
    if (mode != null && (mode == 'bluetooth' || mode == 'wifi')) {
      connectionMode = mode;
      await _prefs?.setString(PrinterService._keyConnectionMode, mode);
    }
    if (wifiIp != null) {
      final clean = wifiIp.trim();
      wifiPrinterIp = clean.isEmpty ? null : clean;
      if (clean.isEmpty) {
        await _prefs?.remove(PrinterService._keyWifiIp);
      } else {
        await _prefs?.setString(PrinterService._keyWifiIp, clean);
      }
    }
    if (wifiPort != null && wifiPort > 0 && wifiPort <= 65535) {
      wifiPrinterPort = wifiPort;
      await _prefs?.setInt(PrinterService._keyWifiPort, wifiPort);
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
          await _prefs?.setString(PrinterService._keyPaperWidth, paperSize);
        }
        await _prefs?.setString(PrinterService._keyMac, cleanMac);
        await _prefs?.setString(PrinterService._keyName, savedPrinterName!);

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
    _prefs?.setString(PrinterService._keyMac, device.macAddress);
    _prefs?.setString(PrinterService._keyName, device.name);
    _prefs?.setString(PrinterService._keyPaperWidth, device.paperSize);
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
      await _prefs?.remove(PrinterService._keyMac);
      await _prefs?.remove(PrinterService._keyName);
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
      await _prefs?.setString(PrinterService._keyDapurMac, device.macAddress);
      await _prefs?.setString(PrinterService._keyDapurName, device.name);
    } else if (normalized == 'bar') {
      printerBarMac = device.macAddress;
      printerBarName = device.name;
      await _prefs?.setString(PrinterService._keyBarMac, device.macAddress);
      await _prefs?.setString(PrinterService._keyBarName, device.name);
    } else {
      printerKasirMac = device.macAddress;
      printerKasirName = device.name;
      savedMacAddress = device.macAddress;
      savedPrinterName = device.name;
      connectedPrinter = device;
      await _prefs?.setString(PrinterService._keyKasirMac, device.macAddress);
      await _prefs?.setString(PrinterService._keyKasirName, device.name);
      await _prefs?.setString(PrinterService._keyMac, device.macAddress);
      await _prefs?.setString(PrinterService._keyName, device.name);
    }
  }


  Future<void> clearPrinterRole(String role) async {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'dapur') {
      printerDapurMac = null;
      printerDapurName = null;
      await _prefs?.remove(PrinterService._keyDapurMac);
      await _prefs?.remove(PrinterService._keyDapurName);
    } else if (normalized == 'bar') {
      printerBarMac = null;
      printerBarName = null;
      await _prefs?.remove(PrinterService._keyBarMac);
      await _prefs?.remove(PrinterService._keyBarName);
    } else {
      printerKasirMac = null;
      printerKasirName = null;
      await _prefs?.remove(PrinterService._keyKasirMac);
      await _prefs?.remove(PrinterService._keyKasirName);
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
      final explicitStation = (item['kds_station'] ?? '').toString().trim().toLowerCase();
      if (explicitStation.isNotEmpty) {
        return explicitStation == 'bar' ||
            explicitStation == 'beverage' ||
            explicitStation == 'coffee';
      }
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
}
