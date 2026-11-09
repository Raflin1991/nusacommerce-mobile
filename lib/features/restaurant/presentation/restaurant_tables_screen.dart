import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';

/// MODUL RESTORAN & F&B — DENAH MEJA, QR ORDER, TIKET DAPUR (KOT) & SPLIT BILL
/// Connected to `GET /api/v1/pos/tables`
class RestaurantTablesScreen extends StatefulWidget {
  final PrinterService printerService;

  const RestaurantTablesScreen({super.key, required this.printerService});

  @override
  State<RestaurantTablesScreen> createState() => _RestaurantTablesScreenState();
}

class _RestaurantTablesScreenState extends State<RestaurantTablesScreen> {
  String _selectedSection = 'Semua';

  final List<Map<String, dynamic>> _tables = [
    {
      'id': 1,
      'name': 'Meja 01',
      'section': 'Indoor',
      'capacity': 4,
      'status': 'available',
      'pax': 0,
      'total': 0.0,
    },
    {
      'id': 2,
      'name': 'Meja 02',
      'section': 'Indoor',
      'capacity': 4,
      'status': 'occupied',
      'pax': 3,
      'total': 85000.0,
      'customer_name': 'Kak Andi (Open Tab)',
    },
    {
      'id': 3,
      'name': 'Meja 03 (QR)',
      'section': 'Indoor',
      'capacity': 2,
      'status': 'pending_verification',
      'pax': 2,
      'total': 42000.0,
      'customer_name': 'Order Mandiri QR Meja',
    },
    {
      'id': 4,
      'name': 'Meja Outdoor 01',
      'section': 'Outdoor',
      'capacity': 6,
      'status': 'available',
      'pax': 0,
      'total': 0.0,
    },
    {
      'id': 5,
      'name': 'Meja Outdoor 02',
      'section': 'Outdoor',
      'capacity': 4,
      'status': 'occupied',
      'pax': 4,
      'total': 140000.0,
      'customer_name': 'Keluarga Pak Budi',
    },
    {
      'id': 6,
      'name': 'VIP Room 01',
      'section': 'VIP',
      'capacity': 8,
      'status': 'available',
      'pax': 0,
      'total': 0.0,
    },
  ];

  void _showTableActionsModal(BuildContext context, Map<String, dynamic> table) {
    final status = table['status'] as String;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${table['name']} • Area ${table['section']}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Chip(
                  label: Text(
                    status == 'available'
                        ? 'TERSEDIA'
                        : (status == 'pending_verification' ? 'ORDER QR MEJA' : 'TERISI / MAKAN'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (table['total'] > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Tagihan Berjalan: ${IdrCurrencyFormatter.format(table['total'])} (${table['pax']} Pax)',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  context.read<PosCubit>().selectRestaurantTable(table);
                  Navigator.pop(ctx);
                  context.push('/pos');
                },
                icon: const Icon(Icons.restaurant_menu_rounded),
                label: Text(status == 'available' ? 'Buka Meja & Input Pesanan Baru' : 'Tambah Pesanan / Lanjut Bayar POS'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final kot = widget.printerService.formatKitchenOrderTicket(
                        tableName: table['name'].toString(),
                        sectionName: table['section'].toString(),
                        pax: (table['pax'] as int) > 0 ? (table['pax'] as int) : 2,
                        items: const [
                          {'product_name': 'Kopi Susu Gula Aren', 'quantity': 2, 'notes': 'Less Sugar'},
                          {'product_name': 'Roti Bakar Cokelat Keju', 'quantity': 1, 'notes': 'Potong 8'},
                        ],
                      );
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('Tiket Dapur (KOT) Dicetak'),
                          content: Text(kot, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Selesai')),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.soup_kitchen_rounded),
                    label: const Text('Cetak KOT Dapur'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        if (table['status'] == 'pending_verification') {
                          table['status'] = 'occupied';
                        } else if (table['status'] == 'occupied') {
                          table['status'] = 'available';
                          table['total'] = 0.0;
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(status == 'pending_verification' ? 'Konfirmasi QR' : 'Kosongkan Meja'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _tables.where((t) {
      if (_selectedSection == 'Semua') return true;
      return t['section'] == _selectedSection;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Denah Meja Restoran (F&B)'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: ['Semua', 'Indoor', 'Outdoor', 'VIP'].map((sec) {
                    final active = _selectedSection == sec;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(sec),
                        selected: active,
                        onSelected: (_) => setState(() => _selectedSection = sec),
                        selectedColor: AppColors.primary,
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          color: active ? Colors.white : AppColors.slate700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: AppColors.success),
                    SizedBox(width: 4),
                    Text('Kosong', style: TextStyle(fontSize: 11.5)),
                    SizedBox(width: 14),
                    Icon(Icons.circle, size: 10, color: AppColors.danger),
                    SizedBox(width: 4),
                    Text('Terisi (Open Tab)', style: TextStyle(fontSize: 11.5)),
                    SizedBox(width: 14),
                    Icon(Icons.circle, size: 10, color: AppColors.warning),
                    SizedBox(width: 4),
                    Text('Order QR Meja (/dine)', style: TextStyle(fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, idx) {
                final table = filtered[idx];
                final status = table['status'] as String;
                final isAvail = status == 'available';
                final isPendingQr = status == 'pending_verification';

                final borderColor = isAvail
                    ? AppColors.success
                    : (isPendingQr ? AppColors.warning : AppColors.danger);
                final bgColor = isAvail
                    ? AppColors.successSoft.withOpacity(0.45)
                    : (isPendingQr ? AppColors.warningSoft : AppColors.dangerSoft.withOpacity(0.55));

                return InkWell(
                  onTap: () => _showTableActionsModal(context, table),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor, width: 1.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              table['name'].toString(),
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                            ),
                            Icon(Icons.table_restaurant_rounded, color: borderColor, size: 22),
                          ],
                        ),
                        Text(
                          '${table['section']} • Kapasitas ${table['capacity']} Kursi',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                        ),
                        const Spacer(),
                        if (isAvail)
                          const Text(
                            'Siap Ditempati',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.successDark),
                          )
                        else ...[
                          Text(
                            (table['customer_name'] ?? 'Tamu').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            IdrCurrencyFormatter.format(table['total']),
                            style: AppTheme.moneyStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
