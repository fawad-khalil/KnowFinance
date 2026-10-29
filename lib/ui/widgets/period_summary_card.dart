import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/currency.dart';
import '../../models/entry_filter.dart';
import '../chart_colors.dart';

/// "Left this month" etc., following the active date filter.
String leftLabel(DatePreset preset) => switch (preset) {
      DatePreset.thisMonth => 'Left this month',
      DatePreset.lastMonth => 'Left last month',
      DatePreset.last3Months => 'Left in the last 3 months',
      DatePreset.thisYear => 'Left this year',
      DatePreset.allTime => 'Left overall',
      DatePreset.custom => 'Left in this period',
    };

/// Income, spending and what's left for the filtered entries: a ring showing
/// the share of income spent next to the net amount. Tap for exact figures.
class PeriodSummaryCard extends StatelessWidget {
  const PeriodSummaryCard({
    super.key,
    required this.income,
    required this.expense,
    required this.loansIn,
    required this.loansOut,
    required this.home,
    required this.label,
    this.missing = 0,
  });

  final double income, expense, loansIn, loansOut;
  final String home;
  final String label;

  /// Entries without a rate into [home], left out of the totals.
  final int missing;

  double get net => income - expense;

  /// Share of income spent, or null when there's no income to compare with.
  double? get spentShare => income > 0 ? expense / income : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final share = spentShare;
    final loans = [
      if (loansOut > 0) 'Loans out ${formatMoneyShort(loansOut, home)}',
      if (loansIn > 0) 'Loans in ${formatMoneyShort(loansIn, home)}',
    ];

    Widget flow(IconData icon, Color color, String name, double v) => Semantics(
          label: '$name ${formatMoney(v, home)}',
          excludeSemantics: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 2),
            Text(formatMoneyShort(v, home),
                style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w500)),
          ]),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Semantics(
                  label: share == null ? 'No income to compare spending with' : '${(share * 100).round()}% of income spent',
                  excludeSemantics: true,
                  child: SpentRing(share: share, track: _trackColor(theme), arc: colors.expense),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 12, color: muted)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(formatSignedMoney(net, home),
                            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(height: 4),
                      Wrap(spacing: 16, runSpacing: 4, children: [
                        flow(Icons.south_west, colors.income, 'Income', income),
                        flow(Icons.north_east, colors.expense, 'Expenses', expense),
                      ]),
                      if (loans.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final l in loans)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(l, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                            ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ]),
              if (missing > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$missing ${missing == 1 ? 'entry needs' : 'entries need'} an exchange rate and '
                  '${missing == 1 ? "isn't" : "aren't"} counted.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Income blue at low emphasis.
  static Color _trackColor(ThemeData theme) =>
      theme.brightness == Brightness.dark ? const Color(0xFF2D3B4D) : const Color(0xFFC9D8E9);

  void _showDetails(BuildContext context) {
    final colors = ChartColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        Widget row(String name, String value, {Color? color, bool bold = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
                Text(value,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
              ]),
            );
        final share = spentShare;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                row('Income', formatMoney(income, home), color: colors.income),
                row('Expenses', formatMoney(expense, home), color: colors.expense),
                if (share != null) row('Share of income spent', '${(share * 100).round()}%'),
                const Divider(),
                row('Net', formatSignedMoney(net, home), bold: true),
                const SizedBox(height: 8),
                Text('Loans, not counted above', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                row('Loans in', formatMoney(loansIn, home)),
                row('Loans out', formatMoney(loansOut, home)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// An 84px ring: the arc is spending as a share of income, capped at a full
/// circle, with the real percentage in the middle ("112%" when over).
class SpentRing extends StatelessWidget {
  const SpentRing({super.key, required this.share, required this.track, required this.arc, this.size = 84});

  /// Null when there's no income: an empty ring and "—".
  final double? share;
  final Color track, arc;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = share;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(fraction: s == null ? 0 : s.clamp(0, 1).toDouble(), track: track, arc: arc),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s == null ? '—' : '${(s * 100).round()}%',
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w500, height: 1.1)),
            if (s != null)
              Text('spent',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontSize: 11, height: 1.1, color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.track, required this.arc});

  final double fraction;
  final Color track, arc;
  static const _stroke = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (fraction <= 0) return;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false,
        paint
          ..color = arc
          ..strokeCap = fraction >= 1 ? StrokeCap.butt : StrokeCap.round);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.track != track || old.arc != arc;
}
