import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../models/enums.dart';
import '../../services/budget_tracker.dart';
import '../../state/budget_providers.dart';
import '../../state/providers.dart';
import '../chart_colors.dart';
import 'budget_edit_screen.dart';
import 'investments_screen.dart' show StatTile;
import 'recurring_screen.dart';

/// A month's spending against its budgets: the total, what recurring
/// payments are due, and each expense type.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final data = ref.watch(budgetMonthDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budget'),
        actions: [
          IconButton(
            tooltip: 'Recurring payments',
            icon: const Icon(Icons.event_repeat),
            onPressed: () => RecurringScreen.open(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => ref.read(budgetMonthProvider.notifier).step(-1),
              ),
              SizedBox(
                width: 160,
                child: Text(DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => ref.read(budgetMonthProvider.notifier).step(1),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'edit-budget',
        onPressed: () => BudgetEditScreen.open(context),
        icon: const Icon(Icons.tune),
        label: const Text('Set budget'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (m) => !m.hasBudget && m.dues.isEmpty ? _Empty(spent: m.spent, home: m.home) : _Month(m: m),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.spent, required this.home});

  final double spent;
  final String home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Plan what you spend each month', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Set one monthly total, or a budget for each expense type that adds up to it. Add rent, bills and fees '
              'as recurring payments: they are logged when due and budgeted for on their own.'
              '${spent > 0 ? '\n\nSpent this month so far: ${formatMoney(spent, home)}.' : ''}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => RecurringForm.open(context),
              icon: const Icon(Icons.event_repeat),
              label: const Text('Add a recurring payment'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.m});

  final BudgetMonth m;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (m.skipped > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${m.skipped} ${m.skipped == 1 ? 'expense needs' : 'expenses need'} an exchange rate and '
              '${m.skipped == 1 ? "isn't" : "aren't"} counted.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        _Summary(m: m),
        if (m.dues.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Dues(m: m),
        ],
        const SizedBox(height: 16),
        _Lines(m: m),
      ],
    );
  }
}

/// A bar of [value] out of 1, red past it, with an optional tick where
/// spending would be at an even pace.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, this.marker, this.height = 8});

  final double value;
  final Color color;
  final double? marker;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final over = value > 1.00001;
    return SizedBox(
      height: height + 4,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          alignment: Alignment.centerLeft,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(height / 2),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: height,
                color: over ? theme.colorScheme.error : color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (marker != null && marker! > 0 && marker! < 1)
              Positioned(
                left: box.maxWidth * marker! - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: theme.colorScheme.onSurface),
              ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.m});

  final BudgetMonth m;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = m.home;
    final over = m.left < 0;
    final projected = m.projected;
    final current = m.daysElapsed > 0 && m.daysElapsed < m.daysInMonth;
    final unallocated = m.unallocated;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.overall != null
                  ? 'Monthly budget'
                  : 'Budget from ${m.lines.where((l) => l.budget > 0).length} expense types',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: formatMoney(m.left.abs(), home),
                  style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: over ? theme.colorScheme.error : null),
                ),
                TextSpan(text: over ? '  over' : '  left', style: theme.textTheme.titleMedium),
              ]),
            ),
            const SizedBox(height: 8),
            _Bar(
              value: m.total <= 0 ? 0 : m.spent / m.total,
              color: theme.colorScheme.primary,
              marker: current ? m.daysElapsed / m.daysInMonth : null,
              height: 10,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                StatTile(label: 'Spent', value: formatMoney(m.spent, home), width: 140),
                StatTile(label: 'Budget', value: formatMoney(m.total, home), width: 140),
                if (m.dailyAllowance != null && m.dailyAllowance! > 0)
                  StatTile(label: 'Per day left', value: formatMoney(m.dailyAllowance!.roundToDouble(), home), width: 140),
                if (m.scheduledOutstanding > 0)
                  StatTile(label: 'Bills still due', value: formatMoney(m.scheduledOutstanding, home), width: 140),
              ],
            ),
            if (current && projected != null) ...[
              const SizedBox(height: 12),
              Text(
                m.spent > m.expectedByNow
                    ? 'Ahead of an even pace by ${formatMoney((m.spent - m.expectedByNow).roundToDouble(), home)}. '
                        'At this rate the month ends at ${formatMoney(projected.roundToDouble(), home)}.'
                    : 'Within an even pace: ${formatMoney((m.expectedByNow - m.spent).roundToDouble(), home)} to spare so far.',
                style: muted,
              ),
            ],
            if (unallocated != null && unallocated.abs() >= 1) ...[
              const SizedBox(height: 8),
              Text(
                unallocated > 0
                    ? '${formatMoney(unallocated, home)} of the monthly budget is not given to any type.'
                    : 'Type budgets and bills add up to ${formatMoney(-unallocated, home)} more than the monthly budget.',
                style: unallocated > 0 ? muted : theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dues extends ConsumerWidget {
  const _Dues({required this.m});

  final BudgetMonth m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Recurring payments', style: theme.textTheme.titleSmall),
            ),
            for (final d in m.dues) _DueTile(d: d, home: m.home),
          ],
        ),
      ),
    );
  }
}

class _DueTile extends ConsumerWidget {
  const _DueTile({required this.d, required this.home});

