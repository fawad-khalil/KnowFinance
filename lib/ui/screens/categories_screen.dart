import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category.dart';
import '../../models/enums.dart';
import '../../state/providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {Category? category, required EntryKind kind}) async {
    final result = await showDialog<Category>(
      context: context,
      builder: (_) => _CategoryDialog(category: category, kind: kind),
    );
    if (result == null) return;
    await ref.read(repositoryProvider).saveCategory(result);
    ref.read(dataVersionProvider.notifier).bump();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${c.name}"?'),
        content: const Text('Existing entries keep this type. It just won\'t be offered for new ones.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).deleteCategory(c.id!);
    ref.read(dataVersionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = (ref.watch(categoriesProvider).value ?? const <Category>[]).where((c) => !c.archived).toList();
    final theme = Theme.of(context);

    Widget section(String title, List<Category> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            ),
            for (final c in items)
              ListTile(
                title: Text(c.name),
                onTap: () => _edit(context, ref, category: c, kind: c.kind),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref, c)),
              ),
          ],
        );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Income & expense types'),
          bottom: const TabBar(tabs: [Tab(text: 'Expenses'), Tab(text: 'Income')]),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton(
            onPressed: () => _edit(
              ctx,
              ref,
              kind: DefaultTabController.of(ctx).index == 0 ? EntryKind.expense : EntryKind.income,
            ),
            child: const Icon(Icons.add),
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                for (final b in Bucket.values)
                  section(b.label, all.where((c) => c.bucket == b).toList()),
              ],
            ),
            ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [section('Income types', all.where((c) => c.kind == EntryKind.income).toList())],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category, required this.kind});

  final Category? category;
  final EntryKind kind;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.name);
  late Bucket? _bucket = widget.category?.bucket ?? (widget.kind == EntryKind.expense ? Bucket.needs : null);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = widget.kind == EntryKind.expense;
    return AlertDialog(
      title: Text(widget.category == null ? (isExpense ? 'New expense type' : 'New income type') : 'Edit type'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          if (isExpense) ...[
            const SizedBox(height: 16),
            SegmentedButton<Bucket>(
              segments: [for (final b in Bucket.values) ButtonSegment(value: b, label: Text(b.label))],
              selected: {_bucket!},
              onSelectionChanged: (s) => setState(() => _bucket = s.first),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            final c = widget.category;
            Navigator.pop(
              context,
              c == null
                  ? Category(name: name, kind: widget.kind, bucket: _bucket)
                  : c.copyWith(name: name, bucket: _bucket),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
