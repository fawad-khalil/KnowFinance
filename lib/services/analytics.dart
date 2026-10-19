import '../models/category.dart';
import '../models/entry.dart';
import '../models/enums.dart';

/// One slice or row of a breakdown: a label, its total in the home
/// currency and how many entries went into it.
class Share {
  Share(this.key, this.label, this.total, this.count);

  final Object key;
  final String label;
  double total;
  int count;
}

enum Granularity { day, month }

/// Everything logged on one day, for the activity heatmap.
class DayActivity {
  DayActivity(this.day);

  final DateTime day;
  int count = 0;
  double income = 0;
  double expense = 0;
}

/// Totals for one point on the time axis.
class Period {
  Period(this.start);

  final DateTime start;
  double income = 0;
  double expense = 0;
  final Map<Bucket, double> buckets = {for (final b in Bucket.values) b: 0};
}

class SavingsSummary {
  const SavingsSummary({
    required this.income,
    required this.needs,
    required this.wants,
    required this.savings,
  });

  final double income;
  final double needs;
  final double wants;

  /// Money explicitly put into Savings-bucket types.
  final double savings;

  double get expense => needs + wants + savings;

  /// Income left after Needs and Wants: what was actually kept, whether it
  /// was logged as a savings deposit or just left in the account.
  double get kept => income - needs - wants;

  double get unallocated => income - expense;

  double pct(double v) => income <= 0 ? 0 : v / income * 100;
}

/// Pure calculations behind the Insights screen. Only entries with a rate in
/// the current home currency are counted; the rest are reported as [skipped].
class Analytics {
  Analytics(List<Entry> all, this.categories, this.home)
      : entries = all.where((e) => e.homeCurrency == home && e.fxRate != null).toList(),
        skipped = all.where((e) => e.homeCurrency != home || e.fxRate == null).length;

  final List<Entry> entries;
  final Map<int, Category> categories;
  final String home;
  final int skipped;

  Iterable<Entry> get _expenses => entries.where((e) => e.kind == EntryKind.expense);

  Bucket? _bucketOf(Entry e) => categories[e.categoryId]?.bucket;

  List<Share> _group(Iterable<Entry> items, Object Function(Entry) key, String Function(Entry) label) {
    final map = <Object, Share>{};
    for (final e in items) {
      final k = key(e);
      final s = map.putIfAbsent(k, () => Share(k, label(e), 0, 0));
      s.total += e.homeAmount!;
      s.count++;
    }
    return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Level 1: Needs / Wants / Savings, always in that order.
  List<Share> byBucket() {
    final shares = {for (final b in Bucket.values) b: Share(b, b.label, 0, 0)};
    for (final e in _expenses) {
      final b = _bucketOf(e);
      if (b == null) continue;
      final s = shares[b]!;
      s.total += e.homeAmount!;
      s.count++;
    }
    return shares.values.where((s) => s.count > 0).toList();
  }

  /// Level 2: expense types inside one bucket.
  List<Share> byExpenseType(Bucket bucket) => _group(
        _expenses.where((e) => _bucketOf(e) == bucket),
        (e) => e.categoryId,
        (e) => categories[e.categoryId]?.name ?? 'Unknown',
      );

  /// Level 3: entries of one type grouped by note.
  List<Share> byNote(int categoryId) =>
      noteGroups(_expenses.where((e) => e.categoryId == categoryId));

  List<Share> incomeByType() => _group(
        entries.where((e) => e.kind == EntryKind.income),
        (e) => e.categoryId,
        (e) => categories[e.categoryId]?.name ?? 'Unknown',
      );

  /// Groups entries whose notes match ignoring case and extra spaces. The
  /// label is the first spelling seen (entries arrive newest first).
  static List<Share> noteGroups(Iterable<Entry> items) {
    final map = <String, Share>{};
    for (final e in items) {
      final key = normalizeNote(e.note);
      final s = map.putIfAbsent(key, () => Share(key, key.isEmpty ? 'No note' : e.note.trim(), 0, 0));
      s.total += e.homeAmount!;
      s.count++;
    }
    return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Expense note groups across every type, for "where does it go" lists.
  List<Share> expenseNoteGroups() => noteGroups(_expenses).where((s) => s.key != '').toList();

  SavingsSummary savings() {
    double income = 0;
    final b = {for (final x in Bucket.values) x: 0.0};
    for (final e in entries) {
      if (e.kind == EntryKind.income) {
        income += e.homeAmount!;
      } else {
        final bucket = _bucketOf(e);
        if (bucket != null) b[bucket] = b[bucket]! + e.homeAmount!;
      }
    }
    return SavingsSummary(
      income: income,
      needs: b[Bucket.needs]!,
      wants: b[Bucket.wants]!,
      savings: b[Bucket.savings]!,
    );
  }

  /// Time series from [start] to [end] with no gaps, so lines don't skip
  /// empty days or months. Ranges up to 62 days are shown per day.
  List<Period> timeline({DateTime? start, DateTime? end}) {
    if (entries.isEmpty && (start == null || end == null)) return const [];
    final dates = entries.map((e) => e.date);
    final from = start ?? dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final to = end ?? dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final g = granularityFor(from, to);

    DateTime keyOf(DateTime d) => g == Granularity.day ? DateTime(d.year, d.month, d.day) : DateTime(d.year, d.month);
    DateTime next(DateTime d) => g == Granularity.day ? DateTime(d.year, d.month, d.day + 1) : DateTime(d.year, d.month + 1);

    final periods = <DateTime, Period>{};
    for (var d = keyOf(from); !d.isAfter(keyOf(to)); d = next(d)) {
      periods[d] = Period(d);
    }
    for (final e in entries) {
      final p = periods[keyOf(e.date)];
      if (p == null) continue;
      if (e.kind == EntryKind.income) {
        p.income += e.homeAmount!;
      } else {
        p.expense += e.homeAmount!;
        final b = _bucketOf(e);
        if (b != null) p.buckets[b] = p.buckets[b]! + e.homeAmount!;
      }
    }
    return periods.values.toList();
  }

  /// Entries per calendar day, keyed by midnight.
  Map<DateTime, DayActivity> daily() {
    final out = <DateTime, DayActivity>{};
    for (final e in entries) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final a = out.putIfAbsent(d, () => DayActivity(d));
      a.count++;
      if (e.kind == EntryKind.income) {
        a.income += e.homeAmount!;
      } else {
        a.expense += e.homeAmount!;
      }
    }
    return out;
  }

  static Granularity granularityFor(DateTime from, DateTime to) =>
      to.difference(from).inDays <= 62 ? Granularity.day : Granularity.month;
}

String normalizeNote(String note) => note.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
