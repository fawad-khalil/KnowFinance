import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/category.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/services/pivot.dart';

void main() {
  const cats = {
    1: Category(id: 1, name: 'Salary', kind: EntryKind.income),
    2: Category(id: 2, name: 'Groceries', kind: EntryKind.expense, bucket: Bucket.needs),
    3: Category(id: 3, name: 'Dining out', kind: EntryKind.expense, bucket: Bucket.wants),
    4: Category(id: 4, name: 'Investments', kind: EntryKind.expense, bucket: Bucket.savings),
  };
  Entry e(int cat, double amt, DateTime d, [String note = '']) => Entry(
        kind: cats[cat]!.kind, amount: amt, currency: 'PKR', homeCurrency: 'PKR', fxRate: 1,
        categoryId: cat, date: d, note: note);

  final entries = [
    e(1, 200000, DateTime(2025, 12, 1)),
    e(1, 250000, DateTime(2026, 1, 1)),
    e(1, 250000, DateTime(2026, 2, 1)),
    e(2, 30000, DateTime(2025, 12, 3), 'Imtiaz'),
    e(2, 35000, DateTime(2026, 1, 3), 'imtiaz'),
    e(2, 5000, DateTime(2026, 2, 9), 'Naheed'),
    e(3, 9000, DateTime(2026, 2, 10), 'KFC'),
    e(4, 50000, DateTime(2026, 2, 25)),
  ];

  test('expense type by year', () {
    final t = Pivot.build(entries: entries, categories: cats, home: 'PKR', kind: EntryKind.expense,
        rows: PivotField.type, columns: PivotField.year);
    expect(t.columns.map((c) => c.$2), ['2025', '2026']);
    expect(t.rows.first.$2, 'Groceries', reason: 'biggest row first');
    expect(t.value('t2', 2025), 30000);
    expect(t.value('t2', 2026), 40000);
    expect(t.value('t3', 2025), isNull);
    expect(t.rowTotal('t2'), 70000);
    expect(t.columnTotal(2026), 99000);
    expect(t.grandTotal, 129000);
  });

  test('notes group case-insensitively, measures switch', () {
    final count = Pivot.build(entries: entries, categories: cats, home: 'PKR', kind: EntryKind.expense,
        rows: PivotField.note, columns: PivotField.none, measure: PivotMeasure.count);
    expect(count.value('nimtiaz', 0), 2);
    final avg = Pivot.build(entries: entries, categories: cats, home: 'PKR', kind: EntryKind.expense,
        rows: PivotField.bucket, columns: PivotField.month, measure: PivotMeasure.average);
    expect(avg.rows.map((r) => r.$2), ['Needs', 'Wants', 'Savings'], reason: 'buckets in natural order');
    expect(avg.columns.map((c) => c.$2), ['Dec 25', 'Jan 26', 'Feb 26']);
    expect(avg.rowTotal(Bucket.needs.index), closeTo(70000 / 3, 0.01));
    final share = Pivot.build(entries: entries, categories: cats, home: 'PKR', kind: EntryKind.income,
        rows: PivotField.type, columns: PivotField.quarter, measure: PivotMeasure.share);
    expect(share.grandTotal, closeTo(100, 0.001));
    expect(share.columns.map((c) => c.$2), ['Q4 2025', 'Q1 2026']);
  });

  test('year summaries', () {
    final ys = yearSummaries(entries, cats, 'PKR');
    expect(ys.map((y) => y.year), [2026, 2025]);
    expect(ys.first.income, 500000);
    expect(ys.first.expense, 99000);
    expect(ys.first.months, 2);
    expect(ys.first.keptPct, closeTo((500000 - 40000 - 9000) / 500000 * 100, 0.001));
  });
}
