import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/import/alert_parser.dart';
import 'package:know_finance/import/import_flags.dart';
import 'package:know_finance/import/pending_import.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';

void main() {
  const samples = [
    'PKR 25,000.00 received from ABC AC#xxxPYMT PK94SCBL888777 as RAAST payment to your AC# 986987 of XYZ BR LHR on 19-Oct-2026 at 18:11',
    'PKR 4,23,434.00 sent to ABC JAXX-xxCASH from your A/C xxx6373 on 18-Oct-2026 at 19:22 Fee: Rs.15.00 TID:87987987 UAN 02132232333',
    'PKR 4,433.00 charded at Google as internet purchase, from A/C xxx1212 (XYZ BR LHR) on 19-Oct-2026 at 01:19 TID:897983',
    'PKR 4,23,434.00 sent to ABC (MBL AC from your A/C xxx6373 on 18-Oct-2026 at 19:22 TID:87987987 UAN 02132232333',
    'Dear Client, PKR 3,645.00 have been paid at MAJNOON on 17-10-26 using Debit Card no. 326XXXXXXX3479.',
    'Dear Client, your account 01-72****48-01 has been credit with amount PKR 48,000.00 from account 00-05xxxxx-32423423432 FAWAD KHALIL from IBFT 18/10/222 on 18/10/26.',
    'Dear Customer, PKR 100,000.00 sent SCB PK A/C ******4801 from FUNDS TRANSFER on 10-Oct-26 11:36 via RAAST for TX ID MBMB1214123131231',
  ];

  List<PendingImport> pending() {
    var id = 0;
    return [
      for (final s in samples)
        () {
          final t = const AlertParser().parse(s, receivedAt: DateTime(2026, 10, 20))!;
          return PendingImport(
            id: ++id,
            source: t.source,
            kind: t.kind,
            amount: t.amount,
            currency: t.currency,
            date: t.date,
            counterparty: t.counterparty,
            bank: t.bank,
            raw: t.raw,
            status: ImportStatus.pending,
          );
        }(),
    ];
  }

  test('reads own and other account tails', () {
    expect(ownAccountTails(samples[1]), {'6373'});
    expect(ownAccountTails(samples[5]), {'4801'});
    expect(otherAccountTails(samples[5]), {'3432'});
    expect(otherAccountTails(samples[6]), {'4801'});
    expect(ownAccountTails(samples[0]), {'6987'});
  });

  test('flags the second alert for the same transfer, within the fee', () {
    final flags = flagImports(pending());
    expect(flags[4]!.single.kind, FlagKind.duplicate);
    expect(flags.containsKey(2), isFalse, reason: 'the first alert is the one to keep');
  });

  test('flags money sent to an account named elsewhere as yours', () {
    final flags = flagImports(pending());
    expect(flags[7]!.single.kind, FlagKind.ownTransfer);
    expect(flags[7]!.single.reason, contains('4801'));
  });

  test('flags money from your own name once it is known', () {
    expect(flagImports(pending()).containsKey(6), isFalse);
    final flags = flagImports(pending(), ownNames: {'Fawad Khalil'});
    expect(flags[6]!.single.kind, FlagKind.ownTransfer);
  });

  test('ordinary spending is not flagged', () {
    final flags = flagImports(pending());
    expect(flags.containsKey(3), isFalse);
    expect(flags.containsKey(5), isFalse);
    expect(flags.containsKey(1), isFalse);
  });

  test('pairs money out with the same money in as a transfer', () {
    PendingImport p(int id, EntryKind k) => PendingImport(
        id: id, source: EntrySource.sms, kind: k, amount: 50000, currency: 'PKR', date: DateTime(2026, 10, 18),
        counterparty: '', bank: null, raw: '', status: ImportStatus.pending);
    final flags = flagImports([p(1, EntryKind.expense), p(2, EntryKind.income)]);
    expect(flags[1]!.single.kind, FlagKind.ownTransfer);
    expect(flags[2]!.single.kind, FlagKind.ownTransfer);
  });

  test('matches an entry already added by hand', () {
    final flags = flagImports(pending(), entries: [
      Entry(kind: EntryKind.expense, amount: 3645, currency: 'PKR', homeCurrency: 'PKR', fxRate: 1, categoryId: 1,
          date: DateTime(2026, 10, 17), note: 'Majnoon'),
    ]);
    expect(flags[5]!.single.kind, FlagKind.duplicate);
    expect(flags[5]!.single.reason, contains('Majnoon'));
  });
}
