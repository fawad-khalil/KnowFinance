import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/finance_repository.dart';
import '../models/enums.dart';
import '../models/investment.dart';
import 'fx_service.dart';

/// Market prices for assets with a price feed.
///
/// Metals (XAU, XAG, XPT, XPD) and crypto come from the same currency API as
/// exchange rates, which also has past dates, so a buy can be compared with
/// the market price on its own day. Anything else is looked up on Yahoo
/// Finance (oil futures, stocks), which gives today's price only.
class PriceService {
  PriceService(this._repo, this._fx, {http.Client? client}) : _client = client ?? http.Client();

  final FinanceRepository _repo;
  final FxService _fx;
  final http.Client _client;

  /// Price of one [unit] of [symbol] in [home] on [date] (today when null).
  /// Null when offline, the symbol is unknown or the units don't convert.
  Future<double?> price(String symbol, QuantityUnit unit, String home, {DateTime? date}) async {
    final feed = feedFor(symbol, unit);
    final factor = unit.perUnitFactor(feed.quotedPer);
    if (factor == null) return null;
    if (!feed.yahoo) {
      // The currency API treats metals and coins as currencies: 1 XAU = n PKR.
      final r = await _fx.rate(feed.symbol, home, date ?? DateTime.now());
      return r == null ? null : r * factor;
    }
    if (date != null) return null;
    final quote = await _yahoo(feed.symbol);
    if (quote == null) return null;
    final (amount, currency) = quote;
    final fx = await _fx.rate(currency, home, DateTime.now());
    return fx == null ? null : amount * fx * factor;
  }

  /// Whether past prices can be looked up, for comparing each buy with the
  /// market on its day.
  static bool hasHistory(String symbol) => priceFeeds.any((f) => f.symbol == symbol && !f.yahoo);

  Future<(double, String)?> _yahoo(String symbol) async {
    final url = Uri.https('query1.finance.yahoo.com', '/v8/finance/chart/$symbol', {'range': '1d', 'interval': '1d'});
    try {
      final res = await _client.get(url, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final meta = (jsonDecode(res.body) as Map<String, dynamic>)['chart']['result'][0]['meta'] as Map<String, dynamic>;
      var price = (meta['regularMarketPrice'] as num?)?.toDouble();
      var currency = meta['currency'] as String?;
      if (price == null || currency == null) return null;
      // London prices come in pence.
      if (currency == 'GBp') {
        price /= 100;
        currency = 'GBP';
      }
      return (price, currency.toUpperCase());
    } catch (_) {
      return null;
    }
  }

  /// Fetches today's price for every open priced asset not yet priced today
  /// in [home]. Returns how many were updated.
  Future<int> refresh(String home, {bool force = false}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var updated = 0;
    for (final inv in await _repo.investments()) {
      if (inv.closed || inv.priceSymbol == null || inv.unit == null) continue;
      if (!force && inv.marketCurrency == home && inv.marketPriceOn != null && !inv.marketPriceOn!.isBefore(today)) continue;
      final p = await price(inv.priceSymbol!, inv.unit!, home);
      if (p == null) continue;
      await _repo.saveInvestment(inv.copyWith(
        marketPrice: () => p,
        marketCurrency: () => home,
        marketPriceOn: () => today,
      ));
      updated++;
    }
    return updated;
  }
}

/// Reads an amount like "2 tola", "10g", "0.5 oz" or "15 shares" from an
/// entry note, for prefilling the quantity of a buy or sale. Only units that
/// convert to [unit] are accepted.
double? quantityFromNote(String note, QuantityUnit unit) {
  const words = <String, QuantityUnit>{
    'tola': QuantityUnit.tola,
    'tolas': QuantityUnit.tola,
    'g': QuantityUnit.gram,
    'gm': QuantityUnit.gram,
    'gms': QuantityUnit.gram,
    'gram': QuantityUnit.gram,
    'grams': QuantityUnit.gram,
    'kg': QuantityUnit.kilogram,
    'oz': QuantityUnit.troyOunce,
    'ounce': QuantityUnit.troyOunce,
    'ounces': QuantityUnit.troyOunce,
    'lb': QuantityUnit.pound,
    'lbs': QuantityUnit.pound,
    'bbl': QuantityUnit.barrel,
    'barrel': QuantityUnit.barrel,
    'barrels': QuantityUnit.barrel,
    'share': QuantityUnit.share,
    'shares': QuantityUnit.share,
    'coin': QuantityUnit.coin,
    'coins': QuantityUnit.coin,
    'btc': QuantityUnit.coin,
    'eth': QuantityUnit.coin,
    'unit': QuantityUnit.unit,
    'units': QuantityUnit.unit,
  };
  // Skips things like "22k" and takes the first amount with a known unit.
  for (final m in RegExp(r'(\d+(?:[.,]\d+)?)\s*([a-z]+)\b', caseSensitive: false).allMatches(note)) {
    final from = words[m.group(2)!.toLowerCase()];
    if (from == null) continue;
    // 2 tola is 2 × (grams per tola ÷ grams per [unit]) of [unit].
    final factor = from.perUnitFactor(unit);
    if (factor == null) return null;
    return double.parse(m.group(1)!.replaceAll(',', '.')) * factor;
  }
  return null;
}
