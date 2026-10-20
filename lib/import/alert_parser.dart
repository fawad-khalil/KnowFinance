import '../models/enums.dart';
import 'parsed_transaction.dart';

/// Reads bank and wallet alerts (SMS or email text) from Pakistani banks.
///
/// Banks word their alerts differently and change them often, so rather
/// than one template per bank this looks for the parts every alert has:
/// an amount with a currency, a direction word (debited, credited, sent,
/// received...), and optionally a merchant, date and balance. Bank-specific
/// tweaks live in [_bankHints].
class AlertParser {
  const AlertParser();

  /// Known sender IDs and the names banks sign their alerts with.
  static const _bankHints = <String, List<String>>{
    'HBL': ['HBL', 'HABIB BANK'],
    'MCB': ['MCB'],
    'UBL': ['UBL', 'UNITED BANK'],
    'Meezan': ['MEEZAN', 'MBL'],
    'Allied': ['ABL', 'ALLIED'],
    'Bank Alfalah': ['ALFALAH', 'BAFL'],
    'Bank Al Habib': ['BAHL', 'AL HABIB', 'BANKALHABIB'],
    'Faysal': ['FAYSAL', 'FBL'],
    'Standard Chartered': ['SCB', 'STANCHART', 'STANDARD CHARTERED'],
    'Askari': ['ASKARI', 'AKBL'],
    'JS Bank': ['JSBANK', 'JS BANK'],
    'NBP': ['NBP', 'NATIONAL BANK'],
    'JazzCash': ['JAZZCASH', 'JAZZ CASH'],
    'Easypaisa': ['EASYPAISA', 'TELENOR MICROFINANCE'],
    'SadaPay': ['SADAPAY'],
    'NayaPay': ['NAYAPAY'],
  };

  static const _currencyWords = {
    'PKR': 'PKR',
    'RS': 'PKR',
    'RUPEES': 'PKR',
    'USD': 'USD',
    r'$': 'USD',
    'EUR': 'EUR',
    'GBP': 'GBP',
    'AED': 'AED',
    'SAR': 'SAR',
  };

  static final _amount = RegExp(
    r'(PKR|Rs\.?|Rupees|USD|EUR|GBP|AED|SAR|\$)\s*:?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)'
    r'|([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(PKR|Rs\.?|USD|EUR|GBP|AED|SAR)\b',
    caseSensitive: false,
  );

  static final _expenseWords = RegExp(
    r'\b(debited|debit|withdrawn|withdrawal|spent|paid|payment of|purchase|purchased|sent|transferred to|'
    r'transfer to|deducted|charged|bill payment|pos|atm cash|cash withdrawal|used for|dr\b)',
    caseSensitive: false,
  );

  static final _incomeWords = RegExp(
    r'\b(credited|credit|received|deposited|deposit|refund|refunded|reversed|transferred from|cr\b|'
    r'has been added|added to your)',
    caseSensitive: false,
  );

  static final _skipWords = RegExp(
    r'\b(otp|one time password|verification code|do not share|login|pin|due date|minimum payment|'
    r'will be debited|failed|declined|unsuccessful|offer|win|cashback offer)\b',
    caseSensitive: false,
  );

  static final _balance = RegExp(
    r'(?:avail(?:able)?\.?\s*)?(?:bal(?:ance)?|bal\.)\s*(?:is|:)?\s*(?:PKR|Rs\.?)?\s*:?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final _counterparty = RegExp(
    r'\b(?:at|to|from|towards|for|@)\s+([A-Za-z0-9][A-Za-z0-9&\-\._\* ]{1,40}?)'
    r'(?=\s+(?:on|via|ref|from|to|at|dated|with|for|using|thru|through|txn|tid|avail|bal|is|has|was|as|a/?c|ac#?)\b'
    r'|\s*\(|[\.,;](?:\s|$)|$)',
    caseSensitive: false,
  );

  /// "from account 00-05xxxxx-3242 FAWAD KHALIL from IBFT": the payer's name
  /// comes after their account number.
  static final _nameAfterAccount = RegExp(
    r'\bfrom\s+(?:account|a/?c|ac)\s*#?\s*[0-9xX\*\-]{4,}\s+([A-Z][A-Za-z\.]*(?:\s+[A-Z][A-Za-z\.]*){0,4}?)'
    r'(?=\s+(?:from|on|via|through|thru)\b|[\.,;]|$)',
  );

  /// "PKR 100,000.00 sent SCB PK A/C ******4801": the receiving bank or
  /// person comes straight after "sent", before their account number.
  static final _sentToAccount = RegExp(
    r'\bsent\s+(?!to\b|from\b)([A-Za-z][A-Za-z0-9&\-\. ]{1,30}?)\s+(?:a/?c|ac|account)\b',
    caseSensitive: false,
  );

