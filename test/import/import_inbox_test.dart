import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/import/alert_parser.dart';
import 'package:know_finance/import/category_suggester.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/import/import_service.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/loan.dart';
import 'package:know_finance/services/fx_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late FinanceRepository repo;
  final now = DateTime(2026, 10, 19);

  setUp(() async {
    appDb = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(appDb);
  });
  tearDown(() => appDb.close());

  test('skips duplicates and accepts into entries', () async {
    const parser = AlertParser();
    final t = parser.parse('PKR 900 debited for purchase at KFC DHA on 18-Oct-26', receivedAt: now)!;
    expect(await repo.addImports([t, t]), 1);
    expect(await repo.addImports([t]), 0);
    final pending = await repo.pendingImports();
    expect(pending.single.counterparty, 'KFC DHA');

    final cats = await repo.categories();
    final dining = cats.firstWhere((c) => c.name == 'Dining out');
    await repo.acceptImport(
      pending.single.id,
      Entry(
        kind: EntryKind.expense,
        amount: 900,
        currency: 'PKR',
        homeCurrency: 'PKR',
        fxRate: 1,
        categoryId: dining.id!,
        date: pending.single.date,
        note: 'KFC DHA',
        source: EntrySource.sms,
      ),
    );
    expect(await repo.pendingImportCount(), 0);
    expect((await repo.noteCategoryHistory())['kfc dha'], dining.id);
  });

  test('suggests from history first, then merchant keywords', () async {
    final cats = await repo.categories();
    int id(String n) => cats.firstWhere((c) => c.name == n).id!;
    final s = CategorySuggester(cats, {'imtiaz super market': id('Shopping')});
    expect(s.suggest(EntryKind.expense, 'IMTIAZ  Super Market', ''), id('Shopping'));
    expect(s.suggest(EntryKind.expense, 'Naheed', ''), id('Groceries'));
    expect(s.suggest(EntryKind.expense, 'K-Electric', ''), id('Utilities'));
    expect(s.suggest(EntryKind.expense, 'Somebody', 'otherwise unknown'), isNull);
    expect(s.suggest(EntryKind.income, 'XYZ', 'Salary for Oct'), id('Salary'));
    expect(s.suggest(EntryKind.income, 'Ali', ''), id('Other income'));
  });

  test('an import can be accepted against a loan', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ImportService(repo, FxService(repo), await SharedPreferences.getInstance());
    final t = const AlertParser().parse(
        'PKR 100,000.00 sent to Ali from your A/C xxx6373 on 18-Oct-2026 at 19:22', receivedAt: now)!;
    await repo.addImports([t]);
    final loan = await repo.saveLoan(const Loan(name: 'Ali', direction: LoanDirection.receivable));

    await service.accept((await repo.pendingImports()).single,
        categoryId: null, kind: EntryKind.expense, note: 'Ali', homeCurrency: 'PKR', loanId: loan);

    final e = (await repo.entries(const EntryFilter(preset: DatePreset.allTime))).single;
    expect(e.loanId, loan);
    expect(e.categoryId, await repo.loanCategoryId(EntryKind.expense));
    expect(await repo.pendingImportCount(), 0);
  });
}
