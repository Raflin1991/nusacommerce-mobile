import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// SURAT PENAWARAN HARGA (QUOTATIONS) & 1-KLIK LANJUT KE KASIR POS
class QuotationsScreen extends StatefulWidget {
  const QuotationsScreen({super.key});

  @override
  State<QuotationsScreen> createState() => _QuotationsScreenState();
}

class _QuotationsScreenState extends State<QuotationsScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  bool _loading = true;
  List<Map<String, dynamic>> _quotations = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  Future<void> _loadData() async {
    setState(() => _loading = true);
    var local = _offlineDb.getLocalQuotations();
    if (!_isLocalStandalone) {
      try {
        final res = await _api.dio.get(ApiEndpoints.quotations);
        final raw = res.data['data'] as List<dynamic>?;
        if (raw != null) {
          local = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _quotations = local;
      _loading = false;
    });
  }

  void _openCreateQuotationModal() {
    final posState = context.read<PosCubit>().state;
    final customers = posState.customers;
    final products = posState.allProducts;

    Map<String, dynamic>? selectedCustomer = customers.isNotEmpty ? customers.first : null;
    final discountCtrl = TextEditingController(text: '0');
    final validDaysCtrl = TextEditingController(text: '7');
    final notesCtrl = TextEditingController();
    final List<Map<String, dynamic>> lines = [];
    bool saving = false;
    String? modalError;

    double computeSubtotal() =>
        lines.fold(0.0, (s, e) => s + ((e['quantity'] as num).toDouble() * (e['unit_price'] as num).toDouble()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final sub = computeSubtotal();
          final disc = IdrCurrencyFormatter.parse(discountCtrl.text).clamp(0.0, sub);
          final grand = (sub - disc).clamp(0.0, double.infinity);

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.86,
            child: Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Buat Surat Penawaran Harga',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (customers.isNotEmpty)
                          DropdownButtonFormField<int?>(
                            value: (selectedCustomer?['id'] as num?)?.toInt(),
                            decoration: const InputDecoration(
                              labelText: 'Pelanggan / Calon Pembeli',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('Pelanggan Umum')),
                              ...customers.map((c) => DropdownMenuItem<int?>(
                                    value: (c['id'] as num).toInt(),
                                    child: Text(c['name'].toString()),
                                  )),
                            ],
                            onChanged: (v) {
                              setModal(() {
                                selectedCustomer = v == null
                                    ? null
                                    : customers.where((c) => (c['id'] as num).toInt() == v).firstOrNull;
                              });
                            },
                          ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _pickProduct(ctx, products, (line) {
                            setModal(() {
                              lines.removeWhere((e) => e['product_id'] == line['product_id']);
                              lines.add(line);
                            });
                          }),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Tambah Item Penawaran'),
                        ),
                        const SizedBox(height: 8),
                        ...lines.map((it) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: NusaCard(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(it['product_name'].toString(),
                                              style: const TextStyle(fontWeight: FontWeight.w700)),
                                          Text(
                                            '${IdrCurrencyFormatter.formatQty((it['quantity'] as num).toDouble())} x ${IdrCurrencyFormatter.format((it['unit_price'] as num).toDouble())}',
                                            style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
                                      onPressed: () => setModal(() => lines.remove(it)),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: discountCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setModal(() {}),
                                decoration: const InputDecoration(labelText: 'Diskon (Rp)'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: validDaysCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Berlaku (Hari)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: notesCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(labelText: 'Syarat & Catatan Penawaran'),
                        ),
                      ],
                    ),
                  ),
                  if (modalError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.dangerDark, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              modalError!,
                              style: const TextStyle(
                                color: AppColors.dangerDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => setModal(() => modalError = null),
                            child: const Icon(Icons.close_rounded, color: AppColors.dangerDark, size: 16),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Penawaran', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        IdrCurrencyFormatter.format(grand),
                        style: AppTheme.moneyStyle(fontSize: 18, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  NusaButton(
                    label: 'Simpan Penawaran',
                    isLoading: saving,
                    icon: Icons.save_rounded,
                    onPressed: (saving || lines.isEmpty)
                        ? null
                        : () async {
                            setModal(() {
                              saving = true;
                              modalError = null;
                            });
                            final validDays = int.tryParse(validDaysCtrl.text.trim()) ?? 7;
                            final validUntil =
                                DateTime.now().add(Duration(days: validDays)).toIso8601String().split('T').first;
                            final custId = (selectedCustomer?['id'] as num?)?.toInt();
                            final custName = (selectedCustomer?['name'] ?? 'Pelanggan Umum').toString();

                            bool cloudOk = false;
                            if (!_isLocalStandalone) {
                              try {
                                await _api.dio.post(ApiEndpoints.quotations, data: {
                                  if (custId != null && custId > 0) 'customer_id': custId,
                                  'customer_name': custName,
                                  'valid_until': validUntil,
                                  'discount_amount': disc,
                                  'notes': notesCtrl.text.trim(),
                                  'items': lines,
                                });
                                cloudOk = true;
                              } catch (e) {
                                if (!ApiClient.isNetworkOfflineError(e)) {
                                  final errMsg = ApiClient.extractErrorMessage(e);
                                  setModal(() {
                                    saving = false;
                                    modalError = errMsg;
                                  });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.danger,
                                        content: Text(errMsg),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              }
                            }
                            if (!cloudOk) {
                              await _offlineDb.addOrUpdateLocalQuotation({
                                'customer_id': custId,
                                'customer_name': custName,
                                'customer_phone': selectedCustomer?['phone'],
                                'valid_until': validUntil,
                                'subtotal': sub,
                                'discount_amount': disc,
                                'grand_total': grand,
                                'status': 'draft',
                                'notes': notesCtrl.text.trim(),
                                'items': lines,
                              });
                            }
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            await _loadData();
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _pickProduct(
    BuildContext parentCtx,
    List<ProductModel> products,
    void Function(Map<String, dynamic> line) onAdd,
  ) {
    String q = '';
    showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final filtered = products.where((p) {
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q.toLowerCase()) ||
                p.sku.toLowerCase().contains(q.toLowerCase());
          }).toList();
          return AlertDialog(
            title: const Text('Pilih Produk'),
            content: SizedBox(
              width: 340,
              height: 340,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setDlg(() => q = v),
                    decoration: const InputDecoration(hintText: 'Cari produk...', prefixIcon: Icon(Icons.search)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, idx) {
                        final p = filtered[idx];
                        return ListTile(
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(IdrCurrencyFormatter.format(p.sellingPrice)),
                          onTap: () {
                            Navigator.pop(ctx);
                            final qtyCtrl = TextEditingController(text: '1');
                            showDialog(
                              context: parentCtx,
                              builder: (qCtx) => AlertDialog(
                                title: Text(p.name),
                                content: TextField(
                                  controller: qtyCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: 'Qty (${p.unitCode})'),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(qCtx), child: const Text('Batal')),
                                  FilledButton(
                                    onPressed: () {
                                      final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1;
                                      onAdd({
                                        'product_id': p.id,
                                        'product_name': p.name,
                                        'sku': p.sku,
                                        'quantity': qty,
                                        'unit_price': p.sellingPrice,
                                      });
                                      Navigator.pop(qCtx);
                                    },
                                    child: const Text('Tambahkan'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _shareQuotationWa(Map<String, dynamic> q) async {
    final storeName = context.read<AuthCubit>().state.session.activeStore.name;
    final custName = (q['customer_name'] ?? 'Pelanggan').toString();
    final number = (q['quotation_number'] ?? q['number'] ?? '-').toString();
    final total = (q['grand_total'] as num?)?.toDouble() ?? 0.0;
    final items = (q['items'] as List<dynamic>? ?? []);
    final sb = StringBuffer()
      ..writeln('📄 *SURAT PENAWARAN HARGA — $storeName*')
      ..writeln('No: *$number* | Pelanggan: *$custName*')
      ..writeln('Berlaku s/d: ${q['valid_until'] ?? '-'}')
      ..writeln('--------------------------------');
    for (final raw in items) {
      if (raw is Map) {
        final name = raw['product_name'] ?? raw['name'] ?? '-';
        final qty = raw['quantity'] ?? 1;
        final price = IdrCurrencyFormatter.format((raw['unit_price'] as num?)?.toDouble() ?? 0);
        sb.writeln('• $name ($qty x $price)');
      }
    }
    sb
      ..writeln('--------------------------------')
      ..writeln('Total Penawaran: *${IdrCurrencyFormatter.format(total)}*')
      ..writeln('Silakan kabari kami jika penawaran ini ingin diproses menjadi pesanan 🙏');

    await WhatsAppService.sendCustomMessage(
      phone: (q['customer_phone'] ?? '').toString(),
      text: sb.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        title: const Text('Penawaran Harga (Quotation)'),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateQuotationModal,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.note_add_rounded),
        label: const Text('Buat Penawaran'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _quotations.isEmpty
              ? const NusaEmptyState(
                  icon: Icons.request_quote_outlined,
                  title: 'Belum Ada Penawaran Harga',
                  subtitle: 'Buat surat penawaran harga untuk dikirim ke WhatsApp pelanggan, lalu konversi ke Kasir POS dalam 1 klik.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  itemCount: _quotations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final q = _quotations[idx];
                    final status = (q['status'] ?? 'draft').toString();
                    final total = (q['grand_total'] as num?)?.toDouble() ?? 0.0;
                    final converted = status == 'converted';

                    return NusaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                (q['quotation_number'] ?? q['number'] ?? '-').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              NusaBadge(
                                label: status.toUpperCase(),
                                variant: converted ? NusaBadgeVariant.success : NusaBadgeVariant.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pelanggan: ${q['customer_name'] ?? 'Umum'} • Berlaku s/d: ${q['valid_until'] ?? '-'}',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.slate600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            IdrCurrencyFormatter.format(total),
                            style: AppTheme.moneyStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _shareQuotationWa(q),
                                icon: const Icon(Icons.share_rounded, size: 17, color: AppColors.successDark),
                                label: const Text('Kirim WA'),
                              ),
                              const SizedBox(width: 8),
                              if (!converted)
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      context.read<PosCubit>().loadCartFromQuotation(q);
                                      context.go('/pos');
                                    },
                                    icon: const Icon(Icons.point_of_sale_rounded, size: 17),
                                    label: const Text('Lanjut ke Kasir POS'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
