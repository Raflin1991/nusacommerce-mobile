import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../../core/network/repositories/backoffice_repository.dart';

part 'customer_parity_modals.dart';

/// PILAR 2 — LAYAR MANAJEMEN PELANGGAN & MEMBER LENGKAP
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final BackofficeRepository _repo = BackofficeRepository.resolve();
  final OfflineDatabase _offlineDb = GetIt.instance<OfflineDatabase>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    context.read<PosCubit>().syncWithCloud(force: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showAddOrEditCustomerModal({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: existing?['email']?.toString() ?? '');
    final bizCtrl = TextEditingController(text: existing?['business_name']?.toString() ?? '');
    final limitCtrl = TextEditingController(
      text: ((existing?['credit_limit'] as num?)?.toInt() ?? 0).toString(),
    );
    final discCtrl = TextEditingController(
      text: ((existing?['default_discount_percent'] as num?)?.toInt() ?? 0).toString(),
    );
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final groups = context.read<PosCubit>().state.customerGroups;
    int? selectedGroupId = (existing?['customer_group_id'] as num?)?.toInt() ??
        (existing?['group_id'] as num?)?.toInt();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
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
                Text(
                  isEdit ? 'Edit Data Pelanggan' : 'Tambah Pelanggan Baru',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Lengkap *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Nomor HP / WhatsApp *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (Opsional)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: bizCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Toko / Bisnis (Opsional)'),
                ),
                if (groups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: groups.any((g) => (g['id'] as num?)?.toInt() == selectedGroupId)
                        ? selectedGroupId
                        : null,
                    decoration: const InputDecoration(labelText: 'Grup / Tier Member'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Reguler (Tanpa Grup)')),
                      ...groups.map((g) => DropdownMenuItem<int?>(
                            value: (g['id'] as num).toInt(),
                            child: Text(g['name'].toString()),
                          )),
                    ],
                    onChanged: (v) => setModalState(() => selectedGroupId = v),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: limitCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Batas Limit Kredit (Rp)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: discCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Diskon Member (%)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Catatan Pelanggan'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: NusaThemeTokens.of(ctx).danger,
                                  content: Text('Nama dan Nomor HP wajib diisi.'),
                                ),
                              );
                              return;
                            }
                            setModalState(() => saving = true);
                            final res = await context.read<PosCubit>().saveCustomer(
                              {
                                'name': nameCtrl.text.trim(),
                                'phone': phoneCtrl.text.trim(),
                                if (emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
                                if (bizCtrl.text.trim().isNotEmpty) 'business_name': bizCtrl.text.trim(),
                                'credit_limit': IdrCurrencyFormatter.parse(limitCtrl.text),
                                'default_discount_percent':
                                    (double.tryParse(discCtrl.text.trim()) ?? 0).clamp(0, 100),
                                if (selectedGroupId != null) 'customer_group_id': selectedGroupId,
                                if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
                              },
                              id: (existing?['id'] as num?)?.toInt(),
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor:
                                      res['success'] == true ? NusaThemeTokens.of(ctx).positive : NusaThemeTokens.of(ctx).danger,
                                  content: Text(
                                    res['success'] == true
                                        ? (isEdit
                                            ? 'Data pelanggan diperbarui.'
                                            : 'Pelanggan baru berhasil ditambahkan.')
                                        : (res['message']?.toString() ?? 'Gagal menyimpan pelanggan.'),
                                  ),
                                ),
                              );
                            }
                          },
                    child: Text(saving ? 'Menyimpan...' : 'Simpan Pelanggan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomerDetailSheet(Map<String, dynamic> customer, PosState posState) {
    final custId = (customer['id'] as num?)?.toInt() ?? 0;
    final storeName = context.read<AuthCubit>().state.session.activeStore.name;
    final history = posState.salesHistory.where((s) {
      final sc = s['customer'];
      if (sc is Map && (sc['id'] as num?)?.toInt() == custId) return true;
      return (s['customer_id'] as num?)?.toInt() == custId;
    }).toList();

    final outstanding = (customer['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
    final limit = (customer['credit_limit'] as num?)?.toDouble() ?? 0.0;
    final ratio = limit > 0 ? (outstanding / limit).clamp(0.0, 1.0) : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NusaThemeTokens.of(context).bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: NusaThemeTokens.of(ctx).accentSoft,
                    child: Text(
                      (customer['name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: NusaThemeTokens.of(ctx).accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer['name'].toString(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${customer['phone'] ?? '-'}${customer['business_name'] != null ? ' • ${customer['business_name']}' : ''}',
                          style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit Pelanggan',
                    icon: Icon(Icons.edit_outlined, color: NusaThemeTokens.of(ctx).accent),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddOrEditCustomerModal(existing: customer);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NusaThemeTokens.of(ctx).borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Limit Kredit Kasbon', style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${IdrCurrencyFormatter.format(outstanding)} / ${IdrCurrencyFormatter.format(limit)}',
                          style: AppTheme.moneyStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(999),
                      backgroundColor: NusaThemeTokens.of(ctx).borderSubtle,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        outstanding > 0 ? NusaThemeTokens.of(ctx).warning : NusaThemeTokens.of(ctx).positive,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        context.read<PosCubit>().selectCustomer(customer);
                        Navigator.pop(ctx);
                        context.go('/pos');
                      },
                      icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                      label: const Text('Pilih di Kasir'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (outstanding > 0)
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: NusaThemeTokens.of(ctx).whatsapp),
                        onPressed: () => WhatsAppService.sendDebtReminder(
                          customerName: customer['name'].toString(),
                          customerPhone: (customer['phone'] ?? '').toString(),
                          invoiceNumber: 'Saldo Piutang',
                          balanceDue: outstanding,
                          storeName: storeName,
                        ),
                        icon: const Icon(Icons.chat_rounded, size: 18, color: Colors.white),
                        label: const Text('Tagih WA', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
              if (outstanding > 0) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: NusaThemeTokens.of(ctx).accent),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openInstallmentFromReceivables(custId, customer['name'].toString());
                    },
                    icon: const Icon(Icons.payments_rounded, color: Colors.white),
                    label: const Text(
                      'Terima Cicilan / Pelunasan Bon',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCustomerStatementModal(customer, history);
                      },
                      icon: const Icon(Icons.account_balance_outlined, size: 18),
                      label: const Text('Kartu Piutang'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showTopupDepositModal(customer);
                      },
                      icon: Icon(Icons.savings_outlined, size: 18, color: NusaThemeTokens.of(ctx).positive),
                      label: const Text('Top-up Deposit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Riwayat Belanja Pelanggan (${history.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Text(
                  'Belum ada riwayat transaksi tercatat untuk pelanggan ini.',
                  style: TextStyle(fontSize: 12.5, color: NusaThemeTokens.of(ctx).textSecondary),
                )
              else
                ...history.take(15).map((sale) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: NusaThemeTokens.of(ctx).accentSoft,
                      child: Icon(Icons.receipt_long_rounded, size: 18, color: NusaThemeTokens.of(ctx).accent),
                    ),
                    title: Text(
                      (sale['number'] ?? '#INV').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      (sale['sale_datetime'] ?? '').toString(),
                      style: TextStyle(fontSize: 11.5, color: NusaThemeTokens.of(ctx).textSecondary),
                    ),
                    trailing: Text(
                      IdrCurrencyFormatter.format((sale['grand_total'] as num?) ?? 0),
                      style: AppTheme.moneyStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInstallmentFromReceivables(int custId, String custName) async {
    try {
      final res = await _repo.fetchReceivables();
      final raw = (res.data['data'] as List?) ?? [];
      final matching = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => (r['customer_id'] as num?)?.toInt() == custId)
          .toList();

      if (!mounted) return;
      if (matching.isEmpty) {
        context.push('/debts');
        return;
      }

      final target = matching.first;
      final balance = (target['balance_due'] as num?)?.toDouble() ?? 0.0;
      final payCtrl = TextEditingController(text: balance.toInt().toString());
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text('Terima Cicilan — $custName', style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tagihan ${target['number'] ?? ''}: ${IdrCurrencyFormatter.format(balance)}'),
              const SizedBox(height: 10),
              TextField(
                controller: payCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal Bayar Cicilan (Rp)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                final amount = IdrCurrencyFormatter.parse(payCtrl.text);
                if (amount <= 0) return;
                try {
                  await _repo.payReceivable(
                    (target['id'] as num).toInt(),
                    {'amount': amount, 'payment_method_id': 1},
                  );
                  if (dCtx.mounted) Navigator.pop(dCtx);
                  if (mounted) {
                    context.read<PosCubit>().syncWithCloud(force: false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: NusaThemeTokens.of(dCtx).positive,
                        content: Text('Pembayaran cicilan berhasil dicatat.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: NusaThemeTokens.of(dCtx).danger,
                        content: Text(ApiClient.extractErrorMessage(e)),
                      ),
                    );
                  }
                }
              },
              child: const Text('Catat Bayar'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) context.push('/debts');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        final q = _searchCtrl.text.trim().toLowerCase();
        final onlyDebtors = _tabController.index == 1;

        final debtorsCount = state.customers
            .where((c) => ((c['outstanding_balance'] as num?)?.toDouble() ?? 0) > 0)
            .length;
        final totalReceivables = state.customers.fold<double>(
          0.0,
          (sum, c) => sum + ((c['outstanding_balance'] as num?)?.toDouble() ?? 0.0),
        );

        final filtered = state.customers.where((c) {
          final balance = (c['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
          if (onlyDebtors && balance <= 0) return false;
          if (q.isEmpty) return true;
          final name = (c['name'] ?? '').toString().toLowerCase();
          final phone = (c['phone'] ?? '').toString().toLowerCase();
          final code = (c['code'] ?? '').toString().toLowerCase();
          return name.contains(q) || phone.contains(q) || code.contains(q);
        }).toList();

        return Scaffold(
          backgroundColor: NusaThemeTokens.of(context).bgPage,
          appBar: AppBar(
            title: const Text('Pelanggan & Member'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => context.read<PosCubit>().syncWithCloud(force: false),
              ),
              IconButton(
                icon: Icon(Icons.person_add_alt_1_rounded, color: NusaThemeTokens.of(context).accent),
                onPressed: () => _showAddOrEditCustomerModal(),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: NusaThemeTokens.of(context).accent,
              unselectedLabelColor: NusaThemeTokens.of(context).textSecondary,
              indicatorColor: NusaThemeTokens.of(context).accent,
              tabs: [
                Tab(text: 'Semua (${state.customers.length})'),
                Tab(text: 'Punya Piutang ($debtorsCount)'),
                Tab(text: 'Grup (${state.customerGroups.length})'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _tabController.index == 2
                ? () => _showAddOrEditGroupModal()
                : () => _showAddOrEditCustomerModal(),
            backgroundColor: NusaThemeTokens.of(context).accent,
            icon: Icon(
              _tabController.index == 2 ? Icons.group_add_rounded : Icons.person_add_rounded,
              color: Colors.white,
            ),
            label: Text(
              _tabController.index == 2 ? 'Tambah Grup' : 'Pelanggan Baru',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          body: _tabController.index == 2
              ? _buildCustomerGroupsTab(state.customerGroups)
              : Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _kpiCard('Total Member', '${state.customers.length}', NusaThemeTokens.of(context).accent),
                        const SizedBox(width: 8),
                        _kpiCard('Berhutang', '$debtorsCount Org', NusaThemeTokens.of(context).warning),
                        const SizedBox(width: 8),
                        _kpiCard(
                          'Piutang Aktif',
                          IdrCurrencyFormatter.formatCompact(totalReceivables),
                          NusaThemeTokens.of(context).danger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Cari nama pelanggan / nomor HP / WA...',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          onlyDebtors
                              ? 'Tidak ada pelanggan dengan saldo piutang bon.'
                              : 'Belum ada data pelanggan.',
                          style: TextStyle(color: NusaThemeTokens.of(context).textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 88),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, idx) {
                          final c = filtered[idx];
                          final balance = (c['outstanding_balance'] as num?)?.toDouble() ?? 0.0;
                          final pts = (c['loyalty_points'] as num?)?.toInt() ?? 0;
                          final group = c['group_name']?.toString();
                          final phone = (c['phone'] ?? '-').toString();

                          return InkWell(
                            onTap: () => _showCustomerDetailSheet(c, state),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: NusaThemeTokens.of(context).borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: NusaThemeTokens.of(context).accentSoft,
                                    child: Text(
                                      (c['name'] ?? 'P').toString().substring(0, 1).toUpperCase(),
                                      style: TextStyle(fontWeight: FontWeight.w800, color: NusaThemeTokens.of(context).accent),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c['name'].toString(),
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                              ),
                                            ),
                                            if (group != null && group.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: NusaThemeTokens.of(context).accentSoft,
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Text(
                                                  group,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: NusaThemeTokens.of(context).accent,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$phone • $pts Poin',
                                          style: TextStyle(fontSize: 12, color: NusaThemeTokens.of(context).textSecondary),
                                        ),
                                        if (balance > 0) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Bon Aktif: ${IdrCurrencyFormatter.format(balance)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: NusaThemeTokens.of(context).warning,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Chat / Tagih WhatsApp',
                                    icon: Icon(Icons.chat_rounded, color: NusaThemeTokens.of(context).whatsapp),
                                    onPressed: () {
                                      final storeName = context.read<AuthCubit>().state.session.activeStore.name;
                                      WhatsAppService.sendDebtReminder(
                                        customerName: c['name'].toString(),
                                        customerPhone: phone,
                                        invoiceNumber: balance > 0 ? 'Saldo Buku Bon' : 'Info Member',
                                        balanceDue: balance,
                                        storeName: storeName,
                                      );
                                    },
                                  ),
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
      },
    );
  }

  Widget _kpiCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: NusaThemeTokens.of(context).textSecondary)),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.moneyStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
