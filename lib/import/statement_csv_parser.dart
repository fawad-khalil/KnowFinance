import 'package:csv/csv.dart';

import '../models/enums.dart';
import 'parsed_transaction.dart';

/// Reads bank statements exported as CSV (or Excel saved as CSV).
///
/// Pakistani banks lay statements out differently, so the header row is
/// found by its column names: a date, a description (narration, particulars,
/// details...), and either separate debit/credit columns or one amount
/// column with a sign or a Dr/Cr marker.
class StatementCsvParser {
  const StatementCsvParser();

  static const _dateHeads = ['transaction date', 'txn date', 'tran date', 'posting date', 'booking date', 'date', 'value date'];
  static const _descHeads = ['description', 'narration', 'particulars', 'details', 'transaction details', 'remarks', 'transaction', 'memo'];
  static const _debitHeads = ['debit', 'withdrawal', 'withdrawals', 'dr', 'debit amount', 'money out', 'paid out'];
  static const _creditHeads = ['credit', 'deposit', 'deposits', 'cr', 'credit amount', 'money in', 'paid in'];
  static const _amountHeads = ['amount', 'transaction amount', 'amount (pkr)', 'amount(pkr)'];
  static const _typeHeads = ['type', 'dr/cr', 'cr/dr', 'debit/credit'];

  /// Throws [FormatException] when no header row can be recognised.
  List<ParsedTransaction> parse(String content, {String currency = 'PKR', String? bank}) {
    final rows = csv.decode(content.replaceFirst('﻿', ''));
    final cells = [for (final r in rows) [for (final c in r) '${c ?? ''}'.trim()]];

    for (var h = 0; h < cells.length && h < 40; h++) {
      final head = [for (final c in cells[h]) c.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')];
      int? find(List<String> names) {
        for (final n in names) {
          final i = head.indexOf(n);
          if (i >= 0) return i;
        }
        for (final n in names) {
          final i = head.indexWhere((c) => c.startsWith(n));
          if (i >= 0) return i;
        }
        return null;
      }

      final date = find(_dateHeads);
      final desc = find(_descHeads);
      final debit = find(_debitHeads);
      final credit = find(_creditHeads);
      final amount = find(_amountHeads);
      final type = find(_typeHeads);
      if (date == null || desc == null || ((debit == null || credit == null) && amount == null)) continue;

      final out = <ParsedTransaction>[];
      for (final row in cells.skip(h + 1)) {
        String at(int? i) => i != null && i < row.length ? row[i] : '';
        final d = parseDate(at(date));
        if (d == null) continue;
        EntryKind kind;
        double value;
        final dr = _number(at(debit));
        final cr = _number(at(credit));
        if (debit != null && credit != null && (dr != null || cr != null) && ((dr ?? 0) != 0 || (cr ?? 0) != 0)) {
          kind = (dr ?? 0) != 0 ? EntryKind.expense : EntryKind.income;
          value = ((dr ?? 0) != 0 ? dr! : cr!).abs();
        } else {
          final a = _number(at(amount));
          if (a == null || a == 0) continue;
          final marker = at(type).toLowerCase();
          final rawAmount = at(amount).toLowerCase();
          final isDebit = marker.startsWith('d') || rawAmount.endsWith('dr') || a < 0;
          kind = isDebit ? EntryKind.expense : EntryKind.income;
          value = a.abs();
        }
        final description = at(desc).replaceAll(RegExp(r'\s+'), ' ');
        out.add(ParsedTransaction(
          kind: kind,
          amount: value,
          currency: currency,
          date: d,
          source: EntrySource.statement,
          raw: row.join(' | '),
          counterparty: description.length > 60 ? description.substring(0, 60) : description,
          bank: bank,
        ));
      }
      return out;
    }
    throw const FormatException('Could not find the date, description and amount columns.');
  }

  static double? _number(String s) {
    var t = s.replaceAll(RegExp(r'(PKR|Rs\.?|,|\s)', caseSensitive: false), '');
    var negative = false;
    if (t.startsWith('(') && t.endsWith(')')) {
      negative = true;
      t = t.substring(1, t.length - 1);
    }
    t = t.replaceAll(RegExp(r'(dr|cr)$', caseSensitive: false), '');
    if (t.isEmpty || t == '-') return null;
    final v = double.tryParse(t);
    return v == null ? null : (negative ? -v : v);
  }

  static const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

  /// Day-first dates as Pakistani banks print them, plus ISO.
  static DateTime? parseDate(String s) {
    final t = s.trim();
    Match? m;
    int year(String y) => y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
    if ((m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t)) != null) {
      return DateTime(int.parse(m![1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    if ((m = RegExp(r'^(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2,4})').firstMatch(t)) != null) {
      final mo = int.parse(m![2]!);
      if (mo < 1 || mo > 12) return null;
      return DateTime(year(m[3]!), mo, int.parse(m[1]!));
    }
    if ((m = RegExp(r'^(\d{1,2})[\s\-/]([A-Za-z]{3})[A-Za-z]*[\s\-/,]+(\d{2,4})').firstMatch(t)) != null) {
      final mo = _months.indexOf(m![2]!.toLowerCase()) + 1;
      if (mo == 0) return null;
      return DateTime(year(m[3]!), mo, int.parse(m[1]!));
    }
    return null;
  }
}
