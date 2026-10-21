import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/currency.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../models/loan.dart';
import '../../services/loan_analytics.dart';
import '../../state/providers.dart';
import 'investments_screen.dart' show StatTile;

/// Balances for every loan from its linked entries.
final loanAnalyticsProvider = Provider<AsyncValue<LoanAnalytics>>((ref) {
  final loans = ref.watch(loansProvider);
  final linked = ref.watch(loanEntriesProvider);
  final home = ref.watch(homeCurrencyProvider);
  if (loans.hasError) return AsyncValue.error(loans.error!, loans.stackTrace ?? StackTrace.empty);
  if (linked.hasError) return AsyncValue.error(linked.error!, linked.stackTrace ?? StackTrace.empty);
  if (!loans.hasValue || !linked.hasValue) return const AsyncValue.loading();
  return AsyncValue.data(LoanAnalytics(loans.value!, linked.value!, home));
});

/// Payables (money the user borrowed) and receivables (money the user lent),
/// each worked out from the money that went out and came back.
class LoansView extends ConsumerWidget {
  const LoansView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(loanAnalyticsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (a) => a.balances.isEmpty ? const _Empty() : _Loans(analytics: a),
        );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.handshake_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Track what you owe and are owed', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Add a loan you took or gave. Money borrowed or got back is not income, and money lent or repaid is not '
              'spending, so loans are kept out of your totals and savings and shown here instead.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Loans extends StatelessWidget {
  const _Loans({required this.analytics});

  final LoanAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final theme = Theme.of(context);
    final home = a.home;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        Card(
          margin: const EdgeInsets.only(top: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Loans', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  runSpacing: 12,
                  children: [
                    StatTile(label: 'You owe (payables)', value: compactMoney(a.totalPayable, home)),
                    StatTile(label: 'Owed to you (receivables)', value: compactMoney(a.totalReceivable, home)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  a.net == 0
                      ? 'What you owe and are owed balance out.'
                      : a.net > 0
                          ? 'Overall you are owed ${formatMoney(a.net, home)}.'
                          : 'Overall you owe ${formatMoney(-a.net, home)}.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        _Section(title: 'Payables', subtitle: 'Money you borrowed', balances: a.payables, home: home),
        _Section(title: 'Receivables', subtitle: 'Money you lent', balances: a.receivables, home: home),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.subtitle, required this.balances, required this.home});

  final String title;
  final String subtitle;
  final List<LoanBalance> balances;
  final String home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(subtitle, style: theme.textTheme.bodySmall),
          ),
          if (balances.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 16), child: Text('None.')),
          for (final b in balances) _LoanTile(balance: b, home: home),
        ],
      ),
    );
  }
}

class _LoanTile extends StatelessWidget {
  const _LoanTile({required this.balance, required this.home});

  final LoanBalance balance;
  final String home;

