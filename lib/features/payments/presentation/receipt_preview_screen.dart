import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';

/// LAYAR 5 / 10 — PRATINJAU STRUK THERMAL & WHATSAPP DISPATCHER
class ReceiptPreviewScreen extends StatefulWidget {
  final Map<String, dynamic> receiptData;
  final OfflineDatabase offlineDb;
  final PrinterService printerService;

  const ReceiptPreviewScreen({
    super.key,
    required this.receiptData,
    required this.offlineDb,
    required this.printerService,
  });

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  late final TextEditingController _waPhoneController;

  @override
  void initState() {
    super.initState();
    final customer = widget.receiptData['customer'] as Map<String, dynamic>?;
    final rawPhone = (customer?['phone'] ?? '').toString().trim();
    _waPhoneController = TextEditingController(
      text: rawPhone == '-' ? '' : rawPhone,
    );
  }

  @override
  void dispose() {
    _waPhoneController.dispose();
    super.dispose();
  }

  bool _isPrinting = false;

  bool get _isReprint => widget.receiptData['is_reprint'] == true;
  int get _reprintCount => (widget.receiptData['reprint_count'] as num?)?.toInt() ?? 1;

  bool get _shouldOpenCashDrawer {
    final balanceDue = (widget.receiptData['balance_due'] as num?)?.toDouble() ?? 0;
    final paidTotal = (widget.receiptData['paid_total'] as num?)?.toDouble() ?? 0;
    final isKasbonZeroDp = balanceDue > 0 && paidTotal <= 0;
    return PrinterService.shouldKickCashDrawer(
      payments: widget.receiptData['payments'] as List<dynamic>?,
      paymentMethods: widget.receiptData['payment_methods'] as List<dynamic>? ??
          [widget.receiptData['payment_method'] ?? 'Tunai'],
      isKasbonZeroDp: isKasbonZeroDp,
      isReprint: _isReprint,
    );
  }

  Future<void> _handleThermalPrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final storeProfile = widget.offlineDb.getStoreProfile();
      final selectedWidth = widget.printerService.paperWidth;
      final formatted = widget.printerService.formatThermalReceiptText(
        storeProfile: storeProfile,
        sale: widget.receiptData,
        paperWidthOverride: selectedWidth,
        isReprint: _isReprint,
        reprintCount: _reprintCount,
      );

      final bytes = widget.printerService.buildEscPosBytesFromText(
        formatted,
        cutPaper: widget.printerService.autoCutPaper,
        openCashDrawer: widget.printerService.autoOpenCashDrawer && _shouldOpenCashDrawer,
      );

      final printed = await widget.printerService.printBytes(bytes);
      if (!mounted) return;

