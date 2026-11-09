import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';

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
    _waPhoneController = TextEditingController(
      text: (customer?['phone'] ?? '081234567890').toString(),
    );
  }

  @override
  void dispose() {
    _waPhoneController.dispose();
    super.dispose();
  }

  void _handleThermalPrint() {
    final storeProfile = widget.offlineDb.getStoreProfile();
    final formatted = widget.printerService.formatThermalReceiptText(
      storeProfile: storeProfile,
      sale: widget.receiptData,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.print_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Struk ESC/POS Thermal (58mm)',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final storeProfile = widget.offlineDb.getStoreProfile();
    final sale = widget.receiptData;
    final items = (sale['items'] as List<dynamic>? ?? []);
    final grandTotal = (sale['grand_total'] as num?) ?? 17000;
    final paid = (sale['paid_total'] as num?) ?? 20000;
    final change = (sale['change_returned'] as num?) ?? 3000;
    final balanceDue = (sale['balance_due'] as num?) ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
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
                    Text(
                      (storeProfile['name'] ?? 'Toko Berkah Jaya').toString(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (storeProfile['address'] ?? 'Jl. Melati No. 12, Jakarta').toString(),
                      style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                    Text(
                      'Telp: ${storeProfile['phone'] ?? '0812 3456 7890'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(),
                    ),
                    ...items.map((raw) {
                      final item = Map<String, dynamic>.from(raw as Map);
                      final qty = (item['quantity'] as num?) ?? 1;
                      final price = (item['unit_price'] as num?) ?? 0;
                      final lineTotal = (item['line_total'] as num?) ?? (qty * price);
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
                    _receiptSummaryRow('Total Tagihan', IdrCurrencyFormatter.format(grandTotal), isBold: true),
                    const SizedBox(height: 6),
                    _receiptSummaryRow(
                      'Metode (${(sale['payment_methods'] as List<dynamic>? ?? ['Tunai']).join(', ')})',
                      IdrCurrencyFormatter.format(paid),
                    ),
                    const SizedBox(height: 6),
                    if (balanceDue > 0)
                      _receiptSummaryRow(
                        'Piutang Buku Bon',
                        IdrCurrencyFormatter.format(balanceDue),
                        valueColor: AppColors.warningDark,
                        isBold: true,
                      )
                    else
                      _receiptSummaryRow(
                        'Kembalian',
                        IdrCurrencyFormatter.format(change),
                        valueColor: AppColors.successDark,
                        isBold: true,
                      ),
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
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _handleThermalPrint,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.print_rounded, color: AppColors.primary),
                      label: const Text(
                        'Cetak Thermal',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _handleSendWhatsApp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      label: const Text(
                        'Kirim Struk WA',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/pos'),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Transaksi Kasir Baru'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptSummaryRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: AppColors.slate700,
          ),
        ),
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
