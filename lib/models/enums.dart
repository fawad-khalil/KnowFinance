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
  crypto('Crypto'),
  deposit('Savings scheme'),
  business('Business'),
  other('Other');

  const AssetType(this.label);
  final String label;

  static AssetType fromName(String name) =>
      AssetType.values.firstWhere((t) => t.name == name, orElse: () => AssetType.other);
}
