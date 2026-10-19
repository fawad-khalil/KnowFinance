import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/currency.dart';
import '../../models/enums.dart';
import '../../services/analytics.dart';
import '../../state/providers.dart';
import '../chart_colors.dart';
import '../widgets/breakdown_pie.dart';
import '../widgets/filter_bar.dart';
import '../widgets/trend_chart.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(insightsEntriesProvider);
    final cats = ref.watch(categoryByIdProvider);
    final home = ref.watch(homeCurrencyProvider);
    final range = ref.watch(filterProvider).effectiveRange();

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: Column(
        children: [
          const FilterBar(datesOnly: true),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (list) {
                final a = Analytics(list, cats, home);
                if (a.entries.isEmpty) {
                  return const Center(child: Text('Add some entries to see insights.'));
                }
                final periods = a.timeline(start: range.start, end: range.end);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                  children: [
                    if (a.skipped > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${a.skipped} ${a.skipped == 1 ? 'entry needs' : 'entries need'} an exchange rate '
                          'and ${a.skipped == 1 ? "isn't" : "aren't"} counted below.',
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    _SavingsCard(summary: a.savings(), currency: home),
                    _Section(title: 'Where the money went', child: _ExpenseDrillDown(analytics: a)),
                    _Section(
                      title: 'Income by type',
                      child: BreakdownPie(
                        slices: BreakdownPie.fold(
                          a.incomeByType(),
                          (i, _) => ChartColors.of(context).slot(i),
                          ChartColors.of(context).other,
                        ),
                        currency: home,
                        centerLabel: 'Income',
                      ),
                    ),
                    _Section(
                      title: 'Income vs expenses',
                      child: TrendChart(
                        periods: periods,
                        currency: home,
                        series: [
                          TrendSeries('Income', ChartColors.of(context).income, [for (final p in periods) p.income]),
                          TrendSeries('Expenses', ChartColors.of(context).expense, [for (final p in periods) p.expense]),
                        ],
                      ),
                    ),
                    _Section(
                      title: 'Income vs Needs, Wants and Savings',
                      child: TrendChart(
                        periods: periods,
                        currency: home,
                        series: [
                          TrendSeries('Income', ChartColors.of(context).income, [for (final p in periods) p.income]),
                          for (final b in Bucket.values)
                            TrendSeries(b.label, ChartColors.of(context).bucket(b), [for (final p in periods) p.buckets[b]!]),
                        ],
                      ),
                    ),
                    _Section(title: 'Spending by note', child: _NoteGroups(groups: a.expenseNoteGroups(), currency: home)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Pie that drills from bucket to expense type to note groups.
class _ExpenseDrillDown extends StatefulWidget {
  const _ExpenseDrillDown({required this.analytics});

  final Analytics analytics;

  @override
  State<_ExpenseDrillDown> createState() => _ExpenseDrillDownState();
}

class _ExpenseDrillDownState extends State<_ExpenseDrillDown> {
  Bucket? _bucket;
  int? _categoryId;

  @override
  Widget build(BuildContext context) {
    final a = widget.analytics;
    final colors = ChartColors.of(context);
    final List<PieSlice> slices;
    final String center;
    void Function(Share)? onTap;

    if (_bucket == null) {
      slices = [for (final s in a.byBucket()) PieSlice(s, colors.bucket(s.key as Bucket))];
      center = 'Expenses';
      onTap = (s) => setState(() => _bucket = s.key as Bucket);
    } else if (_categoryId == null) {
      slices = BreakdownPie.fold(a.byExpenseType(_bucket!), (i, _) => colors.slot(i), colors.other);
      center = _bucket!.label;
      onTap = (s) => setState(() => _categoryId = s.key as int);
    } else {
      slices = BreakdownPie.fold(a.byNote(_categoryId!), (i, _) => colors.slot(i), colors.other);
      center = a.categories[_categoryId]?.name ?? '';
    }

    final crumbs = <(String, VoidCallback?)>[
      ('All expenses', _bucket == null ? null : () => setState(() => _bucket = _categoryId = null)),
      if (_bucket != null) (_bucket!.label, _categoryId == null ? null : () => setState(() => _categoryId = null)),
      if (_categoryId != null) (a.categories[_categoryId]?.name ?? '', null),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < crumbs.length; i++) ...[
              if (i > 0) const Icon(Icons.chevron_right, size: 16),
              crumbs[i].$2 == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Text(crumbs[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                    )
                  : TextButton(onPressed: crumbs[i].$2, child: Text(crumbs[i].$1)),
            ],
          ],
        ),
        BreakdownPie(
          key: ValueKey('$_bucket-$_categoryId'),
          slices: slices,
          currency: a.home,
          centerLabel: center,
          onTap: onTap,
        ),
      ],
    );
  }
}

class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.summary, required this.currency});

  final SavingsSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final s = summary;
    final parts = <(String, double, Color)>[
      ('Needs', s.needs, colors.bucket(Bucket.needs)),
      ('Wants', s.wants, colors.bucket(Bucket.wants)),
      ('Savings', s.savings, colors.bucket(Bucket.savings)),
      if (s.unallocated > 0) ('Unallocated', s.unallocated, colors.other),
    ];
    final barTotal = parts.fold<double>(0, (a, p) => a + p.$2);
    final target = {'Needs': 50, 'Wants': 30, 'Savings': 20};
    final keptPct = s.pct(s.kept);

    return _Section(
      title: 'Savings analysis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _Stat(label: 'Income', value: compactMoney(s.income, currency))),
              Expanded(child: _Stat(label: 'Needs + Wants', value: compactMoney(s.needs + s.wants, currency))),
              Expanded(
                child: _Stat(
                  label: 'Kept',
                  value: s.income > 0 ? '${keptPct.toStringAsFixed(0)}%' : '–',
                  emphasis: s.kept < 0 ? theme.colorScheme.error : null,
                ),
              ),
            ],
          ),
          if (barTotal > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (final p in parts.where((p) => p.$2 > 0))
                      Expanded(
                        flex: (p.$2 / barTotal * 1000).round().clamp(1, 1000),
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          color: p.$3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final p in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p.$1)),
                  Text(formatMoney(p.$2, currency)),
                  SizedBox(
                    width: 110,
                    child: Text(
                      s.income > 0
                          ? '${s.pct(p.$2).toStringAsFixed(0)}%${target[p.$1] != null ? ' of ${target[p.$1]}%' : ''}'
                          : '',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(_advice(s), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// One plain-language line comparing the split with the 50/30/20 rule.
  static String _advice(SavingsSummary s) {
    if (s.income <= 0) return 'Log income for this range to see how much of it you keep.';
    if (s.kept < 0) return 'Needs and Wants were more than your income in this range.';
    final needs = s.pct(s.needs), wants = s.pct(s.wants), kept = s.pct(s.kept);
    if (needs > 50 && wants > 30) return 'Needs and Wants are both above the 50/30/20 guide.';
    if (wants > 30) return 'Wants are ${(wants - 30).toStringAsFixed(0)} points above the 30% guide.';
    if (needs > 50) return 'Needs are ${(needs - 50).toStringAsFixed(0)} points above the 50% guide.';
    if (kept >= 20) return 'You kept ${kept.toStringAsFixed(0)}% of your income, at or above the 20% guide.';
    return 'You kept ${kept.toStringAsFixed(0)}% of your income. The 50/30/20 guide suggests 20%.';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.emphasis});

  final String label;
  final String value;
  final Color? emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: emphasis)),
        ),
      ],
    );
  }
}

class _NoteGroups extends ConsumerWidget {
  const _NoteGroups({required this.groups, required this.currency});

  final List<Share> groups;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) return const Text('Add notes to expenses to group them here.');
    final theme = Theme.of(context);
    final max = groups.first.total;
    return Column(
      children: [
        for (final g in groups.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(g.label, overflow: TextOverflow.ellipsis)),
                    Text('${g.count}×  ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    Text(formatMoney(g.total, currency)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: max <= 0 ? 0 : g.total / max,
                    minHeight: 6,
                    color: ChartColors.of(context).expense,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        if (groups.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('and ${groups.length - 10} more', style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
