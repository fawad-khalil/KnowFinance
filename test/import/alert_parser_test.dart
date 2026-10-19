import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/import/alert_parser.dart';
import 'package:know_finance/models/enums.dart';

// These messages follow the general shape of Pakistani bank alerts but are
// written for the tests. Replace or extend them with real (masked) alerts.
void main() {
  const parser = AlertParser();
  final received = DateTime(2026, 10, 19, 14, 30);

  ({EntryKind kind, double amount, String currency, DateTime date, String who, String? bank}) p(String text, {String? sender}) {
    final t = parser.parse(text, sender: sender, receivedAt: received)!;
    return (kind: t.kind, amount: t.amount, currency: t.currency, date: t.date, who: t.counterparty, bank: t.bank);
  }

  test('card purchase', () {
    final r = p('Dear Customer, PKR 4,560.00 has been debited from your A/C **1234 for POS purchase at IMTIAZ SUPER MARKET on 18-Oct-26. Avail Bal PKR 120,500.25', sender: 'HBL');
    expect(r.kind, EntryKind.expense);
    expect(r.amount, 4560);
    expect(r.currency, 'PKR');
    expect(r.date, DateTime(2026, 10, 18));
    expect(r.who, 'IMTIAZ SUPER MARKET');
    expect(r.bank, 'HBL');
  });

  test('salary credit with Rs.', () {
    final r = p('Your A/C 0123XXXX5678 has been credited with Rs.250,000 from XORLOGICS PVT LTD on 01/10/2026.', sender: 'MeezanBank');
    expect(r.kind, EntryKind.income);
    expect(r.amount, 250000);
    expect(r.date, DateTime(2026, 10, 1));
    expect(r.who, 'XORLOGICS PVT LTD');
    expect(r.bank, 'Meezan');
  });

  test('wallet transfer sent', () {
    final r = p('Rs 1500 sent to Ali Khan 0300xxxx123 via JazzCash. TID: 123456789. Balance: Rs 3,210', sender: '8558');
    expect(r.kind, EntryKind.expense);
    expect(r.amount, 1500);
    expect(r.who, startsWith('Ali Khan'));
    expect(r.bank, 'JazzCash');
    expect(r.date, DateTime(2026, 10, 19), reason: 'falls back to the received date');
  });

  test('amount after currency-less number', () {
    final r = p('You have received 2,000.50 PKR from Sara in your Easypaisa account.');
    expect(r.kind, EntryKind.income);
    expect(r.amount, 2000.5);
    expect(r.bank, 'Easypaisa');
  });

  test('foreign currency card spend', () {
    final r = p('USD 12.99 charged on your UBL Debit Card at NETFLIX.COM on Oct 15, 2026');
    expect(r.currency, 'USD');
    expect(r.amount, 12.99);
    expect(r.who, 'NETFLIX.COM');
    expect(r.date, DateTime(2026, 10, 15));
    expect(r.bank, 'UBL');
  });

  test('ignores OTPs, reminders and failures', () {
    for (final t in [
      'Your OTP for PKR 5,000 payment is 123456. Do not share it.',
      'PKR 12,000 will be debited on 25-Oct-26 for your loan installment.',
      'Your transaction of PKR 900 at KFC was declined.',
      'Your credit card bill of PKR 30,000 has minimum payment PKR 3,000 due date 28-Oct-26',
      'Welcome to HBL Mobile.',
    ]) {
      expect(parser.parse(t, receivedAt: received), isNull, reason: t);
    }
  });

  test('ignores dates in the future such as card expiry', () {
    final r = p('PKR 800 spent at CAREEM using card expiring 12/2029 on 17/10/2026');
    expect(r.date, DateTime(2026, 10, 17));
  });
}
