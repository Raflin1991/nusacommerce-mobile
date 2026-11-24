// ignore_for_file: invalid_use_of_protected_member
part of 'mobile_report_detail_screen.dart';

extension _MobileReportDetailScreenStatePart2Ext on _MobileReportDetailScreenState {

  void _openItemDrillDown(MobileReportRowItem item) {
    final tokens = NusaThemeTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: tokens.borderDefault,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (item.badge != null && item.badge!.isNotEmpty)
                      _buildToneBadge(tokens, item.badge!, item.badgeTone),
                  ],
                ),
                if (item.primaryValue.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: tokens.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tokens.accent.withOpacity(0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Nilai Utama',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.primaryValue,
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.moneyStyle(
                              fontSize: 15.5,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in item.details.entries)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: tokens.borderSubtle),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 6,
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.right,
                                  style: AppTheme.moneyStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                            ],
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
                        onPressed: () async {
                          final summary = [
                            '📌 *${widget.definition.title}*',
                            'Item: ${item.title}',
                            ...item.details.entries
                                .map((e) => '• ${e.key}: ${e.value}'),
                          ].join('\n');
                          await Clipboard.setData(ClipboardData(text: summary));
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Rincian disalin ke clipboard.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text('Salin'),
                      ),
                    ),
                    if (item.phone != null && item.phone!.trim().isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: NusaThemeTokens.of(ctx).whatsapp,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await WhatsAppService.sendCustomMessage(
                              phone: item.phone!,
                              text:
                                  'Halo ${item.title}, terkait ${widget.definition.title} (${item.primaryValue}), mohon konfirmasinya. Terima kasih.',
                            );
                          },
                          icon: const Icon(Icons.chat_rounded, size: 17),
                          label: const Text('Hubungi WA'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Color _toneColor(NusaThemeTokens tokens, String tone) {
    switch (tone) {
      case 'positive':
        return tokens.positive;
      case 'warning':
        return tokens.warning;
      case 'danger':
        return tokens.danger;
      default:
        return tokens.textSecondary;
    }
  }


  Color _toneSoftBg(NusaThemeTokens tokens, String tone) {
    switch (tone) {
      case 'positive':
        return tokens.positiveSoft;
      case 'warning':
        return tokens.warningSoft;
      case 'danger':
        return tokens.dangerSoft;
      default:
        return tokens.bgElevated;
    }
  }


  Widget _buildToneBadge(NusaThemeTokens tokens, String text, String tone) {
    final fg = _toneColor(tokens, tone);
    final bg = _toneSoftBg(tokens, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }


  Widget _buildKpiCard(NusaThemeTokens tokens, MobileReportKpi kpi, {bool isCompact = false}) {
    final toneCol = _toneColor(tokens, kpi.tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: isCompact ? 6 : 8),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: toneCol,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  kpi.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
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
              kpi.formatted,
              maxLines: 1,
              style: AppTheme.moneyStyle(
                fontSize: isCompact ? 16 : 17,
                fontWeight: FontWeight.w800,
                color: kpi.tone == 'neutral' ? tokens.textPrimary : toneCol,
              ),
            ),
          ),
        ],
      ),
    );
  }


  bool _shouldShowVisualBars(List<MobileReportRowItem> items) {
    final numericRows = items
        .where((i) => !i.isSection && !i.isTotal && (i.primaryNumeric ?? 0) > 0)
        .toList();
    return numericRows.length >= 2 && numericRows.length <= 40;
  }


  Widget _buildTopBarsCard(
    NusaThemeTokens tokens,
    List<MobileReportRowItem> items,
  ) {
    final ranked = items
        .where((i) => !i.isSection && !i.isTotal && (i.primaryNumeric ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.primaryNumeric ?? 0).compareTo(a.primaryNumeric ?? 0));
    final top5 = ranked.take(5).toList();
    final maxVal = top5.first.primaryNumeric ?? 1.0;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top ${top5.length} Kontributor Terbesar',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final row in top5) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  row.primaryValue,
                  style: AppTheme.moneyStyle(
                    fontSize: 12,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ((row.primaryNumeric ?? 0) / (maxVal <= 0 ? 1 : maxVal))
                    .clamp(0.03, 1.0),
                minHeight: 6,
                backgroundColor: tokens.bgElevated,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }


  Widget _buildStackedRowCard(
    NusaThemeTokens tokens,
    MobileReportRowItem item,
  ) {
    if (item.isSection) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Text(
          item.title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: tokens.accent,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openItemDrillDown(item),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: item.isTotal ? tokens.accentSoft : tokens.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isTotal
                  ? tokens.accent.withOpacity(0.35)
                  : tokens.borderSubtle,
              width: tokens.borderWidth,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            item.isTotal ? FontWeight.w800 : FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    if (item.badge != null && item.badge!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildToneBadge(tokens, item.badge!, item.badgeTone),
                    ],
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 145),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.primaryValue.isNotEmpty) () {
                      Color valColor = item.isTotal ? tokens.accent : tokens.textPrimary;
                      if (item.primaryValue.startsWith('+')) {
                        valColor = NusaThemeTokens.of(context).positive;
                      } else if (item.primaryValue.startsWith('-')) {
                        valColor = NusaThemeTokens.of(context).danger;
                      }
                      return Text(
                        item.primaryValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTheme.moneyStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: valColor,
                        ),
                      );
                    }(),
                    if (item.secondaryValue != null &&
                        item.secondaryValue!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.secondaryValue!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
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
      ),
    );
  }
}
