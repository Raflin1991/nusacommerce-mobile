import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/models/auth_session_model.dart';

/// Cryptographic integrity & tamper-resistant local vault for OXO.ID PRO / Enterprise
/// entitlement and offline license state.
///
/// Combines:
/// 1. Pure-Dart RFC 6234 SHA-256 + RFC 2104 HMAC-SHA256 authentication tag.
/// 2. Stream-XOR payload encryption derived from SHA-256(masterKey || nonce || counter).
/// 3. Dual persistence: Hardware-backed [FlutterSecureStorage] (Android Keystore / iOS Keychain)
///    with a signed tamper-evident mirror in [SharedPreferences].
///
/// If [SharedPreferences] is edited to self-upgrade `tier` or inject PRO `active_modules`
/// (or cleared to bypass license checks), [verifyAndEnforce] detects the tampering and either
/// restores the authoritative signed state from Keystore or fails closed to `starter`.
class SecureLicenseVault {
  static const String _keyVaultEnvelope = 'nusa_pro_license_vault_v1';
  static const String _keyDeviceSalt = 'nusa_pro_license_device_salt_v1';
  static const String _keyPrefsMirror = 'nusa_pro_license_seal_v1';

  // Application-level domain pepper (combined with per-device random Keystore salt).
  static const String _appPepper = 'OXO.ID::PRO_ENTITLEMENT_VAULT::v1::9F3A7C2E1B8D';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  SecureLicenseVault({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  })  : _secureStorage = secureStorage,
        _prefs = prefs;

  /// Seal and persist the authenticated user's tier, plan, and unlocked modules.
  Future<String> sealSessionEntitlements(AuthSessionModel session) async {
    final salt = await _getOrCreateDeviceSalt();
    final key = _deriveKey(salt, session.tenantSubdomain, session.userId);
    final nonceBytes = _randomBytes(16);
    final nonceHex = _bytesToHex(nonceBytes);

    final sortedModules = <String>{
      'cash_debt',
      ...session.activeModules.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty),
    }.toList()
      ..sort();
    final sortedHidden = session.hiddenModules
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final payloadMap = <String, dynamic>{
      'v': 1,
      'tenant': session.tenantSubdomain.trim().toLowerCase(),
      'uid': session.userId,
      'tier': session.tier.trim().toLowerCase(),
      'plan': session.planName,
      'modules': sortedModules,
      'hidden': sortedHidden,
      'local_trial': session.isLocalTrial,
      'issued_at': DateTime.now().toUtc().toIso8601String(),
    };

    final plainBytes = Uint8List.fromList(utf8.encode(jsonEncode(payloadMap)));
    final cipherBytes = _xorKeystream(plainBytes, key, nonceBytes);
    final body = '$nonceHex.${base64Url.encode(cipherBytes)}';
    final macHex = _bytesToHex(hmacSha256(key, Uint8List.fromList(utf8.encode(body))));
    final envelope = 'v1.$body.$macHex';

