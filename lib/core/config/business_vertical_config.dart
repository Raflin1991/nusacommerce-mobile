/// Modular Business Vertical Engine (Capability-Driven Multi-Industry POS Architecture).
///
/// Menjadi sumber kebenaran tunggal untuk menentukan kapabilitas UI dan alur kerja
/// tiap vertikal industri tanpa perlu menaruh if-else bisnis yang tersebar di widget.
enum BusinessVertical {
  retail,
  restaurant,
  pharmacy,
  workshop,
  laundry,
  salon,
}

extension BusinessVerticalX on BusinessVertical {
  String get key {
    switch (this) {
      case BusinessVertical.retail:
        return 'retail';
      case BusinessVertical.restaurant:
        return 'restaurant';
      case BusinessVertical.pharmacy:
        return 'pharmacy';
      case BusinessVertical.workshop:
        return 'workshop';
      case BusinessVertical.laundry:
        return 'laundry';
      case BusinessVertical.salon:
        return 'salon';
    }
  }

  String get label {
    switch (this) {
      case BusinessVertical.retail:
        return 'Toko Retail & Grosir';
      case BusinessVertical.restaurant:
        return 'Restoran & Kafe (F&B)';
      case BusinessVertical.pharmacy:
        return 'Apotek & Farmasi';
      case BusinessVertical.workshop:
        return 'Bengkel & Servis Otomotif';
      case BusinessVertical.laundry:
        return 'Laundry Kiloan & Satuan';
      case BusinessVertical.salon:
        return 'Salon, Barbershop & Spa';
    }
  }

  String get shortDescription {
    switch (this) {
      case BusinessVertical.retail:
        return 'Minimarket, kelontong, fashion, elektronik & grosir multi-satuan';
      case BusinessVertical.restaurant:
        return 'Manajemen denah meja, pax, pesanan Dine-In/Takeaway & tiket dapur (KOT)';
      case BusinessVertical.pharmacy:
        return 'Resep dokter, obat keras, batch FEFO & nomor izin BPOM';
      case BusinessVertical.workshop:
        return 'PKB/SPK nomor polisi kendaraan, jasa montir & suku cadang';
      case BusinessVertical.laundry:
        return 'Timbangan cucian kiloan, satuan & pelacakan status rak';
      case BusinessVertical.salon:
        return 'Penjadwalan layanan kecantikan & penugasan kapster/stylist per item';
    }
  }

  bool get isAvailable => true;
}

class VerticalCapabilities {
  final bool hasTableManagement; // Denah Meja & Pax (Khusus Resto)
  final bool hasKitchenOrderTicket; // Tiket Dapur / KOT (Khusus Resto)
  final bool hasDineInTakeawayOrderType; // Tipe Pesanan Dine-In vs Takeaway (Khusus Resto)
  final bool hasBarcodeScannerFastMode; // Barcode Scan Super Cepat (Retail, Apotek)
  final bool hasWholesaleMultiUnit; // Multi Satuan Dus/Lusin/Pcs (Retail)
  final bool hasPrescriptionWorkflow; // Alur Resep Obat (Apotek)
  final bool hasVehicleWorkOrder; // PKB / SPK Kendaraan & Jasa (Bengkel)
  final bool hasLaundryOrderMetadata; // Timbangan Kiloan & Rak Cucian (Laundry)
  final bool hasSalonStylistWorkflow; // Pemilihan Kapster / Stylist / Terapis per Layanan (Salon)
  final String posDisplayName; // "Kasir POS Retail", "Kasir Resto & Kafe", dst.
  final String posSubtitle;

  const VerticalCapabilities({
    required this.hasTableManagement,
    required this.hasKitchenOrderTicket,
    required this.hasDineInTakeawayOrderType,
    required this.hasBarcodeScannerFastMode,
    required this.hasWholesaleMultiUnit,
    required this.hasPrescriptionWorkflow,
    required this.hasVehicleWorkOrder,
    this.hasLaundryOrderMetadata = false,
    this.hasSalonStylistWorkflow = false,
    required this.posDisplayName,
    required this.posSubtitle,
  });
}

class VerticalConfig {
  VerticalConfig._();

