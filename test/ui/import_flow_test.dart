import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/main.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/models/loan.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('pasted alerts are reviewed and added', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
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
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byTooltip('Import transactions'));
    await settle();
    await tester.tap(find.text('Paste SMS or email'));
    await settle();
    await tester.enterText(
      find.byType(TextField).last,
      'PKR 4,560.00 debited from your HBL A/C for POS purchase at IMTIAZ SUPER MARKET on 18-Oct-26.\n\n'
      'Your OTP is 123456. Do not share.\n\n'
      'Rs 1,200 paid to K-ELECTRIC via JazzCash on 17-Oct-26.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle();
    await settle();

    expect(find.text('2 to review'), findsOneWidget);
    await tester.tap(find.text('Add all'));
    await settle();
    await settle();
    expect(find.text('2 to review'), findsNothing);

    await tester.pageBack();
    await settle();
    await settle();
    final container = ProviderScope.containerOf(tester.element(find.byType(KnowFinanceApp)));
    final entries = await tester.runAsync(() => container.read(repositoryProvider).entries(
          const EntryFilter(preset: DatePreset.allTime),
        ));
    expect(entries!.map((e) => e.note), containsAll(['IMTIAZ SUPER MARKET', 'K-ELECTRIC']));
    await tester.runAsync(db.close);
  });

  testWidgets('a second alert for the same transfer is flagged and left for review', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
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
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byTooltip('Import transactions'));
    await settle();
    await tester.tap(find.text('Paste SMS or email'));
    await settle();
    await tester.enterText(
      find.byType(TextField).last,
      'PKR 4,23,434.00 sent to ABC JAXX-xxCASH from your A/C xxx6373 on 18-Oct-2026 at 19:22 Fee: Rs.15.00\n\n'
      'PKR 4,23,434.00 sent to ABC (MBL AC from your A/C xxx6373 on 18-Oct-2026 at 19:22 TID:87987987',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle();
    await settle();

    expect(find.text('2 to review'), findsOneWidget);
    expect(find.textContaining('Possible duplicate'), findsOneWidget);
    await tester.tap(find.text('Add all'));
    await settle();
    await settle();
    // The duplicate is never added in bulk; it waits for a decision.
    expect(find.textContaining('Possible duplicate'), findsOneWidget);
    // Newest first, so the duplicate is the top card.
    await tester.tap(find.text('Ignore').first);
    await settle();
    await settle();
    expect(find.text('1 to review'), findsOneWidget);
    expect(find.textContaining('Possible duplicate'), findsNothing);
    await tester.runAsync(db.close);
  });

  testWidgets('an alert naming a loan contact is set as a loan and left out of Add all', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    late AppDatabase db;
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      await FinanceRepository(db).saveLoan(const Loan(name: 'Ali Khan', direction: LoanDirection.receivable));
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
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.byTooltip('Import transactions'));
    await settle();
    await tester.tap(find.text('Paste SMS or email'));
    await settle();
    await tester.enterText(find.byType(TextField).last, 'Rs 20,000 received from Ali Khan in your account on 18-Oct-26.');
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await settle();
    await settle();

    expect(find.textContaining('Got back'), findsOneWidget);
    await tester.tap(find.text('Add all'));
    await settle();
    await settle();
    expect(find.text('1 to review'), findsOneWidget, reason: 'the loan card waits to be added by hand');

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle();
    await settle();
    final container = ProviderScope.containerOf(tester.element(find.byType(KnowFinanceApp)));
    final linked = await tester.runAsync(() => container.read(repositoryProvider).loanEntries());
    expect(linked!.single.amount, 20000);
    await tester.runAsync(db.close);
  });
}
