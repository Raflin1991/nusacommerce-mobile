import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';

/// PESANAN TOKO ONLINE (WEBSTORE ORDERS + NO. RESI + STATUS PEMENUHAN)
class OnlineOrdersScreen extends StatefulWidget {
  const OnlineOrdersScreen({super.key});

  @override
  State<OnlineOrdersScreen> createState() => _OnlineOrdersScreenState();
}

class _OnlineOrdersScreenState extends State<OnlineOrdersScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();

  bool _loading = true;
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    final session = context.read<AuthCubit>().state.session;
    if (session.isLocalTrial || session.isModuleGated('online_store')) {
      setState(() {
        _orders = const [];
        _loading = false;
      });
      return;
    }

    try {
      final res = await _api.dio.get(
        ApiEndpoints.onlineOrders,
        queryParameters: _statusFilter == 'all' ? null : {'online_order_status': _statusFilter},
      );
      final raw = res.data['data'] as List<dynamic>?;
      if (!mounted) return;
      setState(() {
        _orders = (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openFulfillmentModal(Map<String, dynamic> order) {
    final id = (order['id'] as num?)?.toInt() ?? 0;
    String nextStatus = (order['online_order_status'] ?? order['status'] ?? 'processing').toString();
    final orderNo = (order['number'] ?? order['order_number'] ?? id).toString();
    final resiCtrl = TextEditingController(text: (order['tracking_number'] ?? '').toString());
    final courierCtrl = TextEditingController(text: (order['courier'] ?? '').toString());
    bool saving = false;
    String? modalError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Proses Pesanan #$orderNo',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: ['pending_payment', 'paid', 'processing', 'shipped', 'completed', 'cancelled']
                        .contains(nextStatus)
                    ? nextStatus
                    : 'processing',
                decoration: const InputDecoration(labelText: 'Status Pesanan'),
                items: const [
                  DropdownMenuItem(value: 'pending_payment', child: Text('Menunggu Pembayaran')),
                  DropdownMenuItem(value: 'paid', child: Text('Sudah Dibayar')),
                  DropdownMenuItem(value: 'processing', child: Text('Sedang Dikemas / Diproses')),
                  DropdownMenuItem(value: 'shipped', child: Text('Dikirim (Kurir)')),
                  DropdownMenuItem(value: 'completed', child: Text('Selesai Diterima')),
                  DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
                ],
                onChanged: (v) {
                  if (v != null) setModal(() => nextStatus = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: courierCtrl,
                decoration: const InputDecoration(labelText: 'Nama Kurir / Ekspedisi (cth: JNE, J&T)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: resiCtrl,
                decoration: const InputDecoration(labelText: 'Nomor Resi Pengiriman'),
              ),
              const SizedBox(height: 16),
              if (modalError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: NusaThemeTokens.of(ctx).dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: NusaThemeTokens.of(ctx).danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          modalError!,
                          style: TextStyle(
                            color: NusaThemeTokens.of(ctx).danger,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setModal(() => modalError = null),
                        child: Icon(Icons.close_rounded, color: NusaThemeTokens.of(ctx).danger, size: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              NusaButton(
                label: 'Simpan Status Pesanan',
                isLoading: saving,
                icon: Icons.local_shipping_rounded,
                onPressed: saving
                    ? null
                    : () async {
                        setModal(() {
                          saving = true;
                          modalError = null;
                        });
                        try {
                          await _api.dio.post(ApiEndpoints.updateOnlineOrderStatus(id), data: {
                            'online_order_status': nextStatus,
                            if (resiCtrl.text.trim().isNotEmpty)
                              'shipping_tracking_number': resiCtrl.text.trim(),
                            if (courierCtrl.text.trim().isNotEmpty)
                              'courier': courierCtrl.text.trim(),
                          });
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          await _loadOrders();
                        } catch (e) {
                          final errMsg = ApiClient.extractErrorMessage(e);
                          setModal(() {
                            saving = false;
                            modalError = errMsg;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: NusaThemeTokens.of(ctx).danger,
                                content: Text(errMsg),
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthCubit>().state.session;
    final gated = session.isLocalTrial || session.isModuleGated('online_store');

    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        title: const Text('Pesanan Toko Online'),
        actions: [
          IconButton(onPressed: _loadOrders, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: gated
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: NusaCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: NusaThemeTokens.of(context).warningSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.storefront_rounded, size: 36, color: NusaThemeTokens.of(context).warning),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Katalog & Pesanan Toko Online (Paket Pro / Enterprise)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Terima pesanan webstore pelanggan langsung dari HP, sinkronkan stok real-time dengan kasir POS, cetak label kirim, dan input nomor resi kurir otomatis.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(context).textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Row(
                    children: [
                      for (final f in const [
                        ('all', 'Semua'),
                        ('pending_payment', 'Menunggu Bayar'),
                        ('paid', 'Dibayar'),
                        ('processing', 'Diproses'),
                        ('shipped', 'Dikirim'),
                        ('completed', 'Selesai'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.$2),
                            selected: _statusFilter == f.$1,
                            onSelected: (_) {
                              setState(() => _statusFilter = f.$1);
                              _loadOrders();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _orders.isEmpty
                          ? const NusaEmptyState(
                              icon: Icons.shopping_bag_outlined,
                              title: 'Belum Ada Pesanan Online',
                              subtitle: 'Pesanan masuk dari halaman Toko Online Anda akan tampil di sini.',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _orders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, idx) {
                                final o = _orders[idx];
                                final status = (o['online_order_status'] ?? o['status'] ?? 'pending_payment').toString();
                                final orderNo = (o['number'] ?? o['order_number'] ?? o['id']).toString();
                                final resi = (o['tracking_number'] ?? '').toString();
                                return NusaCard(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('#$orderNo',
                                              style: const TextStyle(fontWeight: FontWeight.w800)),
                                          NusaBadge(
                                            label: status.toUpperCase(),
                                            variant: status == 'completed'
                                                ? NusaBadgeVariant.success
                                                : (status == 'cancelled'
                                                    ? NusaBadgeVariant.danger
                                                    : NusaBadgeVariant.primary),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${o['customer_name'] ?? 'Pembeli Online'} • ${o['customer_phone'] ?? '-'}',
                                        style: TextStyle(fontSize: 13, color: NusaThemeTokens.of(context).textSecondary),
                                      ),
                                      if (resi.isNotEmpty)
                                        Text('Resi: $resi (${o['courier'] ?? '-'})',
                                            style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).accent)),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            IdrCurrencyFormatter.format(
                                                (o['grand_total'] as num?)?.toDouble() ?? 0),
                                            style: AppTheme.moneyStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                          ),
                                          Row(
                                            children: [
                                              if ((o['customer_phone'] ?? '').toString().isNotEmpty)
                                                IconButton(
                                                  tooltip: 'Info ke WA Pembeli',
                                                  onPressed: () {
                                                    WhatsAppService.sendCustomMessage(
                                                      phone: o['customer_phone'].toString(),
                                                      text:
                                                          'Halo ${o['customer_name']}, update pesanan #$orderNo: Status *$status*${resi.isNotEmpty ? ' • No. Resi: *$resi*' : ''}. Terima kasih!',
                                                    );
                                                  },
                                                  icon: Icon(Icons.chat_outlined, color: NusaThemeTokens.of(context).positive),
                                                ),
                                              FilledButton(
                                                onPressed: () => _openFulfillmentModal(o),
                                                child: const Text('Update Resi/Status'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
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
