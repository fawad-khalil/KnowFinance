import '../models/entry.dart';
import '../models/enums.dart';
import 'pending_import.dart';

enum FlagKind { duplicate, ownTransfer }

/// Why an import probably shouldn't be added as it is.
class ImportFlag {
  const ImportFlag(this.kind, this.reason);

  final FlagKind kind;
  final String reason;
}

/// Account numbers in alerts are masked ("xxx6373", "01-72****48-01"), so
/// accounts are compared by their last four digits.
String? accountTail(String token) {
  final digits = token.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3) return null;
  return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
}

final _accountRef = RegExp(
  r'\b(your\s+(?:[A-Za-z]+\s+)?)?(?:a/?c|ac|account)(?:\s*(?:#|no\.?|number))?\s*:?\s*([0-9xX\*][0-9xX\*\-]{2,})',
  caseSensitive: false,
);

/// Tails of the user's own accounts named in an alert ("from your A/C
/// xxx6373", "your account 01-72****48-01").
Set<String> ownAccountTails(String raw) => {
      for (final m in _accountRef.allMatches(raw))
        if (m[1] != null) ?accountTail(m[2]!),
    };

/// Tails of the other side's account ("sent SCB PK A/C ******4801").
Set<String> otherAccountTails(String raw) => {
      for (final m in _accountRef.allMatches(raw))
        if (m[1] == null) ?accountTail(m[2]!),
    };

/// Same money within a bank fee or rounding: 0.5%, at least 1.
bool closeAmounts(double a, double b) {
  final big = a > b ? a : b;
  return (a - b).abs() <= (big * 0.005 < 1 ? 1 : big * 0.005);
}

bool _near(DateTime a, DateTime b, int days) => a.difference(b).inDays.abs() <= days;

String normalizeName(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Flags imports that look like a transfer between the user's own accounts
/// or a second alert for something already in the inbox or the entries.
///
/// [ownAccounts] are known account tails and [ownNames] the user's name as
/// banks print it; both grow as the user marks transfers as their own.
Map<int, List<ImportFlag>> flagImports(
  List<PendingImport> pending, {
  List<Entry> entries = const [],
  Set<String> ownAccounts = const {},
  Set<String> ownNames = const {},
  String Function(PendingImport)? describe,
}) {
  String label(PendingImport p) => describe?.call(p) ?? '${p.amount} on ${dateKey(p.date)}';
  final own = {...ownAccounts, for (final p in pending) ...ownAccountTails(p.raw)};
  final names = {for (final n in ownNames) normalizeName(n)}..remove('');
  final out = <int, List<ImportFlag>>{};
  void add(PendingImport p, ImportFlag f) => (out[p.id] ??= []).add(f);

  // Oldest first, so the later of two alerts is the one called a duplicate.
  final sorted = [...pending]..sort((a, b) => a.id.compareTo(b.id));
  for (var i = 0; i < sorted.length; i++) {
    final p = sorted[i];

    final matched = otherAccountTails(p.raw).intersection(own);
    if (matched.isNotEmpty) {
      add(p, ImportFlag(FlagKind.ownTransfer,
          '${p.kind == EntryKind.expense ? 'Sent to' : 'Received from'} your own account ending ${matched.first}.'));
    } else if (names.contains(normalizeName(p.counterparty))) {
      add(p, ImportFlag(FlagKind.ownTransfer, '${p.counterparty} is you, so this is probably between your own accounts.'));
    } else {
      final pair = sorted.where((q) =>
          q.id != p.id && q.kind != p.kind && q.currency == p.currency && closeAmounts(q.amount, p.amount) && _near(q.date, p.date, 2));
      if (pair.isNotEmpty) {
        add(p, ImportFlag(FlagKind.ownTransfer,
            'The same amount ${p.kind == EntryKind.expense ? 'came in' : 'went out'} too (${label(pair.first)}). '
            'Probably a transfer between your own accounts.'));
      }
    }

    final earlier = sorted.take(i).where((q) =>
        q.kind == p.kind && q.currency == p.currency && closeAmounts(q.amount, p.amount) && _near(q.date, p.date, 1));
    if (earlier.isNotEmpty) {
      add(p, ImportFlag(FlagKind.duplicate, 'Looks like a second alert for ${label(earlier.first)}.'));
      continue;
    }
    final entry = entries.where((e) =>
        e.kind == p.kind && e.currency == p.currency && closeAmounts(e.amount, p.amount) && _near(e.date, p.date, 1));
    if (entry.isNotEmpty) {
      final e = entry.first;
      add(p, ImportFlag(FlagKind.duplicate,
          'Already in your entries: ${e.note.isEmpty ? 'an entry' : '"${e.note}"'} on ${dateKey(e.date)}.'));
    }
  }
  return out;
}
