import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:know_finance/data/app_database.dart';
import 'package:know_finance/feedback/feature_request.dart';
import 'package:know_finance/main.dart';
import 'package:know_finance/state/providers.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TempPaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  sqfliteFfiInit();

  test('email body carries details and context', () {
    const r = FeatureRequest('Budgets\nMonthly limits per type', null);
    expect(r.subject, 'KnowFinance feedback: Budgets');
    final body = r.body(screen: 'Insights');
    expect(body, startsWith('Budgets\nMonthly limits per type'));
    expect(body, contains('Screen: Insights'));
    expect(body, isNot(contains('Screenshot attached')));
  });

  test('long first lines are shortened in the subject', () {
    final r = FeatureRequest('${'a' * 80}\nmore', null);
    expect(r.subject.length, lessThanOrEqualTo('KnowFinance feedback: '.length + 60));
    expect(r.subject, endsWith('...'));
  });

  testWidgets('button captures the screen and opens the form', (tester) async {
    PathProviderPlatform.instance = _TempPaths();
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
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.byTooltip('Send feedback'), findsOneWidget);
    await tester.tap(find.byTooltip('Send feedback'));
    await settle();
    await settle();

    expect(find.text('Send feedback'), findsOneWidget);
    expect(find.text('Attach screenshot'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Write a few words first'), findsOneWidget);

    await tester.runAsync(db.close);
  });
}
