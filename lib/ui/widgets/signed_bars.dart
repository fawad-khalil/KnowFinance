import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/investments_screen.dart' show signedMoney;

/// Small bar chart of an amount per month or year, such as profit booked
/// or money saved; negative values hang below the zero line.
class SignedBars extends StatelessWidget {
  const SignedBars({super.key, required this.values, required this.currency});

  /// Period start and its amount, oldest first, with no gaps.
  final List<(DateTime, double)> values;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periods = [for (final (start, total) in values) (start: start, total: total)];
    final maxAbs = periods.map((p) => p.total.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    final hasLoss = periods.any((p) => p.total < 0);
    final yearly = periods.length > 1 && periods[1].start.month == periods[0].start.month;
    final fmt = yearly ? DateFormat('yyyy') : DateFormat('MMM');
    const height = 90.0;
    final every = (periods.length / 6).ceil().clamp(1, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: hasLoss ? height * 1.6 : height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in periods)
                Expanded(
                  child: Tooltip(
                    message:
                        '${(yearly ? DateFormat('yyyy') : DateFormat('MMMM yyyy')).format(p.start)}: '
                        '${signedMoney(p.total, currency)}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        children: [
                          Expanded(
                            flex: 10,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: maxAbs <= 0 || p.total <= 0 ? 0 : p.total / maxAbs,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade600,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (hasLoss) ...[
                            Container(height: 1, color: theme.colorScheme.outlineVariant),
                            Expanded(
                              flex: 6,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxAbs <= 0 || p.total >= 0 ? 0 : (-p.total / maxAbs).clamp(0, 1),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error,
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!hasLoss) Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 4),
        SizedBox(
          height: 16,
          child: Row(
            children: [
              for (var i = 0; i < periods.length; i++)
                Expanded(
                  child: i % every == 0
                      ? OverflowBox(
                          maxWidth: 48,
                          child: Text(
                            fmt.format(periods[i].start),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

