import 'entry.dart';
import 'enums.dart';

/// Something money was put into: a stock, a fund, a plot, gold. Entries are
/// linked to it as buys, costs, sales or dividend/rent income.
class Investment {
  const Investment({
    this.id,
    required this.name,
    required this.type,
    this.currentValue,
    this.valueCurrency,
    this.valuedOn,
    this.closed = false,
    this.unit,
    this.priceSymbol,
    this.marketPrice,
    this.marketCurrency,
    this.marketPriceOn,
  });

  final int? id;
  final String name;
  final AssetType type;

  /// What the holding is worth today, as last typed in. Null when unknown.
  final double? currentValue;
  final String? valueCurrency;
  final DateTime? valuedOn;

  /// Fully sold or wound up: nothing is left to value.
  final bool closed;

  /// What quantities are counted in, when the asset is tracked by amount
  /// held (grams of gold, shares, barrels). Null for things like a plot.
  final QuantityUnit? unit;

  /// Market price feed: a [priceFeeds] symbol or any Yahoo Finance ticker.
  final String? priceSymbol;

  /// Last fetched market price for one [unit], in [marketCurrency].
  final double? marketPrice;
  final String? marketCurrency;
  final DateTime? marketPriceOn;

  Investment copyWith({
    String? name,
    AssetType? type,
    double? Function()? currentValue,
    String? Function()? valueCurrency,
    DateTime? Function()? valuedOn,
    bool? closed,
    QuantityUnit? Function()? unit,
    String? Function()? priceSymbol,
    double? Function()? marketPrice,
    String? Function()? marketCurrency,
    DateTime? Function()? marketPriceOn,
  }) =>
      Investment(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        currentValue: currentValue != null ? currentValue() : this.currentValue,
        valueCurrency: valueCurrency != null ? valueCurrency() : this.valueCurrency,
        valuedOn: valuedOn != null ? valuedOn() : this.valuedOn,
        closed: closed ?? this.closed,
        unit: unit != null ? unit() : this.unit,
        priceSymbol: priceSymbol != null ? priceSymbol() : this.priceSymbol,
        marketPrice: marketPrice != null ? marketPrice() : this.marketPrice,
        marketCurrency: marketCurrency != null ? marketCurrency() : this.marketCurrency,
        marketPriceOn: marketPriceOn != null ? marketPriceOn() : this.marketPriceOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'current_value': currentValue,
        'value_currency': valueCurrency,
        'valued_on': valuedOn == null ? null : dateKey(valuedOn!),
        'closed': closed ? 1 : 0,
        'unit': unit?.name,
        'price_symbol': priceSymbol,
        'market_price': marketPrice,
        'market_currency': marketCurrency,
        'market_price_on': marketPriceOn == null ? null : dateKey(marketPriceOn!),
      };

  factory Investment.fromMap(Map<String, Object?> m) => Investment(
        id: m['id'] as int,
        name: m['name'] as String,
        type: AssetType.fromName(m['type'] as String),
        currentValue: (m['current_value'] as num?)?.toDouble(),
        valueCurrency: m['value_currency'] as String?,
        valuedOn: m['valued_on'] == null ? null : DateTime.parse(m['valued_on'] as String),
        closed: (m['closed'] as int) == 1,
        unit: QuantityUnit.fromName(m['unit'] as String?),
        priceSymbol: m['price_symbol'] as String?,
        marketPrice: (m['market_price'] as num?)?.toDouble(),
        marketCurrency: m['market_currency'] as String?,
        marketPriceOn: m['market_price_on'] == null ? null : DateTime.parse(m['market_price_on'] as String),
      );
}

/// A market price source offered in the asset form.
class PriceFeed {
  const PriceFeed(this.symbol, this.label, this.quotedPer, {this.yahoo = false, this.type});

  final String symbol;
  final String label;

  /// The unit the source quotes a price for.
  final QuantityUnit quotedPer;

  /// Quoted by Yahoo Finance (today's price only) rather than the currency
  /// API, which also has past dates.
  final bool yahoo;

  /// Asset type this feed usually goes with, to prefill the form.
  final AssetType? type;
}

const priceFeeds = <PriceFeed>[
  PriceFeed('XAU', 'Gold', QuantityUnit.troyOunce, type: AssetType.gold),
  PriceFeed('XAG', 'Silver', QuantityUnit.troyOunce, type: AssetType.silver),
  PriceFeed('XPT', 'Platinum', QuantityUnit.troyOunce, type: AssetType.commodity),
  PriceFeed('XPD', 'Palladium', QuantityUnit.troyOunce, type: AssetType.commodity),
  PriceFeed('BTC', 'Bitcoin', QuantityUnit.coin, type: AssetType.crypto),
  PriceFeed('ETH', 'Ethereum', QuantityUnit.coin, type: AssetType.crypto),
  PriceFeed('CL=F', 'WTI crude oil', QuantityUnit.barrel, yahoo: true, type: AssetType.commodity),
  PriceFeed('BZ=F', 'Brent crude oil', QuantityUnit.barrel, yahoo: true, type: AssetType.commodity),
  PriceFeed('HG=F', 'Copper', QuantityUnit.pound, yahoo: true, type: AssetType.commodity),
];

/// The feed for [symbol]; an unknown symbol is treated as a Yahoo ticker
/// quoted per [fallbackUnit] (a share, usually).
PriceFeed feedFor(String symbol, QuantityUnit fallbackUnit) =>
    priceFeeds.where((f) => f.symbol == symbol).firstOrNull ??
    PriceFeed(symbol, symbol, fallbackUnit, yahoo: true);
