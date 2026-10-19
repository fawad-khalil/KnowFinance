import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_database.dart';
import 'feedback/feature_request.dart';
import 'state/providers.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      preferencesProvider.overrideWithValue(prefs),
    ],
    child: const KnowFinanceApp(),
  ));
}

class KnowFinanceApp extends StatelessWidget {
  const KnowFinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1B7F5B);
    return MaterialApp(
      title: 'KnowFinance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      builder: (context, child) => RepaintBoundary(key: screenshotBoundaryKey, child: child),
      home: const HomeShell(),
    );
  }
}
