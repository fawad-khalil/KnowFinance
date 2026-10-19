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

Insights (follows the selected date range):

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

Investments (Invest tab):

- Add a holding (stocks, mutual fund, property, gold, crypto, savings
  scheme, business, other) and link entries to it: expenses as Buy or Cost
  (fees, tax, upkeep), income as Sale or Dividend / rent
- Link from the entry form (an investment whose name the note mentions is
  picked automatically) or from the holding's page, which lists unlinked
  Savings expenses and income with matching notes already ticked
- Per holding: invested, cash returned, current value, profit or loss, ROI,
  income yield, annualised return (XIRR) and how long it has been held
- Portfolio totals and a split of money invested by type. Open holdings
  need a current value (Update on their page) to count towards profit;
  closed ones don't

Reports:

- Year by year: income, Needs, Wants, Savings, expenses, net, share kept
  and average monthly spend
- Pivot table for expenses or income: rows by bucket, type, note, source,
  currency, year or month; columns by year, quarter, month or bucket;
  showing totals, counts, averages or % of total, for all years or one year

Feature requests:

- A lightbulb button on every tab takes a screenshot, opens a short form
  (feature, improvement or problem; title; details) and then opens a mail
  app addressed to iam.fawad.khalil@gmail.com with the screenshot attached.
  Android shows a chooser of installed mail apps; iOS uses Apple Mail, or the
  share sheet when no Apple Mail account is set up. It can be hidden in
  Settings.

Import (inbox icon on the Entries screen):

- Android: scan bank and wallet SMS (first scan looks back 90 days)
- Any platform: paste SMS or email text, or pick a CSV bank statement
- Recognises HBL, MCB, UBL, Meezan, Allied, Bank Alfalah, Bank Al Habib,
  Faysal, Standard Chartered, Askari, JS Bank, NBP, JazzCash, Easypaisa,
  SadaPay and NayaPay; skips OTPs, reminders, offers and failed payments
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

To render the Insights, Invest and Reports screens to PNGs with sample data:

```sh
FLUTTER_ROOT=<flutter sdk> SCREENSHOT_DIR=/tmp/shots flutter test test/ui/screenshots_test.dart --update-goldens
```

Exchange rates come from the free
[fawazahmed0 currency API](https://github.com/fawazahmed0/exchange-api) and are
cached per day in the local database.
