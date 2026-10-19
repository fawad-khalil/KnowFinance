import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/entry_filter.dart';
import '../../models/enums.dart';
import '../../state/providers.dart';

/// Date range, income/expense, bucket and note search controls shared by the
/// entries list and (later) the insights screen.
class FilterBar extends ConsumerStatefulWidget {
  const FilterBar({super.key, this.datesOnly = false});

  /// Insights only follows the date range, so it hides the other controls.
  final bool datesOnly;

  @override
  ConsumerState<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<FilterBar> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(filterProvider).noteQuery);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickPreset(DatePreset preset) async {
    final notifier = ref.read(filterProvider.notifier);
    if (preset != DatePreset.custom) {
      notifier.update((f) => f.copyWith(preset: preset));
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: DateTime(now.year, now.month), end: now),
    );
    if (picked == null) return;
    notifier.update((f) => f.copyWith(
          preset: DatePreset.custom,
          range: DateRange(picked.start, picked.end),
        ));
  }

  String _presetLabel(EntryFilter f) {
    if (f.preset != DatePreset.custom || f.range?.start == null) return f.preset.label;
    final fmt = DateFormat('d MMM yy');
    return '${fmt.format(f.range!.start!)} – ${fmt.format(f.range!.end!)}';
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final notifier = ref.read(filterProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.datesOnly) TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search notes',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: filter.noteQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        notifier.update((f) => f.copyWith(noteQuery: ''));
                      },
                    ),
            ),
            onChanged: (v) => notifier.update((f) => f.copyWith(noteQuery: v)),
          ),
          if (!widget.datesOnly) const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                PopupMenuButton<DatePreset>(
                  onSelected: _pickPreset,
                  itemBuilder: (_) => [
                    for (final p in DatePreset.values) PopupMenuItem(value: p, child: Text(p.label)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(_presetLabel(filter)),
                  ),
                ),
                const SizedBox(width: 8),
                if (!widget.datesOnly) for (final k in [null, EntryKind.income, EntryKind.expense]) ...[
                  ChoiceChip(
                    label: Text(k == null ? 'All' : (k == EntryKind.income ? 'Income' : 'Expenses')),
                    selected: filter.kind == k,
                    onSelected: (_) => notifier.update((f) => f.copyWith(
                          kind: () => k,
                          bucket: k == EntryKind.income ? () => null : null,
                        )),
                  ),
                  const SizedBox(width: 6),
                ],
                if (!widget.datesOnly && filter.kind != EntryKind.income)
                  for (final b in Bucket.values) ...[
                    FilterChip(
                      label: Text(b.label),
                      selected: filter.bucket == b,
                      onSelected: (on) => notifier.update((f) => f.copyWith(bucket: () => on ? b : null)),
                    ),
                    const SizedBox(width: 6),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
