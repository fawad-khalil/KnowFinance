import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/main.dart';
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
}
