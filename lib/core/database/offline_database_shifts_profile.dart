part of 'offline_database.dart';

extension OfflineDatabaseShiftsProfileExt on OfflineDatabase {
  // ===========================================================================
  // 6. STORE PROFILE & PAIRED BLUETOOTH PRINTER (NAME + MAC ADDRESS)
  // ===========================================================================
  /// Returns the explicitly saved store profile or `null` if no store has been configured yet.
  Map<String, dynamic>? getSavedStoreProfile() {
    final raw = _prefs.getString(OfflineDatabase._keyStoreProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final name = (map['name'] ?? '').toString().trim();
      if (name.isEmpty) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  bool get hasSavedStoreProfile => getSavedStoreProfile() != null;

  /// True when an Offline Standalone store was previously created on this device
  /// and its SQLite + SharedPreferences data persists safely across logouts.
  bool get hasExistingStandaloneStore {
    final saved = getSavedStoreProfile();
    if (saved == null) return false;
    final identity = getActiveTenantIdentity() ?? '';
    if (identity.startsWith('local-trial')) return true;
    if (saved['is_standalone'] == true) return true;
    return false;
  }

  Map<String, dynamic> getStoreProfile() {
    final saved = getSavedStoreProfile();
    if (saved != null) return saved;
    return {
      'name': 'OXORA POS',
      'branch': 'Toko Utama',
      'address': '-',
      'phone': '-',
      'receipt_footer': 'Terima kasih atas kunjungan Anda!',
      'paper_size': '58mm',
    };
  }

  Future<void> saveStoreProfile(Map<String, dynamic> profile) async {
    await _prefs.setString(OfflineDatabase._keyStoreProfile, jsonEncode(profile));
  }

  String? getPairedPrinterName() => _prefs.getString(OfflineDatabase._keyPairedPrinter);

  Future<void> setPairedPrinterName(String? name) async {
    if (name == null) {
      await _prefs.remove(OfflineDatabase._keyPairedPrinter);
    } else {
      await _prefs.setString(OfflineDatabase._keyPairedPrinter, name);
    }
  }

  String? getSavedPrinterMac() => _prefs.getString(OfflineDatabase._keyPairedPrinterMac);

  Future<void> setSavedPrinterMac(String? mac) async {
    if (mac == null || mac.trim().isEmpty) {
      await _prefs.remove(OfflineDatabase._keyPairedPrinterMac);
    } else {
      await _prefs.setString(OfflineDatabase._keyPairedPrinterMac, mac.trim());
    }
  }

  // ===========================================================================
  // 7. BUSINESS VERTICAL MODE (Single Source of Truth Fallback)
  // ===========================================================================
  String? getSavedBusinessVertical() => _prefs.getString(OfflineDatabase._keyBusinessVerticalMode);

  Future<void> setSavedBusinessVertical(String mode) async {
    await _prefs.setString(OfflineDatabase._keyBusinessVerticalMode, mode.trim().toLowerCase());
  }


  // ===========================================================================
  // 8. LOCAL SHIFTS & DRAWER CASH MUTATION ENGINE
  // ===========================================================================
  List<Map<String, dynamic>> getLocalShiftsHistory() {
    final list = _readCollectionList(OfflineDatabase._keyLocalShifts);
    list.sort((a, b) => (b['opened_at'] ?? '').toString().compareTo((a['opened_at'] ?? '').toString()));
    return list;
  }

  Future<void> _saveLocalShifts(List<Map<String, dynamic>> shifts) async {
    await _writeCollectionList(OfflineDatabase._keyLocalShifts, shifts);
  }

  DateTime? _parseFlexDateTime(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    final iso = DateTime.tryParse(str);
    if (iso != null) return iso;
    // Handle dd/MM/yyyy HH:mm or dd/MM/yyyy HH:mm:ss
    final reg = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?');
    final m = reg.firstMatch(str);
    if (m != null) {
      return DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
        int.tryParse(m.group(4) ?? '0') ?? 0,
        int.tryParse(m.group(5) ?? '0') ?? 0,
        int.tryParse(m.group(6) ?? '0') ?? 0,
      );
    }
    return null;
  }

  ({double cashSales, int txCount}) _computeShiftCashSales(DateTime openedAt) {
    double cashTotal = 0.0;
    int txCount = 0;
    final sales = getLocalSalesHistory();
    for (final s in sales) {
      final status = (s['status'] ?? 'completed').toString().toLowerCase();
      if (status == 'voided') continue;
      final saleDt = _parseFlexDateTime(s['created_at'] ?? s['sale_datetime']);
      if (saleDt != null && saleDt.isBefore(openedAt.subtract(const Duration(seconds: 2)))) {
        continue;
      }
      txCount++;
      final payments = s['payments'];
      final changeReturned = (s['change_returned'] as num?)?.toDouble() ?? 0.0;
      double saleCash = 0.0;
      if (payments is List && payments.isNotEmpty) {
        for (final p in payments) {
          if (p is! Map) continue;
          final method = (p['method_name'] ?? p['payment_method_name'] ?? p['name'] ?? '').toString().toLowerCase();
          final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          if (method.contains('tunai') || method.contains('cash')) {
            saleCash += amt;
          }
        }
        if (saleCash > 0 && changeReturned > 0) {
          saleCash = (saleCash - changeReturned).clamp(0.0, double.infinity);
        }
      } else {
        final methods = (s['payment_methods'] as List?)?.join(' ').toLowerCase() ?? '';
        if (methods.contains('tunai') || methods.contains('cash')) {
          saleCash = ((s['paid_total'] as num?)?.toDouble() ?? 0.0) - changeReturned;
          if (saleCash < 0) saleCash = 0.0;
        }
      }
      cashTotal += saleCash;
    }
    return (cashSales: cashTotal, txCount: txCount);
  }

  Map<String, dynamic> _enrichShiftTotals(Map<String, dynamic> rawShift) {
    final shift = Map<String, dynamic>.from(rawShift);
    final openedAt = _parseFlexDateTime(shift['opened_at']) ?? DateTime.now();
    final isClosed = (shift['status'] ?? 'open').toString().toLowerCase() == 'closed';
    final computed = isClosed
        ? (
            cashSales: (shift['cash_sales'] as num?)?.toDouble() ?? 0.0,
            txCount: (shift['transactions_count'] as num?)?.toInt() ?? 0,
          )
        : _computeShiftCashSales(openedAt);

    final opening = (shift['opening_cash'] as num?)?.toDouble() ?? 0.0;
    final cashIn = (shift['cash_in'] as num?)?.toDouble() ?? 0.0;
    final cashOut = (shift['cash_out'] as num?)?.toDouble() ?? 0.0;
    final expected = opening + computed.cashSales + cashIn - cashOut;

    shift['cash_sales'] = computed.cashSales;
    shift['transactions_count'] = computed.txCount;
    shift['expected_cash'] = expected;
    if (shift['entries'] is! List) shift['entries'] = <dynamic>[];
    return shift;
  }

  Map<String, dynamic>? getCurrentLocalShift() {
    final shifts = getLocalShiftsHistory();
    for (final s in shifts) {
      if ((s['status'] ?? '').toString().toLowerCase() == 'open') {
        return _enrichShiftTotals(s);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> openLocalShift({
    required double openingCash,
    String? notes,
    String? cashierName,
  }) async {
    final shifts = getLocalShiftsHistory();
    final existingIdx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (existingIdx >= 0) {
      final enriched = _enrichShiftTotals(shifts[existingIdx]);
      enriched['status'] = 'closed';
      enriched['closed_at'] = DateTime.now().toIso8601String();
      enriched['closing_cash'] = enriched['expected_cash'];
      enriched['variance'] = 0.0;
      shifts[existingIdx] = enriched;
      await _sqlite.upsertShift(enriched);
    }

    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch;
    final newShift = <String, dynamic>{
      'id': id,
      'shift_number': 'SHF-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(id % 1000).toString().padLeft(3, '0')}',
      'cashier_name': (cashierName ?? 'Kasir Mandiri').trim().isEmpty ? 'Kasir Mandiri' : cashierName!.trim(),
      'status': 'open',
      'opened_at': now.toIso8601String(),
      'opening_cash': openingCash,
      'cash_sales': 0.0,
      'cash_in': 0.0,
      'cash_out': 0.0,
      'expected_cash': openingCash,
      'no_sale_opens_count': 0,
      'transactions_count': 0,
      'notes': notes,
      'entries': <Map<String, dynamic>>[],
      'is_local': true,
    };

    shifts.insert(0, newShift);
    await _saveLocalShifts(shifts);
    await _sqlite.upsertShift(newShift);
    return newShift;
  }

  Future<Map<String, dynamic>?> addLocalShiftCashEntry({
    required String type,
    required double amount,
    required String reason,
  }) async {
    final shifts = getLocalShiftsHistory();
    final idx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (idx < 0) return null;

    final shift = Map<String, dynamic>.from(shifts[idx]);
    final entries = (shift['entries'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final entry = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'amount': amount,
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
    };
    entries.insert(0, entry);
    shift['entries'] = entries;

    if (type == 'pay_in') {
      shift['cash_in'] = ((shift['cash_in'] as num?)?.toDouble() ?? 0.0) + amount;
    } else if (type == 'pay_out') {
      shift['cash_out'] = ((shift['cash_out'] as num?)?.toDouble() ?? 0.0) + amount;
    } else if (type == 'drawer_open_no_sale') {
      shift['no_sale_opens_count'] = ((shift['no_sale_opens_count'] as num?)?.toInt() ?? 0) + 1;
    }

    final enriched = _enrichShiftTotals(shift);
    shifts[idx] = enriched;
    await _saveLocalShifts(shifts);
    await _sqlite.upsertShift(enriched);
    return enriched;
  }

  Future<Map<String, dynamic>?> closeLocalShift({
    required double actualClosingCash,
    String? notes,
  }) async {
    final shifts = getLocalShiftsHistory();
    final idx = shifts.indexWhere((s) => (s['status'] ?? '').toString().toLowerCase() == 'open');
    if (idx < 0) return null;

    final enriched = _enrichShiftTotals(shifts[idx]);
    final expected = (enriched['expected_cash'] as num?)?.toDouble() ?? 0.0;
    final variance = actualClosingCash - expected;

    enriched['status'] = 'closed';
    enriched['closed_at'] = DateTime.now().toIso8601String();
    enriched['closing_cash'] = actualClosingCash;
    enriched['variance'] = variance;
    if (notes != null && notes.trim().isNotEmpty) {
      enriched['notes'] = notes.trim();
    }

    shifts[idx] = enriched;
    await _saveLocalShifts(shifts);
    await _sqlite.upsertShift(enriched);
    return enriched;
  }

}
