import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../models/investment.dart';
import '../../services/investment_analytics.dart';
import '../../services/price_service.dart';
import '../../state/providers.dart';
import 'investments_screen.dart';

/// Market price on the day of each buy, for assets whose feed has history.
/// Keyed by investment id; entry id -> price per unit in the home currency.
final buyDayPricesProvider = FutureProvider.family<Map<int, double>, int>((ref, id) async {
  final inv = (await ref.watch(investmentsProvider.future)).where((i) => i.id == id).firstOrNull;
  final home = ref.watch(homeCurrencyProvider);
  if (inv?.priceSymbol == null || inv?.unit == null || !PriceService.hasHistory(inv!.priceSymbol!)) return const {};
  final prices = ref.watch(priceServiceProvider);
  final out = <int, double>{};
  for (final e in await ref.watch(investmentEntriesProvider.future)) {
    if (e.investmentId != id || e.investmentFlow != InvestmentFlow.buy || (e.quantity ?? 0) <= 0) continue;
    final p = await prices.price(inv.priceSymbol!, inv.unit!, home, date: e.date);
    if (p != null) out[e.id!] = p;
  }
  return out;
});

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
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete asset'))],
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
                  if (!inv.closed && h.marketValue(home) == null) ...[
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
          if (inv.unit != null) _MarketCard(holding: h, home: home),
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
                    subtitle: Text([
                      DateFormat('d MMM yyyy').format(e.date),
                      if (e.quantity != null && inv.unit != null) '${formatQuantity(e.quantity!)} ${inv.unit!.label}',
                    ].join(' · ')),
                    leading: _FlowBadge(flow: e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind)),
                    trailing: Text(
                      '${e.kind == EntryKind.income ? '+' : '−'}${formatMoney(e.homeCurrency == home ? (e.homeAmount ?? e.amount) : e.amount, e.homeCurrency == home ? home : e.currency)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: e.kind == EntryKind.income ? Colors.green.shade600 : null,
                      ),
                    ),
                    onTap: () => _editLink(context, ref, e, inv.unit),
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
  static Future<void> _editLink(BuildContext context, WidgetRef ref, Entry e, QuantityUnit? unit) async {
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
            if (unit != null)
              ListTile(
                leading: const Icon(Icons.scale_outlined),
                title: Text(e.quantity == null ? 'Set quantity' : 'Quantity: ${formatQuantity(e.quantity!)} ${unit.label}'),
                onTap: () => Navigator.pop(ctx, 'quantity'),
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
    } else if (choice == 'quantity') {
      if (!context.mounted) return;
      final q = await askQuantity(context, unit!, e.quantity ?? quantityFromNote(e.note, unit));
      if (q == null) return;
      await repo.linkEntries(e.investmentId, {e.id!: e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind)},
          quantities: {e.id!: q > 0 ? q : null});
    } else {
      await repo.linkEntries(e.investmentId, {e.id!: choice as InvestmentFlow});
    }
    ref.read(dataVersionProvider.notifier).bump();
  }
}

/// Asks how many units an entry bought or sold. Returns 0 to clear it.
Future<double?> askQuantity(BuildContext context, QuantityUnit unit, double? initial) {
  final controller = TextEditingController(text: initial == null ? '' : formatQuantity(initial));
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('How much?'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(suffixText: unit.label, helperText: 'Leave empty to clear'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text) ?? 0), child: const Text('Save')),
      ],
    ),
  );
}

/// Units held, price paid against today's market price, and each buy
/// against the market price on its own day.
class _MarketCard extends ConsumerWidget {
  const _MarketCard({required this.holding, required this.home});