      if (printed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.successDark,
            content: Text(
              'Struk berhasil dicetak ke ${widget.printerService.activePrinterLabel} ($selectedWidth)!',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warningDark,
          content: Text(
            'Printer (${widget.printerService.activePrinterLabel}) belum tersambung. Menampilkan pratinjau ESC/POS ($selectedWidth).',
          ),
        ),
      );
      _showEscPosPreviewDialog(storeProfile, selectedWidth);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Gagal mencetak struk: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _showEscPosPreviewDialog(Map<String, dynamic> storeProfile, String initialWidth) {
    String selectedWidth = initialWidth;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final formatted = widget.printerService.formatThermalReceiptText(
            storeProfile: storeProfile,
            sale: widget.receiptData,
            paperWidthOverride: selectedWidth,
            isReprint: _isReprint,
            reprintCount: _reprintCount,
          );
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.print_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Struk ESC/POS Thermal ($selectedWidth)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NusaPillFilter(
                        label: '58mm',
                        selected: selectedWidth == '58mm',
                        onTap: () => setModalState(() {
                          selectedWidth = '58mm';
                          widget.printerService.savePreferences(width: '58mm');
                        }),
                      ),
                      const SizedBox(width: 8),
                      NusaPillFilter(
                        label: '80mm',
                        selected: selectedWidth == '80mm',
                        onTap: () => setModalState(() {
                          selectedWidth = '80mm';
                          widget.printerService.savePreferences(width: '80mm');
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      formatted,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final ok = await widget.printerService.kickCashDrawer();
                  final kick = widget.printerService.buildCashDrawerKickBytes();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: ok ? AppColors.successDark : null,
                      content: Text(
                        ok
                            ? 'Laci kasir RJ-11 berhasil dibuka via Bluetooth!'
                            : 'Perintah Pulse RJ-11 siap (${kick.map((b) => '0x${b.toRadixString(16)}').join(' ')}) — sambungkan printer terlebih dahulu.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.point_of_sale_rounded, size: 17),
                label: const Text('Buka Laci'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ok = await widget.printerService.printReceiptText(formatted);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
                      content: Text(
                        ok
                            ? 'Byte ESC/POS ($selectedWidth) dikirim ke printer!'
                            : 'Printer Bluetooth tidak terhubung. Cek Pengaturan > Printer.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.print_rounded, size: 17),
                label: const Text('Cetak Bluetooth'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleSendWhatsApp() async {
    final storeProfile = widget.offlineDb.getStoreProfile();
    await WhatsAppService.sendDigitalReceipt(
      customerPhone: _waPhoneController.text,
      storeProfile: storeProfile,
      sale: widget.receiptData,
    );
  }

  Future<void> _handleCopyDigitalReceipt() async {
    final storeProfile = widget.offlineDb.getStoreProfile();
    final formatted = widget.printerService.formatThermalReceiptText(
      storeProfile: storeProfile,
      sale: widget.receiptData,
      paperWidthOverride: widget.printerService.paperWidth,
      isReprint: _isReprint,
      reprintCount: _reprintCount,
    );
    await Clipboard.setData(ClipboardData(text: formatted));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.successDark,
        content: Text('Teks struk digital berhasil disalin ke clipboard.'),
      ),
    );
  }

  Future<void> _handlePrintKot() async {
    try {
      final rawItems = (widget.receiptData['items'] as List<dynamic>? ?? []);
      final kotItems = rawItems
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final tableName =
          (widget.receiptData['table_name'] ?? 'Meja Umum').toString();
      final pax = (widget.receiptData['pax'] as num?)?.toInt() ?? 1;
      final kotText = widget.printerService.formatKitchenOrderTicket(
        tableName: tableName,
        sectionName: 'Resto',
        pax: pax,
        items: kotItems,
      );

      final printed = await widget.printerService.printReceiptText(
        kotText,
        openCashDrawer: false,
      );
      if (!mounted) return;
      if (printed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.successDark,
            content: Text('Tiket Dapur (KOT) berhasil dikirim ke printer!'),
          ),
        );
        return;
      }

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pratinjau Tiket Dapur (KOT)'),
          content: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                kotText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text('Gagal mencetak KOT: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context.watch<PosCubit>().state.capabilities;
    final storeProfile = widget.offlineDb.getStoreProfile();
    final sale = widget.receiptData;
    final items = (sale['items'] as List<dynamic>? ?? []);
    final grandTotal = (sale['grand_total'] as num?) ?? 0;
    final serviceCharge = (sale['service_charge_amount'] as num?) ?? 0;
    final storeCreditAmount = (sale['store_credit_amount'] as num?) ?? 0;
    final paid = (sale['paid_total'] as num?) ?? grandTotal;
    final change = (sale['change_returned'] as num?) ?? 0;
    final balanceDue = (sale['balance_due'] as num?) ?? 0;
    final dueDate = sale['due_date']?.toString();

    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Struk Transaksi'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 1. Success Checkmark Badge
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 44),
              ),
              const SizedBox(height: 10),
              const Text(
                'Transaksi Berhasil!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
              const SizedBox(height: 4),
              Text(
                'Nomor Nota: ${sale['number']} • ${sale['sale_datetime']}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.slate500, fontWeight: FontWeight.w600),
              ),
              if (sale['notes'] != null && sale['notes'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                  ),
                  child: Text(
                    sale['notes'].toString().trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // 2. Realistic Thermal Paper Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Column(
                  children: [
                    if (_isReprint) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warningDark.withOpacity(0.4)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '*** SALINAN / REPRINT KE-$_reprintCount ***',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: AppColors.warningDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Kasir: ${sale['cashier_name'] ?? sale['cashier'] ?? 'Kasir POS'}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warningDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text(
                      (storeProfile['name'] ?? 'OXO.ID POS').toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (storeProfile['address'] ?? '-').toString(),
                      style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                    Text(
                      'Telp: ${storeProfile['phone'] ?? '-'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                    if (sale['vertical_metadata'] is Map &&
                        (sale['vertical_metadata'] as Map).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (((sale['vertical_metadata'] as Map)['nopol'] ?? '').toString().isNotEmpty)
                              Text(
                                'No. Polisi: ${(sale['vertical_metadata'] as Map)['nopol']} • ${(sale['vertical_metadata'] as Map)['kendaraan'] ?? ''} • KM ${(sale['vertical_metadata'] as Map)['kilometer'] ?? '-'}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            if (((sale['vertical_metadata'] as Map)['doctor_name'] ?? '').toString().isNotEmpty)
                              Text(
                                'Dokter: ${(sale['vertical_metadata'] as Map)['doctor_name']} (SIP: ${(sale['vertical_metadata'] as Map)['doctor_sip'] ?? '-'}) • Pasien: ${(sale['vertical_metadata'] as Map)['patient_name'] ?? '-'}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            if (((sale['vertical_metadata'] as Map)['rack_number'] ?? '').toString().isNotEmpty ||
                                ((sale['vertical_metadata'] as Map)['estimated_ready_at'] ?? '').toString().isNotEmpty)
                              Text(
                                'Rak: ${(sale['vertical_metadata'] as Map)['rack_number'] ?? '-'} • Estimasi Selesai: ${(sale['vertical_metadata'] as Map)['estimated_ready_at'] ?? '-'}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(),
                    ),
                    ...items.map((raw) {
                      final item = Map<String, dynamic>.from(raw as Map);
                      final qty = (item['quantity'] as num?) ?? 1;
                      final price = (item['unit_price'] as num?) ?? 0;
                      final lineTotal = (item['line_total'] as num?) ?? (qty * price);
                      final batchNo = (item['batch_number'] ?? '').toString().trim();
                      final expiryDate = (item['expiry_date'] ?? '').toString().trim();
                      final stylist = (item['stylist_name'] ?? '').toString().trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['product_name'].toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                  Text(
                                    '${IdrCurrencyFormatter.formatQty(qty)} × ${IdrCurrencyFormatter.format(price)}',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
                                  ),
                                  if (batchNo.isNotEmpty || expiryDate.isNotEmpty)
                                    Text(
                                      'Batch: ${batchNo.isEmpty ? '-' : batchNo} • ED: ${expiryDate.isEmpty ? '-' : expiryDate}',
                                      style: const TextStyle(fontSize: 10.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                                    ),
                                  if (stylist.isNotEmpty)
                                    Text(
                                      'Kapster/Terapis: $stylist',
                                      style: const TextStyle(fontSize: 10.5, color: AppColors.slate600, fontWeight: FontWeight.w600),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              IdrCurrencyFormatter.format(lineTotal),
                              style: AppTheme.moneyStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(),
                    ),
                    if (serviceCharge > 0) ...[
                      _receiptSummaryRow('Service Charge', IdrCurrencyFormatter.format(serviceCharge)),
                      const SizedBox(height: 6),
                    ],
                    _receiptSummaryRow('Total Tagihan', IdrCurrencyFormatter.format(grandTotal), isBold: true),
                    const SizedBox(height: 6),
                    if (storeCreditAmount > 0) ...[
                      _receiptSummaryRow(
                        'Potong Saldo Deposit',
                        IdrCurrencyFormatter.format(storeCreditAmount),
                        valueColor: AppColors.primary,
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (balanceDue > 0) ...[
                      _receiptSummaryRow(
                        'Uang Muka (DP)',
                        IdrCurrencyFormatter.format(paid),
                        valueColor: AppColors.successDark,
                      ),
                      const SizedBox(height: 6),
                      _receiptSummaryRow(
                        'Sisa Tagihan (Kasbon)',
                        IdrCurrencyFormatter.format(balanceDue),
                        valueColor: AppColors.warningDark,
                        isBold: true,
                      ),
                      if (dueDate != null && dueDate.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _receiptSummaryRow(
                          'Jatuh Tempo',
                          dueDate.trim(),
                          valueColor: AppColors.slate600,
                        ),
                      ],
                    ] else ...[
                      _receiptSummaryRow(
                        'Metode (${(sale['payment_methods'] as List<dynamic>? ?? ['Tunai']).join(', ')})',
                        IdrCurrencyFormatter.format(paid),
                      ),
                      const SizedBox(height: 6),
                      _receiptSummaryRow(
                        'Kembalian',
                        IdrCurrencyFormatter.format(change),
                        valueColor: AppColors.successDark,
                        isBold: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 3. WhatsApp Customer Phone Input + 1-Click Send
              TextField(
                controller: _waPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Nomor WhatsApp Pelanggan',
                  prefixIcon: Icon(Icons.chat_bubble_outline_rounded, color: AppColors.whatsapp),
                ),
              ),
              const SizedBox(height: 10),
              // Active Printer Channel Indicator + Copy Digital Receipt
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: NusaThemeTokens.of(context).bgElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.printerService.isWifiMode
                                ? Icons.wifi_rounded
                                : Icons.bluetooth_connected_rounded,
                            size: 16,
                            color: NusaThemeTokens.of(context).accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.printerService.activePrinterLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: NusaThemeTokens.of(context).textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _handleCopyDigitalReceipt,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Salin Struk', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: NusaButton(
                      label: _isPrinting ? 'Mencetak...' : 'Cetak Struk',
                      icon: Icons.print_rounded,
                      variant: NusaButtonVariant.outline,
                      isLoading: _isPrinting,
                      onPressed: _isPrinting ? null : _handleThermalPrint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NusaButton(
                      label: 'Kirim Struk WA',
                      icon: Icons.send_rounded,
                      variant: NusaButtonVariant.success,
                      onPressed: _handleSendWhatsApp,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: NusaButton(
                      label: 'Buka Laci Kasir',
                      icon: Icons.point_of_sale_rounded,
                      variant: NusaButtonVariant.outline,
                      onPressed: () async {
                        final ok = await widget.printerService.kickCashDrawer();
                        final kick = widget.printerService.buildCashDrawerKickBytes();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: ok ? AppColors.successDark : AppColors.warningDark,
                            content: Text(
                              ok
                                  ? 'Laci kasir RJ-11 berhasil dibuka (${kick.length} bytes)!'
                                  : 'Pulse RJ-11 gagal: hubungkan printer Bluetooth di Pengaturan.',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NusaButton(
                      label: 'Transaksi Baru',
                      icon: Icons.add_shopping_cart_rounded,
                      onPressed: () => context.go('/pos'),
                    ),
                  ),
                ],
              ),
              if (capabilities.hasKitchenOrderTicket) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: NusaButton(
                    label: 'Cetak Tiket Dapur (KOT)',
                    icon: Icons.restaurant_menu_rounded,
                    variant: NusaButtonVariant.outline,
                    onPressed: _handlePrintKot,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptSummaryRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.slate700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: AppTheme.moneyStyle(
            fontSize: isBold ? 15.5 : 13.5,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: valueColor ?? AppColors.navyDark,
          ),
        ),
      ],
    );
  }
}
