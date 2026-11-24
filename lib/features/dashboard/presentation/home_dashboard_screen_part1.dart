// ignore_for_file: invalid_use_of_protected_member
part of 'home_dashboard_screen.dart';

extension _HomeDashboardScreenStatePart1Ext on _HomeDashboardScreenState {

  String get _periodTitle {
    switch (_selectedPeriod) {
      case 'month':
        return 'Omzet Bulan Ini (MTD)';
      case 'today':
        return 'Omzet Bersih Hari Ini';
      case 'yesterday':
        return 'Omzet Bersih Kemarin';
      case '7d':
        return 'Omzet 7 Hari Terakhir';
      case '30d':
        return 'Omzet 30 Hari Terakhir';
      default:
        return 'Omzet Bersih';
    }
  }


  String get _grossProfitTitle {
    switch (_selectedPeriod) {
      case 'month':
        return 'Laba Kotor Bulan Ini';
      case 'today':
        return 'Laba Kotor Hari Ini';
      case 'yesterday':
        return 'Laba Kotor Kemarin';
      case '7d':
        return 'Laba Kotor 7 Hari';
      case '30d':
        return 'Laba Kotor 30 Hari';
      default:
        return 'Laba Kotor';
    }
  }


  MobileWorkspaceRole _effectiveWorkspace(AuthSessionModel session) {
    return MobileWorkspaceResolver.sanitizeActiveWorkspace(
      session,
      widget.activeWorkspace,
    );
  }


  void _openCopilot(AuthSessionModel session) {
    if (widget.onOpenCopilot != null) {
      widget.onOpenCopilot!();
    } else {
      showNusaCopilotSheet(context, workspace: _effectiveWorkspace(session));
    }
  }


  ThemeCubit? _maybeThemeCubit(BuildContext context) {
    try {
      return context.watch<ThemeCubit>();
    } catch (_) {
      return null;
    }
  }


  void _applyLocalDashboardMetrics({int? storeId, String? period}) {
    final now = DateTime.now();
    final p = period ?? _selectedPeriod;
    DateTime startDate;
    if (p == 'month') {
      startDate = DateTime(now.year, now.month, 1);
    } else if (p == '7d') {
      startDate = now.subtract(const Duration(days: 6));
    } else if (p == '30d') {
      startDate = now.subtract(const Duration(days: 29));
    } else if (p == 'yesterday') {
      final y = now.subtract(const Duration(days: 1));
      startDate = DateTime(y.year, y.month, y.day);
    } else {
      startDate = DateTime(now.year, now.month, now.day);
    }
    final report = _offlineDb.computeLocalBusinessReport(
      startDate: startDate,
      endDate: now,
    );
    final fraud = Map<String, dynamic>.from((report['fraud_indicators'] as Map?) ?? {});
    final receivables = _offlineDb.getLocalReceivables();
    final localShift = _offlineDb.getCurrentLocalShift();
    final expiring = context
        .read<PosCubit>()
        .state
        .allProducts
        .where((p) => p.hasExpiringSoonBatch)
        .length;

    if (!mounted) return;
    setState(() {
      _todaySales = (report['net_sales'] as num?)?.toDouble() ?? 0;
      _todayTxCount = (report['transactions_count'] as num?)?.toInt() ?? 0;
      _grossProfit = (report['gross_profit'] as num?)?.toDouble() ?? 0;
      _growthPercent = 0;
      _growthLabel = _selectedPeriod == 'month' ? 'vs bln lalu' : 'vs kemarin';
      _totalReceivables = (report['total_receivables'] as num?)?.toDouble() ?? 0;
      _totalPayables = (report['total_payables'] as num?)?.toDouble() ?? 0;
      _lowStockCount = (report['low_stock_count'] as num?)?.toInt() ?? 0;
      _expiringCount = expiring;
      _pendingOnlineOrdersCount = 0;
      _voidCount = (fraud['void_count'] as num?)?.toInt() ?? 0;
      _varianceShiftsCount = (fraud['variance_shifts_count'] as num?)?.toInt() ?? 0;
      _hasOpenShift = localShift != null;
      _shiftBlindDropEnforced = true;
      _shiftTerminalLabel = localShift != null ? 'Kasir Mandiri Lokal' : '';
      _overdueReceivables = receivables;
      _tasksList = const [];
      _approvalsList = const [];
      _offlineConflictsList = const [];
      _openTasksCount = 0;
      _pendingApprovalsCount = 0;
      _lastStoreId = storeId ?? context.read<AuthCubit>().state.session.activeStore.id;
      _error = null;
      _loading = false;
    });
  }


