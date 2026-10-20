import 'package:shared_preferences/shared_preferences.dart';

import '../data/finance_repository.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import '../services/fx_service.dart';
import 'alert_parser.dart';
import 'import_flags.dart';
import 'pending_import.dart';
import 'sms_reader.dart';
import 'statement_csv_parser.dart';

class ImportResult {
  const ImportResult(this.found, this.added, {this.scanned});

  /// Transactions recognised in the input.
  final int found;

  /// Of those, how many were new (not imported before).
  final int added;

  /// Messages looked at, for SMS scans.
  final int? scanned;
}

/// Brings transactions into the import inbox and turns accepted ones into
/// entries.
class ImportService {
  ImportService(this._repo, this._fx, this._prefs, [this._sms = const SmsReader()]);

  final FinanceRepository _repo;
  final FxService _fx;
  final SharedPreferences _prefs;
  final SmsReader _sms;

  static const _lastSmsScanKey = 'sms_last_scan';
  static const _ownAccountsKey = 'own_account_tails';
  static const _ownNamesKey = 'own_names';

  /// Last four digits of the user's own accounts, learned from alerts that
  /// say "your A/C ..." and from transfers the user marks as their own.
  Set<String> get ownAccounts => (_prefs.getStringList(_ownAccountsKey) ?? const []).toSet();

  /// The user's name as banks print it, for spotting transfers to self.
  Set<String> get ownNames => (_prefs.getStringList(_ownNamesKey) ?? const []).toSet();

  Future<void> setOwnAccounts(Set<String> tails) => _prefs.setStringList(_ownAccountsKey, tails.toList()..sort());

  Future<void> setOwnNames(Set<String> names) => _prefs.setStringList(_ownNamesKey, names.toList()..sort());

  Future<void> _learnOwnAccounts(Iterable<String> raws) async {
    final known = ownAccounts;
    final all = {...known, for (final r in raws) ...ownAccountTails(r)};
    if (all.length != known.length) await setOwnAccounts(all);
  }

  /// Skips an import the user says moved money between their own accounts,
  /// and remembers the other account and name so the next one is flagged.
  Future<void> ignoreAsOwnTransfer(PendingImport p) async {
    await setOwnAccounts({...ownAccounts, ...otherAccountTails(p.raw)});
    if (p.counterparty.trim().isNotEmpty && p.kind == EntryKind.income) {
      // On money coming in the counterparty is the payer, which is you.
      await setOwnNames({...ownNames, p.counterparty.trim()});
    }
    await _repo.ignoreImport(p.id);
  }

  /// How far back the first SMS scan looks.
  static const firstScanWindow = Duration(days: 90);

  DateTime? get lastSmsScan {
    final ms = _prefs.getInt(_lastSmsScanKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<ImportResult> scanSms() async {
    final started = DateTime.now();
    final since = lastSmsScan ?? started.subtract(firstScanWindow);
    final r = await _sms.read(since);
    final added = await _repo.addImports(r.transactions);
    await _learnOwnAccounts(r.transactions.map((t) => t.raw));
    await _prefs.setInt(_lastSmsScanKey, started.millisecondsSinceEpoch);
    return ImportResult(r.transactions.length, added, scanned: r.scanned);
  }

  /// Pasted SMS or email text. Several messages can be pasted at once,
  /// separated by blank lines.
  Future<ImportResult> importText(String text, {EntrySource source = EntrySource.email}) async {
    const parser = AlertParser();
    final now = DateTime.now();
    final blocks = text.split(RegExp(r'\n\s*\n')).map((b) => b.trim()).where((b) => b.isNotEmpty);
    final parsed = [
      for (final b in blocks) ?parser.parse(b, receivedAt: now, source: source),
    ];
    // One long email often has no blank lines; try it whole as well.
    if (parsed.isEmpty) {
      final whole = parser.parse(text, receivedAt: now, source: source);
      if (whole != null) parsed.add(whole);
    }
    await _learnOwnAccounts(parsed.map((t) => t.raw));
    return ImportResult(parsed.length, await _repo.addImports(parsed));
  }

  Future<ImportResult> importStatementCsv(String content, {String? fileName}) async {
    final bank = AlertParser.bankFor(fileName, '');
    final parsed = const StatementCsvParser().parse(content, bank: bank);
    return ImportResult(parsed.length, await _repo.addImports(parsed));
  }

  Future<void> accept(PendingImport p, {required int categoryId, required EntryKind kind, required String note, required String homeCurrency}) async {
    final rate = await _fx.rate(p.currency, homeCurrency, p.date);
    await _repo.acceptImport(
      p.id,
      Entry(
        kind: kind,
        amount: p.amount,
        currency: p.currency,
        homeCurrency: homeCurrency,
        fxRate: rate,
        categoryId: categoryId,
        date: p.date,
        note: note,
        source: p.source,
      ),
    );
  }

  Future<void> ignore(PendingImport p) => _repo.ignoreImport(p.id);
}
