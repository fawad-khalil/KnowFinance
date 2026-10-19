import 'dart:math' as math;

import '../models/entry.dart';
import '../models/enums.dart';
import '../models/investment.dart';

/// One dated amount of money moving out of (negative) or back into
/// (positive) the user's pocket.
typedef CashFlow = (DateTime, double);

/// Profit and loss for one investment, from its linked entries.
class Holding {
  Holding(this.investment);

  final Investment investment;
  final List<Entry> entries = [];
  double bought = 0;
  double costs = 0;
  double sold = 0;
  double income = 0;

  /// Units bought and sold, from entries that recorded a quantity.
  double qtyBought = 0;
  double qtySold = 0;

  /// Buy amounts for entries that recorded a quantity, so the average price
  /// isn't skewed by buys logged without one.
  double boughtWithQty = 0;

  /// Buys logged without a quantity; their units are missing from [held].
  int buysWithoutQty = 0;

  /// Entries in another currency without a rate; left out of the totals.
  int skipped = 0;
  DateTime? first;
  DateTime? last;

  /// Everything put in: purchases plus fees, taxes and upkeep.
  double get invested => bought + costs;

  /// Cash already back: sale proceeds plus dividends, rent and profit.
  double get returned => sold + income;

  bool get tracksQuantity => investment.unit != null && qtyBought > 0;

  /// Units still held.
  double get held => tracksQuantity ? qtyBought - qtySold : 0;

  /// Average price paid for one unit, before costs.
  double? get avgBuyPrice => tracksQuantity && boughtWithQty > 0 ? boughtWithQty / qtyBought : null;

  /// Today's market price for one unit, when fetched in the home currency.
  double? marketPrice(String home) =>
      investment.marketCurrency == home ? investment.marketPrice : null;

  /// Held units at today's market price.
  double? marketValue(String home) {
    final p = marketPrice(home);
    return p == null || !tracksQuantity ? null : held * p;
  }

  /// What the units still held cost at the average buy price.
  double? get costOfHeld => avgBuyPrice == null ? null : avgBuyPrice! * held;

  /// Market price against the average price paid, as a fraction.
  double? priceChange(String home) {
    final p = marketPrice(home), a = avgBuyPrice;
    return p == null || a == null || a <= 0 ? null : p / a - 1;
  }

  /// Sale proceeds minus what the sold units cost at the average price.
  double? get realizedGain => avgBuyPrice == null || qtySold <= 0 ? null : sold - avgBuyPrice! * qtySold;

  /// What is still held, in the home currency: zero once closed, the market
  /// value when a price and quantities are known, otherwise the value typed
  /// in. Null while open with neither.
  double? valueIn(String home) {
    if (investment.closed) return 0;
    final market = marketValue(home);
    if (market != null) return market;
    if (investment.currentValue == null || investment.valueCurrency != home) return null;
    return investment.currentValue;
  }

  /// When [valueIn] was last true.
  DateTime? get valuedOn => investment.marketPrice != null && tracksQuantity ? investment.marketPriceOn : investment.valuedOn;

  /// Returned plus what is still held, minus what went in. Null while the
  /// holding is open and has no current value.
  double? profit(String home) {
    final v = valueIn(home);
    return v == null ? null : returned + v - invested;
  }

  /// Profit as a share of what went in.
  double? roi(String home) {
    final p = profit(home);
    return p == null || invested <= 0 ? null : p / invested;
  }

  /// Dividend and rent income as a share of what went in.
  double get incomeYield => invested <= 0 ? 0 : income / invested;

  /// Cash flows for XIRR, with the current value as a final inflow.
  List<CashFlow> flows(String home, {DateTime? now}) {
    final out = <CashFlow>[
      for (final e in entries)
        if (e.homeCurrency == home && e.homeAmount != null)
          (e.date, e.kind == EntryKind.expense ? -e.homeAmount! : e.homeAmount!),
    ];
    final v = valueIn(home);
    if (v != null && v > 0) out.add((valuedOn ?? now ?? DateTime.now(), v));
    return out;
  }

  /// Annualised return. Null when it can't be worked out or the holding is
  /// too young for a yearly figure to mean much.
  double? annualReturn(String home, {DateTime? now}) {
    if (profit(home) == null) return null;
    return xirr(flows(home, now: now));
  }
}

/// Profit realised by one asset inside a date range: dividends and rent
/// received, plus sale proceeds minus what the sold part had cost.
class BookedProfit {
  BookedProfit(this.holding);

  final Holding holding;
  double income = 0;
  double proceeds = 0;
  double costOfSold = 0;