  static final _fee = RegExp(
    r'\b(?:fee|charges?)\s*:?\s*(?:PKR|Rs\.?)\s*:?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final _dates = <(RegExp, DateTime? Function(Match))>[
    // 19-Oct-26, 19-Oct-2026, 19 Oct 2026, 19/Oct/26
    (
      RegExp(r'\b(\d{1,2})[\s\-/]([A-Za-z]{3})[A-Za-z]*[\s\-/,]+(\d{2,4})\b'),
      (m) => _mk(m[3]!, _month(m[2]!), m[1]!),
    ),
    // 2026-10-19
    (RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), (m) => _mk(m[1]!, int.parse(m[2]!), m[3]!)),
    // 19/10/2026, 19-10-26, 19.10.2026 (day first, as used in Pakistan)
    (RegExp(r'\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2,4})\b'), (m) => _mk(m[3]!, int.parse(m[2]!), m[1]!)),
    // Oct 19, 2026
    (RegExp(r'\b([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b'), (m) => _mk(m[3]!, _month(m[1]!), m[2]!)),
  ];

  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  static int _month(String s) => _months.indexOf(s.toLowerCase().substring(0, 3)) + 1;

  static DateTime? _mk(String y, int month, String d) {
    if (month < 1 || month > 12) return null;
    var year = int.parse(y);
    if (year < 100) year += 2000;
    final day = int.parse(d);
    if (day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  /// Returns null when the text isn't a completed transaction (OTPs, offers,
  /// reminders, failed payments) or has no amount.
  ParsedTransaction? parse(
    String text, {
    String? sender,
    required DateTime receivedAt,
    EntrySource source = EntrySource.sms,
  }) {
    final body = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (body.isEmpty || _skipWords.hasMatch(body)) return null;

    final amountMatch = _amount.firstMatch(body);
    if (amountMatch == null) return null;
    final rawAmount = amountMatch[2] ?? amountMatch[3]!;
    final currencyWord = (amountMatch[1] ?? amountMatch[4]!).toUpperCase();
    final amount = double.tryParse(rawAmount.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    final kind = _direction(body, amountMatch.start);
    if (kind == null) return null;

    final balanceMatch = _balance.firstMatch(body.substring(amountMatch.end));
    final balance = balanceMatch == null ? null : double.tryParse(balanceMatch[1]!.replaceAll(',', ''));

    final feeMatch = _fee.firstMatch(body.substring(amountMatch.end));
    final fee = feeMatch == null ? null : double.tryParse(feeMatch[1]!.replaceAll(',', ''));

    return ParsedTransaction(
      kind: kind,
      amount: kind == EntryKind.expense && fee != null ? amount + fee : amount,
      fee: fee,
      currency: _currencyWords[currencyWord.replaceAll('.', '')] ?? 'PKR',
      date: _date(body, receivedAt),
      source: source,
      raw: text.trim(),
      counterparty: _merchant(body, kind),
      bank: bankFor(sender, body),
      balance: balance,
    );
  }

  /// Picks the direction word nearest to the amount, so "PKR 500 sent to
  /// Ali. Balance credited..." still reads as an expense.
  static EntryKind? _direction(String body, int amountAt) {
    int? nearest(RegExp re) {
      int? best;
      for (final m in re.allMatches(body)) {
        final d = (m.start - amountAt).abs();
        if (best == null || d < best) best = d;
      }
      return best;
    }

    final e = nearest(_expenseWords);
    final i = nearest(_incomeWords);
    if (e == null && i == null) return null;
    if (i == null) return EntryKind.expense;
    if (e == null) return EntryKind.income;
    return e <= i ? EntryKind.expense : EntryKind.income;
  }

  static DateTime _date(String body, DateTime fallback) {
    for (final (re, build) in _dates) {
      for (final m in re.allMatches(body)) {
        final d = build(m);
        // Ignore matches that are clearly not the transaction date, like
        // card expiry or reference numbers.
        if (d != null && d.isAfter(DateTime(2000)) && !d.isAfter(fallback.add(const Duration(days: 1)))) {
          return d;
        }
      }
    }
    return DateTime(fallback.year, fallback.month, fallback.day);
  }

  static String _merchant(String body, EntryKind kind) {
    final special = kind == EntryKind.income ? _nameAfterAccount.firstMatch(body) : _sentToAccount.firstMatch(body);
    if (special != null) return _tidy(special[1]!);
    final candidates = _counterparty.allMatches(body).map((m) => m[1]!.trim()).where((c) {
      final l = c.toLowerCase();
      return !RegExp(r'^(your|a/?c|acc|account|card|the|pkr|rs|\d)').hasMatch(l) && c.length > 1;
    }).toList();
    if (candidates.isEmpty) return '';
    // "from" names the payer on income, "to/at" the payee on expenses.
    final preferred = kind == EntryKind.income ? RegExp(r'\bfrom\s', caseSensitive: false) : RegExp(r'\b(at|to)\s', caseSensitive: false);
    for (final m in _counterparty.allMatches(body)) {
      if (preferred.hasMatch(m[0]!) && candidates.contains(m[1]!.trim())) return _tidy(m[1]!);
    }
    return _tidy(candidates.first);
  }

  static String _tidy(String s) => s.trim().replaceAll(RegExp(r'[\*_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');

  /// Sender IDs are matched loosely ("MeezanBank", "HBL-ALERT"); the body
  /// only on whole words so "UBL" doesn't match inside other words.
  static String? bankFor(String? sender, String body) {
    final from = (sender ?? '').toUpperCase().replaceAll(RegExp('[^A-Z]'), '');
    final text = body.toUpperCase();
    for (final entry in _bankHints.entries) {
      for (final hint in entry.value) {
        if (from.isNotEmpty && from.contains(hint.replaceAll(' ', ''))) return entry.key;
      }
    }
    for (final entry in _bankHints.entries) {
      for (final hint in entry.value) {
        if (RegExp('(^|[^A-Z])${RegExp.escape(hint)}([^A-Z]|\$)').hasMatch(text)) return entry.key;
      }
    }
    return null;
  }
}
