import '../models/category.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import 'analytics.dart';

/// Income, Needs + Wants spending and what was kept, for one span of days.
class PeriodTotals {
  const PeriodTotals(this.start, this.end, this.summary);

  final DateTime start;
  final DateTime end;
  final SavingsSummary summary;

  double get income => summary.income;
  double get spending => summary.needs + summary.wants;

  /// Income left after Needs and Wants. Money put into Savings-bucket types
  /// counts as saved, since it is still the user's.
  double get saved => summary.kept;
}

/// One month's balance for the savings history.
class MonthBalance {
  const MonthBalance(this.month, this.saved);

  final DateTime month;
  final double saved;
}

/// This month so far against the same days of last month, and every
/// month's balance added up into savings.
class SavingsReport {
  SavingsReport(List<Entry> entries, Map<int, Category> categories, String home, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final monthStart = DateTime(n.year, n.month);
    final lastStart = DateTime(n.year, n.month - 1);
    final lastLen = DateTime(n.year, n.month, 0).day;
    final lastEnd = DateTime(n.year, n.month - 1, n.day > lastLen ? lastLen : n.day);

    PeriodTotals totals(DateTime s, DateTime e) => PeriodTotals(
          s,
          e,
          Analytics(entries.where((x) => _within(x.date, s, e)).toList(), categories, home).savings(),
        );

    thisMonth = totals(monthStart, today);
    lastMonthToDate = totals(lastStart, lastEnd);
    lastMonth = totals(lastStart, DateTime(n.year, n.month, 0));

    final a = Analytics(entries, categories, home);
    final byMonth = <DateTime, double>{};
    for (final e in a.entries) {
      final m = DateTime(e.date.year, e.date.month);
      if (m.isAfter(monthStart)) continue;
      // Savings-bucket money is still the user's, so it isn't taken off.
      final bucket = categories[e.categoryId]?.bucket;
      final sign = e.kind == EntryKind.income ? 1 : (bucket == Bucket.savings ? 0 : -1);
      byMonth[m] = (byMonth[m] ?? 0) + sign * e.homeAmount!;
    }
    final months = <MonthBalance>[];
    if (byMonth.isNotEmpty) {
      var m = byMonth.keys.reduce((x, y) => x.isBefore(y) ? x : y);
      while (!m.isAfter(monthStart)) {
        months.add(MonthBalance(m, byMonth[m] ?? 0));
        m = DateTime(m.year, m.month + 1);
      }
    }
    history = months;
  }

  late final PeriodTotals thisMonth;

  /// Last month up to the same day, so a part month compares fairly.
  late final PeriodTotals lastMonthToDate;
  late final PeriodTotals lastMonth;

  /// Every month from the first entry to this one, oldest first.
  late final List<MonthBalance> history;

  /// Positive months added up: what went into savings.
  double get added => history.where((m) => m.saved > 0).fold(0, (t, m) => t + m.saved);

  /// Months that spent more than came in, drawn from savings.
  double get drawn => history.where((m) => m.saved < 0).fold(0, (t, m) => t - m.saved);

  /// Savings built up so far: positive months in, short months out.
  double get total => added - drawn;

  /// Percent change from [before] to [now]; null when there is nothing to
  /// compare with.
  static double? change(double now, double before) => before == 0 ? null : (now - before) / before.abs() * 100;

  double? get incomeChange => change(thisMonth.income, lastMonthToDate.income);
  double? get spendingChange => change(thisMonth.spending, lastMonthToDate.spending);

  /// Spending as a share of income, this month and the same days last
  /// month. Null without income.
  double? get spendingShare => thisMonth.income <= 0 ? null : thisMonth.spending / thisMonth.income * 100;
  double? get lastSpendingShare =>
      lastMonthToDate.income <= 0 ? null : lastMonthToDate.spending / lastMonthToDate.income * 100;

  static bool _within(DateTime d, DateTime s, DateTime e) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(s) && !day.isAfter(e);
  }
}
