import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';

/// The user's own accounts and name, used to spot transfers between their
/// own accounts in imported alerts. Most of it is learned automatically.
class OwnAccountsScreen extends ConsumerStatefulWidget {
  const OwnAccountsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnAccountsScreen()));

  @override
  ConsumerState<OwnAccountsScreen> createState() => _OwnAccountsScreenState();
}

class _OwnAccountsScreenState extends ConsumerState<OwnAccountsScreen> {
  Future<void> _add({required bool account}) async {
    final controller = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(account ? 'Add an account' : 'Add a name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: account ? TextInputType.number : TextInputType.name,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: account ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)] : null,
          decoration: InputDecoration(
            helperText: account ? 'Last 4 digits, as shown in alerts' : 'As your bank prints it, e.g. FAWAD KHALIL',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (v == null || v.isEmpty || (account && v.length < 3)) return;
    final s = ref.read(importServiceProvider);
    if (account) {
      await s.setOwnAccounts({...s.ownAccounts, v});
    } else {
      await s.setOwnNames({...s.ownNames, v});
    }
    _changed();
  }

  void _changed() {
    ref.read(dataVersionProvider.notifier).bump();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(importServiceProvider);
    final theme = Theme.of(context);
    final accounts = s.ownAccounts.toList()..sort();
    final names = s.ownNames.toList()..sort();
    Widget section(String title, String help, List<String> items, String Function(String) label,
            Future<void> Function(String) remove, VoidCallback add) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(help, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final i in items)
                    InputChip(
                      label: Text(label(i)),
                      onDeleted: () async {
                        await remove(i);
                        _changed();
                      },
                    ),
                  ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add'), onPressed: add),
                ],
              ),
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Your accounts')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          section(
            'Accounts',
            'Learned from alerts that say "your A/C …" and from transfers you skip as your own. Money sent to or '
                'received from these is flagged as a transfer, not income or spending.',
            accounts,
            (t) => '…$t',
            (t) => s.setOwnAccounts(s.ownAccounts..remove(t)),
            () => _add(account: true),
          ),
          section(
            'Your name',
            'When money comes in from someone with this name, it is flagged as a transfer from your own account.',
            names,
            (n) => n,
            (n) => s.setOwnNames(s.ownNames..remove(n)),
            () => _add(account: false),
          ),
        ],
      ),
    );
  }
}
