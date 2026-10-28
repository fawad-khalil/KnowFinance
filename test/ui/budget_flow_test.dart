import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/main.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('sets a budget, adds a bill that logs itself, and tracks both', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    late AppDatabase db;
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        preferencesProvider.overrideWithValue(prefs),
      ],
      child: const KnowFinanceApp(),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await settle();
    await tester.tap(find.text('Budget').last);
    await settle();
    expect(find.text('Plan what you spend each month'), findsOneWidget);

    // A grocery budget of 30,000 makes up the month's budget.
    await tester.tap(find.text('Set budget'));
    await settle();
    final groceries = find.ancestor(of: find.text('Groceries'), matching: find.byType(Row)).first;
    await tester.enterText(find.descendant(of: groceries, matching: find.byType(TextField)), '30000');
    await tester.tap(find.text('Save'));
    await settle();
    expect(find.text('Budget from 1 expense types'), findsOneWidget);
    expect(find.text('PKR 30,000'), findsWidgets);

    // Rent due today is logged at once and budgeted for.
    await tester.tap(find.byTooltip('Recurring payments'));
    await settle();
    await tester.tap(find.text('Add'));
    await settle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'House rent');
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '70000');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Expense type'));
    await settle();
    await tester.tap(find.textContaining('Rent').last);
    await settle();
    await tester.tap(find.text('Save'));
    await settle();
    expect(find.textContaining('Monthly · Rent'), findsOneWidget);
    await tester.pageBack();
    await settle();

    expect(find.text('House rent'), findsOneWidget);
    expect(find.textContaining('Paid'), findsOneWidget);
    expect(find.text('PKR 100,000'), findsOneWidget, reason: 'groceries plus rent');
    expect(find.textContaining('of PKR 70,000 · PKR 70,000 in bills · PKR 0 left'), findsOneWidget);

    final logged = await tester.runAsync(() => FinanceRepository(db).entries(const EntryFilter()));
    expect(logged!.single.note, 'House rent');

    await tester.runAsync(db.close);
  });
}
