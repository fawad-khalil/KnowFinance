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
    const r = FeatureRequest(RequestType.feature, 'Budgets', 'Monthly limits per type', null);
    expect(r.subject, 'KnowFinance Feature request: Budgets');
    final body = r.body(screen: 'Insights');
    expect(body, startsWith('Monthly limits per type'));
    expect(body, contains('Screen: Insights'));
    expect(body, isNot(contains('Screenshot attached')));
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
    expect(find.byTooltip('Request a feature'), findsOneWidget);
    await tester.tap(find.byTooltip('Request a feature'));
    await settle();
    await settle();

    expect(find.text('Request a feature'), findsOneWidget);
    expect(find.text('Attach screenshot'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('Add a short title'), findsOneWidget);

    await tester.runAsync(db.close);
  });
}
