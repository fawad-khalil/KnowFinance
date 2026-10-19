import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../services/analytics.dart';

enum HeatmapMetric {
  count('Transactions'),
  spending('Spending'),
  income('Income');

  const HeatmapMetric(this.label);
  final String label;

  double of(DayActivity? a) => switch (this) {
        HeatmapMetric.count => (a?.count ?? 0).toDouble(),
        HeatmapMetric.spending => a?.expense ?? 0,
        HeatmapMetric.income => a?.income ?? 0,
      };
}

/// A calendar heatmap like GitHub's: one column per week, one row per
/// weekday, darker for busier days. Tapping a day shows its totals.
class ActivityHeatmap extends StatefulWidget {
  const ActivityHeatmap({
    super.key,
    required this.days,
    required this.start,
    required this.end,
    required this.currency,
  });

  final Map<DateTime, DayActivity> days;
  final DateTime start;
  final DateTime end;
  final String currency;

  /// Cells shade in this many steps above empty.
  static const levels = 4;

  /// 0 for nothing, then 1..[levels] by share of the busiest day.
  static int levelOf(double v, double max) {
    if (v <= 0 || max <= 0) return 0;
    return (v / max * levels).ceil().clamp(1, levels);
  }

  @override
  State<ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<ActivityHeatmap> {
  var _metric = HeatmapMetric.count;
  DateTime? _selected;
  final _scroll = ScrollController();

  static const _gap = 3.0;
  static const _labelWidth = 30.0;

  @override
  void initState() {
    super.initState();
    // Long ranges scroll; start at the most recent weeks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _shade(ColorScheme scheme, int level) => level == 0
      ? scheme.surfaceContainerHighest
      : Color.lerp(scheme.primaryContainer, scheme.primary, (level - 1) / (ActivityHeatmap.levels - 1))!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    // Weeks start on Monday, like the reference layout.
    final first = DateTime(widget.start.year, widget.start.month, widget.start.day - (widget.start.weekday - 1));
    final last = DateTime(widget.end.year, widget.end.month, widget.end.day);
    final weeks = (last.difference(first).inDays ~/ 7) + 1;
    final max = widget.days.values.map(_metric.of).fold<double>(0, math.max);

    final selected = _selected == null ? null : widget.days[_selected];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<HeatmapMetric>(
          showSelectedIcon: false,
          segments: [for (final m in HeatmapMetric.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {_metric},
          onSelectionChanged: (s) => setState(() => _metric = s.first),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          // Fill the width when the range is short, otherwise keep cells
          // tappable and scroll.
          final fit = (c.maxWidth - _labelWidth) / weeks - _gap;
          final cell = fit.clamp(14.0, 28.0);
          final grid = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 16,
                child: Row(
                  children: [
                    for (var w = 0; w < weeks; w++)
                      SizedBox(
                        width: cell + _gap,
                        child: _monthLabel(first, w, muted),
                      ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var w = 0; w < weeks; w++)
                    Column(
                      children: [
                        for (var d = 0; d < 7; d++) _cell(first, w, d, cell, max, scheme),
                      ],
                    ),
                ],
              ),
            ],
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    for (var d = 0; d < 7; d++)
                      SizedBox(
                        height: cell + _gap,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: d.isEven ? Text(const ['Mon', '', 'Wed', '', 'Fri', '', 'Sun'][d], style: muted) : null,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: grid,
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _selected == null ? 'Tap a day for details' : _describe(_selected!, selected),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text('Less', style: muted),
            const SizedBox(width: 4),
            for (var l = 0; l <= ActivityHeatmap.levels; l++)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(color: _shade(scheme, l), borderRadius: BorderRadius.circular(2)),
              ),
            const SizedBox(width: 4),
            Text('More', style: muted),
          ],
        ),
      ],
    );
  }

  Widget? _monthLabel(DateTime first, int week, TextStyle? style) {
    final weekStart = DateTime(first.year, first.month, first.day + week * 7);
    final prev = DateTime(weekStart.year, weekStart.month, weekStart.day - 7);
    if (week != 0 && weekStart.month == prev.month) return null;
    return OverflowBox(
      alignment: Alignment.centerLeft,
      maxWidth: 40,
      child: Text(DateFormat('MMM').format(weekStart), style: style),
    );
  }

  Widget _cell(DateTime first, int week, int weekday, double size, double max, ColorScheme scheme) {
    final day = DateTime(first.year, first.month, first.day + week * 7 + weekday);
    final outside = day.isBefore(DateTime(widget.start.year, widget.start.month, widget.start.day)) || day.isAfter(widget.end);
    final level = ActivityHeatmap.levelOf(_metric.of(widget.days[day]), max);
    final isSelected = day == _selected;
    return Padding(
      padding: const EdgeInsets.only(right: _gap, bottom: _gap),
      child: GestureDetector(
        onTap: outside ? null : () => setState(() => _selected = isSelected ? null : day),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: outside ? Colors.transparent : _shade(scheme, level),
            borderRadius: BorderRadius.circular(size / 5),
            border: isSelected ? Border.all(color: scheme.onSurface, width: 2) : null,
          ),
        ),
      ),
    );
  }

  String _describe(DateTime day, DayActivity? a) {
    final date = DateFormat('EEE, d MMM yyyy').format(day);
    if (a == null) return '$date · nothing logged';
    final parts = [
      '${a.count} ${a.count == 1 ? 'transaction' : 'transactions'}',
      if (a.expense > 0) '${formatMoney(a.expense, widget.currency)} out',
      if (a.income > 0) '${formatMoney(a.income, widget.currency)} in',
    ];
    return '$date · ${parts.join(' · ')}';
  }
}
