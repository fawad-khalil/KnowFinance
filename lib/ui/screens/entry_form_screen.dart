import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/category.dart';
import '../../models/currency.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../models/investment.dart';
import '../../models/loan.dart';
import '../../services/investment_analytics.dart';
import '../../services/price_service.dart';
import 'investments_screen.dart' show formatQuantity;
import 'loans_screen.dart' show LoanForm;
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
  int? _investmentId;

  /// Borrowed, repaid, lent or got back: money that is neither income nor
  /// spending, kept against a loan instead.
  var _isLoan = false;
  int? _loanId;
  InvestmentFlow? _flow;

  /// Set once the user picks an investment themselves, so a matching note
  /// no longer changes it.
  var _investmentTouched = false;
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();
  final _qty = TextEditingController();
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
    _investmentId = e?.investmentId;
    _isLoan = e?.loanId != null;
    _loanId = e?.loanId;
    _flow = e?.investmentFlow;
    _investmentTouched = e?.investmentId != null;
    if (e?.quantity != null) _qty.text = formatQuantity(e!.quantity!);
    if (e != null) {
      _amount.text = _plain(e.amount);
      _note.text = e.note;
      if (e.fxRate != null && e.homeCurrency == _home) _rate.text = _plain(e.fxRate!);
    }
    if (_currency != _home && _rate.text.isEmpty) _fetchRate();
    // Added after the note is filled so opening an entry never relinks it.
    _note.addListener(_suggestInvestment);
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _note.dispose();
    _qty.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  /// Links the entry to an investment whose name its note mentions, until
  /// the user picks one themselves.
  void _suggestInvestment() {
    _suggestQuantity();
    if (_investmentTouched) return;
    final list = ref.read(investmentsProvider).value ?? const <Investment>[];
    final match = list.where((i) => !i.closed && noteMatchesInvestment(_note.text, i.name)).firstOrNull;
    if (match?.id == _investmentId) return;
    setState(() {
      _investmentId = match?.id;
      _flow = match == null ? null : InvestmentFlow.defaultFor(_kind);
    });
  }

  Investment? get _investment =>
      (ref.read(investmentsProvider).value ?? const <Investment>[]).where((i) => i.id == _investmentId).firstOrNull;

  /// Fills the quantity from a note like "Gold 2 tola" while it's empty.
  void _suggestQuantity() {
    final unit = _investment?.unit;
    if (unit == null || _qtyTouched) return;
    final q = quantityFromNote(_note.text, unit);
    final text = q == null ? '' : formatQuantity(q);
    if (_qty.text != text) _qty.text = text;
  }

  var _qtyTouched = false;

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
    final loanCategory = _isLoan ? await ref.read(repositoryProvider).loanCategoryId(_kind) : null;
    final entry = Entry(
      id: base?.id,
      kind: _kind,
      amount: amount,
      currency: _currency,
      homeCurrency: _home,
      fxRate: rate,
      categoryId: loanCategory ?? _categoryId!,
      date: _date,
      note: _note.text.trim(),
      source: base?.source ?? EntrySource.manual,
      investmentId: _isLoan ? null : _investmentId,
      investmentFlow: _isLoan || _investmentId == null ? null : (_flow ?? InvestmentFlow.defaultFor(_kind)),
      quantity: _isLoan || _investment?.unit == null ? null : double.tryParse(_qty.text),
      loanId: _isLoan ? _loanId : null,
    );
    await ref.read(repositoryProvider).saveEntry(entry);
    ref.read(dataVersionProvider.notifier).bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeCurrencyProvider);
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final cats = all.where((c) => c.kind == _kind && !c.isSystem && (!c.archived || c.id == _categoryId)).toList();
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) _categoryId = null;
    final notes = ref.watch(recentNotesProvider).value ?? const <String>[];
    final foreign = _currency != home;
    final investments = ref.watch(investmentsProvider).value ?? const <Investment>[];
    final category = all.where((c) => c.id == _categoryId).firstOrNull;
    // Buying goes in Savings; returns can be any income type.
    final loans = ref.watch(loansProvider).value ?? const <Loan>[];
    final loan = loans.where((l) => l.id == _loanId).firstOrNull;
    final showInvestment = !_isLoan &&
        investments.isNotEmpty &&
        (_investmentId != null || _kind == EntryKind.income || category?.bucket == Bucket.savings);

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
                if (_flow != null && _flow!.kind != _kind) _flow = InvestmentFlow.defaultFor(_kind);
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('This is a loan'),
              subtitle: const Text('Money borrowed or lent, or paid back. Kept out of income and spending.'),
              value: _isLoan,
              onChanged: (v) => setState(() => _isLoan = v),
            ),
            if (_isLoan) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey('loan-$_loanId-${loans.length}'),
                initialValue: _loanId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Loan', border: OutlineInputBorder()),
                items: [
                  for (final l in loans)
                    DropdownMenuItem(value: l.id, child: Text('${l.name}  ·  ${l.direction.short}')),
                  const DropdownMenuItem(value: -1, child: Text('New loan…')),
                ],
                onChanged: (v) async {
                  if (v != -1) return setState(() => _loanId = v);
                  // Money coming in usually starts a loan you took; going out, one you gave.
                  final id = await LoanForm.open(context,
                      direction: _kind == EntryKind.income ? LoanDirection.payable : LoanDirection.receivable);
                  if (mounted) setState(() => _loanId = id);
                },
                validator: (v) => v == null || v == -1 ? 'Pick or add a loan' : null,
              ),
              if (loan != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    '${loan.direction.flowLabel(_kind)}: ${switch ((loan.direction, _kind)) {
                      (LoanDirection.payable, EntryKind.income) => 'adds to what you owe.',
                      (LoanDirection.payable, EntryKind.expense) => 'brings down what you owe.',
                      (LoanDirection.receivable, EntryKind.expense) => 'adds to what you are owed.',
                      (LoanDirection.receivable, EntryKind.income) => 'brings down what you are owed.',
                    }} Interest or fees are spending: log them as a separate expense.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            if (!_isLoan) ...[
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
            ],
            if (showInvestment) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                key: ValueKey('inv-$_investmentId'),
                initialValue: _investmentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Investment (optional)',
                  helperText: 'Link buys, costs, sales, dividends and rent to see profit or loss.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None')),
                  for (final i in investments)
                    if (!i.closed || i.id == _investmentId)
                      DropdownMenuItem<int?>(value: i.id, child: Text('${i.name}  ·  ${i.type.label}')),
                ],
                onChanged: (v) {
                  setState(() {
                    _investmentTouched = true;
                    _investmentId = v;
                    _flow = v == null ? null : (_flow ?? InvestmentFlow.defaultFor(_kind));
                  });
                  _suggestQuantity();
                },
              ),
              if (_investmentId != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final f in InvestmentFlow.forKind(_kind))
                      ChoiceChip(
                        label: Text(f.label),
                        selected: (_flow ?? InvestmentFlow.defaultFor(_kind)) == f,
                        onSelected: (_) => setState(() => _flow = f),
                      ),
                  ],
                ),
                if (_investment?.unit != null &&
                    (_flow ?? InvestmentFlow.defaultFor(_kind)) != InvestmentFlow.cost &&
                    (_flow ?? InvestmentFlow.defaultFor(_kind)) != InvestmentFlow.income) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qty,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      suffixText: _investment!.unit!.label,
                      helperText: 'How much this bought or sold. Read from the note when it says e.g. "2 tola".',
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    onChanged: (_) => _qtyTouched = true,
                    validator: (v) => (v ?? '').isEmpty || (double.tryParse(v!) ?? 0) > 0 ? null : 'Enter a valid amount',
                  ),
                ],
              ],
            ],
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
