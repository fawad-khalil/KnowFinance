import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../data/finance_repository.dart';
import '../import/category_suggester.dart';
import '../import/import_flags.dart';
import '../import/import_service.dart';
import '../import/pending_import.dart';
import '../models/category.dart';
import '../models/currency.dart';
import '../models/entry.dart';
import '../models/entry_filter.dart';
import '../models/enums.dart';
import '../models/investment.dart';
import '../services/fx_service.dart';
import '../services/price_service.dart';

/// Overridden in main() once the database is open.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

/// Overridden in main() once preferences are loaded.
final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('preferencesProvider must be overridden'),
);

final repositoryProvider =
    Provider<FinanceRepository>((ref) => FinanceRepository(ref.watch(appDatabaseProvider)));

final fxServiceProvider = Provider<FxService>((ref) => FxService(ref.watch(repositoryProvider)));

final priceServiceProvider =
    Provider<PriceService>((ref) => PriceService(ref.watch(repositoryProvider), ref.watch(fxServiceProvider)));

class HomeCurrencyNotifier extends Notifier<String> {
  static const _key = 'home_currency';

  @override
  String build() => ref.watch(preferencesProvider).getString(_key) ?? defaultCurrencyCode;

  /// Saves the new home currency and re-bases existing entries. Returns how
  /// many entries still need a rate typed in.
  Future<int> set(String code) async {
    await ref.read(preferencesProvider).setString(_key, code);
    state = code;
    final missing = await ref.read(fxServiceProvider).refreshEntries(code);
    ref.read(dataVersionProvider.notifier).bump();
    return missing;
  }
}

final homeCurrencyProvider =
    NotifierProvider<HomeCurrencyNotifier, String>(HomeCurrencyNotifier.new);

/// Bumped after every write so lists and charts reload.
class DataVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

class FilterNotifier extends Notifier<EntryFilter> {
  @override
  EntryFilter build() => const EntryFilter();

  void update(EntryFilter Function(EntryFilter) change) => state = change(state);
}

final filterProvider = NotifierProvider<FilterNotifier, EntryFilter>(FilterNotifier.new);

/// All categories including archived ones, so old entries keep their labels.
final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).categories(includeArchived: true);
});

final categoryByIdProvider = Provider<Map<int, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id!: c};
});

final entriesProvider = FutureProvider<List<Entry>>((ref) {
  ref.watch(dataVersionProvider);
  final filter = ref.watch(filterProvider);
  return ref.watch(repositoryProvider).entries(filter);
});

final recentNotesProvider = FutureProvider<List<String>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).recentNotes();
});

/// Entries for the Insights screen: the shared date range only, ignoring the
/// list's kind, bucket and note filters.
final insightsEntriesProvider = FutureProvider<List<Entry>>((ref) {
  ref.watch(dataVersionProvider);
  final f = ref.watch(filterProvider);
  return ref.watch(repositoryProvider).entries(EntryFilter(preset: f.preset, range: f.range));
});

/// Entries for the period before the selected range, for the change
/// figures on Insights. Empty when the range is unbounded.
final previousPeriodEntriesProvider = FutureProvider<List<Entry>>((ref) async {
  ref.watch(dataVersionProvider);
  final prev = ref.watch(filterProvider).effectiveRange().previous();
  if (prev == null) return const [];
  return ref.watch(repositoryProvider).entries(EntryFilter(preset: DatePreset.custom, range: prev));
});

final pendingImportsProvider = FutureProvider<List<PendingImport>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).pendingImports();
});

final pendingImportCountProvider = FutureProvider<int>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).pendingImportCount();
});

/// Suggests a type for each import using the user's own history.
final categorySuggesterProvider = FutureProvider<CategorySuggester>((ref) async {
  ref.watch(dataVersionProvider);
  final repo = ref.watch(repositoryProvider);
  return CategorySuggester(await repo.categories(), await repo.noteCategoryHistory());
});

final importServiceProvider = Provider<ImportService>((ref) => ImportService(
      ref.watch(repositoryProvider),
      ref.watch(fxServiceProvider),
      ref.watch(preferencesProvider),
    ));

/// Imports that look like duplicates or transfers between the user's own
/// accounts, keyed by import id.
final importFlagsProvider = FutureProvider<Map<int, List<ImportFlag>>>((ref) async {
  final pending = await ref.watch(pendingImportsProvider.future);
  if (pending.isEmpty) return const {};
  final service = ref.watch(importServiceProvider);
  final dates = pending.map((p) => p.date);
  final from = dates.reduce((a, b) => a.isBefore(b) ? a : b).subtract(const Duration(days: 2));
  final to = dates.reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(days: 2));
  final entries = await ref
      .watch(repositoryProvider)
      .entries(EntryFilter(preset: DatePreset.custom, range: DateRange(from, to)));
  return flagImports(
    pending,
    entries: entries,
    ownAccounts: service.ownAccounts,
    ownNames: service.ownNames,
    describe: (p) => '${p.kind == EntryKind.income ? '+' : '−'}${formatMoney(p.amount, p.currency)}'
        '${p.counterparty.isEmpty ? '' : ' ${p.kind == EntryKind.income ? 'from' : 'to'} ${p.counterparty}'}'
        ' on ${DateFormat('d MMM').format(p.date)}',
  );
});

/// Every entry, for year-by-year reports.
final allEntriesProvider = FutureProvider<List<Entry>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).entries(const EntryFilter(preset: DatePreset.allTime));
});

final investmentsProvider = FutureProvider<List<Investment>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).investments();
});

final investmentEntriesProvider = FutureProvider<List<Entry>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).investmentEntries();
});

class ShowFeatureRequestButton extends Notifier<bool> {
  static const _key = 'show_feature_request_button';

  @override
  bool build() => ref.watch(preferencesProvider).getBool(_key) ?? true;

  Future<void> set(bool value) async {
    await ref.read(preferencesProvider).setBool(_key, value);
    state = value;
  }
}

final showFeatureRequestButtonProvider =
    NotifierProvider<ShowFeatureRequestButton, bool>(ShowFeatureRequestButton.new);
