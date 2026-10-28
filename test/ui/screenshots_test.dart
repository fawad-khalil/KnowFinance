// Renders the main screens with the app's sample data to a PNG for eyeballing
// layout. Skipped unless SCREENSHOT_DIR is set.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/data/finance_repository.dart';
import 'package:know_finance/data/sample_data.dart';
import 'package:know_finance/main.dart';
import 'package:know_finance/models/entry_filter.dart';
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

  for (final (tab, dark) in [
    for (final t in ['Insights', 'View insights', 'Snapshot', 'Raast', 'Assets', 'Gold', 'Loans', 'Reports']) ...[(t, false), (t, true)],
  ]) {
    testWidgets('$tab screenshot ${dark ? 'dark' : 'light'}', skip: _dir == null, (tester) async {
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
        await seedSampleData(repo);
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
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      // "Gold" is the gold asset's own page, opened from the Assets list.
      await tester.tap(find.text(switch (tab) { 'Gold' || 'Loans' => 'Assets', 'View insights' || 'Snapshot' || 'Raast' => 'Insights', _ => tab }).last);
      await settle();
      if (tab == 'View insights' || tab == 'Snapshot' || tab == 'Raast') {
        await tester.tap(find.text('View insights'));
        await settle();
      }
      if (tab == 'Snapshot' || tab == 'Raast') {
        await tester.tap(find.text(tab == 'Snapshot' ? 'Last 30 days snapshot' : 'Raast insights'));
        await settle();
      }
      if (tab == 'Loans') {
        await tester.tap(find.text('Loans').last);
        await settle();
      }
      if (tab == 'Gold') {
        await tester.tap(find.widgetWithText(ListTile, 'Gold'));
        await settle();
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dir/${tab.toLowerCase().replaceAll(' ', '_')}_${dark ? 'dark' : 'light'}.png'));
      await tester.runAsync(db.close);
    });
  }
}