  final Holding holding;
  final String home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = holding;
    final inv = h.investment;
    final unit = inv.unit!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final market = h.marketPrice(home);
    final change = h.priceChange(home);
    final realized = h.realizedGain;
    final buyDay = ref.watch(buyDayPricesProvider(inv.id!)).value ?? const {};
    final buys = h.entries.where((e) => e.investmentFlow == InvestmentFlow.buy && (e.quantity ?? 0) > 0).toList();
    String perUnit(double v) => '${formatMoney(v.roundToDouble(), home)}/${unit.label}';

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Purchase vs market', style: theme.textTheme.titleMedium)),
                if (change != null) ChangeChip(value: change * 100),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              runSpacing: 12,
              children: [
                StatTile(label: 'Held', value: '${formatQuantity(h.held)} ${unit.label}'),
                StatTile(label: 'Avg price paid', value: h.avgBuyPrice == null ? '–' : perUnit(h.avgBuyPrice!)),
                StatTile(label: 'Market price', value: market == null ? '–' : perUnit(market)),
                StatTile(label: 'Cost of held', value: h.costOfHeld == null ? '–' : compactMoney(h.costOfHeld!, home)),
                StatTile(label: 'Market value', value: h.marketValue(home) == null ? '–' : compactMoney(h.marketValue(home)!, home)),
                if (realized != null) StatTile(label: 'Gain on sales', value: signedMoney(realized, home, compact: true)),
              ],
            ),
            const SizedBox(height: 8),
            if (inv.priceSymbol == null)
              Text('Add a price feed (Edit) to value this at the market price.', style: muted)
            else if (market != null && inv.marketPriceOn != null)
              Text(
                '${feedFor(inv.priceSymbol!, unit).label} price as of ${DateFormat('d MMM yyyy').format(inv.marketPriceOn!)}. '
                'Tap refresh on the Assets tab to update.',
                style: muted,
              )
            else
              Text('No market price yet. Tap refresh on the Assets tab when online.', style: muted),
            if (h.buysWithoutQty > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${h.buysWithoutQty} ${h.buysWithoutQty == 1 ? 'buy has' : 'buys have'} no quantity, so ${h.buysWithoutQty == 1 ? 'it is' : 'they are'} '
                'left out of the units held. Tap ${h.buysWithoutQty == 1 ? 'it' : 'them'} below to set one.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (buyDay.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Each buy vs the market that day', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('A premium above market is what the seller charged on top (making charges, spread).', style: muted),
              for (final e in buys.reversed)
                if (buyDay[e.id] != null && e.homeAmount != null && e.homeCurrency == home)
                  _BuyRow(
                    date: e.date,
                    paid: e.homeAmount! / e.quantity!,
                    market: buyDay[e.id]!,
                    quantity: '${formatQuantity(e.quantity!)} ${unit.label}',
                    perUnit: perUnit,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BuyRow extends StatelessWidget {
  const _BuyRow({required this.date, required this.paid, required this.market, required this.quantity, required this.perUnit});

  final DateTime date;
  final double paid;
  final double market;
  final String quantity;
  final String Function(double) perUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final premium = market <= 0 ? 0.0 : (paid / market - 1) * 100;
    // Paying above market is the bad direction here.
    final color = premium.abs() < 0.5
        ? theme.colorScheme.onSurfaceVariant
        : premium > 0
            ? theme.colorScheme.error
            : Colors.green.shade600;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${DateFormat('d MMM yyyy').format(date)} · $quantity', style: theme.textTheme.bodyMedium),
                Text('Paid ${perUnit(paid)} · market ${perUnit(market)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text('${premium >= 0 ? '+' : '−'}${premium.abs().toStringAsFixed(1)}%',
              style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
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
  final _quantities = <int, double?>{};
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
        _select(e);
      }
    });
  }

  /// Ticks an entry with its likely role and, for assets counted in units,
  /// the amount its note mentions.
  void _select(Entry e) {
    _selected[e.id!] = InvestmentFlow.defaultFor(e.kind);
    final unit = widget.investment.unit;
    if (unit != null) _quantities[e.id!] = e.quantity ?? quantityFromNote(e.note, unit);
  }

  Future<void> _save() async {
    await ref.read(repositoryProvider).linkEntries(widget.investment.id, _selected,
        quantities: {for (final id in _selected.keys) if (_quantities.containsKey(id)) id: _quantities[id]});
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
                              _select(e);
                            } else {
                              _selected.remove(e.id);
                              _quantities.remove(e.id);
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
                                if (widget.investment.unit != null && (flow == InvestmentFlow.buy || flow == InvestmentFlow.sale))
                                  ActionChip(
                                    avatar: const Icon(Icons.scale_outlined, size: 18),
                                    label: Text(_quantities[e.id] == null
                                        ? 'Quantity?'
                                        : '${formatQuantity(_quantities[e.id]!)} ${widget.investment.unit!.label}'),
                                    onPressed: () async {
                                      final q = await askQuantity(context, widget.investment.unit!, _quantities[e.id]);
                                      if (q != null) setState(() => _quantities[e.id!] = q > 0 ? q : null);
                                    },
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
  late QuantityUnit? _unit = widget.investment?.unit;

  /// A [priceFeeds] symbol, [_custom] for a typed ticker, or null for none.
  late String? _feed = _initialFeed();
  late final _ticker = TextEditingController(text: _feed == _custom ? widget.investment?.priceSymbol : '');

  static const _custom = '_custom';

  String? _initialFeed() {
    final sym = widget.investment?.priceSymbol;
    if (sym == null) return null;
    return priceFeeds.any((f) => f.symbol == sym) ? sym : _custom;
  }

  String? get _symbol => _feed == _custom ? (_ticker.text.trim().isEmpty ? null : _ticker.text.trim().toUpperCase()) : _feed;

  @override
  void dispose() {
    _name.dispose();
    _ticker.dispose();
    super.dispose();
  }

  /// Picking a feed suggests the type and the unit people usually buy in.
  void _pickFeed(String? v) {
    setState(() {
      _feed = v;
      final feed = priceFeeds.where((f) => f.symbol == v).firstOrNull;
      if (feed == null) {
        if (v == _custom) _unit ??= QuantityUnit.share;
        return;
      }
      if (feed.type != null) _type = feed.type!;
      final usual = switch (feed.quotedPer) {
        QuantityUnit.troyOunce => QuantityUnit.tola,
        QuantityUnit.pound => QuantityUnit.kilogram,
        final u => u,
      };
      if (_unit == null || _unit!.perUnitFactor(feed.quotedPer) == null) _unit = usual;
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final base = widget.investment;
    final symbol = _symbol;
    final priceChanged = base == null || base.priceSymbol != symbol || base.unit != _unit;
    var inv = (base ?? Investment(name: '', type: _type)).copyWith(
      name: _name.text.trim(),
      type: _type,
      closed: _closed,
      unit: () => _unit,
      priceSymbol: () => symbol,
    );
    // The stored price is per unit of the old feed; fetch a fresh one.
    if (priceChanged) {
      inv = inv.copyWith(marketPrice: () => null, marketCurrency: () => null, marketPriceOn: () => null);
    }
    final id = await ref.read(repositoryProvider).saveInvestment(inv);
    if (priceChanged && symbol != null && _unit != null) {
      await ref.read(priceServiceProvider).refresh(ref.read(homeCurrencyProvider));
    }
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
        title: Text(widget.investment == null ? 'New asset' : 'Edit asset'),
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
              key: ValueKey('type-$_type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: [for (final t in AssetType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _feed,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Market price',
                helperText: 'Values what you hold at today\'s price and compares it with what you paid.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('None (type the value in)')),
                for (final f in priceFeeds) DropdownMenuItem<String?>(value: f.symbol, child: Text('${f.label} (${f.symbol})')),
                const DropdownMenuItem<String?>(value: _custom, child: Text('Stock or other ticker…')),
              ],
              onChanged: _pickFeed,
            ),
            if (_feed == _custom) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _ticker,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Yahoo Finance ticker',
                  helperText: 'For example AAPL, VOO, or OGDC.KA if your exchange is listed.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a ticker' : null,
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<QuantityUnit?>(
              key: ValueKey('unit-$_unit-$_feed'),
              initialValue: _unit,
              decoration: const InputDecoration(
                labelText: 'Counted in',
                helperText: 'Record how much each buy or sale was, to get the price per unit.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<QuantityUnit?>(value: null, child: Text('Not counted')),
                for (final u in QuantityUnit.values) DropdownMenuItem<QuantityUnit?>(value: u, child: Text(u.label)),
              ],
              onChanged: (v) => setState(() => _unit = v),
              validator: (v) {
                if (_feed == null) return null;
                if (v == null) return 'Pick a unit to use a market price';
                final feed = _feed == _custom ? null : priceFeeds.firstWhere((f) => f.symbol == _feed);
                if (feed != null && v.perUnitFactor(feed.quotedPer) == null) {
                  return '${feed.label} is priced per ${feed.quotedPer.label}';
                }
                return null;
              },
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
