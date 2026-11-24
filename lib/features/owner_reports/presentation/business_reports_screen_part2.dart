// ignore_for_file: invalid_use_of_protected_member
part of 'business_reports_screen.dart';

extension _BusinessReportsScreenStatePart2Ext on _BusinessReportsScreenState {

  Widget _buildExecutivePulseCard(NusaThemeTokens tokens, int antiFraudAlerts) {
    final isUp = _growthPercent >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _openReportById('sales-report'),
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Omzet Bersih ($_selectedDateRange)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (_growthPercent != 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isUp
                                    ? tokens.positiveSoft
                                    : tokens.dangerSoft,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${isUp ? '+' : ''}${_growthPercent.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isUp ? tokens.positive : tokens.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          IdrCurrencyFormatter.format(_netSales),
                          style: AppTheme.moneyStyle(
                            fontSize: 22,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '$_transactionsCount transaksi • Ketuk untuk rincian',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_trend7d.isNotEmpty)
                IconButton(
                  tooltip: _showTrendChart ? 'Sembunyikan Grafik' : 'Lihat Grafik Tren',
                  onPressed: () =>
                      setState(() => _showTrendChart = !_showTrendChart),
                  icon: Icon(
                    _showTrendChart
                        ? Icons.expand_less_rounded
                        : Icons.bar_chart_rounded,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDrillMetricPill(
                  tokens: tokens,
                  label: _profitVisible ? 'Laba Bersih' : 'Beban Toko',
                  value: IdrCurrencyFormatter.format(
                    _profitVisible ? _netProfit : _expensesTotal,
                  ),
                  badge: _profitVisible
                      ? '${_marginPercent.toStringAsFixed(1)}%'
                      : null,
                  accent: _profitVisible
                      ? (_netProfit >= 0 ? tokens.positive : tokens.danger)
                      : tokens.warning,
                  onTap: () => _openReportById(
                    _profitVisible ? 'profit-and-loss' : 'expenses-report',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDrillMetricPill(
                  tokens: tokens,
                  label: 'Piutang / AR',
                  value: IdrCurrencyFormatter.format(_receivablesTotal),
                  accent: _receivablesTotal > 0
                      ? tokens.warning
                      : tokens.textSecondary,
                  onTap: () => _openReportById('aged-receivables'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDrillMetricPill(
                  tokens: tokens,
                  label: 'Audit Kasir',
                  value: '$antiFraudAlerts isu',
                  accent: antiFraudAlerts > 0 ? tokens.danger : tokens.positive,
                  onTap: () => _openReportById('void-refund-audit'),
                ),
              ),
            ],
          ),
          if (_showTrendChart && _trend7d.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= _trend7d.length) {
                            return const SizedBox.shrink();
                          }
                          final lbl = (_trend7d[idx]['day_label'] ??
                                  _trend7d[idx]['date'] ??
                                  '')
                              .toString();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              lbl.length > 5 ? lbl.substring(lbl.length - 5) : lbl,
                              style: TextStyle(
                                fontSize: 9.5,
                                color: tokens.textTertiary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < _trend7d.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: ((_trend7d[i]['revenue'] ??
                                        _trend7d[i]['net_sales'] ??
                                        0) as num)
                                .toDouble(),
                            color: tokens.accent,
                            width: 14,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _buildDrillMetricPill({
    required NusaThemeTokens tokens,
    required String label,
    required String value,
    required Color accent,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
                if (badge != null)
                  Text(
                    badge,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTheme.moneyStyle(fontSize: 12.5, color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCategorySection(
    NusaThemeTokens tokens,
    MobileReportCategory category,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: category.accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  category.icon,
                  size: 17,
                  color: category.accentColor,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      category.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.bgElevated,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  '${category.reports.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (_, constraints) {
              final twoCol = constraints.maxWidth >= 620;
              if (!twoCol) {
                return Column(
                  children: [
                    for (final r in category.reports)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: _buildReportCard(tokens, category, r),
                      ),
                  ],
                );
              }
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: category.reports.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 74,
                ),
                itemBuilder: (_, idx) =>
                    _buildReportCard(tokens, category, category.reports[idx]),
              );
            },
          ),
        ],
      ),
    );
  }


  Widget _buildReportCard(
    NusaThemeTokens tokens,
    MobileReportCategory category,
    MobileReportDefinition report,
  ) {
    return InkWell(
      onTap: () => _openReport(report),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tokens.borderSubtle,
            width: tokens.borderWidth,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: category.accentColor.withOpacity(0.11),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                report.icon,
                size: 19,
                color: category.accentColor,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          report.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (_isOfflineMode && report.supportsOfflineLocal) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.positiveSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Offline',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.positive,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    report.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: tokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
