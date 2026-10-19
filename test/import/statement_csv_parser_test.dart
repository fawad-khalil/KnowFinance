import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/import/statement_csv_parser.dart';
import 'package:know_finance/models/enums.dart';

void main() {
  const parser = StatementCsvParser();

  test('debit and credit columns after preamble rows', () {
    const csv = '''
Account Statement,,,,
Account Title,FAWAD KHALIL,,,
Period,01-Oct-2026 to 19-Oct-2026,,,
Transaction Date,Value Date,Narration,Debit,Credit,Balance
01-Oct-2026,01-Oct-2026,SALARY XORLOGICS,,"250,000.00","300,000.00"
05-Oct-2026,05-Oct-2026,POS IMTIAZ SUPER MARKET,"4,560.00",,"295,440.00"
06/10/2026,06/10/2026,IBFT TO ALI KHAN,"1,500.00",,"293,940.00"
,,Closing balance,,,"293,940.00"
''';
    final t = parser.parse(csv, bank: 'HBL');
    expect(t, hasLength(3));
    expect(t[0].kind, EntryKind.income);
    expect(t[0].amount, 250000);
    expect(t[1].counterparty, 'POS IMTIAZ SUPER MARKET');
    expect(t[1].kind, EntryKind.expense);
    expect(t[2].date, DateTime(2026, 10, 6));
    expect(t.every((x) => x.bank == 'HBL'), isTrue);
  });

  test('single signed amount column', () {
    const csv = 'Date,Description,Amount\n2026-10-02,Netflix,-1100\n2026-10-03,Refund,500\n';
    final t = parser.parse(csv);
    expect(t.map((x) => (x.kind, x.amount)), [(EntryKind.expense, 1100.0), (EntryKind.income, 500.0)]);
  });

  test('amount with Dr/Cr type column', () {
    const csv = 'Txn Date;Particulars;Amount;Dr/Cr\n10-10-26;K-ELECTRIC BILL;"12,340";Dr\n11-10-26;PROFIT;"1,200";Cr\n';
    final t = parser.parse(csv);
    expect(t.first.kind, EntryKind.expense);
    expect(t.first.amount, 12340);
    expect(t.last.kind, EntryKind.income);
  });

  test('rejects files without recognisable columns', () {
    expect(() => parser.parse('a,b\n1,2\n'), throwsFormatException);
  });
}
