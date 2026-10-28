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

  group('real alerts (masked)', () {
    final received = DateTime(2026, 10, 20, 9);
    ({EntryKind kind, double amount, DateTime date, String who}) r(String text) {
      final t = parser.parse(text, receivedAt: received)!;
      return (kind: t.kind, amount: t.amount, date: t.date, who: t.counterparty);
    }

    test('RAAST payment received', () {
      final x = r('PKR 25,000.00 received from ABC AC#xxxPYMT PK94SCBL888777 as RAAST payment to your AC# 986987 '
          'of XYZ BR LHR on 19-Oct-2026 at 18:11');
      expect(x.kind, EntryKind.income);
      expect(x.amount, 25000);
      expect(x.date, DateTime(2026, 10, 19));
      expect(x.who, 'ABC');
    });

    test('transfer sent with lakh grouping and a fee', () {
      final t = parser.parse(
          'PKR 4,23,434.00 sent to ABC JAXX-xxCASH from your A/C xxx6373 on 18-Oct-2026 at 19:22 Fee: Rs.15.00 '
          'TID:87987987 UAN 02132232333',
          receivedAt: received)!;
      expect(t.kind, EntryKind.expense);
      // The fee left the account too, so it is part of the expense.
      expect(t.amount, 423449);
      expect(t.fee, 15);
      expect(t.date, DateTime(2026, 10, 18));
      expect(t.counterparty, 'ABC JAXX-xxCASH');
    });

    test('internet purchase with a misspelt verb', () {
      final x = r('PKR 4,433.00 charded at Google as internet purchase, from A/C xxx1212 (XYZ BR LHR) on 19-Oct-2026 '
          'at 01:19 TID:897983');
      expect(x.kind, EntryKind.expense);
      expect(x.amount, 4433);
      expect(x.who, 'Google');
      expect(x.date, DateTime(2026, 10, 19));
    });

    test('unclosed bracket after the payee', () {
      final x = r('PKR 4,23,434.00 sent to ABC (MBL AC from your A/C xxx6373 on 18-Oct-2026 at 19:22 TID:87987987 '
          'UAN 02132232333');
      expect(x.kind, EntryKind.expense);
      expect(x.amount, 423434);
      expect(x.who, 'ABC');
    });

    test('debit card payment with numeric date', () {
      final x = r('Dear Client, PKR 3,645.00 have been paid at MAJNOON on 17-10-26 using Debit Card no. 326XXXXXXX3479.');
      expect(x.kind, EntryKind.expense);
      expect(x.amount, 3645);
      expect(x.who, 'MAJNOON');
      expect(x.date, DateTime(2026, 10, 17));
    });

    test('IBFT credit names the sender after the account number', () {
      final x = r('Dear Client, your account 01-72****48-01 has been credit with amount PKR 48,000.00 from account '
          '00-05xxxxx-32423423432 FAWAD KHALIL from IBFT 18/10/222 on 18/10/26.');
      expect(x.kind, EntryKind.income);
      expect(x.amount, 48000);
      expect(x.who, 'FAWAD KHALIL');
      expect(x.date, DateTime(2026, 10, 18));
    });

    test('RAAST funds transfer sent to an account', () {
      final x = r('Dear Customer, PKR 100,000.00 sent SCB PK A/C ******4801 from FUNDS TRANSFER on 10-Oct-26 11:36 '
          'via RAAST for TX ID MBMB1214123131231');
      expect(x.kind, EntryKind.expense);
      expect(x.amount, 100000);
      expect(x.who, 'SCB PK');
      expect(x.date, DateTime(2026, 10, 10));
    });
  });

  group('channel, other bank and time', () {
    final received = DateTime(2026, 10, 20, 9, 5);

    test('RAAST received names the sender bank from the IBAN', () {
      final t = parser.parse(
          'PKR 25,000.00 received from ABC AC#xxxPYMT PK94SCBL888777 as RAAST payment to your AC# 986987 '
          'of XYZ BR LHR on 19-Oct-2026 at 18:11',
          receivedAt: received)!;
      expect(t.channel, PayChannel.raast);
      expect(t.counterpartyBank, 'Standard Chartered');
      expect(t.bank, isNull, reason: "the sender's IBAN isn't the user's bank");
      expect(t.minuteOfDay, 18 * 60 + 11);
    });

    test('bank named next to the payee is theirs, not the user\'s', () {
      final t = parser.parse(
          'PKR 4,23,434.00 sent to ABC (MBL AC from your A/C xxx6373 on 18-Oct-2026 at 19:22 TID:87987987',
          receivedAt: received)!;
      expect(t.counterpartyBank, 'Meezan');
      expect(t.bank, isNull);
      expect(t.channel, PayChannel.transfer);
      expect(t.minuteOfDay, 19 * 60 + 22);
    });

    test('RAAST sent to a bank account', () {
      final t = parser.parse(
          'Dear Customer, PKR 100,000.00 sent SCB PK A/C ******4801 from FUNDS TRANSFER on 10-Oct-26 11:36 '
          'via RAAST for TX ID MBMB1214123131231',
          sender: 'MCB',
          receivedAt: received)!;
      expect(t.channel, PayChannel.raast);
      expect(t.counterpartyBank, 'Standard Chartered');
      expect(t.bank, 'MCB');
      expect(t.minuteOfDay, 11 * 60 + 36);
    });

    test('card, ATM and wallet', () {
      PayChannel? c(String text, {String? sender}) => parser.parse(text, sender: sender, receivedAt: received)!.channel;
      expect(c('Dear Client, PKR 3,645.00 have been paid at MAJNOON on 17-10-26 using Debit Card no. 326XXXXXXX3479.'),
          PayChannel.card);
      expect(c('PKR 20,000 withdrawn from ATM at DHA Phase 5 on 18-Oct-26', sender: 'HBL'), PayChannel.atm);
      expect(c('Rs 1500 sent to Ali Khan 0300xxxx123 via JazzCash. TID: 123456789.', sender: '8558'), PayChannel.wallet);
    });

    test('12-hour times', () {
      final t = parser.parse('PKR 800 spent at CAREEM on 17/10/2026 at 7:05 PM', receivedAt: received)!;
      expect(t.minuteOfDay, 19 * 60 + 5);
    });

    test('time from when the SMS arrived only when asked', () {
      const text = 'PKR 800 spent at CAREEM on 17/10/2026';
      expect(parser.parse(text, receivedAt: received)!.minuteOfDay, isNull);
      expect(parser.parse(text, receivedAt: received, useReceivedTime: true)!.minuteOfDay, 9 * 60 + 5);
    });
  });
}
