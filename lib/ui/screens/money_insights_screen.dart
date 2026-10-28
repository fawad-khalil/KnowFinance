import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../services/money_insights.dart';
import '../../state/providers.dart';
import '../chart_colors.dart';

/// Money patterns over the last 30 days, in two tabs: how money flows in
/// and out, and how the user uses Raast.
class MoneyInsightsScreen extends ConsumerWidget {
  const MoneyInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(moneyInsightsProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Money patterns'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.swap_vert), text: 'Money flow'),
            Tab(icon: Icon(Icons.bolt), text: 'Raast'),
          ]),
        ),
        body: insights.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (m) => m.window.isEmpty
              ? const Center(child: Text('Nothing logged in the last 30 days yet.'))
              : TabBarView(children: [_page(context, m, _flowCards(m)), _page(context, m, _raastCards(m))]),
        ),
      ),
    );
  }

  static Widget _page(BuildContext context, MoneyInsights m, List<Widget> cards) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        Text(
          '${DateFormat('d MMM').format(m.start)} – ${DateFormat('d MMM yyyy').format(m.end)}',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        ...cards,
      ],
    );
  }

  static List<Widget> _flowCards(MoneyInsights m) => [
        _Card(title: 'Money in, by sender', icon: Icons.call_received, child: _Senders(m)),
        _Card(title: 'Biggest spend', icon: Icons.shopping_bag_outlined, child: _TopSpending(m)),
        _Card(title: 'Spending pace', icon: Icons.speed, child: _Holding(m)),
        _Card(title: 'Income by bank', icon: Icons.account_balance, child: _BankDependency(m)),
        _Card(title: 'Most-used bank', icon: Icons.star_outline, child: _FinancialHome(m)),
        _Card(title: 'Digital or cash', icon: Icons.payments_outlined, child: _MoneyStyle(m)),
      ];

  static List<Widget> _raastCards(MoneyInsights m) {
    final raast = m.raast();
    if (raast.count == 0) {
      return const [
        _Card(
          title: 'No Raast transfers',
          icon: Icons.bolt,
          child: Text('Raast transfers read from your bank alerts in the last 30 days show up here.'),
        ),
      ];
    }
    return [
      _Card(title: 'Raast at a glance', icon: Icons.bolt, child: _RaastSummary(raast, m.home)),
      _Card(title: 'Your regulars', icon: Icons.people_outline, child: _InnerCircle(raast, m.home)),
      _Card(title: 'Where they bank', icon: Icons.account_balance_outlined, child: _CircleBanks(raast, m.home)),
      _Card(title: 'Busy times', icon: Icons.schedule, child: _BusyTimes(raast)),
    ];
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// The one figure a card is about, with a line saying what it means.
class _Headline extends StatelessWidget {
  const _Headline(this.value, this.caption);

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 2),
        Text(caption, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// A labelled bar sized against the largest in its list.
class _BarRow extends StatelessWidget {
  const _BarRow(
      {required this.label, required this.value, required this.fraction, required this.color, this.detail, this.subtitle});

  final String label;

  /// A second line under the label, such as the person's bank.
  final String? subtitle;
  final String value;
  final double fraction;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            if (detail != null)
              Text('$detail  ', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(value),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0, 1),
              minHeight: 6,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

String _pct(double v) => '${v.toStringAsFixed(0)}%';

String _times(int n) => n == 1 ? 'once' : '$n times';

class _Senders extends StatelessWidget {
  const _Senders(this.m);

  final MoneyInsights m;

  @override
  Widget build(BuildContext context) {
    final senders = m.topSenders();
    if (senders.isEmpty) return const Text('No income logged in the last 30 days.');
    final top = senders.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in top)
          _BarRow(
            label: c.name,
            subtitle: c.bank,
            value: formatMoney(c.received, m.home),
            detail: _times(c.receivedCount),
            fraction: c.received / top.first.received,
            color: ChartColors.of(context).income,
          ),
        if (senders.length > 3) _Muted('and ${senders.length - 3} more'),
      ],
    );
  }
}

class _TopSpending extends StatelessWidget {
  const _TopSpending(this.m);

  final MoneyInsights m;

  @override
  Widget build(BuildContext context) {
    final types = m.spendingByType();
    if (types.isEmpty) return const Text('No spending logged in the last 30 days.');
    final top = types.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(top.label, '${_pct(top.pct)} of your spending, ${formatMoney(top.total, m.home)}'),
        const SizedBox(height: 8),
        for (final (i, t) in types.skip(1).take(3).indexed)
          _BarRow(
            label: t.label,
            value: formatMoney(t.total, m.home),
            detail: _pct(t.pct),
            fraction: t.total / top.total,
            color: ChartColors.of(context).slot(i + 1),
          ),
      ],
    );
  }
}

