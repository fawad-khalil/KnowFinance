import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/main.dart';
import 'package:know_finance/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('adds an expense and shows it in the list', (tester) async {
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
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await settle();
    expect(find.text('No entries for this filter yet.'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '4500');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Expense type'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Groceries').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Note'), 'Imtiaz');

    await tester.tap(find.text('Save'));
    await settle();
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.textContaining('Imtiaz'), findsOneWidget);
    expect(find.textContaining('4,500'), findsWidgets);

    await tester.runAsync(db.close);
  });
}