  static const VerticalCapabilities _retailCapabilities = VerticalCapabilities(
    hasTableManagement: false,
    hasKitchenOrderTicket: false,
    hasDineInTakeawayOrderType: false,
    hasBarcodeScannerFastMode: true,
    hasWholesaleMultiUnit: true,
    hasPrescriptionWorkflow: false,
    hasVehicleWorkOrder: false,
    posDisplayName: 'Kasir POS Retail',
    posSubtitle: 'Scan barcode, timbangan & pembayaran cepat',
  );

  static const VerticalCapabilities _restaurantCapabilities = VerticalCapabilities(
    hasTableManagement: true,
    hasKitchenOrderTicket: true,
    hasDineInTakeawayOrderType: true,
    hasBarcodeScannerFastMode: false,
    hasWholesaleMultiUnit: false,
    hasPrescriptionWorkflow: false,
    hasVehicleWorkOrder: false,
    posDisplayName: 'Kasir Resto & Kafe',
    posSubtitle: 'Denah meja, pesanan dapur & split bill',
  );

  static const VerticalCapabilities _pharmacyCapabilities = VerticalCapabilities(
    hasTableManagement: false,
    hasKitchenOrderTicket: false,
    hasDineInTakeawayOrderType: false,
    hasBarcodeScannerFastMode: true,
    hasWholesaleMultiUnit: true,
    hasPrescriptionWorkflow: true,
    hasVehicleWorkOrder: false,
    posDisplayName: 'Kasir POS Apotek',
    posSubtitle: 'Obat resep dokter, batch FEFO & izin BPOM',
  );

  static const VerticalCapabilities _workshopCapabilities = VerticalCapabilities(
    hasTableManagement: false,
    hasKitchenOrderTicket: false,
    hasDineInTakeawayOrderType: false,
    hasBarcodeScannerFastMode: true,
    hasWholesaleMultiUnit: false,
    hasPrescriptionWorkflow: false,
    hasVehicleWorkOrder: true,
    posDisplayName: 'Kasir POS Bengkel',
    posSubtitle: 'PKB nomor polisi kendaraan, jasa & sparepart',
  );

  static const VerticalCapabilities _laundryCapabilities = VerticalCapabilities(
    hasTableManagement: false,
    hasKitchenOrderTicket: false,
    hasDineInTakeawayOrderType: false,
    hasBarcodeScannerFastMode: true,
    hasWholesaleMultiUnit: false,
    hasPrescriptionWorkflow: false,
    hasVehicleWorkOrder: false,
    hasLaundryOrderMetadata: true,
    posDisplayName: 'Kasir POS Laundry',
    posSubtitle: 'Order kiloan, satuan & status rak cucian',
  );

  static const VerticalCapabilities _salonCapabilities = VerticalCapabilities(
    hasTableManagement: false,
    hasKitchenOrderTicket: false,
    hasDineInTakeawayOrderType: false,
    hasBarcodeScannerFastMode: false,
    hasWholesaleMultiUnit: false,
    hasPrescriptionWorkflow: false,
    hasVehicleWorkOrder: false,
    hasSalonStylistWorkflow: true,
    posDisplayName: 'Kasir POS Salon & Spa',
    posSubtitle: 'Layanan treatment & assignment kapster/stylist per item',
  );

  static BusinessVertical parse(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v == 'restaurant' ||
        v == 'resto' ||
        v == 'fnb' ||
        v == 'f&b' ||
        v == 'cafe' ||
        v == 'kafe') {
      return BusinessVertical.restaurant;
    }
    if (v == 'pharmacy' || v == 'apotek') {
      return BusinessVertical.pharmacy;
    }
    if (v == 'workshop' || v == 'bengkel') {
      return BusinessVertical.workshop;
    }
    if (v == 'laundry') {
      return BusinessVertical.laundry;
    }
    if (v == 'salon' || v == 'barber' || v == 'barbershop' || v == 'spa') {
      return BusinessVertical.salon;
    }
    return BusinessVertical.retail;
  }

  static VerticalCapabilities getCapabilities(BusinessVertical vertical) {
    switch (vertical) {
      case BusinessVertical.retail:
        return _retailCapabilities;
      case BusinessVertical.restaurant:
        return _restaurantCapabilities;
      case BusinessVertical.pharmacy:
        return _pharmacyCapabilities;
      case BusinessVertical.workshop:
        return _workshopCapabilities;
      case BusinessVertical.laundry:
        return _laundryCapabilities;
      case BusinessVertical.salon:
        return _salonCapabilities;
    }
  }
}
