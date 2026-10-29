import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/models/category.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/services/money_insights.dart';

void main() {
  const cats = {
    1: Category(id: 1, name: 'Salary', kind: EntryKind.income),
    2: Category(id: 2, name: 'Groceries', kind: EntryKind.expense, bucket: Bucket.needs),
    3: Category(id: 3, name: 'Dining out', kind: EntryKind.expense, bucket: Bucket.wants),
    4: Category(id: 4, name: 'Other income', kind: EntryKind.income),
  };
  final end = DateTime(2026, 10, 30);

  Entry e(int cat, double amount, DateTime date,
          {String note = '', String who = '', String? bank, String? theirBank, PayChannel? channel, int? minute, int? loan}) =>
      Entry(
        kind: cats[cat]!.kind,
        amount: amount,
        currency: 'PKR',
        homeCurrency: 'PKR',
        fxRate: 1,
        categoryId: cat,
        date: date,
        note: note,
        counterparty: who,
        bank: bank,
        counterpartyBank: theirBank,
        channel: channel,
        minuteOfDay: minute,
        loanId: loan,
      );

  test('window is the last 30 days ending on the given day', () {
    final m = MoneyInsights([
      e(1, 100, DateTime(2026, 9, 30)),
      e(1, 200, DateTime(2026, 10, 1)),
      e(1, 400, DateTime(2026, 10, 30)),
    ], cats, 'PKR', end: end);
    expect(m.start, DateTime(2026, 10, 1));
    expect(m.income, 600);
  });

  test('top senders group by counterparty, or the note when typed by hand', () {
    final m = MoneyInsights([
      e(1, 250000, DateTime(2026, 10, 1), who: 'XORLOGICS PVT LTD', theirBank: 'Meezan'),
      e(4, 20000, DateTime(2026, 10, 5), note: 'Brother'),
      e(4, 30000, DateTime(2026, 10, 20), note: 'brother '),
    ], cats, 'PKR', end: end);
    final s = m.topSenders();
    expect(s.map((c) => c.name), ['XORLOGICS PVT LTD', 'Brother']);
    expect(s.first.bank, 'Meezan');
    expect(s[1].received, 50000);
    expect(s[1].receivedCount, 2);
  });

  test('spending by type leaves loans out', () {
    final m = MoneyInsights([
      e(2, 30000, DateTime(2026, 10, 3)),
      e(3, 10000, DateTime(2026, 10, 4)),
      e(3, 90000, DateTime(2026, 10, 4), loan: 1),
    ], cats, 'PKR', end: end);
    final t = m.spendingByType();
    expect(t.first.label, 'Groceries');
    expect(t.first.pct, 75);
  });

  test('holding time is how long spending takes to catch up with income', () {
    final m = MoneyInsights([
      e(1, 1000, DateTime(2026, 8, 1)), // too early to count
      e(1, 1000, DateTime(2026, 10, 1)),
      e(2, 400, DateTime(2026, 10, 3)),
      e(2, 600, DateTime(2026, 10, 11)), // October's 1000 is spent after 10 days
      e(1, 500, DateTime(2026, 10, 20)),
      e(2, 500, DateTime(2026, 10, 22)), // this 500 after 2
      e(1, 9000, DateTime(2026, 10, 25)), // not spent yet, so left out
    ], cats, 'PKR', end: end);
    final h = m.holdingTime()!;
    expect(h.avgDays, closeTo((1000 * 10 + 500 * 2) / 1500, 0.001));
    expect(h.withinWeekPct, closeTo(500 / 1500 * 100, 0.001));
  });

  test('no holding time without income to spend from', () {
    expect(MoneyInsights([e(2, 500, DateTime(2026, 10, 5))], cats, 'PKR', end: end).holdingTime(), isNull);
  });

  test('bank dependency and financial home', () {
    final m = MoneyInsights([
      e(1, 300000, DateTime(2026, 10, 1), bank: 'Meezan'),
      e(4, 100000, DateTime(2026, 10, 2), bank: 'HBL'),
      e(2, 500, DateTime(2026, 10, 3), bank: 'HBL'),
      e(2, 500, DateTime(2026, 10, 4), bank: 'HBL'),
      e(2, 500, DateTime(2026, 10, 5)),
    ], cats, 'PKR', end: end);
    final income = m.incomeByBank();
    expect(income.first.label, 'Meezan');
    expect(income.first.pct, 75);
    final home = m.activityByBank();
    expect(home.first.label, 'HBL');
    expect(home.first.count, 3);
    expect(home.first.pct, 60);
  });

  test('money style splits digital from cash and keeps unknown apart', () {
    final m = MoneyInsights([
      e(2, 3000, DateTime(2026, 10, 3), channel: PayChannel.card),
      e(2, 1000, DateTime(2026, 10, 3), channel: PayChannel.raast),
      e(2, 2000, DateTime(2026, 10, 4), channel: PayChannel.atm),
      e(2, 500, DateTime(2026, 10, 5)),
    ], cats, 'PKR', end: end);
    final s = m.moneyStyle();
    expect(s.digital, 4000);
    expect(s.cash, 2000);
    expect(s.unknown, 500);
  });

  test('Raast summary, circle, banks and busy times', () {
    final m = MoneyInsights([
      e(3, 5000, DateTime(2026, 8, 1), who: 'Ali', channel: PayChannel.raast),
      e(3, 2000, DateTime(2026, 10, 5), who: 'Ali', theirBank: 'HBL', channel: PayChannel.raast, minute: 21 * 60 + 5),
      e(4, 1000, DateTime(2026, 10, 6), who: 'ali', theirBank: 'HBL', channel: PayChannel.raast, minute: 21 * 60 + 40),
      e(3, 3000, DateTime(2026, 10, 12), who: 'Sara', theirBank: 'Meezan', channel: PayChannel.raast, minute: 9 * 60),
      e(3, 1500, DateTime(2026, 10, 19), who: 'Sara', theirBank: 'Meezan', channel: PayChannel.raast),
      e(3, 1500, DateTime(2026, 10, 19), who: 'Sara', theirBank: 'Meezan', channel: PayChannel.raast, loan: 2),
      e(3, 800, DateTime(2026, 10, 20), who: 'KFC', channel: PayChannel.card),
    ], cats, 'PKR', end: end);
    final r = m.raast();
    expect(r.sentCount, 4, reason: 'loans moved by Raast count too');
    expect(r.sent, 8000);
    expect(r.received, 1000);
    expect(r.contacts.map((c) => c.name), ['Sara', 'Ali']);
    expect(r.newContacts, {'sara'});
    expect(r.repeatCount, 1);
    expect(r.innerCircle.first.name, 'Ali', reason: 'two-way contacts come first');
    expect(r.circleBanks.map((b) => (b.label, b.total, b.count)), [('Meezan', 6000.0, 1), ('HBL', 3000.0, 1)]);
    // 5, 12 and 19 Oct 2026 are Mondays, 6 Oct a Tuesday.
    expect(r.byWeekday.take(2), [4, 1]);
    expect(r.byHour[21], 2);
    expect(r.timed, 3);
  });
}