class _Holding extends StatelessWidget {
  const _Holding(this.m);

  final MoneyInsights m;

  @override
  Widget build(BuildContext context) {
    final h = m.holdingTime();
    if (h == null) return const Text('Log income and spending to see how long money stays with you.');
    final days = h.avgDays.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(days == 0 ? 'Under a day' : days == 1 ? 'About 1 day' : 'About $days days',
            'for your spending to use up what comes in'),
        const SizedBox(height: 12),
        _BarRow(
          label: 'Used up within a week',
          value: _pct(h.withinWeekPct),
          fraction: h.withinWeekPct / 100,
          color: ChartColors.of(context).expense,
        ),
        const _Muted('Counted from each payment you received, until spending after it added up to the same amount.'),
      ],
    );
  }
}

class _BankDependency extends StatelessWidget {
  const _BankDependency(this.m);

  final MoneyInsights m;

  @override
  Widget build(BuildContext context) {
    final banks = m.incomeByBank();
    if (banks.isEmpty) return const Text('Income from bank alerts shows which bank you depend on. None in the last 30 days.');
    final top = banks.first;
    final known = banks.fold<double>(0, (a, b) => a + b.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(_pct(top.pct), 'of your income came in through ${top.label}'),
        const SizedBox(height: 8),
        for (final (i, b) in banks.take(4).indexed)
          _BarRow(
            label: b.label,
            value: formatMoney(b.total, m.home),
            detail: _pct(b.pct),
            fraction: b.pct / 100,
            color: ChartColors.of(context).slot(i),
          ),
        if (known < m.income) _Muted('${formatMoney(m.income - known, m.home)} of income has no bank, as it was typed in.'),
      ],
    );
  }
}

class _FinancialHome extends StatelessWidget {
  const _FinancialHome(this.m);

  final MoneyInsights m;

  @override
  Widget build(BuildContext context) {
    final banks = m.activityByBank();
    if (banks.isEmpty) return const Text('The bank you use most shows here once bank alerts are imported.');
    final top = banks.first;
    final income = m.incomeByBank();
    final salaryElsewhere = income.isNotEmpty && income.first.label != top.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(top.label, '${top.count} of your ${m.window.length} transactions (${_pct(top.pct)})'),
        for (final (i, b) in banks.skip(1).take(3).indexed)
          _BarRow(
            label: b.label,
            value: '${b.count}',
            fraction: b.total / top.total,
            color: ChartColors.of(context).slot(i + 1),
          ),
        if (salaryElsewhere) _Muted('Most income arrives in ${income.first.label}, but you spend from ${top.label}.'),
      ],
    );
  }
}

class _MoneyStyle extends StatelessWidget {
  const _MoneyStyle(this.m);

  final MoneyInsights m;

  @override
  Widget build(BuildContext context) {
    final s = m.moneyStyle();
    final known = s.digital + s.cash;
    if (known <= 0) return const Text('Spending from bank alerts shows how much you pay digitally and in cash.');
    final colors = ChartColors.of(context);
    final digitalPct = s.digital / known * 100;
    final parts = [('Digital', s.digital, colors.slot(0)), ('Cash', s.cash, colors.slot(3))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(
          digitalPct >= 80 ? 'Mostly digital' : digitalPct <= 20 ? 'Mostly cash' : 'Digital and cash',
          '${_pct(digitalPct)} of spending by card, transfer, Raast or wallet',
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 14,
            child: Row(children: [
              for (final p in parts.where((p) => p.$2 > 0))
                Expanded(
                  flex: (p.$2 / known * 1000).round().clamp(1, 1000),
                  child: Container(margin: const EdgeInsets.only(right: 2), color: p.$3),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Expanded(child: Text(p.$1)),
              Text(formatMoney(p.$2, m.home)),
            ]),
          ),
        if (s.unknown > 0) _Muted('${formatMoney(s.unknown, m.home)} of spending doesn\'t say how it was paid.'),
      ],
    );
  }
}

class _RaastSummary extends StatelessWidget {
  const _RaastSummary(this.r, this.home);

  final RaastSummary r;
  final String home;