  /// Sales whose cost couldn't be worked out (an open asset sold in part
  /// without quantities); their proceeds are left out of [gain].
  int unknownCost = 0;
  double unknownProceeds = 0;

  double get gain => proceeds - unknownProceeds - costOfSold;
  double get total => income + gain;
}

/// Booked profit for one month or year, for the chart.
class BookedPeriod {
  BookedPeriod(this.start);

  final DateTime start;
  double income = 0;
  double gain = 0;
  double get total => income + gain;
}

class PortfolioSummary {
  const PortfolioSummary({
    required this.invested,
    required this.returned,
    required this.income,
    required this.value,
    required this.unvalued,
    required this.profit,
    required this.annualReturn,
  });

  final double invested;
  final double returned;

  /// The dividend and rent part of [returned].
  final double income;

  /// Current value of open holdings that have one.
  final double value;

  /// Open holdings with no current value; they are left out of [profit].
  final int unvalued;
  final double profit;
  final double? annualReturn;

  double? get roi => invested <= 0 ? null : profit / invested;
}

/// Pure calculations behind the Investments screen.
class InvestmentAnalytics {
  InvestmentAnalytics(List<Investment> investments, List<Entry> linked, this.home, {DateTime? now})
      : now = now ?? DateTime.now() {
    final byId = {for (final i in investments) i.id!: Holding(i)};
    for (final e in linked) {
      final h = byId[e.investmentId];
      if (h == null) continue;
      h.entries.add(e);
      final amt = e.homeCurrency == home ? e.homeAmount : null;
      if (amt == null) {
        h.skipped++;
        continue;
      }
      final flow = e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind);
      final q = e.quantity;
      switch (flow) {
        case InvestmentFlow.buy:
          h.bought += amt;
          if (q != null && q > 0) {
            h.qtyBought += q;
            h.boughtWithQty += amt;
          } else {
            h.buysWithoutQty++;
          }
        case InvestmentFlow.cost:
          h.costs += amt;
        case InvestmentFlow.sale:
          h.sold += amt;
          if (q != null && q > 0) h.qtySold += q;
        case InvestmentFlow.income:
          h.income += amt;
      }
      if (h.first == null || e.date.isBefore(h.first!)) h.first = e.date;
      if (h.last == null || e.date.isAfter(h.last!)) h.last = e.date;
    }
    holdings = byId.values.toList();
  }

  final String home;
  final DateTime now;
  late final List<Holding> holdings;

  PortfolioSummary summary() {
    double invested = 0, returned = 0, income = 0, value = 0, profit = 0;
    var unvalued = 0;
    final flows = <CashFlow>[];
    for (final h in holdings) {
      final p = h.profit(home);
      if (p == null) {
        if (!h.investment.closed && h.invested > 0) unvalued++;
        continue;
      }
      invested += h.invested;
      returned += h.returned;
      income += h.income;
      value += h.valueIn(home)!;
      profit += p;
      flows.addAll(h.flows(home, now: now));
    }
    return PortfolioSummary(
      invested: invested,
      returned: returned,
      income: income,
      value: value,
      unvalued: unvalued,
      profit: profit,
      annualReturn: xirr(flows),
    );
  }

  /// Invested amount per asset type, for the allocation chart.
  Map<AssetType, double> investedByType() {
    final out = <AssetType, double>{};
    for (final h in holdings) {
      if (h.invested <= 0) continue;
      out[h.investment.type] = (out[h.investment.type] ?? 0) + h.invested;
    }
    return out;
  }

  /// What a sale entry's sold part had cost: its units at the average buy
  /// price, or for a closed asset counted without units, its share of
  /// everything put in. Null when neither applies.
  double? costOfSale(Holding h, Entry sale) {
    final amt = sale.homeAmount;
    if (amt == null) return null;
    final avg = h.avgBuyPrice;
    if (avg != null && (sale.quantity ?? 0) > 0) return avg * sale.quantity!;
    if (h.investment.closed && h.sold > 0) return h.invested * amt / h.sold;
    return null;
  }

  bool _inRange(DateTime d, DateTime? start, DateTime? end) {
    final day = DateTime(d.year, d.month, d.day);
    return (start == null || !day.isBefore(start)) && (end == null || !day.isAfter(end));
  }

  /// Profit booked between [start] and [end] (inclusive; null is open),
  /// per asset, biggest first. Assets with nothing booked are left out.
  List<BookedProfit> booked({DateTime? start, DateTime? end}) {
    final out = <BookedProfit>[];
    for (final h in holdings) {
      final b = BookedProfit(h);
      var any = false;
      for (final e in h.entries) {
        if (e.homeCurrency != home || e.homeAmount == null || !_inRange(e.date, start, end)) continue;
        switch (e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind)) {
          case InvestmentFlow.income:
            b.income += e.homeAmount!;
            any = true;
          case InvestmentFlow.sale:
            b.proceeds += e.homeAmount!;
            final cost = costOfSale(h, e);
            if (cost == null) {
              b.unknownCost++;
              b.unknownProceeds += e.homeAmount!;
            } else {
              b.costOfSold += cost;
            }
            any = true;
          case InvestmentFlow.buy:
          case InvestmentFlow.cost:
            break;
        }
      }
      if (any) out.add(b);
    }
    return out..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Booked profit per month (or per year over spans longer than two
  /// years), with no gaps, for a bar chart.
  List<BookedPeriod> bookedTimeline({DateTime? start, DateTime? end}) {
    final events = <(DateTime, double, bool)>[];
    for (final h in holdings) {
      for (final e in h.entries) {
        if (e.homeCurrency != home || e.homeAmount == null || !_inRange(e.date, start, end)) continue;
        final flow = e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind);
        if (flow == InvestmentFlow.income) events.add((e.date, e.homeAmount!, true));
        if (flow == InvestmentFlow.sale) {
          final cost = costOfSale(h, e);
          if (cost != null) events.add((e.date, e.homeAmount! - cost, false));
        }
      }
    }
    if (events.isEmpty) return const [];
    final from = start ?? events.map((e) => e.$1).reduce((a, b) => a.isBefore(b) ? a : b);
    final to = end ?? events.map((e) => e.$1).reduce((a, b) => a.isAfter(b) ? a : b);
    final yearly = (to.year - from.year) * 12 + to.month - from.month >= 24;
    DateTime keyOf(DateTime d) => yearly ? DateTime(d.year) : DateTime(d.year, d.month);
    final periods = <DateTime, BookedPeriod>{};
    for (var d = keyOf(from); !d.isAfter(keyOf(to)); d = yearly ? DateTime(d.year + 1) : DateTime(d.year, d.month + 1)) {
      periods[d] = BookedPeriod(d);
    }
    for (final (d, amt, isIncome) in events) {
      final p = periods[keyOf(d)];
      if (p == null) continue;
      if (isIncome) {
        p.income += amt;
      } else {
        p.gain += amt;
      }
    }
    return periods.values.toList();
  }

  /// Dividend and rent income per year.
  Map<int, double> incomeByYear() {
    final out = <int, double>{};
    for (final h in holdings) {
      for (final e in h.entries) {
        if ((e.investmentFlow ?? InvestmentFlow.defaultFor(e.kind)) != InvestmentFlow.income) continue;
        if (e.homeCurrency != home || e.homeAmount == null) continue;
        out[e.date.year] = (out[e.date.year] ?? 0) + e.homeAmount!;
      }
    }
    return out;
  }
}

