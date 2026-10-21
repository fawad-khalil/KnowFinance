import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/category.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/loan.dart';
import 'package:know_finance/services/analytics.dart';
import 'package:know_finance/services/loan_analytics.dart';
import 'package:know_finance/services/savings.dart';

void main() {
  const cats = {
    1: Category(id: 1, name: 'Salary', kind: EntryKind.income),
    2: Category(id: 2, name: 'Groceries', kind: EntryKind.expense, bucket: Bucket.needs),
    3: Category(id: 3, name: 'Dining out', kind: EntryKind.expense, bucket: Bucket.wants),
    4: Category(id: 4, name: 'Savings deposit', kind: EntryKind.expense, bucket: Bucket.savings),
    5: Category(id: 5, name: 'Loan', kind: EntryKind.income, system: 'loan'),
    6: Category(id: 6, name: 'Loan', kind: EntryKind.expense, system: 'loan'),
  };

  Entry e(int cat, double amount, DateTime date, {int? loan}) => Entry(
        kind: cats[cat]!.kind,
        amount: amount,
        currency: 'PKR',
        homeCurrency: 'PKR',
        fxRate: 1,
        categoryId: cat,
        date: date,
        loanId: loan,
      );

  group('loans', () {
    const loans = [
      Loan(id: 1, name: 'Bank car loan', direction: LoanDirection.payable),
      Loan(id: 2, name: 'Ali', direction: LoanDirection.receivable),
      Loan(id: 3, name: 'Sara', direction: LoanDirection.receivable),
    ];
    final linked = [
      e(5, 1000000, DateTime(2026, 1, 1), loan: 1), // borrowed
      e(6, 50000, DateTime(2026, 2, 1), loan: 1), // repaid
      e(6, 50000, DateTime(2026, 10, 1), loan: 1), // repaid
      e(6, 30000, DateTime(2026, 9, 5), loan: 2), // lent
      e(5, 10000, DateTime(2026, 10, 3), loan: 2), // got back
      e(6, 5000, DateTime(2026, 3, 1), loan: 3), // lent
      e(5, 5000, DateTime(2026, 4, 1), loan: 3), // got back in full
    ];
    final a = LoanAnalytics(loans, linked, 'PKR');

    test('works out what is owed each way', () {
      final car = a[1]!;
      expect(car.opened, 1000000);
      expect(car.settled, 100000);
      expect(car.outstanding, 900000);
      expect(car.progress, closeTo(0.1, 1e-9));
      expect(a[2]!.outstanding, 20000);
      expect(a[3]!.isSettled, isTrue);
      expect(a.totalPayable, 900000);
      expect(a.totalReceivable, 20000);
      expect(a.net, -880000);
    });

    test('splits a month\'s loan money by what it did', () {
      final f = a.flows(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31));
      expect(f.repaid, 50000);
      expect(f.gotBack, 10000);
      expect(f.borrowed, 0);
      expect(f.lent, 0);
      expect(f.net, -40000);
    });

    test('loan entries are not income or spending', () {
      final an = Analytics([...linked, e(1, 200000, DateTime(2026, 10, 1))], cats, 'PKR');
      expect(an.entries.length, 1);
      expect(an.savings().income, 200000);
      expect(an.skipped, 0);
    });
  });

  group('savings', () {
    final now = DateTime(2026, 10, 21);
    final entries = [
      // September: 200k in, 120k on Needs/Wants by the 21st, 30k more after.
      e(1, 200000, DateTime(2026, 9, 1)),
      e(2, 80000, DateTime(2026, 9, 10)),
      e(3, 40000, DateTime(2026, 9, 20)),
      e(3, 30000, DateTime(2026, 9, 25)),
      // October so far: 220k in, 150k spent, 50k into a savings deposit.
      e(1, 220000, DateTime(2026, 10, 1)),
      e(2, 100000, DateTime(2026, 10, 5)),
      e(3, 50000, DateTime(2026, 10, 15)),
      e(4, 50000, DateTime(2026, 10, 16)),
      // August: spent more than came in.
      e(1, 100000, DateTime(2026, 8, 1)),
      e(2, 130000, DateTime(2026, 8, 2)),
      // A loan in October changes nothing.
      e(5, 500000, DateTime(2026, 10, 2), loan: 1),
    ];
    final r = SavingsReport(entries, cats, 'PKR', now: now);

    test('this month against the same days of last month', () {
      expect(r.thisMonth.income, 220000);
      expect(r.thisMonth.spending, 150000);
      // The savings deposit is still the user's money.
      expect(r.thisMonth.saved, 70000);
      expect(r.lastMonthToDate.end, DateTime(2026, 9, 21));
      expect(r.lastMonthToDate.spending, 120000);
      expect(r.incomeChange, closeTo(10, 1e-9));
      expect(r.spendingChange, closeTo(25, 1e-9));
      expect(r.spendingShare, closeTo(150000 / 220000 * 100, 1e-9));
      expect(r.lastSpendingShare, closeTo(60, 1e-9));
    });

    test('positive months add to savings, short months draw from it', () {
      expect(r.history.map((m) => m.month), [DateTime(2026, 8), DateTime(2026, 9), DateTime(2026, 10)]);
      expect(r.history.map((m) => m.saved), [-30000, 50000, 70000]);
      expect(r.added, 120000);
      expect(r.drawn, 30000);
      expect(r.total, 90000);
      expect(r.lastMonth.saved, 50000);
    });

    test('a month that ends on the 31st compares with a shorter one', () {
      final s = SavingsReport(entries, cats, 'PKR', now: DateTime(2026, 3, 31));
      expect(s.lastMonthToDate.end, DateTime(2026, 2, 28));
    });
  });
}
