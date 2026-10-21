import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sample_data.dart';
import '../../models/currency.dart';
import '../../state/providers.dart';
import 'categories_screen.dart';
import 'import_screen.dart';
import 'own_accounts_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pickCurrency(BuildContext context, WidgetRef ref, String current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => RadioGroup<String>(
        groupValue: current,
        onChanged: (v) => Navigator.pop(ctx, v),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in currencies)
              RadioListTile<String>(value: c.code, title: Text(c.code), subtitle: Text(c.name)),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Converting entries…')));
    final missing = await ref.read(homeCurrencyProvider.notifier).set(picked);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(missing == 0
          ? 'Everything is now shown in $picked.'
          : '$missing ${missing == 1 ? 'entry needs' : 'entries need'} a rate. Connect to the internet or edit them to add one.'),
    ));
  }

  /// Debug builds only: wipes the data and loads about 18 months of
  /// sample entries, assets, loans and imports, for trying the app out.
  Future<void> _loadSample(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything with sample data?'),
        content: const Text('All entries, assets, loans and imports on this device are deleted first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(repositoryProvider);
    await repo.clearAll();
    await seedSampleData(repo);
    ref.read(dataVersionProvider.notifier).bump();
    messenger.showSnackBar(const SnackBar(content: Text('Sample data loaded.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeCurrencyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Home currency'),
            subtitle: Text('Lists, charts and reports are shown in ${currencyFor(home).name}'),
            trailing: Text(home, style: Theme.of(context).textTheme.titleMedium),
            onTap: () => _pickCurrency(context, ref, home),
          ),
          ListTile(
            leading: const Icon(Icons.move_to_inbox_outlined),
            title: const Text('Import transactions'),
            subtitle: const Text('From bank SMS or pasted alerts and emails'),
            onTap: () => ImportScreen.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Your accounts'),
            subtitle: const Text('To spot transfers between your own accounts when importing'),
            onTap: () => OwnAccountsScreen.open(context),
          ),
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('Reset to sample data'),
              subtitle: const Text('Debug builds only'),
              onTap: () => _loadSample(context, ref),
            ),
          if (kDebugMode)
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('Add sample SMS to import'),
              subtitle: const Text('Debug builds only. Leaves your entries as they are'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final added = await seedSampleImports(ref.read(repositoryProvider));
                ref.read(dataVersionProvider.notifier).bump();
                messenger.showSnackBar(SnackBar(content: Text('$added sample alerts added to the import inbox.')));
              },
            ),
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('Feedback button'),
            subtitle: const Text('Shows a button on every tab to send feedback with a screenshot'),
            value: ref.watch(showFeatureRequestButtonProvider),
            onChanged: (v) => ref.read(showFeatureRequestButtonProvider.notifier).set(v),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Income & expense types'),
            subtitle: const Text('Add, rename or move types between Needs, Wants and Savings'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
          ),
        ],
      ),
    );
  }
}
