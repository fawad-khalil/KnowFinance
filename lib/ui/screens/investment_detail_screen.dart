import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../models/investment.dart';
import '../../services/investment_analytics.dart';
import '../../state/providers.dart';
import 'investments_screen.dart';

/// One investment: its profit or loss, and the entries linked to it.
class InvestmentDetailScreen extends ConsumerWidget {
  const InvestmentDetailScreen({super.key, required this.investmentId});

  final int investmentId;

  static Future<void> open(BuildContext context, int id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvestmentDetailScreen(investmentId: id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(investmentAnalyticsProvider).value;
    final h = analytics?.holdings.where((h) => h.investment.id == investmentId).firstOrNull;
    if (analytics == null || h == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final home = analytics.home;
    final theme = Theme.of(context);
    final inv = h.investment;
    final profit = h.profit(home);
    final roi = h.roi(home);
    final annual = h.annualReturn(home);
    final value = h.valueIn(home);
    final cats = ref.watch(categoryByIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => InvestmentFormSheet.open(context, investment: inv),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete' && await _confirmDelete(context)) {
                await ref.read(repositoryProvider).deleteInvestment(inv.id!);
                ref.read(dataVersionProvider.notifier).bump();
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete investment'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'link-entries',
        onPressed: () => LinkEntriesSheet.open(context, inv),
        icon: const Icon(Icons.link),
        label: const Text('Link entries'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${inv.type.label}${inv.closed ? ' · closed' : ''}', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 12),
                  Text('Profit / loss', style: theme.textTheme.labelMedium),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            profit == null ? 'Needs a current value' : signedMoney(profit, home),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: profit == null ? theme.colorScheme.error : plColor(context, profit),
                            ),
                          ),
                        ),
                      ),
                      if (roi != null) ...[const SizedBox(width: 8), ChangeChip(value: roi * 100)],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    runSpacing: 12,
                    children: [
                      StatTile(label: 'Bought', value: formatMoney(h.bought, home)),
                      StatTile(label: 'Costs', value: formatMoney(h.costs, home)),
                      StatTile(label: 'Sold', value: formatMoney(h.sold, home)),
                      StatTile(label: 'Dividends & rent', value: formatMoney(h.income, home)),
                      StatTile(label: 'Income yield', value: h.invested > 0 ? '${(h.incomeYield * 100).toStringAsFixed(1)}%' : '–'),
                      StatTile(label: 'Annual return', value: annual == null ? '–' : '${(annual * 100).toStringAsFixed(1)}%'),
                      if (h.first != null) StatTile(label: 'Held', value: _heldFor(h.first!, inv.closed ? h.last! : DateTime.now())),
                    ],
                  ),
                  if (!inv.closed) ...[
                    const Divider(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Current value', style: theme.textTheme.labelMedium),
                              Text(
                                value == null ? 'Not set' : formatMoney(value, home),
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (inv.valuedOn != null)
                                Text('as of ${DateFormat('d MMM yyyy').format(inv.valuedOn!)}', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _updateValue(context, ref, inv, home),
                          child: const Text('Update'),
                        ),
                      ],
                    ),
                  ],
                  if (h.skipped > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${h.skipped} linked ${h.skipped == 1 ? 'entry needs' : 'entries need'} an exchange rate and '
                      "${h.skipped == 1 ? "isn't" : "aren't"} counted.",
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(top: 12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Linked entries', style: theme.textTheme.titleMedium),
                ),
                if (h.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text('Nothing linked yet. Tap "Link entries" to pick the expenses that bought this and '
                        'the income it brought in.'),
                  ),
                for (final e in h.entries.reversed)
                  ListTile(
                    title: Text(e.note.isEmpty ? (cats[e.categoryId]?.name ?? '') : e.note),
                    subtitle: Text(DateFormat('d MMM yyyy').format(e.date)),
                    leading: _FlowBadge(flow: e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind)),
                    trailing: Text(
                      '${e.kind == EntryKind.income ? '+' : '−'}${formatMoney(e.homeCurrency == home ? (e.homeAmount ?? e.amount) : e.amount, e.homeCurrency == home ? home : e.currency)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: e.kind == EntryKind.income ? Colors.green.shade600 : null,
                      ),
                    ),
                    onTap: () => _editLink(context, ref, e),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _heldFor(DateTime from, DateTime to) {
    final months = (to.year - from.year) * 12 + to.month - from.month - (to.day < from.day ? 1 : 0);
    if (months < 1) return '${to.difference(from).inDays} days';
    if (months < 24) return '$months ${months == 1 ? 'month' : 'months'}';
    final years = months / 12;
    return '${years.toStringAsFixed(1)} years';
  }