  Future<Response<dynamic>?> _safeGet(
    String path, {
    Map<String, dynamic>? queryParameters,
    void Function(Object err)? onFatalError,
  }) async {
    try {
      return await _backofficeRepo.getEndpoint(path, queryParameters: queryParameters);
    } catch (e) {
      if (onFatalError != null) {
        onFatalError(e);
      }
      return null;
    }
  }


  Future<void> _loadDashboard({int? storeId, String? period}) {
    if (_activeLoadFuture != null) {
      return _activeLoadFuture!;
    }
    final future = _executeDashboardLoad(storeId: storeId, period: period);
    _activeLoadFuture = future;
    future.whenComplete(() {
      if (identical(_activeLoadFuture, future)) {
        _activeLoadFuture = null;
      }
    });
    return future;
  }


  Future<void> _executeDashboardLoad({int? storeId, String? period}) async {
    final activePeriod = period ?? _selectedPeriod;
    if (period != null && period != _selectedPeriod) {
      _selectedPeriod = period;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final session = context.read<AuthCubit>().state.session;
    if (session.isLocalTrial || !(await _connectivity.checkOnline())) {
      _applyLocalDashboardMetrics(storeId: storeId, period: activePeriod);
      return;
    }

    final workspace = _effectiveWorkspace(session);
    final activeStoreId = storeId ?? session.activeStore.id;
    final params = <String, dynamic>{'period': activePeriod};
    if (activeStoreId > 0) {
      params['store_id'] = activeStoreId;
    }

    final shouldFetchOwner = MobileWorkspaceResolver.canViewOwnerDashboard(session);
    final shouldFetchApprovals = MobileWorkspaceResolver.canViewApprovals(session);
    final shouldFetchConflicts = MobileWorkspaceResolver.canUsePos(session);
    final shouldFetchReceivables = MobileWorkspaceResolver.canViewReceivables(session) &&
        workspace != MobileWorkspaceRole.warehouseWorkbench &&
        workspace != MobileWorkspaceRole.employeeEss;
    final shouldFetchShift = MobileWorkspaceResolver.canUsePos(session);

    Object? primaryError;

    // PARALLELIZED BATCH (`Future.wait`) — Eliminates serial API round-trips
    final futures = <Future<Response<dynamic>?>>[
      shouldFetchOwner
          ? _safeGet(
              ApiEndpoints.ownerDashboard,
              queryParameters: params,
              onFatalError: (e) => primaryError = e,
            )
          : Future.value(null),
      _safeGet(ApiEndpoints.tasks),
      shouldFetchApprovals ? _safeGet(ApiEndpoints.approvals) : Future.value(null),
      shouldFetchConflicts ? _safeGet(ApiEndpoints.offlineConflicts) : Future.value(null),
      shouldFetchReceivables
          ? _safeGet(ApiEndpoints.receivables, queryParameters: params)
          : Future.value(null),
      shouldFetchShift ? _safeGet(ApiEndpoints.currentShift) : Future.value(null),
    ];

    final responses = await Future.wait(futures);
    if (!mounted) return;

    final ownerRes = responses[0];
    final tasksRes = responses[1];
    final approvalsRes = responses[2];
    final conflictsRes = responses[3];
    final receivablesRes = responses[4];
    final shiftRes = responses[5];

    // If owner dashboard failed catastrophically AND no other endpoint succeeded, handle gracefully
    if (shouldFetchOwner && ownerRes == null && primaryError != null && tasksRes == null) {
      if (_offlineDb.getCachedProducts().isNotEmpty ||
          _offlineDb.getLocalSalesHistory().isNotEmpty) {
        _applyLocalDashboardMetrics(storeId: storeId);
        return;
      }
      setState(() {
        _error = ApiClient.extractErrorMessage(primaryError!);
        _loading = false;
      });
      return;
    }

    final rawOwnerData = ownerRes?.data is Map ? ownerRes!.data['data'] : null;
    final ownerData = rawOwnerData is Map
        ? Map<String, dynamic>.from(rawOwnerData)
        : <String, dynamic>{};
    final kpi = ownerData['kpi'] is Map
        ? Map<String, dynamic>.from(ownerData['kpi'] as Map)
        : <String, dynamic>{};
    final alerts = ownerData['operational_alerts'] is Map
        ? Map<String, dynamic>.from(ownerData['operational_alerts'] as Map)
        : <String, dynamic>{};
    final rawAudit = ownerData['anti_fraud_summary'] ?? ownerData['audit_watch'];
    final auditWatch = rawAudit is Map
        ? Map<String, dynamic>.from(rawAudit)
        : <String, dynamic>{};

    final tasksList = <Map<String, dynamic>>[];
    if (tasksRes?.data is Map && tasksRes!.data['data'] is List) {
      final raw = tasksRes.data['data'] as List<dynamic>;
      for (final item in raw) {
        if (item is Map) tasksList.add(Map<String, dynamic>.from(item));
      }
    }

    final approvalsList = <Map<String, dynamic>>[];
    if (approvalsRes?.data is Map && approvalsRes!.data['data'] is List) {
      final raw = approvalsRes.data['data'] as List<dynamic>;
      for (final item in raw) {
        if (item is Map) approvalsList.add(Map<String, dynamic>.from(item));
      }
    }

    final conflictsList = <Map<String, dynamic>>[];
    if (conflictsRes?.data is Map && conflictsRes!.data['data'] is List) {
      final raw = conflictsRes.data['data'] as List<dynamic>;
      for (final item in raw) {
        if (item is Map) conflictsList.add(Map<String, dynamic>.from(item));
      }
    }

    final overdueList = <Map<String, dynamic>>[];
    if (receivablesRes?.data is Map) {
      final rawData = receivablesRes!.data['data'];
      final rawList = rawData is List
          ? rawData
          : (rawData is Map && rawData['items'] is List
              ? rawData['items'] as List
              : const <dynamic>[]);
      for (final raw in rawList) {
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);
          final dueAmt = ((map['balance_due'] ??
                  map['remaining_amount'] ??
                  map['amount'] ??
                  0) as num)
              .toDouble();
          if (dueAmt > 0) overdueList.add(map);
        }
      }
    }

