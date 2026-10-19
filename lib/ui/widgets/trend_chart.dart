import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../services/analytics.dart';

class TrendSeries {
  const TrendSeries(this.label, this.color, this.values, {this.dashed = false});

  final String label;
  final Color color;
  final List<double> values;
  final bool dashed;
}

/// Line chart over [periods] sharing one money axis, with a legend and a
/// touch tooltip listing every series at that point.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.periods,
    required this.series,
    required this.currency,
  });

  final List<Period> periods;
  final List<TrendSeries> series;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (periods.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Pick a longer date range to see a trend.')),
      );
    }
    final daily = periods.length > 1 && periods[1].start.difference(periods[0].start).inDays == 1;
    final labelFmt = daily ? DateFormat('d MMM') : DateFormat('MMM yy');
    final tooltipFmt = daily ? DateFormat('EEE d MMM') : DateFormat('MMMM yyyy');
    final maxY = series.expand((s) => s.values).fold<double>(0, math.max);
    final niceMax = maxY <= 0 ? 1.0 : _niceCeil(maxY);
    final labelEvery = math.max(1, (periods.length / 5).ceil());
    final muted = theme.colorScheme.onSurfaceVariant;
    final grid = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final s in series)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 14, height: 3, color: s.color),
                const SizedBox(width: 6),
                Text(s.label, style: theme.textTheme.bodySmall),
              ]),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: niceMax,
              minX: 0,
              maxX: (periods.length - 1).toDouble(),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: niceMax / 4,
                getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: niceMax / 4,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(NumberFormat.compact().format(v),
                          style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 28,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i != v || i % labelEvery != 0 || i >= periods.length) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(labelFmt.format(periods[i].start),
                            style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                getTouchedSpotIndicator: (bar, indexes) => [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(
                      FlLine(color: muted, strokeWidth: 1),
                      FlDotData(
                        getDotPainter: (spot, _, bar, _) => FlDotCirclePainter(
                          radius: 4,
                          color: bar.color ?? muted,
                          strokeWidth: 2,
                          strokeColor: theme.colorScheme.surface,
                        ),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 200,
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  getTooltipItems: (spots) {
                    final style = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onInverseSurface);
                    return [
                      for (var j = 0; j < spots.length; j++)
                        LineTooltipItem(
                          '${j == 0 ? '${tooltipFmt.format(periods[spots[j].x.round()].start)}\n' : ''}'
                          '${series[spots[j].barIndex].label}: ${compactMoney(spots[j].y, currency)}',
                          style,
                          textAlign: TextAlign.left,
                        ),
                    ];
                  },
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [for (var i = 0; i < s.values.length; i++) FlSpot(i.toDouble(), s.values[i])],
                    color: s.color,
                    barWidth: 2,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    dashArray: s.dashed ? [6, 4] : null,
                    dotData: FlDotData(show: periods.length <= 12),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _niceCeil(double v) {
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (m * exp >= v) return m * exp;
    }
    return 10 * exp;
  }
}
