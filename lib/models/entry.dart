import 'enums.dart';

/// A single income or expense.
///
/// [amount] is in the entry's own [currency]. [fxRate] converts it to the
/// user's home currency ([homeCurrency] at the time the rate was set), so
/// reports never shift when exchange rates move later.
class Entry {
  const Entry({
    this.id,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.homeCurrency,
    this.fxRate,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.source = EntrySource.manual,
    this.investmentId,
    this.investmentFlow,
    this.quantity,
    this.loanId,
  });

  final int? id;
  final EntryKind kind;
  final double amount;
  final String currency;
  final String homeCurrency;

  /// Null when the entry is in a foreign currency and no rate is known yet.
  final double? fxRate;
  final int categoryId;
  final DateTime date;
  final String note;
  final EntrySource source;

  /// The investment this entry bought, cost, sold or earned from, if any.
  final int? investmentId;
  final InvestmentFlow? investmentFlow;

  /// How much of the investment this bought or sold, in its unit.
  final double? quantity;

  /// The loan this entry borrowed, repaid, lent or got back. Loan entries
  /// move money but are neither income nor spending.
  final int? loanId;

  bool get isLoan => loanId != null;

  bool get needsRate => fxRate == null;

  /// Amount in the home currency, or null while the rate is missing.
  double? get homeAmount => fxRate == null ? null : amount * fxRate!;

  Entry copyWith({
    EntryKind? kind,
    double? amount,
    String? currency,
    String? homeCurrency,
    double? Function()? fxRate,
    int? categoryId,
    DateTime? date,
    String? note,
    int? Function()? investmentId,
    InvestmentFlow? Function()? investmentFlow,
    double? Function()? quantity,
    int? Function()? loanId,
  }) =>
      Entry(
        id: id,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        homeCurrency: homeCurrency ?? this.homeCurrency,
        fxRate: fxRate != null ? fxRate() : this.fxRate,
        categoryId: categoryId ?? this.categoryId,
        date: date ?? this.date,
        note: note ?? this.note,
        source: source,
        investmentId: investmentId != null ? investmentId() : this.investmentId,
        investmentFlow: investmentFlow != null ? investmentFlow() : this.investmentFlow,
        quantity: quantity != null ? quantity() : this.quantity,
        loanId: loanId != null ? loanId() : this.loanId,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'currency': currency,
        'home_currency': homeCurrency,
        'fx_rate': fxRate,
        'category_id': categoryId,
        'date': dateKey(date),
        'note': note,
        'source': source.name,
        'investment_id': investmentId,
        'investment_flow': investmentFlow?.name,
        'quantity': quantity,
        'loan_id': loanId,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int,
        kind: EntryKind.fromName(m['kind'] as String),
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String,
        homeCurrency: m['home_currency'] as String,
        fxRate: (m['fx_rate'] as num?)?.toDouble(),
        categoryId: m['category_id'] as int,
        date: DateTime.parse(m['date'] as String),
        note: m['note'] as String,
        source: EntrySource.fromName(m['source'] as String),
        investmentId: m['investment_id'] as int?,
        investmentFlow: InvestmentFlow.fromName(m['investment_flow'] as String?),
        quantity: (m['quantity'] as num?)?.toDouble(),
        loanId: m['loan_id'] as int?,
      );
}

/// Dates are stored as yyyy-MM-dd so they sort and compare as text.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
