import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/currency.dart';
import '../../models/enums.dart';
import '../../state/budget_providers.dart';
import '../../state/providers.dart';

/// Sets the standing monthly budgets: one total, a budget per expense type,
/// or both, in which case the types divide up the total.
class BudgetEditScreen extends ConsumerStatefulWidget {
  const BudgetEditScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BudgetEditScreen()),
      );

  @override
  ConsumerState<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends ConsumerState<BudgetEditScreen> {
  final _overall = TextEditingController();
  final _byType = <int, TextEditingController>{};
  var _useTotal = false;
  var _loaded = false;
  var _saving = false;

  /// What was saved, to only write what changed.
  final _initial = <int?, double>{};

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  static double? _parse(String s) => double.tryParse(s.replaceAll(',', ''));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final budgets = await ref.read(repositoryProvider).budgets();
    if (!mounted) return;
    setState(() {
      for (final b in budgets) {
        _initial[b.categoryId] = b.amount;
        if (b.isOverall) {
          _useTotal = true;
          _overall.text = _plain(b.amount);
        } else {
          _controller(b.categoryId!).text = _plain(b.amount);
        }
      }
      _loaded = true;
    });
  }

  TextEditingController _controller(int id) => _byType.putIfAbsent(id, TextEditingController.new);

  @override
  void dispose() {
    _overall.dispose();
    for (final c in _byType.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final wanted = <int?, double?>{
      null: _useTotal ? _parse(_overall.text) : null,
      for (final e in _byType.entries) e.key: _parse(e.value.text),
    };
    for (final w in wanted.entries) {
      final v = w.value != null && w.value! > 0 ? w.value : null;
      if (v != _initial[w.key]) await repo.setBudget(w.key, v);
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = ref.watch(homeCurrencyProvider);
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == EntryKind.expense && !c.isSystem && (!c.archived || _byType[c.id]?.text.isNotEmpty == true))
        .toList()
      ..sort((a, b) => a.bucket!.index != b.bucket!.index
          ? a.bucket!.index.compareTo(b.bucket!.index)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final month = ref.watch(budgetMonthDataProvider).value;
    final scheduled = {for (final l in month?.lines ?? const []) l.category.id!: l.scheduled};
    final typesTotal = _byType.values.fold(0.0, (s, c) => s + (_parse(c.text) ?? 0));
    final billsTotal = scheduled.values.fold(0.0, (s, v) => s + v);
    final overall = _parse(_overall.text);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly budget'),
        actions: [TextButton(onPressed: _saving || !_loaded ? null : _save, child: const Text('Save'))],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set a monthly total'),
                  subtitle: Text(_useTotal
                      ? 'Type budgets below are optional and divide up the total.'
                      : 'Off: the month\'s budget is what the types below add up to.'),
                  value: _useTotal,
                  onChanged: (v) => setState(() => _useTotal = v),
                ),
                if (_useTotal) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _overall,
                    decoration: InputDecoration(
                      labelText: 'Monthly total',
                      suffixText: home,
                      border: const OutlineInputBorder(),
                      helperText: billsTotal > 0 ? 'Recurring payments due this month: ${formatMoney(billsTotal, home)}' : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 16),
                Text('By expense type', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Recurring payments budget for themselves: what they fall due for is added on top of what you set here.',
                  style: muted,
                ),
                for (final (i, c) in cats.indexed) ...[
                  if (i == 0 || cats[i - 1].bucket != c.bucket)
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 4),
                      child: Text(c.bucket!.label, style: theme.textTheme.labelLarge),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name),
                              if ((scheduled[c.id] ?? 0) > 0) Text('+ ${formatMoney(scheduled[c.id]!, home)} in bills', style: muted),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _controller(c.id!),
                            textAlign: TextAlign.end,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '0',
                              suffixText: home,
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 32),
                Text(
                  'Types: ${formatMoney(typesTotal, home)}'
                  '${billsTotal > 0 ? ' + bills ${formatMoney(billsTotal, home)} = ${formatMoney(typesTotal + billsTotal, home)}' : ''}',
                  style: theme.textTheme.titleSmall,
                ),
                if (_useTotal && overall != null && overall > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    typesTotal + billsTotal <= overall
                        ? '${formatMoney(overall - typesTotal - billsTotal, home)} of the total is left for anything else.'
                        : 'That is ${formatMoney(typesTotal + billsTotal - overall, home)} more than the monthly total.',
                    style: typesTotal + billsTotal <= overall ? muted : theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
    );
  }
}
