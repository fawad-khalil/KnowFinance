import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/investment.dart';
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

  test('links entries to an investment and unlinks them when it is deleted', () async {
    final invCat = await categoryId('Investments');
    final groceries = await categoryId('Groceries');
    final buy = await repo.saveEntry(expense(invCat, 50000, DateTime(2026, 1, 5), 'Meezan fund'));
    await repo.saveEntry(expense(groceries, 900, DateTime(2026, 1, 6), 'Imtiaz'));

    // Groceries are not a candidate; the Savings-bucket buy is.
    final candidates = await repo.unlinkedInvestmentCandidates();
    expect(candidates.map((e) => e.id), [buy]);

    final id = await repo.saveInvestment(const Investment(name: 'Meezan fund', type: AssetType.fund));
    await repo.linkEntries(id, {buy: InvestmentFlow.buy});
    final linked = await repo.investmentEntries();
    expect(linked.single.investmentId, id);
    expect(linked.single.investmentFlow, InvestmentFlow.buy);
    expect(await repo.unlinkedInvestmentCandidates(), isEmpty);

    await repo.deleteInvestment(id);
    expect(await repo.investments(), isEmpty);
    expect(await repo.investmentEntries(), isEmpty);
    expect((await repo.unlinkedInvestmentCandidates()).single.investmentFlow, isNull);
  });

  test('upgrades a version 2 database without losing entries', () async {
    await appDb.close();
    final path = '${await databaseFactoryFfi.getDatabasesPath()}/upgrade_test.db';
    await databaseFactoryFfi.deleteDatabase(path);
    final v2 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL, bucket TEXT, archived INTEGER NOT NULL DEFAULT 0)');
        await db.execute("CREATE TABLE entries (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, amount REAL NOT NULL, currency TEXT NOT NULL, home_currency TEXT NOT NULL, fx_rate REAL, category_id INTEGER NOT NULL REFERENCES categories(id), date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT 'manual')");
        await db.insert('categories', {'name': 'Investments', 'kind': 'expense', 'bucket': 'savings'});
        await db.insert('entries', {'kind': 'expense', 'amount': 10, 'currency': 'PKR', 'home_currency': 'PKR', 'fx_rate': 1, 'category_id': 1, 'date': '2026-01-01'});
      },
    ));
    await v2.close();

    appDb = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    repo = FinanceRepository(appDb);
    final all = await repo.entries(const EntryFilter(preset: DatePreset.allTime));
    expect(all.single.investmentId, isNull);
    expect(await repo.investments(), isEmpty);
  });
}
