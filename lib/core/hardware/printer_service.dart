import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/currency_formatter.dart';
import 'wifi_printer_transport.dart';

part 'printer_service_part1.dart';
part 'printer_service_part2.dart';

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


  List<BluetoothPrinterDevice> discoveredDevices = [];


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
}