  @override
  Widget build(BuildContext context) {
    final b = balance;
    final theme = Theme.of(context);
    final payable = b.loan.direction == LoanDirection.payable;
    final out = payable ? 'repaid' : 'got back';
    return ListTile(
      onTap: () => LoanDetailScreen.open(context, b.loan.id!),
      title: Text(b.loan.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              '${payable ? 'Borrowed' : 'Lent'} ${compactMoney(b.opened, home)}',
              '$out ${compactMoney(b.settled, home)}',
              if (b.loan.dueDate != null) 'due ${DateFormat('d MMM yyyy').format(b.loan.dueDate!)}',
            ].join(' · '),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: b.progress,
              minHeight: 6,
              color: Colors.green.shade600,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            b.isSettled ? 'Settled' : compactMoney(b.outstanding.abs(), home),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: b.isSettled ? Colors.green.shade600 : (b.isOverdue ? theme.colorScheme.error : null),
            ),
          ),
          Text(
            b.isSettled
                ? ''
                : b.outstanding < 0
                    ? 'overpaid'
                    : b.isOverdue
                        ? 'overdue'
                        : 'left',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// One loan: how much was borrowed or lent, how much has been settled, and
/// every payment with the balance after it.
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final int loanId;

  static Future<void> open(BuildContext context, int id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoanDetailScreen(loanId: id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(loanAnalyticsProvider).value;
    final b = a?[loanId];
    if (a == null || b == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final home = a.home;
    final theme = Theme.of(context);
    final loan = b.loan;
    final payable = loan.direction == LoanDirection.payable;

    // Running balance, oldest first, then shown newest first.
    var running = 0.0;
    final rows = <(Entry, double)>[];
    for (final e in b.entries) {
      final amt = e.homeCurrency == home ? (e.homeAmount ?? 0) : 0.0;
      running += e.kind == loan.direction.openingKind ? amt : -amt;
      rows.add((e, running));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loan.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => LoanForm.open(context, loan: loan),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v != 'delete') return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this loan?'),
                  content: const Text(
                      'Its entries stay in your list on the "Loan" type. Edit them to give each a type again.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok != true) return;
              await ref.read(repositoryProvider).deleteLoan(loan.id!);
              ref.read(dataVersionProvider.notifier).bump();
              if (context.mounted) Navigator.pop(context);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete loan'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'link-loan',
        onPressed: () => LinkLoanEntriesScreen.open(context, loan),
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
                  Text('${loan.direction.short} · ${loan.direction.label}', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 12),
                  Text(b.isSettled ? 'Settled' : (payable ? 'You still owe' : 'Still owed to you'),
                      style: theme.textTheme.labelMedium),
                  Text(
                    b.isSettled ? formatMoney(0, home) : formatMoney(b.outstanding.abs(), home),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (b.outstanding < -0.5)
                    Text(
                      payable
                          ? 'You have paid back ${formatMoney(-b.outstanding, home)} more than you borrowed. '
                              'If that was interest, log it as an expense instead.'
                          : 'You got back ${formatMoney(-b.outstanding, home)} more than you lent.',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: b.progress,
                      minHeight: 10,
                      color: Colors.green.shade600,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${(b.progress * 100).toStringAsFixed(0)}% ${payable ? 'repaid' : 'got back'}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    runSpacing: 12,
                    children: [
                      StatTile(label: payable ? 'Borrowed' : 'Lent', value: formatMoney(b.opened, home)),
                      StatTile(label: payable ? 'Repaid' : 'Got back', value: formatMoney(b.settled, home)),
                      if (loan.dueDate != null)
                        StatTile(label: 'Due', value: DateFormat('d MMM yyyy').format(loan.dueDate!)),
                      if (b.last != null) StatTile(label: 'Last payment', value: DateFormat('d MMM yyyy').format(b.last!)),
                    ],
                  ),
                  if (loan.note.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(loan.note, style: theme.textTheme.bodyMedium),
                  ],
                  if (b.skipped > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${b.skipped} ${b.skipped == 1 ? 'entry needs' : 'entries need'} an exchange rate and '
                      "${b.skipped == 1 ? "isn't" : "aren't"} counted.",
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
                  child: Text('Money in and out', style: theme.textTheme.titleMedium),
                ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text('Nothing yet. Add an entry marked as a loan, or link ones already in your list.'),
                  ),
                for (final (e, after) in rows.reversed)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: e.kind == EntryKind.income
                          ? Colors.green.withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Icon(e.kind == EntryKind.income ? Icons.south_west : Icons.north_east, size: 20),
                    ),
                    title: Text(loan.direction.flowLabel(e.kind)),
                    subtitle: Text([
                      DateFormat('d MMM yyyy').format(e.date),
                      if (e.note.isNotEmpty && e.note != loan.name) e.note,
                    ].join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${e.kind == EntryKind.income ? '+' : '−'}${formatMoney(e.amount, e.currency)}',
                          style: theme.textTheme.titleSmall,
                        ),
                        Text('balance ${compactMoney(after, home)}', style: theme.textTheme.bodySmall),
                      ],
                    ),
                    onLongPress: () async {
                      await ref.read(repositoryProvider).linkLoanEntries(null, [e]);
                      ref.read(dataVersionProvider.notifier).bump();
                    },
                  ),
                if (rows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text('Long-press a payment to unlink it.', style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Adds or edits a loan's name, direction, due date and note.
class LoanForm extends ConsumerStatefulWidget {
  const LoanForm({super.key, this.loan, this.direction});

  final Loan? loan;

  /// Preset direction for a new loan.
  final LoanDirection? direction;

  static Future<int?> open(BuildContext context, {Loan? loan, LoanDirection? direction}) =>
      Navigator.of(context).push<int>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LoanForm(loan: loan, direction: direction),
      ));

  @override
  ConsumerState<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends ConsumerState<LoanForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.loan?.name ?? '');
  late final _note = TextEditingController(text: widget.loan?.note ?? '');
  late var _direction = widget.loan?.direction ?? widget.direction ?? LoanDirection.payable;
  late DateTime? _due = widget.loan?.dueDate;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final base = widget.loan ?? Loan(name: '', direction: _direction);
    final id = await ref.read(repositoryProvider).saveLoan(base.copyWith(
          name: _name.text.trim(),
          direction: _direction,
          note: _note.text.trim(),
          dueDate: () => _due,
        ));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.loan != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit loan' : 'New loan'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<LoanDirection>(
              segments: [
                for (final d in LoanDirection.values) ButtonSegment(value: d, label: Text(d.label)),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _direction == LoanDirection.payable
                  ? 'A payable: money you have to pay back.'
                  : 'A receivable: money someone has to pay you back.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: !editing,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _direction == LoanDirection.payable ? 'Borrowed from' : 'Lent to',
                helperText: 'A person, a bank or a name like "Car loan". Matching entry notes are linked faster.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _due ?? now.add(const Duration(days: 30)),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(now.year + 30),
                );
                if (d != null) setState(() => _due = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Due date (optional)',
                  border: const OutlineInputBorder(),
                  suffixIcon: _due == null
                      ? null
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _due = null)),
                ),
                child: Text(_due == null ? 'None' : DateFormat('EEE, d MMM yyyy').format(_due!)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks existing entries that belong to a loan. Entries whose note
/// mentions the loan's name come first and are ticked.
class LinkLoanEntriesScreen extends ConsumerStatefulWidget {
  const LinkLoanEntriesScreen({super.key, required this.loan});

  final Loan loan;

  static Future<void> open(BuildContext context, Loan loan) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => LinkLoanEntriesScreen(loan: loan)),
      );

