// ignore_for_file: invalid_use_of_protected_member
part of 'printer_service.dart';

extension PrinterServicePart2Ext on PrinterService {

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
      final rawMods = item['modifiers'] as List<dynamic>? ?? const [];
      if (rawMods.isNotEmpty) {
        final modNames = rawMods
            .map((m) => m is Map ? (m['name'] ?? m['label'] ?? '').toString().trim() : m.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (modNames.isNotEmpty) {
          sb.writeln('  + ${modNames.join(', ')}');
        }
      }
      final cookNote = (item['cooking_notes'] ?? '').toString().trim();
      if (cookNote.isNotEmpty) {
        sb.writeln('  *Masak: $cookNote');
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


  /// Build Kitchen Order Ticket (KOT) text for Restaurant / F&B Mode (supports station header + structured modifiers)
  String formatKitchenOrderTicket({
    required String tableName,
    required String sectionName,
    required int pax,
    required List<Map<String, dynamic>> items,
    String? stationLabel,
  }) {
    const width = 32;
    final sb = StringBuffer();
    final headerTitle = (stationLabel != null && stationLabel.trim().isNotEmpty)
        ? '*** KOT [${stationLabel.trim().toUpperCase()}] ***'
        : '*** TIKET DAPUR (KOT) ***';
    sb.writeln(_center(headerTitle, width));
    sb.writeln(_center('$tableName ($sectionName) • $pax Pax', width));
    sb.writeln('=' * width);
    for (final item in items) {
      final stationTag = (item['kds_station'] ?? '').toString().trim().toUpperCase();
      final prefixStation = (stationLabel == null && stationTag.isNotEmpty) ? '[$stationTag] ' : '';
      sb.writeln('[ ${IdrCurrencyFormatter.formatQty((item['quantity'] as num?) ?? 1)}x ] $prefixStation${item['product_name'] ?? item['name'] ?? '-'}');
      final rawMods = item['modifiers'] as List<dynamic>? ?? const [];
      if (rawMods.isNotEmpty) {
        final modNames = rawMods
            .map((m) => m is Map ? (m['name'] ?? m['label'] ?? '').toString().trim() : m.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (modNames.isNotEmpty) {
          sb.writeln('   + ${modNames.join(', ')}');
        }
      }
      final cookNote = (item['cooking_notes'] ?? '').toString().trim();
      final regNote = (item['notes'] ?? '').toString().trim();
      final combinedNote = cookNote.isNotEmpty ? cookNote : regNote;
      if (combinedNote.isNotEmpty) {
        sb.writeln('   >> CATATAN: $combinedNote');
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
