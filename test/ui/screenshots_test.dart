// Renders the Insights screen with sample data to a PNG for eyeballing
// layout. Skipped unless SCREENSHOT_DIR is set.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/main.dart';
import 'package:know_finance/models/entry.dart';
import 'package:know_finance/models/entry_filter.dart';
import 'package:know_finance/models/enums.dart';
import 'package:know_finance/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  final root = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$root/Roboto-$w.ttf').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$root/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  sqfliteFfiInit();

  for (final dark in [false, true]) {
    testWidgets('insights screenshot ${dark ? 'dark' : 'light'}', skip: _dir == null, (tester) async {
      tester.view.physicalSize = const Size(1080, 7600);
      tester.view.devicePixelRatio = 2.6;
      tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
      late AppDatabase db;
      late SharedPreferences prefs;
      await tester.runAsync(() async {
        await _loadFonts();
        db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        final repo = FinanceRepository(db);
        final cats = {for (final c in await repo.categories()) c.name: c.id!};
        Future<void> add(String cat, double amt, DateTime d, String note, EntryKind k) => repo.saveEntry(Entry(
              kind: k, amount: amt, currency: 'PKR', homeCurrency: 'PKR', fxRate: 1,
              categoryId: cats[cat]!, date: d, note: note));
        for (var m = 5; m <= 10; m++) {
          await add('Salary', 250000, DateTime(2026, m, 1), 'Xorlogics', EntryKind.income);
          if (m.isEven) await add('Freelance', 60000.0 + m * 1000, DateTime(2026, m, 15), 'Upwork', EntryKind.income);
          await add('Rent', 70000, DateTime(2026, m, 2), 'House rent', EntryKind.expense);
          await add('Groceries', 25000.0 + m * 900, DateTime(2026, m, 6), 'Imtiaz', EntryKind.expense);
          await add('Groceries', 9000, DateTime(2026, m, 18), 'imtiaz', EntryKind.expense);
          await add('Utilities', 18000.0 - m * 500, DateTime(2026, m, 10), 'K-Electric', EntryKind.expense);
          await add('Fuel & transport', 15000, DateTime(2026, m, 12), 'Careem', EntryKind.expense);
          await add('Dining out', 8000.0 + m * 1500, DateTime(2026, m, 20), 'KFC', EntryKind.expense);
          await add('Shopping', 12000, DateTime(2026, m, 22), 'Daraz', EntryKind.expense);
          await add('Committee (BC)', 30000, DateTime(2026, m, 5), 'BC', EntryKind.expense);
          await add('Investments', 20000, DateTime(2026, m, 25), 'Meezan fund', EntryKind.expense);
        }
      });
      final scope = ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          preferencesProvider.overrideWithValue(prefs),
        ],
        child: const KnowFinanceApp(),
      );
      await tester.pumpWidget(scope);
      final container = ProviderScope.containerOf(tester.element(find.byType(KnowFinanceApp)));
      container.read(filterProvider.notifier).update((f) => f.copyWith(preset: DatePreset.allTime));
      await tester.tap(find.text('Insights'));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dir/insights_${dark ? 'dark' : 'light'}.png'));
      await tester.runAsync(db.close);
    });
  }
}
