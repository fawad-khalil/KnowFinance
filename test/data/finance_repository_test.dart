import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/models/enums.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late FinanceRepository repo;

  setUp(() async {
    appDb = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = FinanceRepository(appDb);
  });

  tearDown(() => appDb.close());

  Future<int> categoryId(String name) async =>
      (await repo.categories()).firstWhere((c) => c.name == name).id!;

  Entry expense(int cat, double amount, DateTime date, String note) => Entry(
        kind: EntryKind.expense,
        amount: amount,
        currency: 'PKR',
        homeCurrency: 'PKR',
        fxRate: 1,
        categoryId: cat,
        date: date,
        note: note,
      );

  test('seeds income and expense types', () async {
    final income = await repo.categories(kind: EntryKind.income);
    final expense = await repo.categories(kind: EntryKind.expense);
    expect(income.map((c) => c.name), contains('Salary'));
    expect(expense.every((c) => c.bucket != null), isTrue);
  });

  test('filters by date range, bucket and case-insensitive note', () async {
    final groceries = await categoryId('Groceries');
    final dining = await categoryId('Dining out');
    await repo.saveEntry(expense(groceries, 5000, DateTime(2026, 10, 3), 'Imtiaz Store'));
    await repo.saveEntry(expense(groceries, 3000, DateTime(2026, 10, 12), 'imtiaz store'));
    await repo.saveEntry(expense(dining, 2500, DateTime(2026, 10, 14), 'KFC'));
    await repo.saveEntry(expense(groceries, 4000, DateTime(2026, 9, 28), 'Imtiaz'));

    final now = DateTime(2026, 10, 19);
    final thisMonth = await repo.entries(const EntryFilter(), now: now);
    expect(thisMonth, hasLength(3));
    expect(thisMonth.first.note, 'KFC', reason: 'newest first');

    final lastMonth = await repo.entries(
      const EntryFilter(preset: DatePreset.lastMonth),
      now: now,
    );
    expect(lastMonth.single.note, 'Imtiaz');

    final imtiaz = await repo.entries(
      const EntryFilter(preset: DatePreset.allTime, noteQuery: 'IMTIAZ'),
      now: now,
    );
    expect(imtiaz, hasLength(3));

    final wants = await repo.entries(
      const EntryFilter(bucket: Bucket.wants),
      now: now,
    );
    expect(wants.single.note, 'KFC');
  });

  test('archives a used category instead of deleting it', () async {
    final groceries = await categoryId('Groceries');
    await repo.saveEntry(expense(groceries, 100, DateTime(2026, 10, 1), ''));
    await repo.deleteCategory(groceries);
    final active = await repo.categories();
    final all = await repo.categories(includeArchived: true);
    expect(active.any((c) => c.id == groceries), isFalse);
    expect(all.any((c) => c.id == groceries), isTrue);
  });
}
