import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../state/providers.dart';
import '../widgets/filter_bar.dart';
import 'entry_form_screen.dart';
import 'import_screen.dart';

class EntriesScreen extends ConsumerWidget {
  const EntriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesProvider);
    final toReview = ref.watch(pendingImportCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KnowFinance'),
        actions: [
          IconButton(
            tooltip: 'Import transactions',
            onPressed: () => ImportScreen.open(context),
            icon: Badge(
              isLabelVisible: toReview > 0,
              label: Text('$toReview'),
              child: const Icon(Icons.move_to_inbox_outlined),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => EntryFormScreen.open(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          const FilterBar(),
          Expanded(
            child: entries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load entries: $e')),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No entries for this filter yet.'))
                  : _EntryList(entries: list),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeCurrencyProvider);
    final rows = <Widget>[_Summary(entries: entries, home: home)];
    String? lastDay;
    for (final e in entries) {
      final day = dateKey(e.date);
      if (day != lastDay) {
        lastDay = day;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            DateFormat('EEE, d MMM yyyy').format(e.date),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ));
      }
      rows.add(_EntryTile(entry: e, home: home));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: rows);
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.entries, required this.home});

  final List<Entry> entries;
  final String home;

  @override
  Widget build(BuildContext context) {
    var income = 0.0, expense = 0.0, missing = 0;
    for (final e in entries) {
      final amt = e.homeCurrency == home ? e.homeAmount : null;
      if (amt == null) {
        missing++;
        continue;
      }
      if (e.kind == EntryKind.income) {
        income += amt;
      } else {
        expense += amt;
      }
    }
    final theme = Theme.of(context);
    Widget cell(String label, double v, Color? color) => Expanded(
          child: Column(
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(formatMoney(v, home),
                    style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              cell('Income', income, Colors.green.shade600),
              cell('Expenses', expense, theme.colorScheme.error),
              cell('Net', income - expense, null),
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
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.home});

  final Entry entry;
  final String home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(categoryByIdProvider)[entry.categoryId];
    final theme = Theme.of(context);
    final isIncome = entry.kind == EntryKind.income;
    final sign = isIncome ? '+' : '−';
    final color = isIncome ? Colors.green.shade600 : theme.colorScheme.onSurface;
    final foreign = entry.currency != home;
    final homeAmt = entry.homeCurrency == home ? entry.homeAmount : null;

    final investment = entry.investmentId == null
        ? null
        : ref.watch(investmentsProvider).value?.where((i) => i.id == entry.investmentId).firstOrNull;
    final subtitle = [
      if (cat?.bucket != null) cat!.bucket!.label,
      if (investment != null) '${(entry.investmentFlow ?? InvestmentFlow.defaultFor(entry.kind)).label}: ${investment.name}',
      if (entry.note.isNotEmpty) entry.note,
    ].join(' · ');

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this entry?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      ),
      onDismissed: (_) async {
        await ref.read(repositoryProvider).deleteEntry(entry.id!);
        ref.read(dataVersionProvider.notifier).bump();
      },
      child: ListTile(
        onTap: () => EntryFormScreen.open(context, entry: entry),
        leading: CircleAvatar(
          backgroundColor: isIncome ? Colors.green.withValues(alpha: 0.15) : theme.colorScheme.surfaceContainerHighest,
          child: Icon(isIncome ? Icons.south_west : Icons.north_east, color: color, size: 20),
        ),
        title: Text(cat?.name ?? 'Unknown'),
        subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$sign${formatMoney(foreign ? entry.amount : (homeAmt ?? entry.amount), foreign ? entry.currency : home)}',
                style: theme.textTheme.titleSmall?.copyWith(color: color)),
            if (foreign)
              Text(
                homeAmt == null ? 'Rate needed' : formatMoney(homeAmt, home),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: homeAmt == null ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
