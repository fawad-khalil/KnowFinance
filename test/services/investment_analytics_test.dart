import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/investment.dart';
import 'package:know_finance/services/analytics.dart';
import 'package:know_finance/services/investment_analytics.dart';
import 'package:know_finance/ui/widgets/activity_heatmap.dart';

void main() {
  Entry e(int inv, InvestmentFlow flow, double amount, DateTime date, {double? rate = 1}) => Entry(
        kind: flow.kind,
        amount: amount,
        currency: rate == 1 ? 'PKR' : 'USD',
        homeCurrency: 'PKR',
        fxRate: rate,
        categoryId: 1,
        date: date,
        investmentId: inv,
        investmentFlow: flow,
      );

  group('Holding', () {
    test('adds up buys, costs, sales and income into profit and ROI', () {
      final a = InvestmentAnalytics(
        [
          const Investment(id: 1, name: 'Plot', type: AssetType.property, closed: true),
        ],
        [
          e(1, InvestmentFlow.buy, 1000000, DateTime(2024, 1, 1)),
          e(1, InvestmentFlow.cost, 50000, DateTime(2024, 1, 2)),
          e(1, InvestmentFlow.income, 30000, DateTime(2024, 6, 1)),
          e(1, InvestmentFlow.sale, 1200000, DateTime(2025, 1, 1)),
          e(1, InvestmentFlow.income, 10, DateTime(2025, 2, 1), rate: null),
        ],
        'PKR',
      );
      final h = a.holdings.single;
      expect(h.invested, 1050000);
      expect(h.returned, 1230000);
      expect(h.skipped, 1);
      expect(h.profit('PKR'), 180000);
      expect(h.roi('PKR'), closeTo(180000 / 1050000, 1e-9));
      expect(h.incomeYield, closeTo(30000 / 1050000, 1e-9));
    });

    test('an open holding needs a current value in the home currency', () {
      Investment fund({double? value, String? currency}) => Investment(
          id: 1, name: 'Fund', type: AssetType.fund, currentValue: value, valueCurrency: currency, valuedOn: DateTime(2026, 1, 1));
      final linked = [e(1, InvestmentFlow.buy, 100000, DateTime(2025, 1, 1))];

      expect(InvestmentAnalytics([fund()], linked, 'PKR').holdings.single.profit('PKR'), isNull);
      expect(InvestmentAnalytics([fund(value: 500, currency: 'USD')], linked, 'PKR').holdings.single.profit('PKR'), isNull);

      final h = InvestmentAnalytics([fund(value: 112000, currency: 'PKR')], linked, 'PKR').holdings.single;
      expect(h.profit('PKR'), 12000);
      // One year, 12% up.
      expect(h.annualReturn('PKR'), closeTo(0.12, 0.002));
    });

    test('portfolio leaves unvalued holdings out and counts them', () {
      final a = InvestmentAnalytics(
        [
          Investment(id: 1, name: 'A', type: AssetType.stocks, currentValue: 150, valueCurrency: 'PKR', valuedOn: DateTime(2026, 1, 1)),
          const Investment(id: 2, name: 'B', type: AssetType.gold),
        ],
        [
          e(1, InvestmentFlow.buy, 100, DateTime(2025, 1, 1)),
          e(2, InvestmentFlow.buy, 500, DateTime(2025, 1, 1)),
        ],
        'PKR',
      );
      final s = a.summary();
      expect(s.invested, 100);
      expect(s.profit, 50);
      expect(s.unvalued, 1);
      expect(s.roi, 0.5);
      expect(a.investedByType(), {AssetType.stocks: 100, AssetType.gold: 500});
    });
  });

  group('xirr', () {
    test('matches a simple compound return', () {
      final r = xirr([(DateTime(2020, 1, 1), -1000), (DateTime(2022, 1, 1), 1210)]);
      expect(r, closeTo(0.10, 0.001));
    });

    test('handles losses', () {
      final r = xirr([(DateTime(2020, 1, 1), -1000), (DateTime(2021, 1, 1), 800)]);
      expect(r, closeTo(-0.2, 0.002));
    });

    test('is null without both directions or over a short span', () {
      expect(xirr([(DateTime(2020, 1, 1), -1000)]), isNull);
      expect(xirr([(DateTime(2020, 1, 1), -1000), (DateTime(2020, 1, 10), 1100)]), isNull);
    });
  });

  test('note matching ignores case and works both ways', () {
    expect(noteMatchesInvestment('Meezan Fund top-up', 'meezan fund'), isTrue);
    expect(noteMatchesInvestment('meezan', 'Meezan fund'), isTrue);
    expect(noteMatchesInvestment('KFC', 'Meezan fund'), isFalse);
    expect(noteMatchesInvestment('', 'Meezan fund'), isFalse);
  });

  group('previous period', () {
    test('month-to-date compares with the same days last month', () {
      final p = DateRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31)).previous()!;
      expect(p.start, DateTime(2026, 2, 1));
      expect(p.end, DateTime(2026, 2, 28));
      final q = DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 20)).previous()!;
      expect(q.end, DateTime(2026, 9, 20));
    });

    test('other ranges move back by their length', () {
      final p = DateRange(DateTime(2026, 3, 10), DateTime(2026, 3, 19)).previous()!;
      expect(p.start, DateTime(2026, 2, 28));
      expect(p.end, DateTime(2026, 3, 9));
    });

    test('unbounded has none', () {
      expect(const DateRange(null, null).previous(), isNull);
    });
  });

  test('heatmap levels scale with the busiest day', () {
    expect(ActivityHeatmap.levelOf(0, 10), 0);
    expect(ActivityHeatmap.levelOf(1, 10), 1);
    expect(ActivityHeatmap.levelOf(5, 10), 2);
    expect(ActivityHeatmap.levelOf(10, 10), ActivityHeatmap.levels);
  });

  test('daily activity groups entries by day', () {
    final a = Analytics([
      Entry(kind: EntryKind.expense, amount: 10, currency: 'PKR', homeCurrency: 'PKR', fxRate: 1, categoryId: 1, date: DateTime(2026, 1, 1, 9)),
      Entry(kind: EntryKind.income, amount: 50, currency: 'PKR', homeCurrency: 'PKR', fxRate: 1, categoryId: 1, date: DateTime(2026, 1, 1)),
    ], const {}, 'PKR');
    final d = a.daily()[DateTime(2026, 1, 1)]!;
    expect(d.count, 2);
    expect(d.expense, 10);
    expect(d.income, 50);
  });
}