  final ScheduledDue d;
  final String home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = d.payment;
    final (icon, color) = switch (d.status) {
      DueStatus.paid => (Icons.check_circle, ChartColors.of(context).slot(2)),
      DueStatus.skipped => (Icons.remove_circle_outline, theme.colorScheme.onSurfaceVariant),
      DueStatus.missed => (Icons.error_outline, theme.colorScheme.error),
      DueStatus.upcoming => (Icons.schedule, theme.colorScheme.onSurfaceVariant),
      DueStatus.before => (Icons.history, theme.colorScheme.onSurfaceVariant),
    };
    final open = d.status == DueStatus.missed || d.status == DueStatus.upcoming;
    final shown = d.paidAmount ?? d.amount;
    final differs = d.paidAmount != null && d.amount != null && (d.paidAmount! - d.amount!).abs() >= 1;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(p.name),
      subtitle: Text([
        '${d.status.label} ${DateFormat('d MMM').format(d.due)}',
        if (differs) 'planned ${formatMoney(d.amount!, home)}',
        if (open && p.autoPost) 'logs itself',
      ].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(shown == null ? formatMoney(p.amount, p.currency) : formatMoney(shown, home),
              style: theme.textTheme.titleSmall?.copyWith(
                  decoration: d.status == DueStatus.skipped ? TextDecoration.lineThrough : null)),
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (v) => _act(context, ref, v),
            itemBuilder: (_) => [
              if (open || d.status == DueStatus.before) const PopupMenuItem(value: 'paid', child: Text('Mark paid')),
              if (open) const PopupMenuItem(value: 'skip', child: Text('Skip this one')),
              if (d.status == DueStatus.paid || d.status == DueStatus.skipped)
                const PopupMenuItem(value: 'undo', child: Text('Mark not paid')),
              const PopupMenuItem(value: 'edit', child: Text('Edit payment')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(repositoryProvider);
    final p = d.payment;
    switch (action) {
      case 'paid':
        final paid = await showDialog<(double, DateTime)>(context: context, builder: (_) => _PaidDialog(d: d));
        if (paid == null) return;
        await ref.read(recurringServiceProvider).markPaid(p, d.due, ref.read(homeCurrencyProvider), amount: paid.$1, paidOn: paid.$2);
      case 'skip':
        await repo.skipRecurring(p.id!, d.due);
      case 'undo':
        if (d.entryId != null && context.mounted) {
          final remove = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Mark not paid?'),
              content: Text('The expense logged for ${p.name} on ${DateFormat('d MMM').format(d.due)} can be removed too.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep expense')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove it')),
              ],
            ),
          );
          if (remove == null) return;
          if (remove) await repo.deleteEntry(d.entryId!);
        }
        await repo.undoRecurringPost(p.id!, d.due);
      case 'edit':
        if (context.mounted) await RecurringForm.open(context, payment: p);
        return;
    }
    ref.read(dataVersionProvider.notifier).bump();
  }
}

class _PaidDialog extends StatefulWidget {
  const _PaidDialog({required this.d});

  final ScheduledDue d;

  @override
  State<_PaidDialog> createState() => _PaidDialogState();
}

class _PaidDialogState extends State<_PaidDialog> {
  late final _amount = TextEditingController(text: _plain(widget.d.payment.amount));
  late DateTime _date = () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return widget.d.due.isAfter(today) ? today : widget.d.due;
  }();

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.d.payment;
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    return AlertDialog(
      title: Text('${p.name} paid'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Amount', suffixText: p.currency, border: const OutlineInputBorder()),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime.now());
              if (d != null) setState(() => _date = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Paid on', border: OutlineInputBorder()),
              child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: amount == null || amount <= 0 ? null : () => Navigator.pop(context, (amount, _date)),
          child: const Text('Log expense'),
        ),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.m});

  final BudgetMonth m;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ChartColors.of(context);
    final home = m.home;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final children = <Widget>[];
    Bucket? bucket;
    for (final l in m.lines) {
      final b = l.category.bucket ?? Bucket.needs;
      if (b != bucket) {
        bucket = b;
        final t = m.buckets[b]!;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 16, bottom: 4),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: colors.bucket(b), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(b.label, style: theme.textTheme.titleSmall)),
              Text(
                t.budget > 0 ? '${compactMoney(t.spent, home)} of ${compactMoney(t.budget, home)}' : compactMoney(t.spent, home),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ));
      }
      final notes = [
        if (l.budget <= 0) 'no budget' else 'of ${formatMoney(l.budget, home)}',
        if (l.scheduled > 0) '${formatMoney(l.scheduled, home)} in bills',
        if (l.budget > 0) l.over ? '${formatMoney(-l.left, home)} over' : '${formatMoney(l.left, home)} left',
      ];
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(l.category.name, overflow: TextOverflow.ellipsis)),
                Text(formatMoney(l.spent, home)),
              ],
            ),
            const SizedBox(height: 4),
            _Bar(value: l.budget > 0 ? l.used : 0, color: colors.bucket(b), marker: null, height: 6),
            const SizedBox(height: 2),
            Text(notes.join(' · '),
                style: l.over && l.budget > 0 ? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error) : muted),
          ],
        ),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('By expense type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (children.isEmpty) Text('Nothing spent yet.', style: muted) else ...children,
          ],
        ),
      ),
    );
  }
}