    await _prefs.setString(_keyPrefsMirror, envelope);
    try {
      await _secureStorage.write(key: _keyVaultEnvelope, value: envelope);
    } catch (_) {
      // Safe fallback on web/headless runtimes without native Keystore plugin
    }
    return envelope;
  }

  /// Verify cached [AuthSessionModel] entitlements against the encrypted signed vault.
  /// - Restores authoritative signed entitlements from Keystore if SharedPreferences was tampered.
  /// - Fails closed to `starter` (`['cash_debt']`) if PRO/Enterprise claims have no valid signature.
  Future<({AuthSessionModel session, bool tampered, String status})> verifyAndEnforce(
    AuthSessionModel cachedSession,
  ) async {
    final salt = await _readDeviceSalt();
    final key = salt != null
        ? _deriveKey(salt, cachedSession.tenantSubdomain, cachedSession.userId)
        : null;

    Map<String, dynamic>? verifiedSecure;
    Map<String, dynamic>? verifiedMirror;

    if (key != null) {
      String? secureEnv;
      try {
        secureEnv = await _secureStorage.read(key: _keyVaultEnvelope);
      } catch (_) {}
      final mirrorEnv = _prefs.getString(_keyPrefsMirror);

      if (secureEnv != null && secureEnv.isNotEmpty) {
        verifiedSecure = _openEnvelope(secureEnv, key);
      }
      if (mirrorEnv != null && mirrorEnv.isNotEmpty) {
        verifiedMirror = _openEnvelope(mirrorEnv, key);
      }
    }

    final authoritative = verifiedSecure ?? verifiedMirror;

    if (authoritative != null && _matchesIdentity(authoritative, cachedSession)) {
      final authTier = (authoritative['tier'] ?? 'starter').toString().trim().toLowerCase();
      final authModules = (authoritative['modules'] as List<dynamic>? ?? const ['cash_debt'])
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      final authHidden = (authoritative['hidden'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final cachedModules = cachedSession.activeModules
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final sameTier = cachedSession.tier.trim().toLowerCase() == authTier;
      final sameModules = _listEquals(cachedModules, authModules);

      if (sameTier && sameModules) {
        return (session: cachedSession, tampered: false, status: 'verified');
      }

      // Tampering detected in SharedPreferences -> restore authoritative signed entitlements
      final restored = cachedSession.copyWith(
        tier: authTier,
        activeModules: authModules.isEmpty ? const ['cash_debt'] : authModules,
        hiddenModules: authHidden,
      );
      return (session: restored, tampered: true, status: 'restored_from_vault');
    }

    // No valid signed license record matches this session.
    // Check whether session claims privileged PRO/Enterprise access.
    final claimsElevatedTier = cachedSession.tier.trim().toLowerCase() != 'starter';
    final claimsPaidModule = cachedSession.activeModules.any(
      (m) => m.trim().toLowerCase().isNotEmpty && m.trim().toLowerCase() != 'cash_debt',
    );

    if (claimsElevatedTier || claimsPaidModule) {
      // Fail closed: re-lock PRO/Enterprise features until verified online by Cloud /auth/me.
      final locked = cachedSession.copyWith(
        tier: 'starter',
        activeModules: const ['cash_debt'],
      );
      return (session: locked, tampered: true, status: 'downgraded_unverified');
    }

    // Free starter / local-trial session: seal freshly for future tamper detection.
    await sealSessionEntitlements(cachedSession);
    return (session: cachedSession, tampered: false, status: 'starter_sealed');
  }

  /// Check whether a valid encrypted license seal currently exists for [session].
  Future<bool> hasValidSeal(AuthSessionModel session) async {
    final res = await verifyAndEnforce(session);
    return !res.tampered;
  }

  /// Clear sealed license records (only on Factory Reset or foreign tenant switch).
  Future<void> clearVault() async {
    await _prefs.remove(_keyPrefsMirror);
    await _prefs.remove(_keyDeviceSalt);
    try {
      await _secureStorage.delete(key: _keyVaultEnvelope);
    } catch (_) {}
  }

  bool _matchesIdentity(Map<String, dynamic> payload, AuthSessionModel session) {
    final pTenant = (payload['tenant'] ?? '').toString().trim().toLowerCase();
    final sTenant = session.tenantSubdomain.trim().toLowerCase();
    final pUid = (payload['uid'] as num?)?.toInt() ?? -1;
    final pLocalTrial = payload['local_trial'] == true;
    return pTenant == sTenant && pUid == session.userId && pLocalTrial == session.isLocalTrial;
  }

  Map<String, dynamic>? _openEnvelope(String envelope, Uint8List key) {
    final parts = envelope.split('.');
    if (parts.length != 4 || parts[0] != 'v1') return null;
    final nonceHex = parts[1];
    final cipherB64 = parts[2];
    final providedMacHex = parts[3];

    final body = '$nonceHex.$cipherB64';
    final expectedMacHex = _bytesToHex(hmacSha256(key, Uint8List.fromList(utf8.encode(body))));
    if (!_constantTimeEquals(providedMacHex, expectedMacHex)) {
      return null;
    }

    try {
      final nonceBytes = _hexToBytes(nonceHex);
      final cipherBytes = base64Url.decode(cipherB64);
      final plainBytes = _xorKeystream(Uint8List.fromList(cipherBytes), key, nonceBytes);
      final decoded = jsonDecode(utf8.decode(plainBytes));
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> _readDeviceSalt() async {
    try {
      final sec = await _secureStorage.read(key: _keyDeviceSalt);
      if (sec != null && sec.isNotEmpty) {
        if ((_prefs.getString(_keyDeviceSalt) ?? '').isEmpty) {
          await _prefs.setString(_keyDeviceSalt, sec);
        }
        return sec;
      }
    } catch (_) {}
    final pref = _prefs.getString(_keyDeviceSalt);
    if (pref != null && pref.isNotEmpty) return pref;
    return null;
  }

  Future<String> _getOrCreateDeviceSalt() async {
    final existing = await _readDeviceSalt();
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = _bytesToHex(_randomBytes(32));
    await _prefs.setString(_keyDeviceSalt, fresh);
    try {
      await _secureStorage.write(key: _keyDeviceSalt, value: fresh);
    } catch (_) {}
    return fresh;
  }

  Uint8List _deriveKey(String salt, String tenantSubdomain, int userId) {
    final material = '$_appPepper|$salt|${tenantSubdomain.trim().toLowerCase()}|$userId';
    return sha256(Uint8List.fromList(utf8.encode(material)));
  }

  static Uint8List _xorKeystream(Uint8List input, Uint8List key, Uint8List nonce) {
    final out = Uint8List(input.length);
    int offset = 0;
    int counter = 0;
    while (offset < input.length) {
      final blockInput = Uint8List(key.length + nonce.length + 4);
      blockInput.setRange(0, key.length, key);
      blockInput.setRange(key.length, key.length + nonce.length, nonce);
      final cOff = key.length + nonce.length;
      blockInput[cOff] = (counter >> 24) & 0xff;
      blockInput[cOff + 1] = (counter >> 16) & 0xff;
      blockInput[cOff + 2] = (counter >> 8) & 0xff;
      blockInput[cOff + 3] = counter & 0xff;
      final streamBlock = sha256(blockInput);
      final take = min(streamBlock.length, input.length - offset);
      for (int i = 0; i < take; i++) {
        out[offset + i] = input[offset + i] ^ streamBlock[i];
      }
      offset += take;
      counter++;
    }
    return out;
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // ===========================================================================
  // Pure-Dart RFC 6234 SHA-256 & RFC 2104 HMAC-SHA256 (Zero External Dependencies)
  // ===========================================================================
  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x & 0xffffffff) >>> n) | ((x << (32 - n)) & 0xffffffff);

  /// Compute SHA-256 digest (32 bytes).
  static Uint8List sha256(Uint8List data) {
    int h0 = 0x6a09e667;
    int h1 = 0xbb67ae85;
    int h2 = 0x3c6ef372;
    int h3 = 0xa54ff53a;
    int h4 = 0x510e527f;
    int h5 = 0x9b05688c;
    int h6 = 0x1f83d9ab;
    int h7 = 0x5be0cd19;

    final bitLen = data.length * 8;
    final padLen = ((56 - ((data.length + 1) % 64)) + 64) % 64;
    final totalLen = data.length + 1 + padLen + 8;
    final msg = Uint8List(totalLen);
    msg.setRange(0, data.length, data);
    msg[data.length] = 0x80;

    final highBits = (bitLen ~/ 0x100000000) & 0xffffffff;
    final lowBits = bitLen & 0xffffffff;
    msg[totalLen - 8] = (highBits >> 24) & 0xff;
    msg[totalLen - 7] = (highBits >> 16) & 0xff;
    msg[totalLen - 6] = (highBits >> 8) & 0xff;
    msg[totalLen - 5] = highBits & 0xff;
    msg[totalLen - 4] = (lowBits >> 24) & 0xff;
    msg[totalLen - 3] = (lowBits >> 16) & 0xff;
    msg[totalLen - 2] = (lowBits >> 8) & 0xff;
    msg[totalLen - 1] = lowBits & 0xff;

    final w = Uint32List(64);
    for (int chunk = 0; chunk < totalLen; chunk += 64) {
      for (int i = 0; i < 16; i++) {
        final j = chunk + (i * 4);
        w[i] = ((msg[j] << 24) | (msg[j + 1] << 16) | (msg[j + 2] << 8) | msg[j + 3]) & 0xffffffff;
      }
      for (int i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      int a = h0;
      int b = h1;
      int c = h2;
      int d = h3;
      int e = h4;
      int f = h5;
      int g = h6;
      int h = h7;

      for (int i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final digest = Uint8List(32);
    final words = [h0, h1, h2, h3, h4, h5, h6, h7];
    for (int i = 0; i < 8; i++) {
      digest[i * 4] = (words[i] >> 24) & 0xff;
      digest[i * 4 + 1] = (words[i] >> 16) & 0xff;
      digest[i * 4 + 2] = (words[i] >> 8) & 0xff;
      digest[i * 4 + 3] = words[i] & 0xff;
    }
    return digest;
  }

  /// Compute HMAC-SHA256 digest (32 bytes).
  static Uint8List hmacSha256(Uint8List key, Uint8List message) {
    const blockSize = 64;
    Uint8List normalizedKey = key.length > blockSize ? sha256(key) : key;
    final paddedKey = Uint8List(blockSize);
    paddedKey.setRange(0, normalizedKey.length, normalizedKey);

    final oKeyPad = Uint8List(blockSize);
    final iKeyPad = Uint8List(blockSize);
    for (int i = 0; i < blockSize; i++) {
      oKeyPad[i] = paddedKey[i] ^ 0x5c;
      iKeyPad[i] = paddedKey[i] ^ 0x36;
    }

    final innerInput = Uint8List(blockSize + message.length);
    innerInput.setRange(0, blockSize, iKeyPad);
    innerInput.setRange(blockSize, blockSize + message.length, message);
    final innerHash = sha256(innerInput);

    final outerInput = Uint8List(blockSize + innerHash.length);
    outerInput.setRange(0, blockSize, oKeyPad);
    outerInput.setRange(blockSize, blockSize + innerHash.length, innerHash);
    return sha256(outerInput);
  }
}
