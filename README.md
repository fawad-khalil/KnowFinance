# KnowFinance

A Flutter app (Android and iOS) for logging income and expenses, sorting
expenses into Needs, Wants and Savings, and seeing where the money goes.

## Status

Steps 1 and 2 of the plan are in place, and step 3 (import) has its first version.

Logging:

- Add, edit and delete income and expenses (swipe left to delete)
- Income types and expense types, each expense type in Needs, Wants or Savings
- Each entry has its own currency (PKR by default). A home currency in
  Settings is used for every list, total and chart. Foreign-currency entries
  store the exchange rate for their date, fetched online or typed in.
- Filters for date range, income/expense, bucket and note text (case-insensitive)
- Everything is stored on the device (SQLite)

Insights:

- This month so far: how much was saved (income minus Needs and Wants) and
  its share of income; income and spending against the same days of last
  month, with the % change and whether spending is growing faster than
  income; loan money that moved this month, kept apart
- Savings: every month's balance added up. Months with money left over add
  to savings, short months draw from it; a bar per month for the last year
- The rest follows the selected date range:

- Headline cards for income, expenses, net and share kept, each with the
  change from the period before (month-to-date compares with the same days
  of last month)
- Transaction activity heatmap: one square per day, shaded by number of
  transactions, spending or income; tap a day for its totals
- Savings analysis: Needs, Wants and Savings as a share of income, compared
  with the 50/30/20 guide
- Expense pie that drills down from bucket to expense type to note groups
- Income by type pie
- Income vs expenses line chart, and income vs Needs, Wants and Savings
- Spending grouped by note (case-insensitive, extra spaces ignored)

Assets & investments (Assets tab):

- Track anything you own or invested in: stocks, mutual funds, property,
  gold, silver, other commodities, crypto, savings schemes, a business, a
  vehicle. Link entries to it: expenses as Buy or Cost (fees, tax, upkeep),
  income as Sale or Dividend / rent
- Link from the entry form (an asset whose name the note mentions is picked
  automatically) or from the asset's page, which lists unlinked Savings
  expenses and income with matching notes already ticked
- Assets can be counted in grams, tola, troy ounces, kg, lb, barrels,
  shares, coins or units. Buys and sales record a quantity, read from the
  note when it says e.g. "Gold 2 tola" or "10g"
- Market prices: gold, silver, platinum and palladium (XAU, XAG, XPT, XPD),
  Bitcoin and Ethereum come from the currency API, converted from troy
  ounces to the unit you hold. WTI and Brent crude oil, copper and any stock
  or ETF ticker come from Yahoo Finance. Prices refresh once a day when the
  tab opens, or on demand with the refresh button
- Purchase vs market: average price paid per unit against today's price,
  cost of what you still hold against its market value, gain on units sold,
  and for metals and crypto each buy against the market price on its own
  day (the premium a jeweller or exchange charged)
- Per asset: invested, cash returned, current value (market value when
  priced, otherwise typed in), profit or loss, ROI, income yield,
  annualised return (XIRR) and how long it has been held
- Portfolio totals and a split of money invested by type
- Profit booked in a chosen period (this month, last month, last 3 months,
  this year, all time or a custom range): dividends and rent received plus
  gains on sales, with a monthly (or yearly) bar chart and a row per asset.
  A sale's cost is its units at the average buy price, or for a closed
  asset counted without units, its share of everything put in

Loans (Assets tab › Loans):

- Payables (money you borrowed) and receivables (money you lent), each with
  who it is with, an optional due date and a note
- Turn on "This is a loan" when adding an entry and pick the loan: money in
  is borrowed (payable) or got back (receivable), money out is repaid or
  lent. Existing entries can be linked from the loan's page; ones whose
  note mentions the loan are ticked
- Loan money is never income or spending: it is left out of Insights,
  Reports, savings and the Entries totals, which show it on its own line
- Per loan: borrowed or lent, paid back, what is left, progress, overdue
  and overpaid, and every payment with the balance after it. Totals for
  what you owe, what you are owed and the net. Interest is spending: log it
  as a separate expense

Reports:

- Year by year: income, Needs, Wants, Savings, expenses, net, share kept
  and average monthly spend
- Pivot table for expenses or income: rows by bucket, type, note, source,
  currency, year or month; columns by year, quarter, month or bucket;
  showing totals, counts, averages or % of total, for all years or one year

Feedback:

- A lightbulb button on every tab takes a screenshot, opens a one-box form
  (just say what you'd like or what went wrong; sorting it into a feature,
  improvement or bug is left to the developer) and then opens a mail
  app addressed to iam.fawad.khalil@gmail.com with the screenshot attached.
  Android shows a chooser of installed mail apps; iOS uses Apple Mail, or the
  share sheet when no Apple Mail account is set up. It can be hidden in
  Settings.

Import (inbox icon on the Entries screen):

- Android: scan bank and wallet SMS (first scan looks back 90 days)
- Any platform: paste SMS or email text. (Statement import is hidden until
  PDF statements can be read; the CSV reader is kept for then.)
- Recognises HBL, MCB, UBL, Meezan, Allied, Bank Alfalah, Bank Al Habib,
  Faysal, Standard Chartered, Askari, JS Bank, NBP, JazzCash, Easypaisa,
  SadaPay and NayaPay; skips OTPs, reminders, offers and failed payments
- Bank fees named in an alert ("Fee: Rs.15.00") are added to the expense, so
  it matches what left the account
- Possible duplicates are flagged: a second alert for the same money (within
  a fee) or one matching an entry already added. So are likely transfers
  between your own accounts: money sent to an account you hold (learned from
  alerts that say "your A/C ..."), money from your own name, or the same
  amount going out and coming in within two days. Flagged items are never
  added by "Add all"; "Skip: own transfer" ignores one and remembers that
  account and name. Settings > Your accounts lists and edits what was learned
- Everything lands in a review list with a suggested type before it is
  added; the same message is never imported twice

The parser was written from the general shape of Pakistani bank alerts and
still needs tuning against real messages.

## Running

```sh
flutter pub get
flutter run            # with a phone or emulator connected
flutter test
```

To render the Insights, Assets (list and the gold page) and Reports screens to PNGs with sample data:

```sh
FLUTTER_ROOT=<flutter sdk> SCREENSHOT_DIR=/tmp/shots flutter test test/ui/screenshots_test.dart --update-goldens
```

Exchange rates come from the free
[fawazahmed0 currency API](https://github.com/fawazahmed0/exchange-api) and are
cached per day in the local database.
