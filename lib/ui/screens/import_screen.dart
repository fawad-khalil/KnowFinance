import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../import/import_service.dart';
import '../../import/pending_import.dart';
import '../../import/sms_reader.dart';
import '../../models/category.dart';
import '../../models/currency.dart';
import '../../models/enums.dart';
import '../../state/providers.dart';

/// Hidden for now: banks send statements as PDF, and only CSV is read so
/// far. The CSV parser stays for when PDF reading is added.
const statementImportEnabled = false;

/// Brings in transactions from SMS, pasted text or statements, and lists
/// them for review before they become entries.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen()));

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  var _busy = false;

  ImportService get _service => ref.read(importServiceProvider);

  Future<void> _run(Future<ImportResult> Function() job, {String? what}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await job();
      ref.read(dataVersionProvider.notifier).bump();
      final scanned = r.scanned == null ? '' : 'Checked ${r.scanned} messages. ';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.found == 0
                ? '${scanned}No transactions found${what == null ? '' : ' in $what'}.'
                : '$scanned${r.added} new to review${r.found > r.added ? ', ${r.found - r.added} already imported' : ''}.',
          ),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanSms() async {
    final access = await const SmsReader().requestAccess();
    if (!mounted) return;
    switch (access) {
      case SmsAccess.granted:
        await _run(_service.scanSms);
      case SmsAccess.permanentlyDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('SMS access is turned off for KnowFinance.'),
            action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
          ),
        );
      case SmsAccess.denied:
      case SmsAccess.unsupported:
        break;
    }
  }

  Future<void> _paste() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _PasteDialog());
    if (text == null || text.trim().isEmpty) return;
    await _run(() => _service.importText(text), what: 'that text');
  }

  Future<void> _statement() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    if (files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    await _run(
      () => _service.importStatementCsv(utf8.decode(bytes, allowMalformed: true), fileName: file.name),
      what: file.name,
    );
  }

  Future<void> _acceptAll(List<PendingImport> items) async {
    final suggester = await ref.read(categorySuggesterProvider.future);
    final home = ref.read(homeCurrencyProvider);
    setState(() => _busy = true);
    var added = 0;
    for (final p in items) {
      final cat = suggester.suggest(p.kind, p.counterparty, p.raw);
      if (cat == null) continue;
      await _service.accept(p, categoryId: cat, kind: p.kind, note: p.counterparty, homeCurrency: home);
      added++;
    }
    ref.read(dataVersionProvider.notifier).bump();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $added. ${items.length - added > 0 ? '${items.length - added} need a type picked.' : ''}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingImportsProvider);
    final items = pending.value ?? const <PendingImport>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import'),
        actions: [
          if (items.isNotEmpty)
            TextButton(onPressed: _busy ? null : () => _acceptAll(items), child: const Text('Add all')),
        ],
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (SmsReader.supported)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _scanSms,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Scan SMS'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Paste SMS or email'),
                ),
                if (statementImportEnabled)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _statement,
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Bank statement (CSV)'),
                  ),
              ],
            ),
          ),
          if (SmsReader.supported && _service.lastSmsScan != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'SMS last checked ${DateFormat('d MMM, h:mm a').format(_service.lastSmsScan!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          if (pending.isLoading && items.isEmpty) const Center(child: CircularProgressIndicator()),
          if (!pending.isLoading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nothing to review. Imported transactions appear here before they are added.',
                textAlign: TextAlign.center,
              ),
            ),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('${items.length} to review', style: Theme.of(context).textTheme.titleSmall),
            ),
          for (final p in items) _ImportCard(key: ValueKey(p.id), item: p),
        ],
      ),
    );
  }
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste SMS or email'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 10,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: 'Paste one or more bank alerts. Separate messages with a blank line.',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Import')),
      ],
    );
  }
}

class _ImportCard extends ConsumerStatefulWidget {
  const _ImportCard({super.key, required this.item});

  final PendingImport item;

  @override
  ConsumerState<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends ConsumerState<_ImportCard> {
  late EntryKind _kind = widget.item.kind;
  int? _categoryId;
  var _touched = false;
  var _showRaw = false;
  late final _note = TextEditingController(text: widget.item.counterparty);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final cat = _categoryId;
    if (cat == null) return;
    await ref
        .read(importServiceProvider)
        .accept(
          widget.item,
          categoryId: cat,
          kind: _kind,
          note: _note.text.trim(),
          homeCurrency: ref.read(homeCurrencyProvider),
        );
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<void> _ignore() async {
    await ref.read(importServiceProvider).ignore(widget.item);
    ref.read(dataVersionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.item;
    final theme = Theme.of(context);
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == _kind && !c.archived)
        .toList();
    final suggester = ref.watch(categorySuggesterProvider).value;
    if (!_touched && _categoryId == null && suggester != null) {
      _categoryId = suggester.suggest(_kind, p.counterparty, p.raw);
    }
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) _categoryId = null;
    final isIncome = _kind == EntryKind.income;
    final source = switch (p.source) {
      EntrySource.sms => 'SMS',
      EntrySource.email => 'Email',
      EntrySource.statement => 'Statement',
      EntrySource.manual => 'Manual',
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  '${isIncome ? '+' : '−'}${formatMoney(p.amount, p.currency)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isIncome ? Colors.green.shade600 : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [DateFormat('d MMM yyyy').format(p.date), ?p.bank, source].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<EntryKind>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: EntryKind.expense, label: Text('Expense')),
                    ButtonSegment(value: EntryKind.income, label: Text('Income')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _categoryId = null;
                    _touched = false;
                  }),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('$_kind-${p.id}'),
                  initialValue: _categoryId,
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('Pick type'),
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() {
                    _categoryId = v;
                    _touched = true;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note', isDense: true, border: OutlineInputBorder()),
            ),
            if (_showRaw)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(p.raw, style: theme.textTheme.bodySmall),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: _showRaw ? 'Hide original message' : 'Show original message',
                  onPressed: () => setState(() => _showRaw = !_showRaw),
                  icon: Icon(_showRaw ? Icons.expand_less : Icons.notes),
                ),
                const Spacer(),
                TextButton(onPressed: _ignore, child: const Text('Ignore')),
                const SizedBox(width: 4),
                FilledButton(onPressed: _categoryId == null ? null : _accept, child: const Text('Add')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
