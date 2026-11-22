import 'wifi_printer_transport_stub.dart'
    if (dart.library.io) 'wifi_printer_transport_io.dart' as transport;

/// Cross-platform TCP/IP RAW 9100 Thermal Printer Transport (Android/iOS/Desktop).
/// Gracefully returns `false` on Flutter Web where raw TCP sockets are unavailable.
Future<bool> sendEscPosOverTcp({
  required String host,
  required int port,
  required List<int> bytes,
  Duration timeout = const Duration(seconds: 4),
}) {
  return transport.sendEscPosOverTcpImpl(
    host: host,
    port: port,
    bytes: bytes,
    timeout: timeout,
  );
}
