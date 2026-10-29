import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/feature_request.dart';
import '../state/budget_providers.dart';
import '../state/providers.dart';

import 'screens/budget_screen.dart';
import 'screens/entries_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/investments_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _postRecurring());
  }

  /// Logs recurring payments that fell due since the app was last opened.
  Future<void> _postRecurring() async {
    final posted = await ref.read(recurringServiceProvider).postDue(ref.read(homeCurrencyProvider));
    if (posted > 0 && mounted) ref.read(dataVersionProvider.notifier).bump();
  }

  static const _pages = [EntriesScreen(), InsightsScreen(), BudgetScreen(), InvestmentsScreen(), ReportsScreen(), SettingsScreen()];
  static const _names = ['Entries', 'Insights', 'Budget', 'Assets', 'Reports', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _pages),
          // Bottom left, clear of each tab's own add button on the right.
          if (ref.watch(showFeatureRequestButtonProvider))
            Positioned(
              left: 16,
              bottom: 16,
              child: FeatureRequestButton(screenName: () => _names[_index]),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Entries'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.trending_up), selectedIcon: Icon(Icons.trending_up), label: 'Assets'),
          NavigationDestination(icon: Icon(Icons.table_chart_outlined), selectedIcon: Icon(Icons.table_chart), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
