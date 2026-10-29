import '../models/enums.dart';

/// A transaction read from an SMS, email or statement, before the user
/// confirms it.
class ParsedTransaction {
  const ParsedTransaction({
    required this.kind,
    required this.amount,
    required this.currency,
    required this.date,
    required this.source,
    required this.raw,
    this.counterparty = '',
    this.bank,
    this.balance,
    this.fee,
    this.counterpartyBank,
    this.channel,
    this.minuteOfDay,
  });

  final EntryKind kind;
  final double amount;
  final String currency;
  final DateTime date;
  final EntrySource source;

  /// The original text, kept so the user can see what was parsed.
  final String raw;

  /// Merchant, payee or payer when the message names one. Becomes the note.
  final String counterparty;
  final String? bank;
  final double? balance;

  /// Bank charge named in the alert ("Fee: Rs.15.00"). Already included in
  /// [amount] for money going out, so the entry matches what left the account.
  final double? fee;

  /// The other side's bank, from an IBAN or a bank named next to their
  /// account ("ABC (MBL AC", "PK94SCBL...").
  final String? counterpartyBank;
  final PayChannel? channel;

  /// Time of day in minutes after midnight: the time in the alert, or when
  /// the SMS arrived.
  final int? minuteOfDay;

  /// Same message imported twice gives the same fingerprint.
  String get fingerprint =>
      '${source.name}|${date.toIso8601String().substring(0, 10)}|${kind.name}|${amount.toStringAsFixed(2)}|$currency|${raw.hashCode}';
}
