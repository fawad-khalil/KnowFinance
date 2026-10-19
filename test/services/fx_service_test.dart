import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/services/fx_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late FinanceRepository repo;
  var calls = 0;
  var online = true;

  final client = MockClient((req) async {
    calls++;
    if (!online) throw http.ClientException('offline');
    return http.Response(
      jsonEncode({
        'date': '2026-10-01',
        'usd': {'pkr': 280.5, 'eur': 0.9},
      }),
      200,
    );
  });

  setUp(() async {
    calls = 0;
    online = true;
    appDb = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(appDb);
  });

  tearDown(() => appDb.close());

  test('fetches once, then serves from cache', () async {
    final fx = FxService(repo, client: client);
    expect(await fx.rate('USD', 'PKR', DateTime(2026, 10, 1)), 280.5);
    expect(await fx.rate('USD', 'PKR', DateTime(2026, 10, 1)), 280.5);
    expect(calls, 1);
    expect(await fx.rate('PKR', 'PKR', DateTime(2026, 10, 1)), 1);
  });

  test('returns null offline so the user can type the rate', () async {
    online = false;
    final fx = FxService(repo, client: client);
    expect(await fx.rate('USD', 'PKR', DateTime(2026, 10, 1)), isNull);
  });

  test('re-bases entries when the home currency changes', () async {
    final cat = (await repo.categories(kind: EntryKind.income)).first.id!;
    await repo.saveEntry(Entry(
      kind: EntryKind.income,
      amount: 100,
      currency: 'USD',
      homeCurrency: 'EUR',
      fxRate: 0.9,
      categoryId: cat,
      date: DateTime(2026, 10, 1),
    ));
    final fx = FxService(repo, client: client);
    expect(await fx.refreshEntries('PKR'), 0);
    final e = (await repo.entriesNeedingRate('EUR')).single;
    expect(e.homeCurrency, 'PKR');
    expect(e.homeAmount, closeTo(28050, 0.001));
  });
}
