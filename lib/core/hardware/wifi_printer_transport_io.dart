import 'dart:io';

Future<bool> sendEscPosOverTcpImpl({
  required String host,
  required int port,
  required List<int> bytes,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final cleanHost = host.trim();
  if (cleanHost.isEmpty || port <= 0 || bytes.isEmpty) return false;
  Socket? socket;
  try {
    socket = await Socket.connect(cleanHost, port, timeout: timeout);
    socket.add(bytes);
    await socket.flush().timeout(timeout);
    await socket.close().timeout(const Duration(seconds: 2));
    return true;
  } catch (_) {
    try {
      socket?.destroy();
    } catch (_) {}
    return false;
  }
}
