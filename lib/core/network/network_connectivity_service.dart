import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Reactive Connectivity Service wrapping `connectivity_plus` v6+ (`List<ConnectivityResult>`).
class NetworkConnectivityService {
  final Connectivity _connectivity;

  NetworkConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  static bool hasActiveConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Check current connectivity state safely.
  Future<bool> checkOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return hasActiveConnection(results);
    } catch (_) {
      return true;
    }
  }

  /// Broadcast stream emitting `true` (wifi / mobile / ethernet) or `false` (none).
  Stream<bool> get onOnlineChanged {
    return _connectivity.onConnectivityChanged
        .map(hasActiveConnection)
        .distinct();
  }
}
