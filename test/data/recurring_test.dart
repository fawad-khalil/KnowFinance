import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/models/recurring_payment.dart';
import 'package:know_finance/services/fx_service.dart';
import 'package:know_finance/services/recurring_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late FinanceRepository repo;
  late RecurringService service;

  setUp(() async {
    appDb = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(appDb);
    service = RecurringService(repo, FxService(repo));
  });

  tearDown(() => appDb.close());

  Future<int> categoryId(String name) async => (await repo.categories()).firstWhere((c) => c.name == name).id!;

  Future<List<Entry>> all() => repo.entries(const EntryFilter(preset: DatePreset.allTime));

  test('keeps one overall budget and one per type', () async {
    final groceries = await categoryId('Groceries');
    await repo.setBudget(null, 100000);
    await repo.setBudget(null, 120000);
    await repo.setBudget(groceries, 30000);
    await repo.setBudget(groceries, 35000);
    expect((await repo.budgets()).map((b) => (b.categoryId, b.amount)), unorderedEquals([(null, 120000.0), (groceries, 35000.0)]));
    await repo.setBudget(groceries, null);
    expect(await repo.budgets(), hasLength(1));
  });

  test('posts automatic payments once per due date since they were set up', () async {
    final rent = await repo.saveRecurring(RecurringPayment(
        name: 'House rent', categoryId: await categoryId('Rent'), amount: 70000, currency: 'PKR',
        startDate: DateTime(2026, 1, 2), createdOn: DateTime(2026, 8, 20)));
    await repo.saveRecurring(RecurringPayment(
        name: 'School fee', categoryId: await categoryId('Education'), amount: 18000, currency: 'PKR',
        startDate: DateTime(2026, 1, 8), createdOn: DateTime(2026, 8, 20), autoPost: false));

    expect(await service.postDue('PKR', now: DateTime(2026, 10, 15)), 2, reason: 'September and October');
    expect(await service.postDue('PKR', now: DateTime(2026, 10, 15)), 0, reason: 'never twice');
    final posted = await all();
    expect(posted.map((e) => (dateKey(e.date), e.note, e.fxRate)),
        [('2026-10-02', 'House rent', 1.0), ('2026-09-02', 'House rent', 1.0)]);

    // A deleted entry is not posted again.
    await repo.deleteEntry(posted.first.id!);
    expect(await service.postDue('PKR', now: DateTime(2026, 10, 15)), 0);
    final posts = await repo.recurringPosts(from: DateTime(2026, 10), to: DateTime(2026, 10, 31));
    expect(posts.single.recurringId, rent);
    expect(posts.single.entryId, isNull);
  });

  test('manual payments are marked paid or skipped', () async {
    final id = await repo.saveRecurring(RecurringPayment(
        name: 'K-Electric', categoryId: await categoryId('Utilities'), amount: 17000, currency: 'PKR',
        startDate: DateTime(2026, 1, 10), createdOn: DateTime(2026), autoPost: false));
    final bill = (await repo.recurringPayments()).single;
    expect(bill.id, id);
    expect(await service.markPaid(bill, DateTime(2026, 10, 10), 'PKR', amount: 21450, paidOn: DateTime(2026, 10, 12)), isNotNull);
    expect(await service.markPaid(bill, DateTime(2026, 10, 10), 'PKR'), isNull);
    await repo.skipRecurring(id, DateTime(2026, 9, 10));
    final posts = await repo.recurringPosts();
    expect(posts.map((p) => (dateKey(p.due), p.skipped)), unorderedEquals([('2026-10-10', false), ('2026-09-10', true)]));
    expect((await all()).single.amount, 21450);

    await repo.undoRecurringPost(id, DateTime(2026, 9, 10));
    await repo.deleteRecurring(id);
    expect(await repo.recurringPosts(), isEmpty);
    expect(await all(), hasLength(1), reason: 'logged entries stay');
  });

  test('upgrades a version 5 database', () async {
    final path = '${await databaseFactoryFfi.getDatabasesPath()}/v5_upgrade_test.db';
    await databaseFactoryFfi.deleteDatabase(path);
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 5, onCreate: (db, _) => db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY)')));
    await old.close();
    final upgraded = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final tables = await upgraded.db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    expect(tables.map((t) => t['name']), containsAll(['budgets', 'recurring', 'recurring_posts']));
    await upgraded.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
}