  static Future<bool> _confirmDelete(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this investment?'),
          content: const Text('Its linked entries stay in your list; they are just unlinked.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      ) ??
      false;

  static Future<void> _updateValue(BuildContext context, WidgetRef ref, Investment inv, String home) async {
    final controller = TextEditingController(
      text: inv.currentValue != null && inv.valueCurrency == home ? inv.currentValue!.toStringAsFixed(0) : '',
    );
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What is it worth today?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(prefixText: '$home ', helperText: 'Market price × units you still hold'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(',', ''))),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v == null) return;
    final now = DateTime.now();
    await ref.read(repositoryProvider).saveInvestment(inv.copyWith(
          currentValue: () => v,
          valueCurrency: () => home,
          valuedOn: () => DateTime(now.year, now.month, now.day),
        ));
    ref.read(dataVersionProvider.notifier).bump();
  }

  /// Change what a linked entry did, or unlink it.
  static Future<void> _editLink(BuildContext context, WidgetRef ref, Entry e) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in InvestmentFlow.forKind(e.kind))
              ListTile(
                leading: Icon(f == (e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind))
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(f.label),
                onTap: () => Navigator.pop(ctx, f),
              ),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Unlink from this investment'),
              onTap: () => Navigator.pop(ctx, 'unlink'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final repo = ref.read(repositoryProvider);
    if (choice == 'unlink') {
      await repo.linkEntries(null, {e.id!: null});
    } else {
      await repo.linkEntries(e.investmentId, {e.id!: choice as InvestmentFlow});
    }
    ref.read(dataVersionProvider.notifier).bump();
  }
}

class _FlowBadge extends StatelessWidget {
  const _FlowBadge({required this.flow});

  final InvestmentFlow flow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, bg) = switch (flow) {
      InvestmentFlow.buy => (Icons.shopping_cart_outlined, scheme.surfaceContainerHighest),
      InvestmentFlow.cost => (Icons.receipt_outlined, scheme.surfaceContainerHighest),
      InvestmentFlow.sale => (Icons.sell_outlined, Colors.green.withValues(alpha: 0.15)),
      InvestmentFlow.income => (Icons.payments_outlined, Colors.green.withValues(alpha: 0.15)),
    };
    return Tooltip(
      message: flow.label,
      child: CircleAvatar(backgroundColor: bg, child: Icon(icon, size: 20, color: scheme.onSurface)),
    );
  }
}

/// Picks unlinked entries to link to an investment. Entries whose note
/// mentions the investment's name are listed first and pre-selected.
class LinkEntriesSheet extends ConsumerStatefulWidget {
  const LinkEntriesSheet({super.key, required this.investment});

  final Investment investment;

  static Future<void> open(BuildContext context, Investment investment) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => LinkEntriesSheet(investment: investment)),
      );

  @override
  ConsumerState<LinkEntriesSheet> createState() => _LinkEntriesSheetState();
}

