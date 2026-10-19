import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/currency.dart';
import '../../services/analytics.dart';

/// A slice ready to draw: the share plus its color, or null key for the
/// folded "Other" slice.
class PieSlice {
  const PieSlice(this.share, this.color, {this.drillable = true});

  final Share share;
  final Color color;
  final bool drillable;
}

/// Donut chart with a legend that lists every slice's amount and percentage.
/// Tapping a slice or legend row calls [onTap] when it is drillable.
class BreakdownPie extends StatefulWidget {
  const BreakdownPie({
    super.key,
    required this.slices,
    required this.currency,
    this.onTap,
    this.centerLabel,
  });

  final List<PieSlice> slices;
  final String currency;
  final void Function(Share share)? onTap;
  final String? centerLabel;

  /// Keeps at most [maxSlices] - 1 shares and folds the rest into "Other",
  /// so no slice needs a color past the palette.
  static List<PieSlice> fold(List<Share> shares, Color Function(int i, Share s) colorOf, Color other,
      {int maxSlices = 8}) {
    if (shares.length <= maxSlices) {
      return [for (var i = 0; i < shares.length; i++) PieSlice(shares[i], colorOf(i, shares[i]))];
    }
    final keep = shares.take(maxSlices - 1).toList();
    final rest = shares.skip(maxSlices - 1);
    final otherShare = Share('_other', 'Other (${rest.length})', 0, 0);
    for (final s in rest) {
      otherShare.total += s.total;
      otherShare.count += s.count;
    }
    return [
      for (var i = 0; i < keep.length; i++) PieSlice(keep[i], colorOf(i, keep[i])),
      PieSlice(otherShare, other, drillable: false),
    ];
  }

  @override
  State<BreakdownPie> createState() => _BreakdownPieState();
}

class _BreakdownPieState extends State<BreakdownPie> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.slices.fold<double>(0, (a, s) => a + s.share.total);
    if (total <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Nothing in this range yet.')),
      );
    }
    final touched = _touched != null && _touched! < widget.slices.length ? widget.slices[_touched!] : null;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 58,
                  startDegreeOffset: -90,
                  sections: [
                    for (var i = 0; i < widget.slices.length; i++)
                      PieChartSectionData(
                        value: widget.slices[i].share.total,
                        color: widget.slices[i].color,
                        radius: i == _touched ? 40 : 34,
                        showTitle: false,
                      ),
                  ],
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      final i = response?.touchedSection?.touchedSectionIndex;
                      if (event is FlTapUpEvent && i != null && i >= 0) {
                        final s = widget.slices[i];
                        if (s.drillable) widget.onTap?.call(s.share);
                        return;
                      }
                      if (!event.isInterestedForInteractions) {
                        if (_touched != null) setState(() => _touched = null);
                        return;
                      }
                      final next = (i != null && i >= 0) ? i : null;
                      if (next != _touched) setState(() => _touched = next);
                    },
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    touched?.share.label ?? widget.centerLabel ?? 'Total',
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    compactMoney(touched?.share.total ?? total, widget.currency),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (touched != null)
                    Text('${(touched.share.total / total * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final s in widget.slices)
          InkWell(
            onTap: s.drillable && widget.onTap != null ? () => widget.onTap!(s.share) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.share.count > 1 ? '${s.share.label}  ·  ${s.share.count}' : s.share.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(formatMoney(s.share.total, widget.currency), style: theme.textTheme.bodyMedium),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(s.share.total / total * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  SizedBox(
                    width: 20,
                    child: s.drillable && widget.onTap != null
                        ? Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant)
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
