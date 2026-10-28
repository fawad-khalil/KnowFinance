import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/category.dart';
import '../../models/currency.dart';
import '../../models/enums.dart';
import '../../models/recurring_payment.dart';
import '../../state/budget_providers.dart';
import '../../state/providers.dart';

/// Rent, bills, fees and subscriptions that repeat on a schedule.
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecurringScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cats = ref.watch(categoryByIdProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring payments')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-recurring',
        onPressed: () => RecurringForm.open(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ref.watch(recurringProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load: $e')),
            data: (list) => list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Add rent, utility bills, school fees or subscriptions. Each is logged as an expense when it falls '
                        'due, or waits for you to mark it paid, and what is due each month is budgeted for it.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final p in list)
                        ListTile(
                          enabled: !p.paused,
                          leading: Icon(p.autoPost ? Icons.autorenew : Icons.notifications_none),
                          title: Text(p.name),
                          subtitle: Text([
                            p.scheduleLabel,
                            cats[p.categoryId]?.name ?? '',
                            if (p.paused)
                              'paused'
                            else if (_next(p, today) case final next?)
                              'next ${DateFormat('d MMM').format(next)}'
                            else
                              'ended',
                          ].join(' · ')),
                          trailing: Text(formatMoney(p.amount, p.currency), style: theme.textTheme.titleSmall),
                          onTap: () => RecurringForm.open(context, payment: p),
                        ),
                    ],
                  ),
          ),
    );
  }

  static DateTime? _next(RecurringPayment p, DateTime today) {
    final ahead = p.dueDates(today, DateTime(today.year + 2, today.month, today.day));
    return ahead.isEmpty ? null : ahead.first;
  }
}

class RecurringForm extends ConsumerStatefulWidget {
  const RecurringForm({super.key, this.payment});

  final RecurringPayment? payment;

  static Future<void> open(BuildContext context, {RecurringPayment? payment}) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => RecurringForm(payment: payment)),
      );

  @override
  ConsumerState<RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<RecurringForm> {
  final _form = GlobalKey<FormState>();
  late final RecurringPayment? _p = widget.payment;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _amount = TextEditingController(text: _p == null ? '' : _plain(_p.amount));
  late final _every = TextEditingController(text: '${_p?.every ?? 1}');
  late String _currency = _p?.currency ?? ref.read(homeCurrencyProvider);
  late int? _categoryId = _p?.categoryId;
  late var _unit = _p?.unit ?? RepeatUnit.month;
  late var _start = _p?.startDate ?? _today;
  late DateTime? _end = _p?.endDate;
  late var _autoPost = _p?.autoPost ?? true;
  late var _paused = _p?.paused ?? false;
  var _saving = false;

  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _every.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final values = RecurringPayment(
      name: _name.text.trim(),
      categoryId: _categoryId!,
      amount: double.parse(_amount.text.replaceAll(',', '')),
      currency: _currency,
      every: int.parse(_every.text),
      unit: _unit,
      startDate: _start,
      endDate: _end,
      autoPost: _autoPost,
      paused: _paused,
      createdOn: _today,
    );
    final p = _p == null
        ? values
        : _p.copyWith(
            name: values.name,
            categoryId: values.categoryId,
            amount: values.amount,
            currency: values.currency,
            every: values.every,
            unit: values.unit,
            startDate: values.startDate,
            endDate: () => values.endDate,
            autoPost: values.autoPost,
            paused: values.paused,
          );
    await ref.read(repositoryProvider).saveRecurring(p);
    if (_p?.paused == true && !p.paused) await ref.read(recurringServiceProvider).skipWhilePaused(p);
    await ref.read(recurringServiceProvider).postDue(ref.read(homeCurrencyProvider));
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_p!.name}?'),
        content: const Text('It stops being logged and budgeted. Expenses already logged for it stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).deleteRecurring(_p!.id!);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(_today.year + 30),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == EntryKind.expense && !c.isSystem && (!c.archived || c.id == _categoryId))
        .toList();
    final every = int.tryParse(_every.text) ?? 1;
    final preview = RecurringPayment(
            name: '', categoryId: 0, amount: 0, currency: '', every: every < 1 ? 1 : every, unit: _unit,
            startDate: _start, endDate: _end, createdOn: _today)
        .dueDates(_today, DateTime(_today.year + 3, _today.month, _today.day))
        .take(3);
    return Scaffold(
      appBar: AppBar(
        title: Text(_p == null ? 'New recurring payment' : 'Edit recurring payment'),
        actions: [
          if (_p != null) IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: _p == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'House rent, K-Electric, School fee',
                helperText: 'Used as the note on each expense, so it groups with the ones you log by hand.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(
                        labelText: 'Amount', helperText: 'The usual amount', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    validator: (v) {
                      final n = double.tryParse((v ?? '').replaceAll(',', ''));
                      return n == null || n <= 0 ? 'Enter an amount' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder()),
                    items: [
                      for (final c in currencies) DropdownMenuItem(value: c.code, child: Text(c.code)),
                      if (!currencies.any((c) => c.code == _currency))
                        DropdownMenuItem(value: _currency, child: Text(_currency)),
                    ],
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Expense type', border: OutlineInputBorder()),
              items: [
                for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${c.name}  ·  ${c.bucket!.label}')),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
              validator: (v) => v == null ? 'Pick a type' : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    controller: _every,
                    decoration: const InputDecoration(labelText: 'Every', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? '1 or more' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<RepeatUnit>(
                    initialValue: _unit,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      for (final u in RepeatUnit.values)
                        DropdownMenuItem(value: u, child: Text(every == 1 ? u.label : '${u.label}s')),
                    ],
                    onChanged: (v) => setState(() => _unit = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final d = await _pick(_start);
                if (d != null) setState(() => _start = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'First due date', border: OutlineInputBorder()),
                child: Text(DateFormat('EEE, d MMM yyyy').format(_start)),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final d = await _pick(_end ?? _start.add(const Duration(days: 365)));
                if (d != null) setState(() => _end = d);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Ends (optional)',
                  border: const OutlineInputBorder(),
                  suffixIcon:
                      _end == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _end = null)),
                ),
                child: Text(_end == null ? 'Never' : DateFormat('EEE, d MMM yyyy').format(_end!)),
              ),
            ),
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text('Next: ${preview.map(DateFormat('d MMM yyyy').format).join(', ')}', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log it automatically'),
              subtitle: Text(_autoPost
                  ? 'An expense for the usual amount is added on each due date. Edit it if the bill came to more or less.'
                  : 'It shows as due on the Budget tab until you mark it paid with the actual amount.'),
              value: _autoPost,
              onChanged: (v) => setState(() => _autoPost = v),
            ),
            if (_p != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Paused'),
                subtitle: const Text('Not logged or budgeted until resumed.'),
                value: _paused,
                onChanged: (v) => setState(() => _paused = v),
              ),
            if (_p == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Due dates before today are taken as already logged, so nothing is added twice.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
