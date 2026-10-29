import '../models/budget.dart';
import '../models/category.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import '../models/recurring_payment.dart';

enum DueStatus {
  paid('Paid'),
  skipped('Skipped'),
  missed('Due'),
  upcoming('Upcoming'),

  /// Fell due before the payment was set up, so it was logged by hand.
  before('Before tracking');

  const DueStatus(this.label);
  final String label;
}

/// One due date of a recurring payment within the month.
class ScheduledDue {
  const ScheduledDue(this.payment, this.due, this.amount, this.status, {this.paidAmount, this.entryId});

  final RecurringPayment payment;
  final DateTime due;

  /// The expected amount in the home currency, or null without a rate.
  final double? amount;
  final DueStatus status;

  /// What the logged entry came to in the home currency, when it is known.
  final double? paidAmount;
  final int? entryId;
}

/// Budget against spending for one expense type in the month.
class BudgetLine {
  BudgetLine(this.category);

  final Category category;

  /// Set by the user.
  double set = 0;

  /// What the type's recurring payments fall due for this month.
  double scheduled = 0;
  double spent = 0;

  double get budget => set + scheduled;
  double get left => budget - spent;
  bool get over => spent > budget + 0.005;

  /// Share of the budget spent, 0 to 1 and beyond.
  double get used => budget <= 0 ? (spent > 0 ? 1.0 : 0.0) : spent / budget;
}

class BucketTotals {
  double budget = 0;
  double spent = 0;
}

/// Spending in one calendar month against its budgets.
///
/// Category budgets add up to the month's total unless an overall budget is
/// set; then the overall one is the total and category budgets only divide
/// it up. Recurring payments budget for themselves: what falls due in the
/// month is added to their type's budget.
class BudgetMonth {
  BudgetMonth({
    required DateTime month,
    required List<Budget> budgets,
    required List<RecurringPayment> payments,
    required List<RecurringPost> posts,
    required List<Entry> entries,
    required Map<int, Category> categories,
    required this.home,
    Map<String, double> rates = const {},
    DateTime? now,
  }) : month = DateTime(month.year, month.month) {
    final n = now ?? DateTime.now();
    today = DateTime(n.year, n.month, n.day);
    final last = DateTime(this.month.year, this.month.month + 1, 0);
    daysInMonth = last.day;
    daysElapsed = today.isBefore(this.month) ? 0 : (today.isAfter(last) ? daysInMonth : today.day);

    final byId = <int, BudgetLine>{};
    BudgetLine? lineFor(int id) {
      final c = categories[id];
      if (c == null || c.kind != EntryKind.expense) return null;
      return byId.putIfAbsent(id, () => BudgetLine(c));
    }

    for (final b in budgets) {
      if (b.isOverall) {
        overall = b.amount;
      } else {
        lineFor(b.categoryId!)?.set = b.amount;
      }
    }

    final entryById = <int, Entry>{};
    for (final e in entries) {
      if (e.isLoan || e.kind != EntryKind.expense) continue;
      if (e.homeCurrency != home || e.fxRate == null) {
        skipped++;
        continue;
      }
      entryById[e.id ?? -1] = e;
      spent += e.homeAmount!;
      lineFor(e.categoryId)?.spent += e.homeAmount!;
    }

    final postFor = {for (final p in posts) (p.recurringId, dateKey(p.due)): p};
    for (final p in payments) {
      final rate = p.currency == home ? 1.0 : rates[p.currency];
      for (final due in p.dueDates(this.month, last)) {
        final post = postFor[(p.id, dateKey(due))];
        if (p.paused && post == null) continue;
        final amount = rate == null ? null : p.amount * rate;
        if (amount != null) lineFor(p.categoryId)?.scheduled += amount;
        final status = switch (post) {
          RecurringPost(skipped: true) => DueStatus.skipped,
          RecurringPost() => DueStatus.paid,
          _ when due.isBefore(p.createdOn) => DueStatus.before,
          _ when due.isAfter(today) => DueStatus.upcoming,
          _ => DueStatus.missed,
        };
        dues.add(ScheduledDue(p, due, amount, status,
            paidAmount: entryById[post?.entryId]?.homeAmount, entryId: post?.entryId));
      }
    }
    dues.sort((a, b) => a.due.compareTo(b.due));

    lines = byId.values.where((l) => l.budget > 0 || l.spent > 0).toList()
      ..sort((a, b) {
        final byBucket = (a.category.bucket?.index ?? 9).compareTo(b.category.bucket?.index ?? 9);
        return byBucket != 0 ? byBucket : a.category.name.toLowerCase().compareTo(b.category.name.toLowerCase());
      });
    for (final l in lines) {
      final t = buckets.putIfAbsent(l.category.bucket ?? Bucket.needs, BucketTotals.new);
      t.budget += l.budget;
      t.spent += l.spent;
    }
  }

  final DateTime month;
  final String home;
  late final DateTime today;
  late final int daysInMonth;

  /// Days of the month gone by, today included: 0 for a month still to come.
  late final int daysElapsed;

  /// The overall monthly budget, when one is set.
  double? overall;
  double spent = 0;

  /// Expenses left out because they have no rate in the home currency.
  int skipped = 0;

  /// Expense types with a budget or spending, Needs first.
  late final List<BudgetLine> lines;
  final dues = <ScheduledDue>[];
  final buckets = <Bucket, BucketTotals>{};

  /// What category budgets and recurring payments add up to.
  double get allocated => lines.fold(0.0, (s, l) => s + l.budget);

  /// The month's budget: the overall one if set, otherwise [allocated].
  double get total => overall ?? allocated;

  /// What the overall budget leaves after category budgets; null without
  /// one. Negative when the parts add up to more than the whole.
  double? get unallocated => overall == null ? null : overall! - allocated;

  double get left => total - spent;
  bool get hasBudget => total > 0;

  /// Where spending would be if it ran evenly through the month.
  double get expectedByNow => total * daysElapsed / daysInMonth;

  /// Month-end spending at the pace so far; null before the month starts.
  double? get projected => daysElapsed == 0 ? null : spent / daysElapsed * daysInMonth;

  /// What can still be spent each remaining day, today included.
  double? get dailyAllowance {
    if (daysElapsed == 0 || today.isAfter(DateTime(month.year, month.month, daysInMonth))) return null;
    return left / (daysInMonth - daysElapsed + 1);
  }

  /// Scheduled payments still to come, or due and not logged.
  double get scheduledOutstanding => dues
      .where((d) => d.status == DueStatus.upcoming || d.status == DueStatus.missed)
      .fold(0.0, (s, d) => s + (d.amount ?? 0));
}
