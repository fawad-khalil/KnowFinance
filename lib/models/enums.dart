/// Whether money came in or went out.
enum EntryKind {
  income,
  expense;

  static EntryKind fromName(String name) =>
      EntryKind.values.firstWhere((k) => k.name == name);
}

/// The top-level bucket every expense type belongs to.
enum Bucket {
  needs('Needs'),
  wants('Wants'),
  savings('Savings');

  const Bucket(this.label);
  final String label;

  static Bucket? fromName(String? name) => name == null
      ? null
      : Bucket.values.firstWhere((b) => b.name == name);
}

/// Where an entry was created from.
enum EntrySource {
  manual,
  sms,
  email,
  statement;

  static EntrySource fromName(String name) =>
      EntrySource.values.firstWhere((s) => s.name == name);
}

/// A payable is money the user borrowed and owes back; a receivable is
/// money the user lent and is owed.
enum LoanDirection {
  payable('I borrowed', 'Payable'),
  receivable('I lent', 'Receivable');

  const LoanDirection(this.label, this.short);
  final String label;
  final String short;

  /// The kind of entry that starts the loan: borrowing brings money in,
  /// lending sends it out.
  EntryKind get openingKind => this == payable ? EntryKind.income : EntryKind.expense;

  /// What an entry of [kind] does to a loan in this direction.
  String flowLabel(EntryKind kind) => switch ((this, kind)) {
        (payable, EntryKind.income) => 'Borrowed',
        (payable, EntryKind.expense) => 'Repaid',
        (receivable, EntryKind.expense) => 'Lent',
        (receivable, EntryKind.income) => 'Got back',
      };
}

/// What an entry linked to an investment did to it. Expenses are [buy] or
/// [cost]; incomes are [sale] or [income].
enum InvestmentFlow {
  buy('Buy', EntryKind.expense),
  cost('Cost', EntryKind.expense),
  sale('Sale', EntryKind.income),
  income('Dividend / rent', EntryKind.income);

  const InvestmentFlow(this.label, this.kind);
  final String label;
  final EntryKind kind;

  static InvestmentFlow? fromName(String? name) => name == null
      ? null
      : InvestmentFlow.values.firstWhere((f) => f.name == name);

  static List<InvestmentFlow> forKind(EntryKind kind) =>
      InvestmentFlow.values.where((f) => f.kind == kind).toList();

  /// What a newly linked entry most likely is.
  static InvestmentFlow defaultFor(EntryKind kind) =>
      kind == EntryKind.expense ? InvestmentFlow.buy : InvestmentFlow.income;
}

enum AssetType {
  stocks('Stocks'),
  fund('Mutual fund'),
  property('Property'),
  gold('Gold'),
  silver('Silver'),
  commodity('Commodity'),
  crypto('Crypto'),
  deposit('Savings scheme'),
  business('Business'),
  vehicle('Vehicle'),
  other('Other');

  const AssetType(this.label);
  final String label;

  static AssetType fromName(String name) =>
      AssetType.values.firstWhere((t) => t.name == name, orElse: () => AssetType.other);
}

/// What an asset is counted in. Mass units carry their weight in grams so
/// prices can be converted between them (gold is quoted per troy ounce,
/// bought per tola or gram).
enum QuantityUnit {
  gram('g', 1),
  tola('tola', 11.6638038),
  troyOunce('troy oz', 31.1034768),
  kilogram('kg', 1000),
  pound('lb', 453.59237),
  barrel('barrel'),
  share('share'),
  coin('coin'),
  unit('unit');

  const QuantityUnit(this.label, [this.grams]);
  final String label;
  final double? grams;

  static QuantityUnit? fromName(String? name) => name == null
      ? null
      : QuantityUnit.values.firstWhere((u) => u.name == name, orElse: () => QuantityUnit.unit);

  /// Factor to turn a price per [from] into a price per this unit, or null
  /// when the two can't be compared (barrels and grams).
  double? perUnitFactor(QuantityUnit from) {
    if (from == this) return 1;
    if (grams != null && from.grams != null) return grams! / from.grams!;
    return null;
  }
}