  @override
  ConsumerState<LinkLoanEntriesScreen> createState() => _LinkLoanEntriesScreenState();
}

class _LinkLoanEntriesScreenState extends ConsumerState<LinkLoanEntriesScreen> {
  List<Entry>? _candidates;
  final _selected = <int>{};
  var _matches = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _mentions(Entry e) {
    final n = e.note.toLowerCase().trim(), l = widget.loan.name.toLowerCase().trim();
    return n.isNotEmpty && (n.contains(l) || l.contains(n));
  }

  Future<void> _load() async {
    final list = await ref.read(repositoryProvider).unlinkedLoanCandidates();
    final matches = list.where(_mentions).toList();
    if (!mounted) return;
    setState(() {
      _candidates = [...matches, ...list.where((e) => !_mentions(e))];
      _matches = matches.length;
      _selected.addAll(matches.map((e) => e.id!));
    });
  }

  Future<void> _save() async {
    await ref
        .read(repositoryProvider)
        .linkLoanEntries(widget.loan.id, _candidates!.where((e) => _selected.contains(e.id)));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoryByIdProvider);
    final theme = Theme.of(context);
    final list = _candidates;
    final loan = widget.loan;
    return Scaffold(
      appBar: AppBar(
        title: Text('Link to ${loan.name}'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _save,
            child: Text(_selected.isEmpty ? 'Link' : 'Link ${_selected.length}'),
          ),
        ],
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      '${_matches > 0 ? '$_matches ${_matches == 1 ? 'entry mentions' : 'entries mention'} "${loan.name}" and '
                          '${_matches == 1 ? 'is' : 'are'} ticked. ' : ''}'
                      'Linked entries stop counting as income or spending. Money in is '
                      '${loan.direction.flowLabel(EntryKind.income).toLowerCase()}, money out is '
                      '${loan.direction.flowLabel(EntryKind.expense).toLowerCase()}.',
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                }
                final e = list[i - 1];
                final income = e.kind == EntryKind.income;
                return CheckboxListTile(
                  value: _selected.contains(e.id),
                  onChanged: (on) => setState(() => on == true ? _selected.add(e.id!) : _selected.remove(e.id)),
                  title: Text(e.note.isEmpty ? (cats[e.categoryId]?.name ?? '') : e.note),
                  subtitle: Text(
                      '${loan.direction.flowLabel(e.kind)} · ${cats[e.categoryId]?.name ?? ''} · ${DateFormat('d MMM yyyy').format(e.date)}'),
                  secondary: Text(
                    '${income ? '+' : '−'}${formatMoney(e.amount, e.currency)}',
                    style: theme.textTheme.titleSmall?.copyWith(color: income ? Colors.green.shade600 : null),
                  ),
                );
              },
            ),
    );
  }
}
