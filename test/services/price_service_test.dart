import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/investment.dart';
import 'package:know_finance/services/fx_service.dart';
import 'package:know_finance/services/investment_analytics.dart';
import 'package:know_finance/services/price_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase appDb;
  late FinanceRepository repo;
  late PriceService prices;
  final requested = <String>[];

  // Currency API: 1 XAU = 1,166,380.38 PKR (about 437,393 PKR a tola at
  // 11.6638 g a tola), 1 USD = 280 PKR. Yahoo: WTI at 98 USD a barrel.
  final client = MockClient((req) async {
    requested.add(req.url.toString());
    if (req.url.host.contains('yahoo')) {
      return http.Response(jsonEncode({
        'chart': {
          'result': [
            {'meta': {'symbol': 'CL=F', 'regularMarketPrice': 98.0, 'currency': 'USD'}}
          ]
        }
      }), 200);
    }
    final base = req.url.pathSegments.last.split('.').first;
    final rates = {
      'xau': {'pkr': 1166380.38},
      'usd': {'pkr': 280.0},
    };
    if (!rates.containsKey(base)) return http.Response('', 404);
    return http.Response(jsonEncode({'date': '2026-10-01', base: rates[base]}), 200);
  });

  setUp(() async {
    requested.clear();
    appDb = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = FinanceRepository(appDb);
    prices = PriceService(repo, FxService(repo, client: client), client: client);
  });

  tearDown(() => appDb.close());

  test('converts metal prices per troy ounce to the unit held', () async {
    final perTola = await prices.price('XAU', QuantityUnit.tola, 'PKR');
    expect(perTola, closeTo(1166380.38 / 31.1034768 * 11.6638038, 0.01));
    final perGram = await prices.price('XAU', QuantityUnit.gram, 'PKR');
    expect(perGram, closeTo(1166380.38 / 31.1034768, 0.01));
    // Gold isn't sold by the barrel.
    expect(await prices.price('XAU', QuantityUnit.barrel, 'PKR'), isNull);
  });

  test('converts a Yahoo quote to the home currency', () async {
    expect(await prices.price('CL=F', QuantityUnit.barrel, 'PKR'), closeTo(98 * 280, 1e-6));
    // Yahoo has no past prices.
    expect(await prices.price('CL=F', QuantityUnit.barrel, 'PKR', date: DateTime(2025, 1, 1)), isNull);
    expect(PriceService.hasHistory('XAU'), isTrue);
    expect(PriceService.hasHistory('CL=F'), isFalse);
  });

  test('refresh stores today\'s price on priced open assets only', () async {
    final gold = await repo.saveInvestment(
        const Investment(name: 'Gold', type: AssetType.gold, unit: QuantityUnit.tola, priceSymbol: 'XAU'));
    await repo.saveInvestment(const Investment(name: 'Plot', type: AssetType.property));
    await repo.saveInvestment(const Investment(
        name: 'Old gold', type: AssetType.gold, unit: QuantityUnit.tola, priceSymbol: 'XAU', closed: true));

    expect(await prices.refresh('PKR'), 1);
    final saved = (await repo.investments()).firstWhere((i) => i.id == gold);
    expect(saved.marketPrice, closeTo(1166380.38 / 31.1034768 * 11.6638038, 0.01));
    expect(saved.marketCurrency, 'PKR');

    // Already priced today, so nothing is fetched again.
    expect(await prices.refresh('PKR'), 0);
  });

  test('reads quantities from notes', () {
    expect(quantityFromNote('Gold 22k 2 tola', QuantityUnit.tola), 2);
    expect(quantityFromNote('gold 10g ring', QuantityUnit.tola), closeTo(10 / 11.6638038, 1e-9));
    expect(quantityFromNote('2 tola', QuantityUnit.gram), closeTo(23.3276076, 1e-6));
    expect(quantityFromNote('Bought 15 shares', QuantityUnit.share), 15);
    expect(quantityFromNote('0.5 oz silver', QuantityUnit.troyOunce), 0.5);
    expect(quantityFromNote('Gold from Hamid jewellers', QuantityUnit.tola), isNull);
    expect(quantityFromNote('3 barrels', QuantityUnit.tola), isNull);
  });

  test('holding compares average price paid with the market', () {
    Entry e(InvestmentFlow f, double amount, double? qty, DateTime d) => Entry(
          kind: f.kind,
          amount: amount,
          currency: 'PKR',
          homeCurrency: 'PKR',
          fxRate: 1,
          categoryId: 1,
          date: d,
          investmentId: 1,
          investmentFlow: f,
          quantity: qty,
        );
    final a = InvestmentAnalytics(
      [
        Investment(
          id: 1,
          name: 'Gold',
          type: AssetType.gold,
          unit: QuantityUnit.tola,
          priceSymbol: 'XAU',
          marketPrice: 450000,
          marketCurrency: 'PKR',
          marketPriceOn: DateTime(2026, 10, 1),
        ),
      ],
      [
        e(InvestmentFlow.buy, 600000, 2, DateTime(2024, 1, 1)),
        e(InvestmentFlow.buy, 400000, 1, DateTime(2025, 1, 1)),
        e(InvestmentFlow.buy, 5000, null, DateTime(2025, 2, 1)),
        e(InvestmentFlow.sale, 420000, 1, DateTime(2026, 1, 1)),
      ],
      'PKR',
    );
    final h = a.holdings.single;
    expect(h.held, 2);
    expect(h.avgBuyPrice, closeTo(1000000 / 3, 1e-6));
    expect(h.costOfHeld, closeTo(2000000 / 3, 1e-6));
    expect(h.marketValue('PKR'), 900000);
    expect(h.priceChange('PKR'), closeTo(450000 / (1000000 / 3) - 1, 1e-9));
    expect(h.realizedGain, closeTo(420000 - 1000000 / 3, 1e-6));
    expect(h.buysWithoutQty, 1);
    // Market value replaces a typed-in value: 420k back + 900k held - 1,005k in.
    expect(h.profit('PKR'), closeTo(315000, 1e-6));
    expect(h.marketValue('USD'), isNull);
  });

  test('unit conversion', () {
    expect(QuantityUnit.tola.perUnitFactor(QuantityUnit.gram), closeTo(11.6638038, 1e-9));
    expect(QuantityUnit.share.perUnitFactor(QuantityUnit.share), 1);
    expect(QuantityUnit.barrel.perUnitFactor(QuantityUnit.gram), isNull);
  });
}
