import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';

/// LAYAR 8 — LAPORAN BISNIS & OWNER COMMAND CENTER (TAB 4 NAVIGASI)
/// Matches 1:1 with Screen 7 of `Papan Konsep UI KasirKu Modern-1.png` + Full Cloud Owner Parity
class BusinessReportsScreen extends StatefulWidget {
  const BusinessReportsScreen({super.key});

  @override
  State<BusinessReportsScreen> createState() => _BusinessReportsScreenState();
}

class _BusinessReportsScreenState extends State<BusinessReportsScreen> {
  String _selectedDateRange = '1 – 31 Okt 2026';
  String _selectedStoreScope = 'Semua Cabang';
  int _activeTabIndex = 0; // 0: Ringkasan, 1: Penjualan, 2: Laba Rugi

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          // Multi-Branch Consolidation Selector for Owner
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedStoreScope,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.primary),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
                items: const [
                  DropdownMenuItem(value: 'Semua Cabang', child: Text('🏢 Semua Cabang')),
                  DropdownMenuItem(value: 'Toko Kemang', child: Text('📍 Toko Kemang')),
                  DropdownMenuItem(value: 'Cabang Bandung', child: Text('📍 Cabang Bandung')),
                ],
                onChanged: (v) => setState(() => _selectedStoreScope = v!),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Date Range Selector Pill ("📅 1 - 31 Okt 2026 v" Persis Mockup Screen 7)
            InkWell(
              onTap: _showDateRangeSheet,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      _selectedDateRange,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.slate600),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. Segmented Control Tabs: Ringkasan | Penjualan | Laba Rugi (Persis Mockup Screen 7)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0).withOpacity(0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildSegmentTab(0, 'Ringkasan'),
                  _buildSegmentTab(1, 'Penjualan'),
                  _buildSegmentTab(2, 'Laba Rugi'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. Main Total Penjualan Card with Sparkline Chart ("Rp 25.000.000 ↑ 15%" Persis Mockup Screen 7)
            _buildTotalPenjualanHeroCard(),
            const SizedBox(height: 14),

            // 4. 4 Grid Metric Cards (2x2: Laba Kotor, Piutang, Pembelian, Pengeluaran Persis Mockup Screen 7)
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.85,
              children: [
                _buildReportMetricTile(
                  icon: Icons.monetization_on_rounded,
                  iconColor: AppColors.success,
                  label: 'Laba Kotor',
                  value: 'Rp 8.500.000',
                ),
                _buildReportMetricTile(
                  icon: Icons.schedule_rounded,
                  iconColor: AppColors.warning,
                  label: 'Piutang',
                  value: 'Rp 1.200.000',
                ),
                _buildReportMetricTile(
                  icon: Icons.shopping_bag_rounded,
                  iconColor: AppColors.primary,
                  label: 'Pembelian',
                  value: 'Rp 10.000.000',
                ),
                _buildReportMetricTile(
                  icon: Icons.money_off_csred_rounded,
                  iconColor: AppColors.danger,
                  label: 'Pengeluaran',
                  value: 'Rp 2.500.000',
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 5. Section "Grafik Penjualan" (Persis Mockup Screen 7)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Grafik Penjualan',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                      ),
                      InkWell(
                        onTap: () => setState(() => _activeTabIndex = 2),
                        child: const Text(
                          'Lihat Detail →',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 150,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                            color: AppColors.border,
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              getTitlesWidget: (val, _) => Text(
                                '${val.toInt()}jt',
                                style: const TextStyle(fontSize: 10, color: AppColors.slate400),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (val, _) {
                                const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
                                final idx = val.toInt();
                                if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    days[idx],
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.slate500),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: const [
                              FlSpot(0, 2.4),
                              FlSpot(1, 3.1),
                              FlSpot(2, 2.8),
                              FlSpot(3, 3.9),
                              FlSpot(4, 3.5),
                              FlSpot(5, 4.6),
                              FlSpot(6, 4.9),
                            ],
                            isCurved: true,
                            color: AppColors.primary,
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.primary.withOpacity(0.14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 6. SAK EMKM Net Profit & Multi-Branch / Anti-Fraud Executive Cards
            _buildSakEmkmAndAntiFraudSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentTab(int index, String label) {
    final isSelected = _activeTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTabIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [const BoxShadow(color: Color(0x140F172A), blurRadius: 6, offset: Offset(0, 2))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? AppColors.primary : AppColors.slate600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTotalPenjualanHeroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Penjualan',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 13, color: AppColors.successDark),
                    SizedBox(width: 2),
                    Text(
                      '15%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.successDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Rp 25.000.000',
            style: AppTheme.moneyStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: CustomPaint(
              painter: _ReportSparklinePainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportMetricTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: AppTheme.moneyStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppColors.navyDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSakEmkmAndAntiFraudSection() {
    return Column(
      children: [
        // Laba Rugi Bersih SAK EMKM Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.executiveNavyGradient,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Laba Bersih Operasional (SAK EMKM)',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.success,
                    label: Text(
                      'Margin 24.0%',
                      style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              Text(
                IdrCurrencyFormatter.format(6000000),
                style: AppTheme.moneyStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'Rumus: Laba Kotor (Rp 8.500.000) − Pengeluaran Operasional (Rp 2.500.000)',
                style: TextStyle(color: Colors.white60, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Anti-Fraud Watch Card for Owner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.danger, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Radar Anti-Fraud & Pengawasan Kasir',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('• Transaksi Void / Batal Hari Ini:', style: TextStyle(fontSize: 12.5)),
                  Text('0 Nota (Aman)', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.successDark)),
                ],
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('• Selisih Kas Tutup Shift (Variance):', style: TextStyle(fontSize: 12.5)),
                  Text('Rp 0 (Sesuai)', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.successDark)),
                ],
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('• Buka Laci Tanpa Penjualan:', style: TextStyle(fontSize: 12.5)),
                  Text('1 Kali', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warningDark)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showDateRangeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pilih Periode Laporan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final range in ['Hari Ini', '7 Hari Terakhir', '1 – 31 Okt 2026', 'Bulan Ini (Nov 2026)'])
              ListTile(
                title: Text(range, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: _selectedDateRange == range
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _selectedDateRange = range);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final pts = [
      Offset(0, size.height * 0.8),
      Offset(size.width * 0.2, size.height * 0.45),
      Offset(size.width * 0.42, size.height * 0.6),
      Offset(size.width * 0.68, size.height * 0.25),
      Offset(size.width * 0.85, size.height * 0.35),
      Offset(size.width * 0.98, size.height * 0.1),
    ];

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, linePaint);

    for (final p in pts) {
      canvas.drawCircle(p, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