  @override
  Widget build(BuildContext context) {
    final colors = ChartColors.of(context);
    Widget tile(String label, String value, String sub, Color? accent) {
      final theme = Theme.of(context);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (accent != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Text(label, style: theme.textTheme.labelMedium),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    String transfers(int n) => n == 1 ? '1 transfer' : '$n transfers';
    String people(int n) => n == 1 ? '1 person' : '$n people';
    return Column(children: [
      Row(children: [
        Expanded(child: tile('Sent', formatMoney(r.sent, home), transfers(r.sentCount), colors.expense)),
        const SizedBox(width: 8),
        Expanded(child: tile('Received', formatMoney(r.received, home), transfers(r.receivedCount), colors.income)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: tile('Returning', '${r.repeatCount}', '${people(r.repeatCount)} from before', null)),
        const SizedBox(width: 8),
        Expanded(child: tile('New', '${r.newContacts.length}', '${people(r.newContacts.length)} for the first time', null)),
      ]),
    ]);
  }
}

class _InnerCircle extends StatelessWidget {
  const _InnerCircle(this.r, this.home);

  final RaastSummary r;
  final String home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final circle = r.innerCircle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in circle)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Text(c.name.characters.first.toUpperCase(),
                    style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      if (c.twoWay) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Money went both ways',
                          child: Icon(Icons.swap_horiz, size: 16, color: theme.colorScheme.primary),
                        ),
                      ],
                    ]),
                    Text(
                      [_times(c.count), ?c.bank].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (c.sent > 0)
                  Text('−${formatMoney(c.sent, home)}', style: theme.textTheme.bodySmall?.copyWith(color: colors.expense)),
                if (c.received > 0)
                  Text('+${formatMoney(c.received, home)}', style: theme.textTheme.bodySmall?.copyWith(color: colors.income)),
              ]),
            ]),
          ),
        if (circle.any((c) => c.twoWay)) const _Muted('People you both send to and receive from come first, then the most frequent.'),
      ],
    );
  }
}

class _CircleBanks extends StatelessWidget {
  const _CircleBanks(this.r, this.home);

  final RaastSummary r;
  final String home;

  @override
  Widget build(BuildContext context) {
    final banks = r.circleBanks;
    final colors = ChartColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Where your Raast money flows, by the bank or wallet of the person on the other side.'),
        const SizedBox(height: 4),
        for (final (i, b) in banks.take(6).indexed)
          _BarRow(
            label: b.label,
            value: formatMoney(b.total, home),
            detail: '${_pct(b.pct)} · ${b.count == 1 ? '1 person' : '${b.count} people'}',
            fraction: b.total / banks.first.total,
            color: b.label == 'Bank not shown' ? colors.other : colors.slot(i),
          ),
      ],
    );
  }
}

class _BusyTimes extends StatelessWidget {
  const _BusyTimes(this.r);

  final RaastSummary r;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _longDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static String _hour(int h) => DateFormat('ha').format(DateTime(2000, 1, 1, h)).toLowerCase();

  static int _peak(List<int> v) => v.indexOf(v.reduce((a, b) => a > b ? a : b));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = _peak(r.byWeekday);
    final hour = r.timed == 0 ? null : _peak(r.byHour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Headline(
          hour == null ? _longDays[day] : '${_longDays[day]}s, ${_hour(hour)} to ${_hour((hour + 1) % 24)}',
          'is when you use Raast most',
        ),
        const SizedBox(height: 16),
        Text('By day', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        _Columns(values: r.byWeekday, labels: _days, every: 1),
        if (hour != null) ...[
          const SizedBox(height: 16),
          Text('By hour', style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          _Columns(values: r.byHour, labels: [for (var h = 0; h < 24; h++) _hour(h)], every: 6),
          if (r.timed < r.count) _Muted('${r.count - r.timed} of ${r.count} transfers have no time in their alert.'),
        ],
      ],
    );
  }
}

/// Small column chart of counts, the busiest column in full color.
class _Columns extends StatelessWidget {
  const _Columns({required this.values, required this.labels, required this.every});

  final List<int> values;
  final List<String> labels;

  /// Label every this many columns, so 24 hours don't crowd.
  final int every;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ChartColors.of(context).slot(6);
    final max = values.fold(0, (a, b) => a > b ? a : b);
    return Column(children: [
      SizedBox(
        height: 64,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Tooltip(
                  message: '${labels[i]}: ${values[i] == 1 ? '1 transfer' : '${values[i]} transfers'}',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        // Empty columns keep a sliver so the axis reads.
                        heightFactor: max == 0 ? 0.04 : (values[i] / max).clamp(0.04, 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: values[i] == 0
                                ? theme.colorScheme.surfaceContainerHighest
                                : values[i] == max
                                    ? color
                                    : color.withValues(alpha: 0.45),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: i % every == 0
                ? Text(labels[i], softWrap: false, overflow: TextOverflow.visible, style: theme.textTheme.labelSmall)
                : const SizedBox(),
          ),
      ]),
    ]);
  }
}