/// Annualised internal rate of return for irregular cash flows, found by
/// bisection. Null when there aren't both outflows and inflows, or they
/// span less than 30 days.
double? xirr(List<CashFlow> flows) {
  if (!flows.any((f) => f.$2 < 0) || !flows.any((f) => f.$2 > 0)) return null;
  final start = flows.map((f) => f.$1).reduce((a, b) => a.isBefore(b) ? a : b);
  final end = flows.map((f) => f.$1).reduce((a, b) => a.isAfter(b) ? a : b);
  if (end.difference(start).inDays < 30) return null;

  double npv(double rate) {
    var sum = 0.0;
    for (final (d, amt) in flows) {
      sum += amt / math.pow(1 + rate, d.difference(start).inDays / 365.0);
    }
    return sum;
  }

  var lo = -0.9999, hi = 1.0;
  var fLo = npv(lo), fHi = npv(hi);
  while (fLo.sign == fHi.sign && hi < 1e6) {
    hi *= 4;
    fHi = npv(hi);
  }
  if (fLo.sign == fHi.sign || fLo.isNaN || fHi.isNaN) return null;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    final fMid = npv(mid);
    if (fMid.abs() < 1e-7 || hi - lo < 1e-9) return mid;
    if (fMid.sign == fLo.sign) {
      lo = mid;
      fLo = fMid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Ranks unlinked entries for an investment: notes that mention its name
/// (ignoring case) come first.
bool noteMatchesInvestment(String note, String name) {
  final n = note.toLowerCase().trim(), i = name.toLowerCase().trim();
  if (n.isEmpty || i.isEmpty) return false;
  return n.contains(i) || i.contains(n);
}
