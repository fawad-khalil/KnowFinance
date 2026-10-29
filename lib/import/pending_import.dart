import '../models/entry.dart';
import '../models/enums.dart';
import 'parsed_transaction.dart';

enum ImportStatus { pending, accepted, ignored }

/// A parsed transaction stored in the import inbox.
class PendingImport {
  const PendingImport({
    required this.id,
    required this.source,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.date,
    required this.counterparty,
    required this.bank,
    required this.raw,
    required this.status,
    this.counterpartyBank,
    this.channel,
    this.minuteOfDay,
  });

  final int id;
  final EntrySource source;
  final EntryKind kind;
  final double amount;
  final String currency;
  final DateTime date;
  final String counterparty;
  final String? bank;
  final String raw;
  final ImportStatus status;
  final String? counterpartyBank;
  final PayChannel? channel;
  final int? minuteOfDay;

  static Map<String, Object?> toRow(ParsedTransaction t) => {
        'fingerprint': t.fingerprint,
        'source': t.source.name,
        'kind': t.kind.name,
        'amount': t.amount,
        'currency': t.currency,
        'date': dateKey(t.date),
        'counterparty': t.counterparty,
        'bank': t.bank,
        'raw': t.raw,
        'counterparty_bank': t.counterpartyBank,
        'channel': t.channel?.name,
        'minute_of_day': t.minuteOfDay,
      };

  factory PendingImport.fromMap(Map<String, Object?> m) => PendingImport(
        id: m['id'] as int,
        source: EntrySource.fromName(m['source'] as String),
        kind: EntryKind.fromName(m['kind'] as String),
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String,
        date: DateTime.parse(m['date'] as String),
        counterparty: m['counterparty'] as String,
        bank: m['bank'] as String?,
        raw: m['raw'] as String,
        status: ImportStatus.values.byName(m['status'] as String),
        counterpartyBank: m['counterparty_bank'] as String?,
        channel: PayChannel.fromName(m['channel'] as String?),
        minuteOfDay: m['minute_of_day'] as int?,
      );
}
