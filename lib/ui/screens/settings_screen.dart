import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/currency.dart';
import '../../state/providers.dart';
import 'categories_screen.dart';
import 'import_screen.dart';

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
            subtitle: const Text('From bank SMS, pasted emails or CSV statements'),
            onTap: () => ImportScreen.open(context),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lightbulb_outline),
            title: const Text('Feature request button'),
            subtitle: const Text('Shows a button on every tab to send an idea with a screenshot'),
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
