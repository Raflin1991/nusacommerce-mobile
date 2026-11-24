import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/models/pos_models.dart';
import '../../../core/network/repositories/restaurant_table_repository.dart';

/// KITCHEN DISPLAY SYSTEM (KDS DAPUR RESTORAN & F&B — Wave 3.4 Station Filter & Live SLA Aging)
class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  final RestaurantTableRepository _tableRepo = RestaurantTableRepository.resolve();
  bool _loading = true;
  String _tabStatus = 'all'; // all, pending, cooking, ready
  String _selectedStation = 'all'; // all, kitchen, bar, pastry
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
        final raw = await _tableRepo.getKdsQueue(station: _selectedStation);
        if (!mounted) return;
        setState(() {
          _tickets = raw;
          _loading = false;
        });
        return;
      } catch (_) {}
    }

    // Offline / Standalone fallback: derive kitchen tickets from held carts
    final posState = context.read<PosCubit>().state;
    final derived = <Map<String, dynamic>>[];
    for (final h in posState.heldCarts) {
      final rawItems = (h['cart_items'] as List<dynamic>? ?? []);
      final createdIso = (h['created_at'] ?? '').toString();
      final parsedCreated = DateTime.tryParse(createdIso);
      final elapsedMins = parsedCreated != null
          ? DateTime.now().difference(parsedCreated).inMinutes.clamp(0, 999)
          : 0;
      derived.add({
        'id': h['id'],
        'number': h['number'] ?? 'KOT-${h['id']}',
        'order_type': h['table_name'] != null ? 'Dine-In • ${h['table_name']}' : (h['held_label'] ?? 'Antrian'),
        'kds_status': (h['kds_status'] ?? 'pending').toString(),
        'elapsed_mins': elapsedMins,
        'items': rawItems.map((it) {
          if (it is CartItemModel) {
            return {
              'name': it.displayName,
              'quantity': it.quantity,
              'kds_station': it.product.kdsStation,
              'notes': it.cookingNotes?.trim().isNotEmpty == true ? it.cookingNotes : it.notes,
              'cooking_notes': it.cookingNotes,
              'modifiers': it.modifierLabels,
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
        await _tableRepo.updateKdsStatus(id, nextStatus);
      } catch (_) {}
    }
  }

  String _normalizeKitchenStatus(Map<String, dynamic> ticket) {
    final raw = (ticket['kitchen_status'] ?? ticket['kds_status'] ?? 'pending').toString();
    return raw == 'preparing' || raw == 'sent_to_kitchen' ? 'cooking' : raw;
  }

  bool _matchesStation(Map<String, dynamic> ticket) {
    if (_selectedStation == 'all') return true;
    final items = (ticket['items'] as List<dynamic>? ?? []);
    return items.any((it) {
      if (it is! Map) return true;
      final st = (it['kds_station'] ?? 'kitchen').toString().trim().toLowerCase();
      return st == _selectedStation;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final filtered = _tickets.where((t) {
      final st = _normalizeKitchenStatus(t);
      final statusOk = _tabStatus == 'all' ? st != 'served' : st == _tabStatus;
      return statusOk && _matchesStation(t);
    }).toList();

    return Scaffold(
      backgroundColor: tokens.bgPage,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final st in const [
                  ('all', 'Semua Stasiun'),
                  ('kitchen', 'Kitchen / Dapur'),
                  ('bar', 'Bar & Coffee'),
                  ('pastry', 'Pastry'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(st.$2),
                      selected: _selectedStation == st.$1,
                      onSelected: (_) {
                        setState(() => _selectedStation = st.$1);
                        _loadQueue();
                      },
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                        subtitle: 'Pesanan Dine-In / Takeaway yang dikirim ke stasiun ini akan muncul secara real-time.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final t = filtered[idx];
                          final st = _normalizeKitchenStatus(t);
                          final elapsedMins = (t['elapsed_mins'] as num?)?.toInt() ?? 0;
                          final isBreach = elapsedMins > 15;
                          final isWarn = elapsedMins >= 10 && elapsedMins <= 15;
                          final slaColor = isBreach
                              ? tokens.danger
                              : (isWarn ? tokens.warning : tokens.positive);
                          final slaSoft = isBreach
                              ? tokens.dangerSoft
                              : (isWarn ? tokens.warningSoft : tokens.positiveSoft);

                          final items = (t['items'] as List<dynamic>? ?? []).where((it) {
                            if (_selectedStation == 'all' || it is! Map) return true;
                            return (it['kds_station'] ?? 'kitchen').toString().toLowerCase() == _selectedStation;
                          }).toList();

                          final nextLabel = st == 'pending'
                              ? 'Mulai Masak'
                              : (st == 'cooking' ? 'Siap Disajikan' : 'Selesai / Antar');
                          final nextValue = st == 'pending'
                              ? 'cooking'
                              : (st == 'cooking' ? 'ready' : 'served');

                          return NusaCard(
                            borderColor: isBreach
                                ? tokens.danger
                                : (st == 'ready'
                                    ? tokens.positive
                                    : (st == 'cooking' ? tokens.warning : tokens.accent)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${t['number']} • ${t['order_type'] ?? t['table_name'] ?? 'Meja'}',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: slaSoft,
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: slaColor),
                                          ),
                                          child: Text(
                                            '⏱ $elapsedMins mnt${isBreach ? ' • SLA!' : ''}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: slaColor,
                                            ),
                                          ),
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
                                  ],
                                ),
                                const Divider(height: 16),
                                ...items.map((it) {
                                  final m = it is Map ? it : {};
                                  final qty = m['quantity'] ?? 1;
                                  final name = (m['name'] ?? m['product_name'] ?? '-').toString();
                                  final note = (m['cooking_notes'] ?? m['notes'] ?? '').toString().trim();
                                  final rawMods = m['modifiers'] as List<dynamic>? ?? const [];
                                  final mods = rawMods
                                      .map((e) => e is Map ? (e['name'] ?? '').toString().trim() : e.toString().trim())
                                      .where((s) => s.isNotEmpty)
                                      .toList();

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${qty}x ',
                                          style: TextStyle(fontWeight: FontWeight.w800, color: tokens.accent),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                                              ),
                                              if (mods.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Wrap(
                                                    spacing: 4,
                                                    runSpacing: 4,
                                                    children: [
                                                      for (final mod in mods)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: tokens.accentSoft,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            '+ $mod',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w700,
                                                              color: tokens.accent,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              if (note.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 3),
                                                  child: Text(
                                                    'Catatan Masak: $note',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: tokens.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 8),
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
