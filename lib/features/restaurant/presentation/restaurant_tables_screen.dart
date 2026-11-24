import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../pos/bloc/pos_cubit.dart';

/// MODUL RESTORAN & F&B — DENAH MEJA (Live API Bound — `PRD-07`)
class RestaurantTablesScreen extends StatefulWidget {
  final PrinterService printerService;

  const RestaurantTablesScreen({super.key, required this.printerService});

  @override
  State<RestaurantTablesScreen> createState() => _RestaurantTablesScreenState();
}

class _RestaurantTablesScreenState extends State<RestaurantTablesScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();

  String _selectedSection = 'Semua';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tables = [];

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.dio.get(ApiEndpoints.restaurantTables);
      final raw = (res.data['data'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _tables = raw;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiClient.extractErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _openOrSelectTable(Map<String, dynamic> table) async {
    final tableId = (table['id'] as num).toInt();
    final status = (table['status'] ?? 'available').toString();

    if (status == 'available') {
      try {
        await _api.dio.post(
          ApiEndpoints.openTable(tableId),
          data: {'pax': (table['capacity'] as num?)?.toInt() ?? 2},
        );
        await _loadTables();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.extractErrorMessage(e))),
        );
        return;
      }
    }

    if (!mounted) return;
    context.read<PosCubit>().selectRestaurantTable(table);
    context.push('/pos');
  }

  Future<void> _showTransferDialog(Map<String, dynamic> sourceTable) async {
    final sourceId = (sourceTable['id'] as num).toInt();
    final availableTables = _tables.where((t) => (t['status'] ?? '') == 'available').toList();
    if (availableTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada meja kosong tersedia untuk pindahan.')),
      );
      return;
    }

    int? destId = (availableTables.first['id'] as num).toInt();
    String? modalError;
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setModalState) {
          final tokens = NusaThemeTokens.of(dCtx);
          return AlertDialog(
            title: Text('Pindah ${sourceTable['name']} ke Meja:'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  value: destId,
                  isExpanded: true,
                  items: availableTables
                      .map((t) => DropdownMenuItem<int>(
                            value: (t['id'] as num).toInt(),
                            child: Text(
                              '${t['name']} (${t['section'] ?? 'Indoor'})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setModalState(() => destId = v),
                ),
                if (modalError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tokens.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.danger),
                    ),
                    child: Text(
                      modalError!,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tokens.danger),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (destId == null) return;
                        setModalState(() {
                          submitting = true;
                          modalError = null;
                        });
                        try {
                          await _api.dio.post(
                            ApiEndpoints.transferTable(sourceId),
                            data: {'destination_table_id': destId},
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadTables();
                        } catch (e) {
                          setModalState(() {
                            submitting = false;
                            modalError = ApiClient.extractErrorMessage(e);
                          });
                        }
                      },
                child: Text(submitting ? 'Memindahkan...' : 'Pindahkan'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTableActionsModal(BuildContext context, Map<String, dynamic> table) {
    final status = (table['status'] ?? 'available').toString();
    final activeOrder = (table['active_sale'] ?? table['active_order']) as Map?;
    final total = (activeOrder?['grand_total'] as num?)?.toDouble() ?? 0.0;
    final customerName = activeOrder?['customer_name']?.toString();
    final pax = (activeOrder?['pax'] as num?)?.toInt() ?? 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${table['name']} • Area ${table['section'] ?? 'Indoor'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                Chip(
                  label: Text(
                    status == 'available' ? 'TERSEDIA' : status.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (activeOrder != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${activeOrder['number'] ?? 'Open Tab'} • Tagihan: ${IdrCurrencyFormatter.format(total)}${customerName != null ? ' • $customerName' : ''}',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(ctx).accent),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openOrSelectTable(table);
                },
                icon: const Icon(Icons.restaurant_menu_rounded),
                label: Text(status == 'available' ? 'Buka Meja & Input Pesanan Baru' : 'Tambah Pesanan / Lanjut Bayar POS'),
              ),
            ),
            if (status != 'available') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final rawItems = (activeOrder?['items'] as List?) ?? [];
                    final cartItems = context.read<PosCubit>().state.cart;
                    final kotItems = rawItems.isNotEmpty
                        ? rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                        : cartItems
                            .map((c) => {
                                  'product_name': c.displayName,
                                  'quantity': c.quantity,
                                  'notes': c.notes,
                                })
                            .toList();
                    final kotText = widget.printerService.formatKitchenOrderTicket(
                      tableName: table['name'].toString(),
                      sectionName: (table['section'] ?? 'Indoor').toString(),
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
                        SnackBar(
                          backgroundColor: NusaThemeTokens.of(ctx).positive,
                          content: Text('Tiket Dapur (KOT) ${table['name']} dicetak ke printer!'),
                        ),
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: const Text('Tiket Dapur (KOT Thermal)', style: TextStyle(fontWeight: FontWeight.w800)),
                        content: SingleChildScrollView(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: NusaThemeTokens.of(dCtx).borderSubtle),
                            ),
                            child: Text(kotText, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                          ),
                        ),
                        actions: [
                          TextButton.icon(
                            onPressed: () async {
                              final ok = await widget.printerService.printReceiptText(
                                kotText,
                                openCashDrawer: false,
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: ok ? NusaThemeTokens.of(dCtx).positive : NusaThemeTokens.of(dCtx).warning,
                                  content: Text(
                                    ok
                                        ? 'Tiket Dapur (KOT) dikirim ke printer Bluetooth!'
                                        : 'Printer Bluetooth tidak terhubung. Cek Pengaturan > Printer.',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.print_rounded, size: 17),
                            label: const Text('Cetak ke Printer'),
                          ),
                          ElevatedButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Tutup')),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('Cetak Tiket Dapur (KOT)'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showTransferDialog(table);
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Pindah Meja (Transfer Order)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = <String>{
      'Semua',
      ..._tables.map((t) => (t['section'] ?? 'Indoor').toString()),
    }.toList();

    final filtered = _tables.where((t) {
      if (_selectedSection == 'Semua') return true;
      return (t['section'] ?? 'Indoor') == _selectedSection;
    }).toList();

    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        title: const Text('Denah Meja Restoran (F&B)'),
        actions: [
          IconButton(onPressed: _loadTables, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: NusaThemeTokens.of(context).danger)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadTables, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: sections.map((sec) {
                                final active = _selectedSection == sec;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(sec),
                                    selected: active,
                                    onSelected: (_) => setState(() => _selectedSection = sec),
                                    selectedColor: NusaThemeTokens.of(context).accent,
                                    showCheckmark: false,
                                    labelStyle: TextStyle(
                                      color: active ? Colors.white : NusaThemeTokens.of(context).textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.circle, size: 10, color: NusaThemeTokens.of(context).positive),
                              SizedBox(width: 4),
                              Text('Kosong', style: TextStyle(fontSize: 11.5)),
                              SizedBox(width: 14),
                              Icon(Icons.circle, size: 10, color: NusaThemeTokens.of(context).danger),
                              SizedBox(width: 4),
                              Text('Terisi (Open Tab)', style: TextStyle(fontSize: 11.5)),
                              SizedBox(width: 14),
                              Icon(Icons.circle, size: 10, color: NusaThemeTokens.of(context).warning),
                              SizedBox(width: 4),
                              Text('Billed', style: TextStyle(fontSize: 11.5)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text('Belum ada meja restoran terdaftar.', style: TextStyle(color: NusaThemeTokens.of(context).textSecondary)),
                            )
                          : GridView.builder(
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
                                final status = (table['status'] ?? 'available').toString();
                                final isAvail = status == 'available';
                                final isBilled = status == 'billed';
                                final activeOrder = (table['active_sale'] ?? table['active_order']) as Map?;
                                final total = (activeOrder?['grand_total'] as num?)?.toDouble() ?? 0.0;

                                final borderColor = isAvail
                                    ? NusaThemeTokens.of(context).positive
                                    : (isBilled ? NusaThemeTokens.of(context).warning : NusaThemeTokens.of(context).danger);
                                final bgColor = isAvail
                                    ? NusaThemeTokens.of(context).positiveSoft.withOpacity(0.45)
                                    : (isBilled ? NusaThemeTokens.of(context).warningSoft : NusaThemeTokens.of(context).dangerSoft.withOpacity(0.55));

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
                                          '${table['section'] ?? 'Indoor'} • Kapasitas ${table['capacity']} Kursi',
                                          style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(context).textSecondary),
                                        ),
                                        const Spacer(),
                                        if (isAvail)
                                          Text(
                                            'Siap Ditempati',
                                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).positive),
                                          )
                                        else ...[
                                          Text(
                                            (activeOrder?['customer_name'] ?? activeOrder?['number'] ?? 'Tamu').toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                          ),
                                          Text(
                                            IdrCurrencyFormatter.format(total),
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
