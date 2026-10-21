import 'dart:math';

import '../import/alert_parser.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import '../models/investment.dart';
import '../models/loan.dart';
import 'finance_repository.dart';

/// Sample bank alerts for the import inbox (masked, as received).
const sampleAlerts = [
  'PKR 25,000.00 received from ABC AC#xxxPYMT PK94SCBL888777 as RAAST payment to your AC# 986987 of XYZ BR LHR on {d1} at 18:11',
  'PKR 4,23,434.00 sent to ABC JAXX-xxCASH from your A/C xxx6373 on {d2} at 19:22 Fee: Rs.15.00 TID:87987987 UAN 02132232333',
  'PKR 4,433.00 charded at Google as internet purchase, from A/C xxx1212 (XYZ BR LHR) on {d1} at 01:19 TID:897983',
  'PKR 4,23,434.00 sent to ABC (MBL AC from your A/C xxx6373 on {d2} at 19:22 TID:87987987 UAN 02132232333',
  'Dear Client, PKR 3,645.00 have been paid at MAJNOON on {d3} using Debit Card no. 326XXXXXXX3479.',
];

/// Fills the database with about 18 months of realistic data ending today:
/// salary and side income, Needs/Wants/Savings spending with daily small
/// purchases, investments and priced assets, loans each way, and a few
/// alerts waiting in the import inbox. Used by the debug "Reset to sample
/// data" setting and the screenshot tests.
Future<void> seedSampleData(FinanceRepository repo, {DateTime? now, bool withImports = true}) async {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final rnd = Random(42);
  final cats = {for (final c in await repo.categories()) c.name: c.id!};

  DateTime monthsAgo(int m, int day) {
    final first = DateTime(today.year, today.month - m);
    final last = DateTime(first.year, first.month + 1, 0).day;
    final d = DateTime(first.year, first.month, day.clamp(1, last));
    return d.isAfter(today) ? today : d;
  }

  double vary(double base, double spread) => (base * (1 + (rnd.nextDouble() * 2 - 1) * spread)).roundToDouble();

  Future<void> add(String cat, double amt, DateTime d, String note, EntryKind k,
      {int? inv, InvestmentFlow? flow, double? qty, int? loan}) async {
    if (d.isAfter(today)) return;
    await repo.saveEntry(Entry(
      kind: k,
      amount: amt,
      currency: 'PKR',
      homeCurrency: 'PKR',
      fxRate: 1,
      categoryId: loan != null ? await repo.loanCategoryId(k) : cats[cat]!,
      date: d,
      note: note,
      investmentId: inv,
      investmentFlow: flow,
      quantity: qty,
      loanId: loan,
    ));
  }

  const months = 18;

  // Everyday income and spending, month by month up to today.
  for (var m = months - 1; m >= 0; m--) {
    final raise = m < 6 ? 1.08 : 1.0;
    await add('Salary', 250000 * raise, monthsAgo(m, 1), 'Xorlogics', EntryKind.income);
    if (m % 2 == 0) await add('Freelance', vary(65000, 0.3), monthsAgo(m, 15), 'Upwork', EntryKind.income);
    if (m % 5 == 2) await add('Remittance', 50000, monthsAgo(m, 18), 'Brother (UAE)', EntryKind.income);
    await add('Rent', 70000, monthsAgo(m, 2), 'House rent', EntryKind.expense);
    await add('Utilities', vary(m % 12 < 4 ? 26000 : 17000, 0.15), monthsAgo(m, 10), 'K-Electric', EntryKind.expense);
    await add('Utilities', vary(4500, 0.2), monthsAgo(m, 11), 'SSGC gas', EntryKind.expense);
    await add('Mobile & internet', 4999, monthsAgo(m, 4), 'PTCL Flash fiber', EntryKind.expense);
    await add('Education', 18000, monthsAgo(m, 8), 'School fee', EntryKind.expense);
    await add('Groceries', vary(28000, 0.15), monthsAgo(m, 6), 'Imtiaz', EntryKind.expense);
    await add('Groceries', vary(9000, 0.25), monthsAgo(m, 20), 'imtiaz', EntryKind.expense);
    await add('Subscriptions', 1500, monthsAgo(m, 3), 'Netflix', EntryKind.expense);
    await add('Shopping', vary(14000, 0.5), monthsAgo(m, 22), 'Daraz', EntryKind.expense);
    if (m % 3 == 0) await add('Health', vary(7000, 0.4), monthsAgo(m, 14), 'Pharmacy', EntryKind.expense);
    await add('Savings deposit', 25000, monthsAgo(m, 3), 'Meezan savings', EntryKind.expense);
    await add('Committee (BC)', 20000, monthsAgo(m, 5), 'BC', EntryKind.expense);

    // Small purchases on random days for the activity heatmap.
    for (var i = 0; i < 9 + rnd.nextInt(6); i++) {
      final day = monthsAgo(m, 1 + rnd.nextInt(28));
      final pick = rnd.nextInt(4);
      final (cat, note, base) = switch (pick) {
        0 => ('Dining out', 'KFC', 2500.0),
        1 => ('Fuel & transport', 'Careem', 900.0),
        2 => ('Fuel & transport', 'PSO petrol', 6000.0),
        _ => ('Dining out', 'Kolachi', 7000.0),
      };
      await add(cat, vary(base, 0.3), day, note, EntryKind.expense);
    }
  }
  // An expensive month two months back, so the savings history has a dip.
  await add('Travel', 260000, monthsAgo(2, 24), 'Hunza trip', EntryKind.expense);

  // Investments and priced assets.
  final fund = await repo.saveInvestment(Investment(
      name: 'Meezan fund', type: AssetType.fund, currentValue: 395000, valueCurrency: 'PKR', valuedOn: today));
  final plot = await repo.saveInvestment(Investment(
      name: 'DHA plot', type: AssetType.property, currentValue: 5600000, valueCurrency: 'PKR', valuedOn: today));
  final shares = await repo.saveInvestment(const Investment(name: 'PSO shares', type: AssetType.stocks, closed: true));
  final gold = await repo.saveInvestment(Investment(
      name: 'Gold', type: AssetType.gold, unit: QuantityUnit.tola, priceSymbol: 'XAU',
      marketPrice: 435000, marketCurrency: 'PKR', marketPriceOn: today.subtract(const Duration(days: 1))));
  final silver = await repo.saveInvestment(Investment(
      name: 'Silver', type: AssetType.silver, unit: QuantityUnit.tola, priceSymbol: 'XAG',
      marketPrice: 6000, marketCurrency: 'PKR', marketPriceOn: today.subtract(const Duration(days: 1))));
  for (var m = 12; m >= 0; m--) {
    await add('Investments', 20000, monthsAgo(m, 25), 'Meezan fund', EntryKind.expense,
        inv: fund, flow: InvestmentFlow.buy);
  }
  await add('Investments', 5000000, monthsAgo(17, 3), 'DHA plot', EntryKind.expense, inv: plot, flow: InvestmentFlow.buy);
  await add('Investments', 150000, monthsAgo(17, 4), 'DHA plot transfer fee', EntryKind.expense,
      inv: plot, flow: InvestmentFlow.cost);
  for (var m = 14; m >= 0; m--) {
    await add('Rental', 45000, monthsAgo(m, 7), 'DHA plot rent', EntryKind.income, inv: plot, flow: InvestmentFlow.income);
  }
  await add('Investments', 300000, monthsAgo(16, 10), 'PSO shares', EntryKind.expense, inv: shares, flow: InvestmentFlow.buy);
  await add('Profit & dividends', 12000, monthsAgo(13, 20), 'PSO dividend', EntryKind.income,
      inv: shares, flow: InvestmentFlow.income);
  await add('Business', 340000, monthsAgo(7, 15), 'PSO shares sold', EntryKind.income, inv: shares, flow: InvestmentFlow.sale);
  await add('Investments', 355000, monthsAgo(16, 2), 'Gold 1 tola', EntryKind.expense, inv: gold, flow: InvestmentFlow.buy, qty: 1);
  await add('Investments', 262000, monthsAgo(8, 8), 'Gold 0.5 tola', EntryKind.expense,
      inv: gold, flow: InvestmentFlow.buy, qty: 0.5);
  await add('Investments', 42000, monthsAgo(14, 9), 'Silver 10 tola', EntryKind.expense,
      inv: silver, flow: InvestmentFlow.buy, qty: 10);

  // Loans: a car loan being paid off, money lent to a friend, one settled.
  final car = await repo.saveLoan(Loan(
      name: 'Car loan (Meezan)', direction: LoanDirection.payable, dueDate: DateTime(today.year + 2, 6, 1)));
  final ali = await repo.saveLoan(const Loan(name: 'Ali', direction: LoanDirection.receivable, note: 'For his wedding'));
  final sara = await repo.saveLoan(const Loan(name: 'Sara', direction: LoanDirection.receivable));
  await add('', 1200000, monthsAgo(16, 1), 'Car loan', EntryKind.income, loan: car);
  for (var m = 15; m >= 0; m--) {
    await add('', 40000, monthsAgo(m, 5), 'Car loan instalment', EntryKind.expense, loan: car);
  }
  await add('', 50000, monthsAgo(5, 10), 'Ali', EntryKind.expense, loan: ali);
  await add('', 20000, monthsAgo(1, 12), 'Ali', EntryKind.income, loan: ali);
  await add('', 15000, monthsAgo(8, 1), 'Sara', EntryKind.expense, loan: sara);
  await add('', 15000, monthsAgo(7, 1), 'Sara', EntryKind.income, loan: sara);

  if (withImports) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}-${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}-${d.year}';
    String num(DateTime d) => '${d.day}-${d.month}-${d.year % 100}';
    final d1 = today, d2 = today.subtract(const Duration(days: 1)), d3 = today.subtract(const Duration(days: 2));
    const parser = AlertParser();
    await repo.addImports([
      for (final a in sampleAlerts)
        ?parser.parse(
          a.replaceAll('{d1}', fmt(d1)).replaceAll('{d2}', fmt(d2)).replaceAll('{d3}', num(d3)),
          receivedAt: today.add(const Duration(hours: 23)),
        ),
    ]);
  }
}