    bool hasOpenShift = false;
    bool blindDropEnforced = true;
    String shiftTerminal = '';
    final rawShiftData = shiftRes?.data is Map ? shiftRes!.data['data'] : null;
    if (rawShiftData is Map) {
      final sData = Map<String, dynamic>.from(rawShiftData);
      hasOpenShift = sData['has_open_shift'] == true && sData['shift'] is Map;
      blindDropEnforced = sData['blind_drop_enforced'] == true;
      if (hasOpenShift) {
        final sMap = Map<String, dynamic>.from(sData['shift'] as Map);
        final term = sMap['terminal'] as Map?;
        shiftTerminal = (term?['name'] ?? 'POS Utama').toString();
      }
    }

    setState(() {
      _todaySales = (kpi['net_sales'] as num?)?.toDouble() ?? 0;
      _todayTxCount = (kpi['transactions_count'] as num?)?.toInt() ?? 0;
      _grossProfit = (kpi['gross_profit'] as num?)?.toDouble() ?? 0;
      _growthPercent = ((kpi['growth_percent'] ?? kpi['growth_vs_yesterday_percent']) as num?)?.toDouble() ?? 0;
      _growthLabel = (kpi['growth_label'] as String?) ?? (_selectedPeriod == 'month' ? 'vs bln lalu' : 'vs kemarin');
      _totalReceivables = (alerts['receivables_total'] as num?)?.toDouble() ?? 0;
      _totalPayables = (alerts['payables_total'] as num?)?.toDouble() ?? 0;
      _lowStockCount = (alerts['low_stock_count'] as num?)?.toInt() ?? 0;
      _expiringCount = (alerts['expiring_batches_count'] as num?)?.toInt() ?? 0;
      _pendingOnlineOrdersCount =
          (alerts['pending_online_orders_count'] as num?)?.toInt() ?? 0;
      _voidCount = ((auditWatch['voided_sales_count'] ?? auditWatch['void_count']) as num?)
              ?.toInt() ??
          0;
      _varianceShiftsCount =
          ((auditWatch['shift_variance_alerts_count'] ?? auditWatch['variance_shifts_count'])
                      as num?)
                  ?.toInt() ??
              0;
      _hasOpenShift = hasOpenShift;
      _shiftBlindDropEnforced = blindDropEnforced;
      _shiftTerminalLabel = shiftTerminal;
      _overdueReceivables = overdueList;
      _tasksList = tasksList;
      _approvalsList = approvalsList;
      _offlineConflictsList = conflictsList;
      _openTasksCount = tasksList.length;
      _pendingApprovalsCount = approvalsList.length;
      _lastStoreId = activeStoreId;
      _error = null;
      _loading = false;
    });
  }


  Widget _buildWorkspaceSwitcherStrip(
    NusaThemeTokens tokens,
    MobileWorkspaceRole current,
  ) {
    return SizedBox(
      key: const Key('workspace_switcher_strip'),
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final role in MobileWorkspaceResolver.operationalWorkspaces) ...[
            NusaPillFilter(
              key: Key('workspace_chip_${role.name}'),
              label: MobileWorkspaceResolver.specFor(role).title,
              icon: MobileWorkspaceResolver.specFor(role).icon,
              selected: role == current,
              onTap: () => widget.onSelectWorkspace?.call(role),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }


  Widget _buildOwnerPulseWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    int lowStock,
    int expiring,
  ) {
    return Column(
      key: const Key('workspace_owner_pulse'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.ownerPulse),
        const SizedBox(height: 12),
        _buildPrimaryActionStrip(context, tokens, posState.capabilities),
        const SizedBox(height: 14),
        _buildExecutivePulseCard(context, tokens),
        const SizedBox(height: 12),
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.ownerPulse),
        const SizedBox(height: 12),
        _buildQuickActionSpeedDial(context, tokens, session),
        const SizedBox(height: 12),
        _buildOperationalMetricsGrid(context, tokens, lowStock, expiring),
        const SizedBox(height: 12),
        _buildAllModulesBanner(context, tokens),
        const SizedBox(height: 18),
        Text(
          'Direktori Operasional Toko',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Akses 1-ketuk seluruh alur kerja kasir, stok, piutang & kontrol cabang.',
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        const SizedBox(height: 12),
        _buildModulesDirectory(context, tokens, posState.capabilities),
      ],
    );
  }


  Widget _buildManagerDeskWorkspace(
    BuildContext context,
    NusaThemeTokens tokens,
    AuthSessionModel session,
    PosState posState,
    String displayName,
    int lowStock,
    int expiring,
    List<Map<String, dynamic>> mergedConflicts,
  ) {
    final canViewProfit = MobileWorkspaceResolver.canViewProfit(session);
    final canUsePos = MobileWorkspaceResolver.canUsePos(session);
    final canViewShifts = MobileWorkspaceResolver.canViewShifts(session);
    final canViewReports = MobileWorkspaceResolver.canViewOwnerDashboard(session);
    return Column(
      key: const Key('workspace_manager_desk'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOperatorStrip(tokens, session, displayName, MobileWorkspaceRole.managerDesk),
        const SizedBox(height: 12),
        if (canUsePos || canViewShifts) ...[
          _buildPrimaryActionStrip(context, tokens, posState.capabilities),
          const SizedBox(height: 12),
        ] else if (canViewReports) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/reports'),
              style: ElevatedButton.styleFrom(
                backgroundColor: tokens.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.analytics_rounded, size: 20),
              label: const Text(
                'Buka Laporan & Audit Terpadu',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Action-first Operational Queue Strip
        NusaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Antrean Pengawasan Cabang',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NusaBadge(
                    label: '${_pendingApprovalsCount + _openTasksCount + _varianceShiftsCount} Item',
                    variant: (_pendingApprovalsCount + _varianceShiftsCount) > 0
                        ? NusaBadgeVariant.warning
                        : NusaBadgeVariant.success,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: MobileWorkspaceResolver.canViewApprovals(session)
                          ? () => context.push('/approvals')
                          : null,
                      borderRadius: BorderRadius.circular(10),
                      child: _compactStatChip(
                        tokens,
                        label: 'Approval',
                        value: '$_pendingApprovalsCount',
                        accent: tokens.warning,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactStatChip(
                      tokens,
                      label: 'Tugas',
                      value: '$_openTasksCount',
                      accent: tokens.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _compactStatChip(
                      tokens,
                      label: 'Selisih Shift',
                      value: '$_varianceShiftsCount',
                      accent: _varianceShiftsCount > 0 ? tokens.danger : tokens.positive,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (canViewReports) ...[
          _buildExecutivePulseCard(context, tokens),
          const SizedBox(height: 12),
        ],
        _buildCopilotBanner(context, tokens, session, MobileWorkspaceRole.managerDesk),
        const SizedBox(height: 12),
        if (canViewProfit)
          _buildOperationalMetricsGrid(context, tokens, lowStock, expiring)
        else
          Row(
            children: [
              Expanded(
                child: _buildOperationalMetricTile(
                  tokens,
                  icon: Icons.inventory_2_outlined,
                  accentColor: (lowStock + expiring) > 0 ? tokens.danger : tokens.positive,
                  label: 'Stok Menipis & FEFO',
                  value: '$lowStock Menipis • $expiring FEFO',
                  onTap: () => widget.onSwitchTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildOperationalMetricTile(
                  tokens,
                  icon: Icons.sync_problem_outlined,
                  accentColor: mergedConflicts.isNotEmpty ? tokens.danger : tokens.positive,
                  label: 'Konflik & Order Online',
                  value: '${mergedConflicts.length} Konflik • $_pendingOnlineOrdersCount Web',
                  onTap: () => context.push('/online-orders'),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        _buildQuickActionSpeedDial(context, tokens, session),
      ],
    );
  }
}
