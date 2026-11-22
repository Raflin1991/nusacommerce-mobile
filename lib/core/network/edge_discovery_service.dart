import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../constants/api_endpoints.dart';

enum EdgeConnectionTier {
  lanEdge,
  cloudMaster,
  deviceSqlite,
}

/// 3-Tier Deterministic Endpoint Discovery Service for NusaEdge:
/// 1) Branch LAN Edge Node (`https://erp.cabang.local/api/v1`) with strict 1.5s probe
/// 2) Cloud Master ERP (`cloudBaseUrl`)
/// 3) On-Device SQLite Failover (`EdgeConnectionTier.deviceSqlite`)
class EdgeDiscoveryService {
  final SharedPreferences _prefs;

  static const String _keyEdgeBaseUrl = 'nusa_edge_lan_base_url';
  static const String _keyCloudBaseUrl = 'nusa_cloud_master_base_url';
  static const String _keyMobileNodeCode = 'nusa_mobile_node_code';
  static const String _keyLowBandwidth = 'nusa_edge_low_bandwidth_mode';
  static const String _keyLastTier = 'nusa_edge_last_tier';

  EdgeConnectionTier currentTier = EdgeConnectionTier.cloudMaster;

  EdgeDiscoveryService(this._prefs);

  String? getEdgeBaseUrl() {
    final val = _prefs.getString(_keyEdgeBaseUrl)?.trim();
    return (val == null || val.isEmpty) ? null : val.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> setEdgeBaseUrl(String? url) async {
    final cleaned = url?.trim().replaceAll(RegExp(r'/+$'), '') ?? '';
    if (cleaned.isEmpty) {
      await _prefs.remove(_keyEdgeBaseUrl);
    } else {
      await _prefs.setString(_keyEdgeBaseUrl, cleaned);
    }
  }

  String getCloudBaseUrl({String fallback = ApiEndpoints.defaultBaseUrl}) {
    final val = _prefs.getString(_keyCloudBaseUrl)?.trim();
    if (val != null && val.isNotEmpty) {
      return val.replaceAll(RegExp(r'/+$'), '');
    }
    return fallback;
  }

  Future<void> setCloudBaseUrl(String url) async {
    await _prefs.setString(_keyCloudBaseUrl, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  /// Returns this physical device's persistent terminal/node partition code
  /// (e.g. `M4F9A` auto-generated per install, or explicit admin override `M01`..`M99`).
  /// Ensures multi-device offline POS terminals in the same store never collide on
  /// `UNIQUE(store_id, number)` when draining offline queues to Cloud.
  String getMobileNodeCode() {
    final saved = _prefs.getString(_keyMobileNodeCode)?.trim().toUpperCase();
    if (saved != null && RegExp(r'^M[A-Z0-9]{2,5}$').hasMatch(saved)) {
      return saved;
    }
    final hex4 = const Uuid().v4().replaceAll('-', '').substring(0, 4).toUpperCase();
    final assigned = 'M$hex4';
    _prefs.setString(_keyMobileNodeCode, assigned);
    return assigned;
  }

  Future<void> setMobileNodeCode(String code) async {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.isEmpty) return;
    final prefixed = clean.startsWith('M') ? clean : 'M$clean';
    final normalized = prefixed.length > 6 ? prefixed.substring(0, 6) : prefixed;
    await _prefs.setString(_keyMobileNodeCode, normalized);
  }

  bool isLowBandwidthMode() => _prefs.getBool(_keyLowBandwidth) ?? false;

  Future<void> setLowBandwidthMode(bool enabled) async {
    await _prefs.setBool(_keyLowBandwidth, enabled);
  }

  /// Probe LAN Edge -> Cloud Master -> On-Device SQLite deterministically.
  Future<EdgeConnectionTier> probeBestTier({
    Dio? probeDio,
    Duration lanTimeout = const Duration(milliseconds: 1500),
    Duration cloudTimeout = const Duration(seconds: 4),
  }) async {
    final client = probeDio ?? Dio();
    final edgeUrl = getEdgeBaseUrl();

    if (edgeUrl != null && edgeUrl.isNotEmpty) {
      if (await _isEndpointHealthy(client, '$edgeUrl${ApiEndpoints.edgeHealth}', lanTimeout)) {
        currentTier = EdgeConnectionTier.lanEdge;
        await _prefs.setString(_keyLastTier, currentTier.name);
        return currentTier;
      }
    }

    final cloudUrl = getCloudBaseUrl();
    if (await _isEndpointHealthy(client, '$cloudUrl${ApiEndpoints.edgeHealth}', cloudTimeout)) {
      currentTier = EdgeConnectionTier.cloudMaster;
      await _prefs.setString(_keyLastTier, currentTier.name);
      return currentTier;
    }

    currentTier = EdgeConnectionTier.deviceSqlite;
    await _prefs.setString(_keyLastTier, currentTier.name);
    return currentTier;
  }

  String activeBaseUrlForTier(EdgeConnectionTier tier) {
    if (tier == EdgeConnectionTier.lanEdge) {
      return getEdgeBaseUrl() ?? getCloudBaseUrl();
    }
    return getCloudBaseUrl();
  }

  Future<bool> _isEndpointHealthy(Dio client, String url, Duration timeout) async {
    try {
      final res = await client.get(
        url,
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
      );
      return res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }
}
