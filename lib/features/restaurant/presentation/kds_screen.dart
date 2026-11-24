import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';

/// KITCHEN DISPLAY SYSTEM (KDS DAPUR RESTORAN & F&B)
/// Menampilkan antrian tiket dapur: Menunggu -> Sedang Dimasak -> Siap Saji.
class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  final ApiClient _api = GetIt.instance<ApiClient>();
  bool _loading = true;
  String _tabStatus = 'all'; // all, pending, cooking, ready
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  bool get _isLocalStandalone => context.read<AuthCubit>().state.session.isLocalTrial;

  Future<void> _loadQueue() async {
    setState(() => _loading = true);
    if (!_isLocalStandalone) {
      try {
        final res = await _api.dio.get(ApiEndpoints.kdsQueue);
        final raw = res.data['data'] as List<dynamic>?;
        if (raw != null) {
          if (!mounted) return;
          setState(() {
            _tickets = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _loading = false;
          });
          return;
        }
      } catch (_) {}
    }

    // Offline / Standalone fallback: derive kitchen tickets from held carts & active dine-in/takeaway orders
    final posState = context.read<PosCubit>().state;
    final derived = <Map<String, dynamic>>[];
    for (final h in posState.heldCarts) {
      final rawItems = (h['cart_items'] as List<dynamic>? ?? []);
      derived.add({
        'id': h['id'],
        'number': h['number'] ?? 'KOT-${h['id']}',
        'order_type': h['table_name'] != null ? 'Dine-In • ${h['table_name']}' : (h['held_label'] ?? 'Antrian'),
        'kds_status': (h['kds_status'] ?? 'pending').toString(),
        'created_at': h['held_at'] ?? '',
        'items': rawItems.map((it) {
          if (it is CartItemModel) {
            return {
              'name': it.displayName,
              'quantity': it.quantity,
              'notes': it.notes,
            };
          }
          return it;
        }).toList(),
      });
    }
    if (!mounted) return;
    setState(() {
      _tickets = derived;
      _loading = false;
    });
  }

  Future<void> _bumpStatus(Map<String, dynamic> ticket, String nextStatus) async {
    final id = ((ticket['sale_id'] ?? ticket['id']) as num?)?.toInt() ?? 0;
    setState(() {
      ticket['kitchen_status'] = nextStatus;
      ticket['kds_status'] = nextStatus;
      if (nextStatus == 'served') {
        _tickets.remove(ticket);
      }
    });
    if (!_isLocalStandalone && id > 0) {
      try {
        await _api.dio.post(
          ApiEndpoints.updateKdsStatus(id),
          data: {'kitchen_status': nextStatus},
        );
      } catch (_) {}
    }
  }

  String _normalizeKitchenStatus(Map<String, dynamic> ticket) {
    final raw = (ticket['kitchen_status'] ?? ticket['kds_status'] ?? 'pending').toString();
    return raw == 'preparing' ? 'cooking' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _tickets.where((t) {
      final st = _normalizeKitchenStatus(t);
      if (_tabStatus == 'all') return st != 'served';
      return st == _tabStatus;
    }).toList();

    return Scaffold(
      backgroundColor: NusaThemeTokens.of(context).bgPage,
      appBar: AppBar(
        title: const Text('Layar Dapur KDS'),
        actions: [
          IconButton(onPressed: _loadQueue, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                for (final f in const [
                  ('all', 'Semua Aktif'),
                  ('pending', 'Menunggu'),
                  ('cooking', 'Dimasak'),
                  ('ready', 'Siap Saji'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _tabStatus == f.$1,
                      onSelected: (_) => setState(() => _tabStatus = f.$1),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const NusaEmptyState(
                        icon: Icons.soup_kitchen_outlined,
                        title: 'Antrian Dapur Bersih',
                        subtitle: 'Pesanan Dine-In / Takeaway yang ditahan atau dikirim ke dapur akan muncul di layar KDS ini secara real-time.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final t = filtered[idx];
                          final st = _normalizeKitchenStatus(t);
                          final items = (t['items'] as List<dynamic>? ?? []);
                          final nextLabel = st == 'pending'
                              ? 'Mulai Masak'
                              : (st == 'cooking' ? 'Siap Disajikan' : 'Selesai / Antar');
                          final nextValue = st == 'pending'
                              ? 'cooking'
                              : (st == 'cooking' ? 'ready' : 'served');

                          return NusaCard(
                            borderColor: st == 'ready'
                                ? NusaThemeTokens.of(context).positive
                                : (st == 'cooking' ? NusaThemeTokens.of(context).warning : NusaThemeTokens.of(context).accent),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${t['number']} • ${t['order_type'] ?? t['table_name'] ?? 'Meja'}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                    NusaBadge(
                                      label: st == 'ready'
                                          ? 'SIAP SAJI'
                                          : (st == 'cooking' ? 'DIMASAK' : 'MENUNGGU'),
                                      variant: st == 'ready'
                                          ? NusaBadgeVariant.success
                                          : (st == 'cooking' ? NusaBadgeVariant.warning : NusaBadgeVariant.primary),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                ...items.map((it) {
                                  final m = it is Map ? it : {};
                                  final qty = m['quantity'] ?? 1;
                                  final name = (m['name'] ?? m['product_name'] ?? '-').toString();
                                  final note = (m['notes'] ?? '').toString();
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${qty}x ',
                                            style: TextStyle(fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).accent)),
                                        Expanded(
                                          child: Text(
                                            '$name${note.isNotEmpty ? '\n   Catatan: $note' : ''}',
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 10),
                                NusaButton(
                                  label: nextLabel,
                                  variant: st == 'cooking'
                                      ? NusaButtonVariant.success
                                      : NusaButtonVariant.primary,
                                  icon: Icons.check_rounded,
                                  onPressed: () => _bumpStatus(t, nextValue),
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
