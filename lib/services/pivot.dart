import '../models/category.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import 'analytics.dart';

/// Fields an entry can be grouped by, on either axis of a pivot.
enum PivotField {
  bucket('Bucket'),
  type('Type'),
  note('Note'),
  source('Source'),
  currency('Currency'),
  year('Year'),
  quarter('Quarter'),
  month('Month'),
  none('Total');

  const PivotField(this.label);
  final String label;

  /// Bucket only applies to expenses.
  static List<PivotField> rowsFor(EntryKind kind) => [
        if (kind == EntryKind.expense) bucket,
        type,
        note,
        source,
        currency,
        year,
        month,
      ];

  static const columns = [year, quarter, month, bucket, none];
}

enum PivotMeasure {
  total('Total'),
  count('Count'),
  average('Average per entry'),
  share('% of total');

  const PivotMeasure(this.label);
  final String label;
}

class PivotTable {
  PivotTable(this.rows, this.columns, this.cells, this.counts, this.measure);

  /// Row and column keys in display order, with their labels.
  final List<(Object, String)> rows;
  final List<(Object, String)> columns;
  final Map<(Object, Object), double> cells;
  final Map<(Object, Object), int> counts;
  final PivotMeasure measure;

  double _sumWhere(bool Function((Object, Object)) test) =>
      cells.entries.where((e) => test(e.key)).fold(0.0, (a, e) => a + e.value);
  int _countWhere(bool Function((Object, Object)) test) =>
      counts.entries.where((e) => test(e.key)).fold(0, (a, e) => a + e.value);

  late final double grandSum = _sumWhere((_) => true);

  double? _measure(double sum, int count) => switch (measure) {
        PivotMeasure.total => count == 0 ? null : sum,
        PivotMeasure.count => count.toDouble(),
        PivotMeasure.average => count == 0 ? null : sum / count,
        PivotMeasure.share => count == 0 || grandSum == 0 ? null : sum / grandSum * 100,
      };

  double? value(Object row, Object col) => _measure(cells[(row, col)] ?? 0, counts[(row, col)] ?? 0);

  double? rowTotal(Object row) => _measure(_sumWhere((k) => k.$1 == row), _countWhere((k) => k.$1 == row));

  double? columnTotal(Object col) => _measure(_sumWhere((k) => k.$2 == col), _countWhere((k) => k.$2 == col));

  double? get grandTotal => _measure(grandSum, _countWhere((_) => true));
}

/// Groups income or expenses by any two fields, like a spreadsheet pivot.
class Pivot {
  static const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// [entries] should already be limited to the date range wanted. Only
  /// entries with a rate in [home] are counted.
  static PivotTable build({
    required List<Entry> entries,
    required Map<int, Category> categories,
    required String home,
    required EntryKind kind,
    required PivotField rows,
    required PivotField columns,
    PivotMeasure measure = PivotMeasure.total,
  }) {
    final usable = entries.where((e) => e.kind == kind && e.homeCurrency == home && e.fxRate != null);
    final cells = <(Object, Object), double>{};
    final counts = <(Object, Object), int>{};
    final rowLabels = <Object, String>{};
    final colLabels = <Object, String>{};

    for (final e in usable) {
      final r = _key(rows, e, categories);
      final c = _key(columns, e, categories);
      rowLabels[r.$1] = r.$2;
      colLabels[c.$1] = c.$2;
      cells[(r.$1, c.$1)] = (cells[(r.$1, c.$1)] ?? 0) + e.homeAmount!;
      counts[(r.$1, c.$1)] = (counts[(r.$1, c.$1)] ?? 0) + 1;
    }

    // Time and bucket axes keep their natural order; everything else is
    // sorted by size so the biggest rows come first.
    List<(Object, String)> order(PivotField f, Map<Object, String> labels, bool isRow) {
      final list = labels.entries.map((e) => (e.key, e.value)).toList();
      if (_natural(f)) {
        list.sort((a, b) => Comparable.compare(a.$1 as Comparable, b.$1 as Comparable));
      } else {
        double total(Object k) => cells.entries
            .where((e) => (isRow ? e.key.$1 : e.key.$2) == k)
            .fold(0.0, (a, e) => a + e.value);
        list.sort((a, b) => total(b.$1).compareTo(total(a.$1)));
      }
      return list;
    }

    return PivotTable(order(rows, rowLabels, true), order(columns, colLabels, false), cells, counts, measure);
  }

  static bool _natural(PivotField f) =>
      f == PivotField.year || f == PivotField.quarter || f == PivotField.month || f == PivotField.bucket;

  /// Sortable key and display label for one entry on one field.
  static (Object, String) _key(PivotField f, Entry e, Map<int, Category> cats) {
    final d = e.date;
    switch (f) {
      case PivotField.bucket:
        final b = cats[e.categoryId]?.bucket;
        return (b?.index ?? 99, b?.label ?? 'Unsorted');
      case PivotField.type:
        return ('t${e.categoryId}', cats[e.categoryId]?.name ?? 'Unknown');
      case PivotField.note:
        final k = normalizeNote(e.note);
        return ('n$k', k.isEmpty ? 'No note' : e.note.trim());
      case PivotField.source:
        return (e.source.index, switch (e.source) {
          EntrySource.manual => 'Manual',
          EntrySource.sms => 'SMS',
          EntrySource.email => 'Email',
          EntrySource.statement => 'Statement',
        });
      case PivotField.currency:
        return ('c${e.currency}', e.currency);
      case PivotField.year:
        return (d.year, '${d.year}');
      case PivotField.quarter:
        return (d.year * 10 + (d.month - 1) ~/ 3 + 1, 'Q${(d.month - 1) ~/ 3 + 1} ${d.year}');
      case PivotField.month:
        return (d.year * 100 + d.month, '${_monthNames[d.month - 1]} ${d.year % 100}');
      case PivotField.none:
        return (0, 'Total');
    }
  }
}

/// One row of the year-by-year summary.
class YearSummary {
  YearSummary(this.year);

  final int year;
  double income = 0;
  final Map<Bucket, double> buckets = {for (final b in Bucket.values) b: 0};
  int months = 0;

  double get expense => buckets.values.fold(0, (a, b) => a + b);
  double get net => income - expense;

  /// Share of income not spent on Needs or Wants.
  double? get keptPct => income <= 0 ? null : (income - buckets[Bucket.needs]! - buckets[Bucket.wants]!) / income * 100;

  double get avgMonthlyExpense => months == 0 ? 0 : expense / months;
}

List<YearSummary> yearSummaries(List<Entry> entries, Map<int, Category> cats, String home) {
  final years = <int, YearSummary>{};
  final activeMonths = <int, Set<int>>{};
  for (final e in entries.where((e) => e.homeCurrency == home && e.fxRate != null)) {
    final y = years.putIfAbsent(e.date.year, () => YearSummary(e.date.year));
    activeMonths.putIfAbsent(e.date.year, () => {}).add(e.date.month);
    if (e.kind == EntryKind.income) {
      y.income += e.homeAmount!;
    } else {
      final b = cats[e.categoryId]?.bucket ?? Bucket.needs;
      y.buckets[b] = y.buckets[b]! + e.homeAmount!;
    }
  }
  for (final y in years.values) {
    y.months = activeMonths[y.year]!.length;
  }
  return years.values.toList()..sort((a, b) => b.year.compareTo(a.year));
}
