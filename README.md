# KnowFinance

A Flutter app (Android and iOS) for logging income and expenses, sorting
expenses into Needs, Wants and Savings, and seeing where the money goes.

## Status

Step 1 of the plan is in place:

- Add, edit and delete income and expenses (swipe left to delete)
- Income types and expense types, each expense type in Needs, Wants or Savings
- Each entry has its own currency (PKR by default). A home currency in
  Settings is used for every list, total and chart. Foreign-currency entries
  store the exchange rate for their date, fetched online or typed in.
- Filters for date range, income/expense, bucket and note text (case-insensitive)
- Everything is stored on the device (SQLite)

Coming next: charts and insights, then SMS (Android), email and bank
statement import for Pakistani banks.

## Running

```sh
flutter pub get
flutter run            # with a phone or emulator connected
flutter test
```

Exchange rates come from the free
[fawazahmed0 currency API](https://github.com/fawazahmed0/exchange-api) and are
cached per day in the local database.
