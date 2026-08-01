import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/themes/colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/product_labels.dart';
import '../../providers/stats_providers.dart';
import '../widgets/empty_state.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final period = ref.watch(statsPeriodProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [
          SegmentedButton<StatsPeriod>(
            segments: [
              for (final p in StatsPeriod.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {period},
            onSelectionChanged: (s) =>
                ref.read(statsPeriodProvider.notifier).state = s.first,
          ),
          const SizedBox(height: 16),
          if (stats.total == 0)
            const EmptyState(
              icon: Icons.insights_outlined,
              title: 'Пока нет данных',
              message:
                  'Отмечайте продукты как съеденные или выброшенные — здесь появится статистика.',
            )
          else ...[
            _SavedRateCard(stats: stats),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MoneyCard(
                    title: 'Сэкономлено',
                    value: stats.savedMoney,
                    color: AppColors.freshGreen,
                    icon: Icons.savings_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MoneyCard(
                    title: 'Потеряно',
                    value: stats.lostMoney,
                    color: AppColors.criticalRed,
                    icon: Icons.money_off,
                  ),
                ),
              ],
            ),
            if (stats.timeline.length > 1) ...[
              const SizedBox(height: 16),
              _TimelineCard(stats: stats),
            ],
            if (stats.byCategory.isNotEmpty) ...[
              const SizedBox(height: 16),
              _CategoryCard(stats: stats),
            ],
          ],
        ],
      ),
    );
  }
}

class _SavedRateCard extends StatelessWidget {
  const _SavedRateCard({required this.stats});

  final StatsData stats;

  @override
  Widget build(BuildContext context) {
    final rate = (stats.savedRate * 100).round();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: 2,
                      centerSpaceRadius: 32,
                      sections: [
                        PieChartSectionData(
                          value: stats.consumed.toDouble(),
                          color: AppColors.freshGreen,
                          radius: 14,
                          showTitle: false,
                        ),
                        PieChartSectionData(
                          value: stats.wasted.toDouble(),
                          color: AppColors.criticalRed,
                          radius: 14,
                          showTitle: false,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$rate%',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Спасено от мусорки',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _Legend(
                    color: AppColors.freshGreen,
                    label: 'Съедено',
                    value: stats.consumed,
                  ),
                  const SizedBox(height: 4),
                  _Legend(
                    color: AppColors.criticalRed,
                    label: 'Выброшено',
                    value: stats.wasted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        Text('$value', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final double value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(
              '${value.toStringAsFixed(0)} ₽',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.stats});

  final StatsData stats;

  @override
  Widget build(BuildContext context) {
    final points = stats.timeline;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 14),
              child: Text(
                'Динамика',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData:
                      const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: _labelInterval(points.length),
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              AppDateUtils.shortDate(points[index].date),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: true, reservedSize: 28),
                    ),
                  ),
                  lineBarsData: [
                    _line(points.map((p) => p.consumed).toList(),
                        AppColors.freshGreen),
                    _line(points.map((p) => p.wasted).toList(),
                        AppColors.criticalRed),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _labelInterval(int pointCount) {
    if (pointCount <= 7) return 2;
    if (pointCount <= 31) return 7;
    return 90;
  }

  LineChartBarData _line(List<int> values, Color color) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < values.length; i++)
          FlSpot(i.toDouble(), values[i].toDouble()),
      ],
      isCurved: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.stats});

  final StatsData stats;

  @override
  Widget build(BuildContext context) {
    final entries = stats.byCategory.entries.take(6).toList();
    final max = entries.first.value;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Чаще всего выбрасываем',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            for (final e in entries) ...[
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      ProductLabels.category(e.key),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: e.value / max,
                        minHeight: 8,
                        backgroundColor:
                            AppColors.criticalRed.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.criticalRed,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('${e.value}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
