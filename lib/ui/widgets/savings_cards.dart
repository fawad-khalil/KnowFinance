import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../services/loan_analytics.dart';
import '../../services/savings.dart';
import '../../state/providers.dart';
import '../screens/investments_screen.dart' show plColor, signedMoney;
import '../screens/loans_screen.dart';
import 'signed_bars.dart';
import 'trend_chip.dart';

/// Savings figures for this month and the months before. They don't follow
/// the date filter: "this month" always means the calendar month so far.
final savingsReportProvider = Provider<SavingsReport?>((ref) {
  final all = ref.watch(allEntriesProvider).value;
  if (all == null) return null;
  return SavingsReport(all, ref.watch(categoryByIdProvider), ref.watch(homeCurrencyProvider));
});

/// How much was kept this month, and how income and spending moved against
/// the same days of last month.
class ThisMonthCard extends ConsumerWidget {
  const ThisMonthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(savingsReportProvider);
    if (r == null) return const SizedBox.shrink();
    final home = ref.watch(homeCurrencyProvider);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final m = r.thisMonth;
    final day = DateFormat('d MMM');
    final compare = '${day.format(r.lastMonthToDate.start)} – ${day.format(r.lastMonthToDate.end)}';
    final loans = ref.watch(loanAnalyticsProvider).value?.flows(start: m.start, end: m.end);

    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${DateFormat('MMMM').format(m.start)} so far', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(m.saved >= 0 ? 'Saved' : 'Overspent', style: theme.textTheme.labelMedium),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoney(m.saved.abs(), home),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: plColor(context, m.saved),
                      ),
                    ),
                  ),
                ),
                if (m.income > 0) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${(m.saved / m.income * 100).toStringAsFixed(0)}% of income', style: muted),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _ChangeRow(label: 'Income', value: formatMoney(m.income, home), change: r.incomeChange),
            _ChangeRow(
              label: 'Spending (Needs + Wants)',
              value: formatMoney(m.spending, home),
              change: r.spendingChange,
              upIsGood: false,
            ),
            const SizedBox(height: 4),
            Text('Changes compare with $compare.', style: muted),
            const SizedBox(height: 8),
            Text(_verdict(r), style: theme.textTheme.bodyMedium),
            if (loans != null && !loans.isEmpty) ...[
              const SizedBox(height: 8),
              Text(_loanLine(loans, home), style: muted),
            ],
          ],
        ),
      ),
    );
  }

  /// One sentence on whether spending is outpacing income.
  static String _verdict(SavingsReport r) {
    final share = r.spendingShare, last = r.lastSpendingShare;
    if (share == null) return 'No income logged this month yet.';
    final s = 'Spending is ${share.toStringAsFixed(0)}% of income';
    if (last == null) return '$s.';
    final diff = share - last;
    if (diff.abs() < 1) return '$s, about the same as last month.';
    return diff > 0
        ? '$s, up ${diff.toStringAsFixed(0)} points on last month: spending is growing faster than income.'
        : '$s, down ${(-diff).toStringAsFixed(0)} points on last month.';
  }

  static String _loanLine(LoanFlows f, String home) => [
        'Loans this month (not counted above):',
        [
          if (f.borrowed > 0) 'borrowed ${compactMoney(f.borrowed, home)}',
          if (f.repaid > 0) 'repaid ${compactMoney(f.repaid, home)}',
          if (f.lent > 0) 'lent ${compactMoney(f.lent, home)}',
          if (f.gotBack > 0) 'got back ${compactMoney(f.gotBack, home)}',
        ].join(', '),
      ].join(' ');
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.label, required this.value, required this.change, this.upIsGood = true});

  final String label;
  final String value;
  final double? change;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = change;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Align(
              alignment: Alignment.centerRight,
              child: c == null
                  ? Text('–', style: theme.textTheme.bodySmall)
                  : TrendChip(value: c, upIsGood: upIsGood),
            ),
          ),
        ],
      ),
    );
  }

}

/// Every month's balance added into savings: months with money left over
/// add to it, short months draw from it.
class SavingsHistoryCard extends ConsumerWidget {
  const SavingsHistoryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(savingsReportProvider);
    if (r == null || r.history.isEmpty) return const SizedBox.shrink();
    final home = ref.watch(homeCurrencyProvider);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final recent = r.history.length > 12 ? r.history.sublist(r.history.length - 12) : r.history;
    final good = r.history.where((m) => m.saved > 0).length;
    final short = r.history.where((m) => m.saved < 0).length;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Savings', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(r.total, home),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: r.total < 0 ? theme.colorScheme.error : null,
                ),
              ),
            ),
            Text(
              'Added ${compactMoney(r.added, home)} in $good ${good == 1 ? 'month' : 'months'} with money left over'
              '${short > 0 ? ', drew ${compactMoney(r.drawn, home)} in $short short ${short == 1 ? 'month' : 'months'}' : ''}.',
              style: muted,
            ),
            if (recent.length > 1) ...[
              const SizedBox(height: 16),
              SignedBars(values: [for (final m in recent) (m.month, m.saved)], currency: home),
              const SizedBox(height: 4),
              Text('Left over each month (income minus Needs and Wants), last ${recent.length} months.', style: muted),
            ],
            if (r.lastMonth.income > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Last month you ${r.lastMonth.saved >= 0 ? 'saved' : 'overspent by'} '
                '${signedMoney(r.lastMonth.saved, home).substring(1)}.',
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
