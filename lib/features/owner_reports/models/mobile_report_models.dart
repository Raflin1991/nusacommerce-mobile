part of 'mobile_report_catalog.dart';

/// Definition of a single Cloud-parity report inside the Mobile 50-Report BI Center.
class MobileReportDefinition {
  final String id;
  final String categoryCode;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> permissions;
  final List<String> keywords;
  final String dateMode; // 'range' | 'as_of' | 'snapshot'
  final bool supportsOfflineLocal;
  final bool isNew;

  const MobileReportDefinition({
    required this.id,
    required this.categoryCode,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.permissions,
    this.keywords = const [],
    this.dateMode = 'range',
    this.supportsOfflineLocal = false,
    this.isNew = false,
  });

  bool matchesQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q) ||
        id.toLowerCase().contains(q)) {
      return true;
    }
    return keywords.any((k) => k.toLowerCase().contains(q));
  }
}

/// Grouping category inside the Mobile 50-Report BI Hub (8 business-cycle categories).
class MobileReportCategory {
  final String code;
  final String title;
  final String shortTitle;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<MobileReportDefinition> reports;

  const MobileReportCategory({
    required this.code,
    required this.title,
    required this.shortTitle,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.reports,
  });

  MobileReportCategory copyWithReports(List<MobileReportDefinition> next) {
    return MobileReportCategory(
      code: code,
      title: title,
      shortTitle: shortTitle,
      subtitle: subtitle,
      icon: icon,
      accentColor: accentColor,
      reports: next,
    );
  }
}

class MobileReportKpi {
  final String label;
  final String formatted;
  final num? numericValue;
  final String type; // 'currency' | 'count' | 'percent' | 'text'
  final String tone; // 'positive' | 'warning' | 'danger' | 'neutral'
  final double? trendPercent;

  const MobileReportKpi({
    required this.label,
    required this.formatted,
    this.numericValue,
    this.type = 'text',
    this.tone = 'neutral',
    this.trendPercent,
  });

  factory MobileReportKpi.fromJson(Map<String, dynamic> json) {
    final rawVal = json['value'];
    return MobileReportKpi(
      label: (json['label'] ?? '-').toString(),
      formatted: (json['formatted'] ?? rawVal ?? '-').toString(),
      numericValue: rawVal is num ? rawVal : num.tryParse(rawVal?.toString() ?? ''),
      type: (json['type'] ?? 'text').toString(),
      tone: (json['tone'] ?? 'neutral').toString(),
      trendPercent: (json['trend_pct'] as num?)?.toDouble(),
    );
  }
}

class MobileReportRowItem {
  final String title;
  final String subtitle;
  final String? badge;
  final String badgeTone;
  final String primaryValue;
  final double? primaryNumeric;
  final String? secondaryValue;
  final bool isSection;
  final bool isTotal;
  final String? phone;
  final Map<String, String> details;

  const MobileReportRowItem({
    required this.title,
    this.subtitle = '',
    this.badge,
    this.badgeTone = 'neutral',
    this.primaryValue = '',
    this.primaryNumeric,
    this.secondaryValue,
    this.isSection = false,
    this.isTotal = false,
    this.phone,
    this.details = const {},
  });

  factory MobileReportRowItem.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'];
    final detailMap = <String, String>{};
    if (rawDetails is Map) {
      rawDetails.forEach((k, v) {
        detailMap[k.toString()] = (v ?? '-').toString();
      });
    }
    return MobileReportRowItem(
      title: (json['title'] ?? '-').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      badge: json['badge']?.toString(),
      badgeTone: (json['badge_tone'] ?? 'neutral').toString(),
      primaryValue: (json['primary_value'] ?? '').toString(),
      primaryNumeric: (json['primary_numeric'] as num?)?.toDouble(),
      secondaryValue: json['secondary_value']?.toString(),
      isSection: json['is_section'] == true,
      isTotal: json['is_total'] == true,
      phone: json['phone']?.toString(),
      details: detailMap,
    );
  }

  bool matchesSearch(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q) ||
        primaryValue.toLowerCase().contains(q) ||
        (badge?.toLowerCase().contains(q) ?? false)) {
      return true;
    }
    return details.values.any((v) => v.toLowerCase().contains(q));
  }
}

class MobileReportPayload {
  final String reportId;
  final String title;
  final String subtitle;
  final String dateMode;
  final String storeLabel;
  final String periodLabel;
  final String startDate;
  final String endDate;
  final List<MobileReportKpi> kpis;
  final List<String> columns;
  final List<MobileReportRowItem> items;
  final int totalRows;
  final String whatsappSummary;
  final String csvContent;
  final bool isOfflineData;
  final String? lastSyncLabel;
  final String? offlineNotice;

  const MobileReportPayload({
    required this.reportId,
    required this.title,
    required this.subtitle,
    required this.dateMode,
    required this.storeLabel,
    required this.periodLabel,
    required this.startDate,
    required this.endDate,
    required this.kpis,
    required this.columns,
    required this.items,
    required this.totalRows,
    required this.whatsappSummary,
    required this.csvContent,
    this.isOfflineData = false,
    this.lastSyncLabel,
    this.offlineNotice,
  });

  factory MobileReportPayload.fromApiJson(
    Map<String, dynamic> data, {
    required String periodLabel,
  }) {
    final filter = data['filter'] is Map
        ? Map<String, dynamic>.from(data['filter'] as Map)
        : const <String, dynamic>{};
    final rawKpis = (data['kpis'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => MobileReportKpi.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final rawItems = (data['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => MobileReportRowItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final cols = (data['columns'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    return MobileReportPayload(
      reportId: (data['report_id'] ?? '').toString(),
      title: (data['title'] ?? 'Laporan').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      dateMode: (data['date_mode'] ?? 'range').toString(),
      storeLabel: (filter['store_label'] ?? 'Semua Cabang').toString(),
      periodLabel: periodLabel,
      startDate: (filter['start_date'] ?? '').toString(),
      endDate: (filter['end_date'] ?? '').toString(),
      kpis: rawKpis,
      columns: cols,
      items: rawItems,
      totalRows: (data['total_rows'] as num?)?.toInt() ?? rawItems.length,
      whatsappSummary: (data['whatsapp_summary'] ?? '').toString(),
      csvContent: (data['csv_content'] ?? '').toString(),
      isOfflineData: false,
    );
  }
}

/// Single Source of Truth for the Mobile 50-Report BI Catalog — 1:1 parity with
/// Cloud `App\Support\ReportCatalog` (50 reports across 8 business-cycle categories)
/// plus dedicated `oversold` quick-audit definition.
