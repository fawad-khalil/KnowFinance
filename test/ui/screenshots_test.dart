// Renders the Insights and Reports screens with sample data to a PNG for eyeballing
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
import 'package:know_finance/models/investment.dart';
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
    for (final t in ['Insights', 'Invest', 'Reports']) ...[(t, false), (t, true)],
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
        final cats = {for (final c in await repo.categories()) c.name: c.id!};
        final fund = await repo.saveInvestment(Investment(
            name: 'Meezan fund', type: AssetType.fund, currentValue: 395000, valueCurrency: 'PKR', valuedOn: DateTime(2026, 10, 1)));
        final plot = await repo.saveInvestment(Investment(
            name: 'DHA plot', type: AssetType.property, currentValue: 5600000, valueCurrency: 'PKR', valuedOn: DateTime(2026, 10, 1)));
        final shares = await repo.saveInvestment(const Investment(name: 'PSO shares', type: AssetType.stocks, closed: true));
        final gold = await repo.saveInvestment(const Investment(name: 'Gold', type: AssetType.gold));
        Future<void> add(String cat, double amt, DateTime d, String note, EntryKind k, {int? inv, InvestmentFlow? flow}) =>
            repo.saveEntry(Entry(
              kind: k, amount: amt, currency: 'PKR', homeCurrency: 'PKR', fxRate: 1,
              categoryId: cats[cat]!, date: d, note: note, investmentId: inv, investmentFlow: flow));
        await add('Investments', 5000000, DateTime(2025, 5, 3), 'DHA plot', EntryKind.expense, inv: plot, flow: InvestmentFlow.buy);
        await add('Investments', 150000, DateTime(2025, 5, 4), 'DHA plot transfer fee', EntryKind.expense, inv: plot, flow: InvestmentFlow.cost);
        await add('Investments', 300000, DateTime(2025, 6, 10), 'PSO shares', EntryKind.expense, inv: shares, flow: InvestmentFlow.buy);
        await add('Profit & dividends', 12000, DateTime(2025, 9, 20), 'PSO dividend', EntryKind.income, inv: shares, flow: InvestmentFlow.income);
        await add('Business', 340000, DateTime(2026, 3, 15), 'PSO shares sold', EntryKind.income, inv: shares, flow: InvestmentFlow.sale);
        await add('Investments', 180000, DateTime(2026, 2, 8), 'Gold', EntryKind.expense, inv: gold, flow: InvestmentFlow.buy);
        for (var i = 0; i < 18; i++) {
          final m = i < 12 ? i + 1 : i - 11;
          final y = i < 12 ? 2025 : 2026;
          if (y == 2025 && m < 5) continue;
          await add('Salary', 250000, DateTime(y, m, 1), 'Xorlogics', EntryKind.income);
          if (m.isEven) await add('Freelance', 60000.0 + m * 1000, DateTime(y, m, 15), 'Upwork', EntryKind.income);
          await add('Rent', 70000, DateTime(y, m, 2), 'House rent', EntryKind.expense);
          await add('Groceries', 25000.0 + m * 900, DateTime(y, m, 6), 'Imtiaz', EntryKind.expense);
          await add('Groceries', 9000, DateTime(y, m, 18), 'imtiaz', EntryKind.expense);
          await add('Utilities', 18000.0 - m * 500, DateTime(y, m, 10), 'K-Electric', EntryKind.expense);
          await add('Fuel & transport', 15000, DateTime(y, m, 12), 'Careem', EntryKind.expense);
          await add('Dining out', 8000.0 + m * 1500, DateTime(y, m, 20), 'KFC', EntryKind.expense);
          await add('Shopping', 12000, DateTime(y, m, 22), 'Daraz', EntryKind.expense);
          await add('Committee (BC)', 30000, DateTime(y, m, 5), 'BC', EntryKind.expense);
          await add('Investments', 20000, DateTime(y, m, 25), 'Meezan fund', EntryKind.expense, inv: fund, flow: InvestmentFlow.buy);
          if (y == 2026 || m > 6) await add('Rental', 45000, DateTime(y, m, 7), 'DHA plot rent', EntryKind.income, inv: plot, flow: InvestmentFlow.income);
          if (m % 3 == 0) await add('Dining out', 4500, DateTime(y, m, 21), 'Kolachi', EntryKind.expense);
          if (m.isOdd) await add('Health', 6000, DateTime(y, m, 14), 'Pharmacy', EntryKind.expense);
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
      await tester.tap(find.text(tab));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dir/${tab.toLowerCase()}_${dark ? 'dark' : 'light'}.png'));
      await tester.runAsync(db.close);
    });
  }
}
