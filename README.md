# KnowFinance

A Flutter app (Android and iOS) for logging income and expenses, sorting
expenses into Needs, Wants and Savings, and seeing where the money goes.

## Status

Steps 1 and 2 of the plan are in place.

Logging:

- Add, edit and delete income and expenses (swipe left to delete)
- Income types and expense types, each expense type in Needs, Wants or Savings
- Each entry has its own currency (PKR by default). A home currency in
  Settings is used for every list, total and chart. Foreign-currency entries
  store the exchange rate for their date, fetched online or typed in.
- Filters for date range, income/expense, bucket and note text (case-insensitive)
- Everything is stored on the device (SQLite)

Insights (follows the selected date range):

- Savings analysis: Needs, Wants and Savings as a share of income, compared
  with the 50/30/20 guide
- Expense pie that drills down from bucket to expense type to note groups
- Income by type pie
- Income vs expenses line chart, and income vs Needs, Wants and Savings
- Spending grouped by note (case-insensitive, extra spaces ignored)

Coming next: SMS (Android), email and bank statement import for Pakistani
banks.

## Running

```sh
flutter pub get
flutter run            # with a phone or emulator connected
flutter test
```

To render the Insights screen to PNGs with sample data:

```sh
FLUTTER_ROOT=<flutter sdk> SCREENSHOT_DIR=/tmp/shots flutter test test/ui/insights_screenshot_test.dart --update-goldens
```

Exchange rates come from the free
[fawazahmed0 currency API](https://github.com/fawazahmed0/exchange-api) and are
cached per day in the local database.
