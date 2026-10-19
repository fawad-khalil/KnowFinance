import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/category.dart';
import '../../models/entry.dart';
import '../../models/enums.dart';
import '../../services/pivot.dart';
import '../../state/providers.dart';

/// Year-by-year totals and a pivot table for slicing income or expenses
/// by any two fields.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int? _year;
  var _kind = EntryKind.expense;
  var _rows = PivotField.type;
  PivotField? _columns;
  var _measure = PivotMeasure.total;

  PivotField get _effectiveColumns => _columns ?? (_year == null ? PivotField.year : PivotField.month);

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allEntriesProvider);
    final cats = ref.watch(categoryByIdProvider);
    final home = ref.watch(homeCurrencyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: all.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (entries) {
          if (entries.isEmpty) return const Center(child: Text('Add some entries to see reports.'));
          final years = entries.map((e) => e.date.year).toSet().toList()..sort((a, b) => b.compareTo(a));
          if (_year != null && !years.contains(_year)) _year = null;
          final scoped = _year == null ? entries : entries.where((e) => e.date.year == _year).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final y in <int?>[null, ...years]) ...[
                      ChoiceChip(
                        label: Text(y == null ? 'All years' : '$y'),
                        selected: _year == y,
                        onSelected: (_) => setState(() => _year = y),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              _Card(
                title: 'Year by year',
                subtitle: 'Amounts in $home',
                child: _YearTable(summaries: yearSummaries(entries, cats, home), highlight: _year),
              ),
              _Card(
                title: 'Pivot',
                subtitle: '${_year ?? 'All years'} · amounts in $home',
                child: _pivot(scoped, cats, home),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pivot(List<Entry> entries, Map<int, Category> cats, String home) {
    final rowOptions = PivotField.rowsFor(_kind);
    if (!rowOptions.contains(_rows)) _rows = PivotField.type;
    final colOptions = PivotField.columns.where((f) => f != _rows && (f != PivotField.bucket || _kind == EntryKind.expense)).toList();
    var cols = _effectiveColumns;
    if (!colOptions.contains(cols)) cols = PivotField.none;

    final table = Pivot.build(
      entries: entries,
      categories: cats,
      home: home,
      kind: _kind,
      rows: _rows,
      columns: cols,
      measure: _measure,
    );

    Widget picker<T>(String label, T value, List<T> options, String Function(T) name, void Function(T) onChanged) =>
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(name(o)))],
            onChanged: (v) => setState(() => onChanged(v as T)),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<EntryKind>(
          segments: const [
            ButtonSegment(value: EntryKind.expense, label: Text('Expenses')),
            ButtonSegment(value: EntryKind.income, label: Text('Income')),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            picker('Rows', _rows, rowOptions, (f) => f.label, (v) => _rows = v),
            picker('Columns', cols, colOptions, (f) => f.label, (v) => _columns = v),
            picker('Show', _measure, PivotMeasure.values, (m) => m.label, (v) => _measure = v),
          ],
        ),
        const SizedBox(height: 12),
        if (table.rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Nothing for this selection.')),
          )
        else
          _PivotGrid(table: table, showTotalColumn: table.columns.length > 1),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

final _num = NumberFormat('#,##0', 'en_US');

String _fmt(double? v, PivotMeasure m) {
  if (v == null) return '–';
  return switch (m) {
    PivotMeasure.share => '${v.toStringAsFixed(1)}%',
    PivotMeasure.count => v.toStringAsFixed(0),
    _ => _num.format(v),
  };
}

/// A scrollable grid with the row labels pinned on the left.
class _PivotGrid extends StatefulWidget {
  const _PivotGrid({required this.table, required this.showTotalColumn});

  final PivotTable table;
  final bool showTotalColumn;

  @override
  State<_PivotGrid> createState() => _PivotGridState();
}

class _PivotGridState extends State<_PivotGrid> {
  static const _pageSize = 25;
  var _showAll = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.table;
    final theme = Theme.of(context);
    final rows = _showAll ? t.rows : t.rows.take(_pageSize).toList();
    const rowH = 40.0;
    const labelW = 132.0;
    const cellW = 96.0;
    final header = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final bold = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final divider = BorderSide(color: theme.colorScheme.outlineVariant);
    final cols = [
      ...t.columns.map((c) => (c.$2, (Object r) => t.value(r, c.$1), t.columnTotal(c.$1))),
      if (widget.showTotalColumn) ('Total', (Object r) => t.rowTotal(r), t.grandTotal),
    ];

    Widget cell(String text, {TextStyle? style, double width = cellW, bool left = false, bool top = false}) => Container(
          width: width,
          height: rowH,
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border(bottom: divider, top: top ? divider : BorderSide.none)),
          child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                cell('', width: labelW, left: true),
                for (final r in rows) cell(r.$2, width: labelW, left: true),
                cell('Total', width: labelW, left: true, style: bold, top: true),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [for (final c in cols) cell(c.$1, style: header)]),
                    for (final r in rows)
                      Row(children: [
                        for (var i = 0; i < cols.length; i++)
                          cell(_fmt(cols[i].$2(r.$1), t.measure),
                              style: widget.showTotalColumn && i == cols.length - 1 ? bold : null),
                      ]),
                    Row(children: [for (final c in cols) cell(_fmt(c.$3, t.measure), style: bold, top: true)]),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (t.rows.length > _pageSize)
          TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Show top $_pageSize' : 'Show all ${t.rows.length} rows'),
          ),
      ],
    );
  }
}

class _YearTable extends StatelessWidget {
  const _YearTable({required this.summaries, required this.highlight});

  final List<YearSummary> summaries;
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final headings = ['Year', 'Income', 'Needs', 'Wants', 'Savings', 'Expenses', 'Net', 'Kept', 'Avg / month'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 40,
        columnSpacing: 20,
        horizontalMargin: 0,
        columns: [
          for (var i = 0; i < headings.length; i++)
            DataColumn(label: Text(headings[i], style: muted), numeric: i > 0),
        ],
        rows: [
          for (final y in summaries)
            DataRow(
              selected: y.year == highlight,
              cells: [
                DataCell(Text('${y.year}', style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(_num.format(y.income))),
                DataCell(Text(_num.format(y.buckets[Bucket.needs]))),
                DataCell(Text(_num.format(y.buckets[Bucket.wants]))),
                DataCell(Text(_num.format(y.buckets[Bucket.savings]))),
                DataCell(Text(_num.format(y.expense))),
                DataCell(Text(
                  _num.format(y.net),
                  style: y.net < 0 ? TextStyle(color: theme.colorScheme.error) : null,
                )),
                DataCell(Text(y.keptPct == null ? '–' : '${y.keptPct!.toStringAsFixed(0)}%')),
                DataCell(Text(_num.format(y.avgMonthlyExpense))),
              ],
            ),
        ],
      ),
    );
  }
}
