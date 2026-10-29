import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/budget.dart';
import 'package:know_finance/models/category.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/recurring_payment.dart';
import 'package:know_finance/services/budget_tracker.dart';

void main() {
  const cats = {
    1: Category(id: 1, name: 'Salary', kind: EntryKind.income),
    2: Category(id: 2, name: 'Groceries', kind: EntryKind.expense, bucket: Bucket.needs),
    3: Category(id: 3, name: 'Dining out', kind: EntryKind.expense, bucket: Bucket.wants),
    4: Category(id: 4, name: 'Rent', kind: EntryKind.expense, bucket: Bucket.needs),
    5: Category(id: 5, name: 'Education', kind: EntryKind.expense, bucket: Bucket.needs),
  };

  Entry e(int cat, double amount, DateTime date, {int? id, double? rate = 1}) => Entry(
        id: id,
        kind: cats[cat]!.kind,
        amount: amount,
        currency: 'PKR',
        homeCurrency: 'PKR',
        fxRate: rate,
        categoryId: cat,
        date: date,
      );

  RecurringPayment rent({bool autoPost = true}) => RecurringPayment(
      id: 1, name: 'House rent', categoryId: 4, amount: 70000, currency: 'PKR',
      startDate: DateTime(2026, 1, 2), createdOn: DateTime(2026, 1, 1), autoPost: autoPost);

  group('due dates', () {
    test('monthly keeps the day, or the last day of shorter months', () {
      final r = RecurringPayment(
          name: 'x', categoryId: 4, amount: 1, currency: 'PKR', startDate: DateTime(2026, 1, 31), createdOn: DateTime(2026));
      expect(r.dueDates(DateTime(2026, 2, 1), DateTime(2026, 4, 30)),
          [DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30)]);
    });

    test('quarterly falls only in its months; weekly several times a month', () {
      final fee = RecurringPayment(
          name: 'School fee', categoryId: 5, amount: 1, currency: 'PKR', every: 3, startDate: DateTime(2026, 1, 10),
          createdOn: DateTime(2026));
      expect(fee.dueDates(DateTime(2026, 4, 1), DateTime(2026, 4, 30)), [DateTime(2026, 4, 10)]);
      expect(fee.dueDates(DateTime(2026, 5, 1), DateTime(2026, 6, 30)), isEmpty);
      final maid = RecurringPayment(
          name: 'Maid', categoryId: 5, amount: 1, currency: 'PKR', unit: RepeatUnit.week, startDate: DateTime(2026, 10, 3),
          createdOn: DateTime(2026));
      expect(maid.dueDates(DateTime(2026, 10, 1), DateTime(2026, 10, 31)), hasLength(5));
    });

    test('stop at the end date', () {
      final r = rent().copyWith(endDate: () => DateTime(2026, 3, 1));
      expect(r.dueDates(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), [DateTime(2026, 1, 2), DateTime(2026, 2, 2)]);
    });
  });

  test('category budgets add up to the month total', () {
    final m = BudgetMonth(
      month: DateTime(2026, 10),
      budgets: const [Budget(categoryId: 2, amount: 30000), Budget(categoryId: 3, amount: 10000)],
      payments: const [],
      posts: const [],
      entries: [e(2, 12000, DateTime(2026, 10, 3)), e(3, 15000, DateTime(2026, 10, 9)), e(1, 250000, DateTime(2026, 10, 1))],
      categories: cats,
      home: 'PKR',
      now: DateTime(2026, 10, 15),
    );
    expect(m.total, 40000);
    expect(m.spent, 27000, reason: 'income is not spending');
    expect(m.unallocated, isNull);
    final dining = m.lines.firstWhere((l) => l.category.id == 3);
    expect(dining.over, isTrue);
    expect(dining.left, -5000);
    expect(m.lines.first.category.bucket, Bucket.needs);
    expect(m.buckets[Bucket.wants]!.spent, 15000);
    expect(m.expectedByNow, closeTo(40000 * 15 / 31, 0.01));
    expect(m.dailyAllowance, closeTo(13000 / 17, 0.01));
  });

  test('an overall budget is the total and category budgets divide it', () {
    final m = BudgetMonth(
      month: DateTime(2026, 10),
      budgets: const [Budget(amount: 150000), Budget(categoryId: 2, amount: 30000)],
      payments: [rent()],
      posts: const [],
      entries: [e(3, 5000, DateTime(2026, 10, 9))],
      categories: cats,
      home: 'PKR',
      now: DateTime(2026, 10, 15),
    );
    expect(m.total, 150000);
    expect(m.allocated, 100000, reason: 'groceries plus the rent due this month');
    expect(m.unallocated, 50000);
    expect(m.lines.map((l) => l.category.name), ['Groceries', 'Rent', 'Dining out']);
  });

  test('recurring payments budget for themselves and track what was paid', () {
    final fee = RecurringPayment(
        id: 2, name: 'School fee', categoryId: 5, amount: 18000, currency: 'PKR', startDate: DateTime(2026, 1, 20),
        createdOn: DateTime(2026, 1, 1), autoPost: false);
    final late = RecurringPayment(
        id: 3, name: 'Gym', categoryId: 3, amount: 5000, currency: 'PKR', startDate: DateTime(2026, 10, 1),
        createdOn: DateTime(2026, 10, 12));
    final m = BudgetMonth(
      month: DateTime(2026, 10),
      budgets: const [Budget(categoryId: 4, amount: 5000)],
      payments: [rent(), fee, late],
      posts: [RecurringPost(recurringId: 1, due: DateTime(2026, 10, 2), entryId: 7)],
      entries: [e(4, 72000, DateTime(2026, 10, 2), id: 7)],
      categories: cats,
      home: 'PKR',
      now: DateTime(2026, 10, 15),
    );
    final rentLine = m.lines.firstWhere((l) => l.category.id == 4);
    expect(rentLine.scheduled, 70000);
    expect(rentLine.budget, 75000, reason: 'scheduled plus what the user set');
    expect(m.dues.map((d) => (d.payment.name, d.status)), [
      ('Gym', DueStatus.before),
      ('House rent', DueStatus.paid),
      ('School fee', DueStatus.upcoming),
    ]);
    expect(m.dues[1].paidAmount, 72000);
    expect(m.scheduledOutstanding, 18000);
  });

  test('a due date passed without being logged is missed; paused ones drop out', () {
    final m = BudgetMonth(
      month: DateTime(2026, 10),
      budgets: const [],
      payments: [rent(autoPost: false), rent().copyWith(paused: true)],
      posts: const [],
      entries: const [],
      categories: cats,
      home: 'PKR',
      now: DateTime(2026, 10, 15),
    );
    expect(m.dues.single.status, DueStatus.missed);
    expect(m.total, 70000);
  });

  test('foreign payments use the given rate; entries without one are skipped', () {
    final netflix = RecurringPayment(
        id: 4, name: 'Netflix', categoryId: 3, amount: 10, currency: 'USD', startDate: DateTime(2026, 1, 5),
        createdOn: DateTime(2026));
    final m = BudgetMonth(
      month: DateTime(2026, 10),
      budgets: const [],
      payments: [netflix],
      posts: const [],
      entries: [e(3, 100, DateTime(2026, 10, 3), rate: null)],
      categories: cats,
      home: 'PKR',
      rates: const {'USD': 280},
      now: DateTime(2026, 11, 3),
    );
    expect(m.total, 2800);
    expect(m.skipped, 1);
    expect(m.daysElapsed, 31);
    expect(m.dailyAllowance, isNull, reason: 'the month is over');
  });
}
