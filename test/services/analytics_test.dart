import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/category.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/services/analytics.dart';

void main() {
  const cats = {
    1: Category(id: 1, name: 'Salary', kind: EntryKind.income),
    2: Category(id: 2, name: 'Groceries', kind: EntryKind.expense, bucket: Bucket.needs),
    3: Category(id: 3, name: 'Dining out', kind: EntryKind.expense, bucket: Bucket.wants),
    4: Category(id: 4, name: 'Savings deposit', kind: EntryKind.expense, bucket: Bucket.savings),
  };

  Entry e(int cat, double amount, DateTime date, {String note = '', String currency = 'PKR', double? rate = 1}) => Entry(
        kind: cats[cat]!.kind,
        amount: amount,
        currency: currency,
        homeCurrency: 'PKR',
        fxRate: rate,
        categoryId: cat,
        date: date,
        note: note,
      );

  final entries = [
    e(1, 200000, DateTime(2026, 9, 1)),
    e(1, 500, DateTime(2026, 10, 1), currency: 'USD', rate: 280),
    e(2, 30000, DateTime(2026, 9, 5), note: 'Imtiaz Store'),
    e(2, 20000, DateTime(2026, 10, 5), note: '  imtiaz   store '),
    e(2, 5000, DateTime(2026, 10, 6), note: 'Naheed'),
    e(3, 8000, DateTime(2026, 10, 7), note: 'KFC'),
    e(4, 40000, DateTime(2026, 10, 8)),
    e(3, 99, DateTime(2026, 10, 9), currency: 'USD', rate: null),
  ];
  final a = Analytics(entries, cats, 'PKR');

  test('skips entries without a rate', () {
    expect(a.skipped, 1);
    expect(a.entries, hasLength(7));
  });

  test('drills down bucket, type and note', () {
    expect(a.byBucket().map((s) => (s.label, s.total)), [('Needs', 55000.0), ('Wants', 8000.0), ('Savings', 40000.0)]);
    expect(a.byExpenseType(Bucket.needs).single.total, 55000);
    final notes = a.byNote(2);
    expect(notes.first.label, 'Imtiaz Store');
    expect(notes.first.total, 50000);
    expect(notes.first.count, 2);
  });

  test('income by type converts foreign income', () {
    expect(a.incomeByType().single.total, 340000);
  });

  test('savings summary', () {
    final s = a.savings();
    expect(s.income, 340000);
    expect(s.kept, 340000 - 55000 - 8000);
    expect(s.unallocated, 340000 - 103000);
    expect(s.pct(s.needs), closeTo(16.18, 0.01));
  });

  test('timeline fills gaps and picks granularity', () {
    final monthly = a.timeline(start: DateTime(2026, 8, 1), end: DateTime(2026, 10, 31));
    expect(monthly.map((p) => p.start.month), [8, 9, 10]);
    expect(monthly[1].income, 200000);
    expect(monthly[2].buckets[Bucket.savings], 40000);
    final daily = a.timeline(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 10));
    expect(daily, hasLength(10));
    expect(daily[4].expense, 20000);
  });
}
