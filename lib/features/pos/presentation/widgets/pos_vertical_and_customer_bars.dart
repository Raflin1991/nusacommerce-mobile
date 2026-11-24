// ignore_for_file: invalid_use_of_protected_member
part of '../pos_catalog_screen.dart';

extension _PosVerticalAndCustomerBarsExt on _PosCatalogScreenState {
  void _showVerticalMetadataSheet(BuildContext context, PosState state) {
    final caps = state.capabilities;
    final meta = state.verticalMetadata;

    final String title;
    final IconData icon;
    if (caps.hasPrescriptionWorkflow) {
      title = 'Data Resep & Farmasi (Apotek)';
      icon = Icons.medication_outlined;
    } else if (caps.hasVehicleWorkOrder) {
      title = 'Data Kendaraan & PKB (Bengkel)';
      icon = Icons.build_circle_outlined;
    } else if (caps.hasSalonStylistWorkflow) {
      title = 'Penugasan Kapster / Stylist (Salon)';
      icon = Icons.content_cut_rounded;
    } else {
      title = 'Detail Rak & Estimasi Selesai (Laundry)';
      icon = Icons.local_laundry_service_outlined;
    }

    // Workshop controllers
    final nopolCtrl = TextEditingController(text: (meta['nopol'] ?? '').toString());
    final vehicleCtrl = TextEditingController(text: (meta['kendaraan'] ?? meta['vehicle_model'] ?? '').toString());
    final kmCtrl = TextEditingController(text: (meta['kilometer'] ?? meta['km'] ?? '').toString());
    final mechanicCtrl = TextEditingController(text: (meta['mechanic_name'] ?? '').toString());

    // Pharmacy controllers
    final doctorCtrl = TextEditingController(text: (meta['doctor_name'] ?? '').toString());
    final sipCtrl = TextEditingController(text: (meta['doctor_sip'] ?? '').toString());
    final patientCtrl = TextEditingController(text: (meta['patient_name'] ?? '').toString());
    final rxNoCtrl = TextEditingController(text: (meta['prescription_number'] ?? '').toString());

    // Laundry controllers
    final rackCtrl = TextEditingController(text: (meta['rack_number'] ?? '').toString());
    final estReadyCtrl = TextEditingController(text: (meta['estimated_ready_at'] ?? '').toString());

    // Salon controller
    final stylistCtrl = TextEditingController(text: (meta['stylist_name'] ?? '').toString());
    final hasAnyExisting = meta.isNotEmpty || (state.orderNotes?.trim().isNotEmpty ?? false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: NusaThemeTokens.of(ctx).accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (caps.hasVehicleWorkOrder) ...[
                TextField(
                  controller: nopolCtrl,
                  textCapitalization: TextCapitalization.characters,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Polisi (Plat Motor / Mobil) *',
                    hintText: 'Contoh: B 1234 XYZ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: vehicleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Merk / Tipe Kendaraan *',
                    hintText: 'Contoh: Honda PCX 160 / Toyota Avanza',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kmCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Kilometer (KM) Kendaraan',
                    hintText: 'Contoh: 24500',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mechanicCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Mekanik & Keluhan (Opsional)',
                    hintText: 'Contoh: Mekanik Agung • Ganti Oli & Tune Up',
                  ),
                ),
              ] else if (caps.hasPrescriptionWorkflow) ...[
                TextField(
                  controller: doctorCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama Dokter Penulis Resep *',
                    hintText: 'Contoh: dr. Andi Wijaya, Sp.PD',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nomor SIP Dokter *',
                    hintText: 'Contoh: 503/0142/SIP.D/2026',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: patientCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Pasien *',
                    hintText: 'Contoh: Tn. Budi Santoso',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rxNoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Resep / RM (Opsional)',
                    hintText: 'Contoh: RX-2026-0142',
                  ),
                ),
              ] else if (caps.hasSalonStylistWorkflow) ...[
                TextField(
                  controller: stylistCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nama Kapster / Stylist / Terapis',
                    hintText: 'Contoh: Rina (Senior Stylist)',
                  ),
                ),
              ] else ...[
                TextField(
                  controller: rackCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Rak Penyimpanan Cucian *',
                    hintText: 'Contoh: Rak B-04',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: estReadyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Estimasi Selesai Cuci (Tanggal & Jam) *',
                    hintText: 'Contoh: 17 Nov 2026 • 17:00 WIB',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (hasAnyExisting)
                    OutlinedButton(
                      onPressed: () {
                        context.read<PosCubit>().setVerticalMetadata({});
                        Navigator.pop(ctx);
                      },
                      child: const Text('Hapus'),
                    ),
                  if (hasAnyExisting) const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          final cubit = context.read<PosCubit>();
                          if (caps.hasVehicleWorkOrder) {
                            cubit.setVerticalMetadata({
                              'nopol': nopolCtrl.text.trim(),
                              'kendaraan': vehicleCtrl.text.trim(),
                              'kilometer': kmCtrl.text.trim(),
                              'mechanic_name': mechanicCtrl.text.trim(),
                            });
                          } else if (caps.hasPrescriptionWorkflow) {
                            cubit.setVerticalMetadata({
                              'doctor_name': doctorCtrl.text.trim(),
                              'doctor_sip': sipCtrl.text.trim(),
                              'patient_name': patientCtrl.text.trim(),
                              'prescription_number': rxNoCtrl.text.trim(),
                            });
                          } else if (caps.hasSalonStylistWorkflow) {
                            cubit.setVerticalMetadata({
                              'stylist_name': stylistCtrl.text.trim(),
                            });
                          } else {
                            cubit.setVerticalMetadata({
                              'rack_number': rackCtrl.text.trim(),
                              'estimated_ready_at': estReadyCtrl.text.trim(),
                            });
                          }
                          Navigator.pop(ctx);
                        },
                        child: const Text('Simpan Info Order'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalMetadataBar(BuildContext context, PosState state) {
    final caps = state.capabilities;
    final hasNotes = state.orderNotes != null && state.orderNotes!.trim().isNotEmpty;
    final IconData icon;
    final String emptyLabel;
    if (caps.hasPrescriptionWorkflow) {
      icon = Icons.medication_outlined;
      emptyLabel = 'Input Dokter, No. SIP & Pasien (Resep Apotek)';
    } else if (caps.hasVehicleWorkOrder) {
      icon = Icons.directions_car_outlined;
      emptyLabel = 'Input No. Polisi, Kendaraan & KM (Bengkel)';
    } else if (caps.hasSalonStylistWorkflow) {
      icon = Icons.content_cut_rounded;
      emptyLabel = 'Pilih Kapster / Stylist (Tap item utk per-layanan)';
    } else {
      icon = Icons.local_laundry_service_outlined;
      emptyLabel = 'Input Nomor Rak & Estimasi Selesai (Laundry)';
    }

    return InkWell(
      onTap: () => _showVerticalMetadataSheet(context, state),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hasNotes ? NusaThemeTokens.of(context).accentSoft : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasNotes ? NusaThemeTokens.of(context).accent.withOpacity(0.35) : NusaThemeTokens.of(context).borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: hasNotes ? NusaThemeTokens.of(context).accent : NusaThemeTokens.of(context).textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasNotes ? state.orderNotes! : emptyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasNotes ? FontWeight.w700 : FontWeight.w600,
                  color: hasNotes ? NusaThemeTokens.of(context).textPrimary : NusaThemeTokens.of(context).textSecondary,
                ),
              ),
            ),
            Icon(
              hasNotes ? Icons.edit_outlined : Icons.add_circle_outline_rounded,
              size: 16,
              color: NusaThemeTokens.of(context).accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerStatusBar(BuildContext context, PosState state) {
    final tokens = NusaThemeTokens.of(context);
    final cust = state.selectedCustomer;
    if (cust == null) {
      return Material(
        color: tokens.bgElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _showCustomerSelectorSheet(context, state),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
            ),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 16, color: tokens.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pelanggan Umum',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.textPrimary),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: tokens.textSecondary),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: tokens.borderSubtle,
                ),
                Tooltip(
                  message: 'Member Baru',
                  child: InkWell(
                    onTap: () => _showQuickAddCustomerModal(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.person_add_alt_1_outlined, size: 16, color: tokens.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final groupName = cust['group_name']?.toString() ?? 'Member';
    final discPct = (cust['default_discount_percent'] as num?)?.toDouble() ?? 0;
    final pts = (cust['loyalty_points'] as num?)?.toInt() ?? 0;

    return Material(
      color: tokens.accentSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _showCustomerSelectorSheet(context, state),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.35), width: tokens.borderWidth),
          ),
          child: Row(
            children: [
              Icon(Icons.workspace_premium_rounded, size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  discPct > 0
                      ? '${cust['name']} (-${discPct.toInt()}%)'
                      : '${cust['name']} ($groupName)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tokens.textPrimary),
                ),
              ),
              if (pts > 0) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _showRedeemPointsDialog(context, state),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: state.redeemedLoyaltyPoints > 0 ? tokens.positive : tokens.warningSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      state.redeemedLoyaltyPoints > 0
                          ? '-${state.redeemedLoyaltyPoints}p'
                          : '${pts}p',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: state.redeemedLoyaltyPoints > 0 ? Colors.white : tokens.warning,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              InkWell(
                onTap: () => context.read<PosCubit>().selectCustomer(null),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 15, color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
