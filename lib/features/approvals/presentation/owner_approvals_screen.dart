import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';
import '../../../core/network/repositories/backoffice_repository.dart';

part 'owner_approvals_screen_part1.dart';
part 'owner_approvals_screen_part2.dart';

/// MEJA PERSETUJUAN OWNER (APPROVALS DESK — MAKER-CHECKER SOD)
/// Memberikan kendali otorisasi 1-ketuk kepada Owner/Manager untuk permintaan
/// pembatalan nota (void), diskon khusus, transfer gudang, penyesuaian stok, PO, dan biaya.
class OwnerApprovalsScreen extends StatefulWidget {
  const OwnerApprovalsScreen({super.key});

  @override
  State<OwnerApprovalsScreen> createState() => _OwnerApprovalsScreenState();
}


class _OwnerApprovalsScreenState extends State<OwnerApprovalsScreen> {
  final BackofficeRepository _repo = BackofficeRepository.resolve();

  final NetworkConnectivityService _connectivity = GetIt.instance<NetworkConnectivityService>();

  final TextEditingController _searchCtrl = TextEditingController();


  bool _loading = true;

  bool _isOffline = false;

  String? _error;

  String _statusFilter = 'pending';

  String _searchQuery = '';

  List<Map<String, dynamic>> _items = const [];


  @override
  void initState() {
    super.initState();
    _loadApprovals();
  }


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final session = context.watch<AuthCubit>().state.session;
    final visible = _filteredItems;

    return Scaffold(
      backgroundColor: tokens.bgPage,
      appBar: AppBar(
        title: const Text('Meja Persetujuan Owner'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang antrean',
            onPressed: _loading ? null : _loadApprovals,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: tokens.bgSurface,
              border: Border(
                bottom: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(fontSize: 13, color: tokens.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Cari pemohon, cabang, jenis transaksi, atau alasan...',
                    hintStyle: TextStyle(fontSize: 13, color: tokens.textTertiary),
                    prefixIcon: Icon(Icons.search_rounded, size: 20, color: tokens.textTertiary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 18, color: tokens.textSecondary),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: tokens.bgElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final opt in const [
                        ('pending', 'Menunggu'),
                        ('approved', 'Disetujui'),
                        ('rejected', 'Ditolak'),
                        ('all', 'Semua'),
                      ]) ...[
                        NusaPillFilter(
                          label: opt.$2,
                          selected: _statusFilter == opt.$1,
                          onTap: () {
                            if (_statusFilter == opt.$1) return;
                            setState(() => _statusFilter = opt.$1);
                            _loadApprovals();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: tokens.accent,
              onRefresh: _loadApprovals,
              child: _buildBody(context, tokens, session, visible),
            ),
          ),
        ],
      ),
    );
  }
}
