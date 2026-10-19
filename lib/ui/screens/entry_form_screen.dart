import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/category.dart';
import '../../models/currency.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../state/providers.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({super.key, this.entry});

  final Entry? entry;

  static Future<void> open(BuildContext context, {Entry? entry}) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => EntryFormScreen(entry: entry)),
      );

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  final _form = GlobalKey<FormState>();
  late EntryKind _kind;
  late String _currency;
  late DateTime _date;
  int? _categoryId;
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  var _fetchingRate = false;
  var _saving = false;

  String get _home => ref.read(homeCurrencyProvider);

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _kind = e?.kind ?? EntryKind.expense;
    _currency = e?.currency ?? _home;
    _date = e?.date ?? DateTime.now();
    _categoryId = e?.categoryId;
    if (e != null) {
      _amount.text = _plain(e.amount);
      _note.text = e.note;
      if (e.fxRate != null && e.homeCurrency == _home) _rate.text = _plain(e.fxRate!);
    }
    if (_currency != _home && _rate.text.isEmpty) _fetchRate();
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _fetchRate() async {
    if (_currency == _home) return;
    setState(() => _fetchingRate = true);
    final r = await ref.read(fxServiceProvider).rate(_currency, _home, _date);
    if (!mounted) return;
    setState(() {
      _fetchingRate = false;
      if (r != null) _rate.text = r.toStringAsFixed(4);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    if (_currency != _home) _fetchRate();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final amount = double.parse(_amount.text.replaceAll(',', ''));
    final rate = _currency == _home ? 1.0 : double.tryParse(_rate.text);
    final base = widget.entry;
    final entry = Entry(
      id: base?.id,
      kind: _kind,
      amount: amount,
      currency: _currency,
      homeCurrency: _home,
      fxRate: rate,
      categoryId: _categoryId!,
      date: _date,
      note: _note.text.trim(),
      source: base?.source ?? EntrySource.manual,
    );
    await ref.read(repositoryProvider).saveEntry(entry);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeCurrencyProvider);
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final cats = all.where((c) => c.kind == _kind && (!c.archived || c.id == _categoryId)).toList();
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) _categoryId = null;
    final notes = ref.watch(recentNotesProvider).value ?? const <String>[];
    final foreign = _currency != home;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'New entry' : 'Edit entry'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<EntryKind>(
              segments: const [
                ButtonSegment(value: EntryKind.expense, label: Text('Expense'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: EntryKind.income, label: Text('Income'), icon: Icon(Icons.south_west)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _amount,
                    autofocus: widget.entry == null,
                    decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
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
                    onChanged: (v) {
                      setState(() {
                        _currency = v!;
                        _rate.clear();
                      });
                      _fetchRate();
                    },
                  ),
                ),
              ],
            ),
            if (foreign) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _rate,
                decoration: InputDecoration(
                  labelText: '1 $_currency = ? $home',
                  helperText: 'Fetched for the entry date. Leave empty to fill in later.',
                  border: const OutlineInputBorder(),
                  suffixIcon: _fetchingRate
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(icon: const Icon(Icons.refresh), tooltip: 'Fetch rate', onPressed: _fetchRate),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = double.tryParse(v);
                  return n == null || n <= 0 ? 'Enter a valid rate' : null;
                },
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey(_kind),
              initialValue: _categoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _kind == EntryKind.income ? 'Income type' : 'Expense type',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in cats)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.bucket == null ? c.name : '${c.name}  ·  ${c.bucket!.label}'),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
              validator: (v) => v == null ? 'Pick a type' : null,
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
              ),
            ),
            const SizedBox(height: 16),
            RawAutocomplete<String>(
              textEditingController: _note,
              focusNode: _noteFocus,
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const [];
                return notes.where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q).take(5);
              },
              fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
                controller: controller,
                focusNode: focus,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  helperText: 'Entries with matching notes are grouped in Insights.',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final o in options) ListTile(title: Text(o), onTap: () => onSelected(o)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
