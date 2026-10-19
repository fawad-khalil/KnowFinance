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

  Investment copyWith({
    String? name,
    AssetType? type,
    double? Function()? currentValue,
    String? Function()? valueCurrency,
    DateTime? Function()? valuedOn,
    bool? closed,
  }) =>
      Investment(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        currentValue: currentValue != null ? currentValue() : this.currentValue,
        valueCurrency: valueCurrency != null ? valueCurrency() : this.valueCurrency,
        valuedOn: valuedOn != null ? valuedOn() : this.valuedOn,
        closed: closed ?? this.closed,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'current_value': currentValue,
        'value_currency': valueCurrency,
        'valued_on': valuedOn == null ? null : dateKey(valuedOn!),
        'closed': closed ? 1 : 0,
      };

  factory Investment.fromMap(Map<String, Object?> m) => Investment(
        id: m['id'] as int,
        name: m['name'] as String,
        type: AssetType.fromName(m['type'] as String),
        currentValue: (m['current_value'] as num?)?.toDouble(),
        valueCurrency: m['value_currency'] as String?,
        valuedOn: m['valued_on'] == null ? null : DateTime.parse(m['valued_on'] as String),
        closed: (m['closed'] as int) == 1,
      );
}