class _LinkEntriesSheetState extends ConsumerState<LinkEntriesSheet> {
  List<Entry>? _candidates;
  final _selected = <int, InvestmentFlow>{};
  var _matchCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(repositoryProvider).unlinkedInvestmentCandidates();
    final name = widget.investment.name;
    final matches = list.where((e) => noteMatchesInvestment(e.note, name)).toList();
    final rest = list.where((e) => !noteMatchesInvestment(e.note, name)).toList();
    if (!mounted) return;
    setState(() {
      _candidates = [...matches, ...rest];
      _matchCount = matches.length;
      for (final e in matches) {
        _selected[e.id!] = InvestmentFlow.defaultFor(e.kind);
      }
    });
  }

  Future<void> _save() async {
    await ref.read(repositoryProvider).linkEntries(widget.investment.id, _selected);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoryByIdProvider);
    final home = ref.watch(homeCurrencyProvider);
    final theme = Theme.of(context);
    final list = _candidates;
    return Scaffold(
      appBar: AppBar(
        title: Text('Link to ${widget.investment.name}'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _save,
            child: Text(_selected.isEmpty ? 'Link' : 'Link ${_selected.length}'),
          ),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No unlinked Savings expenses or income to link. Add one from the Entries tab first.',
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          _matchCount > 0
                              ? '$_matchCount ${_matchCount == 1 ? 'entry mentions' : 'entries mention'} '
                                  '"${widget.investment.name}" and ${_matchCount == 1 ? 'is' : 'are'} already ticked.'
                              : 'Showing Savings expenses and all income that are not linked yet.',
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    }
                    final e = list[i - 1];
                    final flow = _selected[e.id];
                    final amount = e.homeCurrency == home && e.homeAmount != null
                        ? formatMoney(e.homeAmount!, home)
                        : formatMoney(e.amount, e.currency);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CheckboxListTile(
                          value: flow != null,
                          onChanged: (on) => setState(() {
                            if (on == true) {
                              _selected[e.id!] = InvestmentFlow.defaultFor(e.kind);
                            } else {
                              _selected.remove(e.id);
                            }
                          }),
                          title: Text(e.note.isEmpty ? (cats[e.categoryId]?.name ?? '') : e.note),
                          subtitle: Text('${cats[e.categoryId]?.name ?? ''} · ${DateFormat('d MMM yyyy').format(e.date)}'),
                          secondary: Text(
                            '${e.kind == EntryKind.income ? '+' : '−'}$amount',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: e.kind == EntryKind.income ? Colors.green.shade600 : null,
                            ),
                          ),
                        ),
                        if (flow != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                for (final f in InvestmentFlow.forKind(e.kind))
                                  ChoiceChip(
                                    label: Text(f.label),
                                    selected: flow == f,
                                    onSelected: (_) => setState(() => _selected[e.id!] = f),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
    );
  }
}

/// Adds or edits an investment's name, type and whether it is closed.
class InvestmentFormSheet extends ConsumerStatefulWidget {
  const InvestmentFormSheet({super.key, this.investment});

  final Investment? investment;

  static Future<void> open(BuildContext context, {Investment? investment}) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => InvestmentFormSheet(investment: investment)),
      );

  @override
  ConsumerState<InvestmentFormSheet> createState() => _InvestmentFormSheetState();
}

class _InvestmentFormSheetState extends ConsumerState<InvestmentFormSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.investment?.name ?? '');
  late var _type = widget.investment?.type ?? AssetType.stocks;
  late var _closed = widget.investment?.closed ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final base = widget.investment;
    final inv = base == null
        ? Investment(name: _name.text.trim(), type: _type, closed: _closed)
        : base.copyWith(name: _name.text.trim(), type: _type, closed: _closed);
    final id = await ref.read(repositoryProvider).saveInvestment(inv);
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    // A new investment opens its page, where linking entries comes next.
    if (base == null) {
      await Navigator.pushReplacement(
          context, MaterialPageRoute<void>(builder: (_) => InvestmentDetailScreen(investmentId: id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.investment == null ? 'New investment' : 'Edit investment'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.investment == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Use the same words as your entry notes (e.g. "Meezan fund") to link them faster.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AssetType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: [for (final t in AssetType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Closed'),
              subtitle: const Text('Fully sold. Profit is final and no current value is needed.'),
              value: _closed,
              onChanged: (v) => setState(() => _closed = v),
            ),
          ],
        ),
      ),
    );
  }
}
