import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/budget.dart';
import '../models/entry_filter.dart';
import '../models/recurring_payment.dart';
import '../services/budget_tracker.dart';
import '../services/recurring_service.dart';
import 'providers.dart';

final recurringServiceProvider =
    Provider<RecurringService>((ref) => RecurringService(ref.watch(repositoryProvider), ref.watch(fxServiceProvider)));

/// The month shown on the Budget tab, as its first day.
class BudgetMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  void step(int months) => state = DateTime(state.year, state.month + months);
}

final budgetMonthProvider = NotifierProvider<BudgetMonthNotifier, DateTime>(BudgetMonthNotifier.new);

final budgetsProvider = FutureProvider<List<Budget>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).budgets();
});

final recurringProvider = FutureProvider<List<RecurringPayment>>((ref) {
  ref.watch(dataVersionProvider);
  return ref.watch(repositoryProvider).recurringPayments();
});

/// The selected month's spending against its budgets.
final budgetMonthDataProvider = FutureProvider<BudgetMonth>((ref) async {
  ref.watch(dataVersionProvider);
  final month = ref.watch(budgetMonthProvider);
  final home = ref.watch(homeCurrencyProvider);
  final repo = ref.watch(repositoryProvider);
  final last = DateTime(month.year, month.month + 1, 0);
  final payments = await ref.watch(recurringProvider.future);
  final fx = ref.watch(fxServiceProvider);
  final rates = <String, double>{};
  for (final c in payments.map((p) => p.currency).toSet()..remove(home)) {
    final r = await fx.rate(c, home, last);
    if (r != null) rates[c] = r;
  }
  return BudgetMonth(
    month: month,
    budgets: await ref.watch(budgetsProvider.future),
    payments: payments,
    posts: await repo.recurringPosts(from: month, to: last),
    entries: await repo.entries(EntryFilter(preset: DatePreset.custom, range: DateRange(month, last))),
    categories: await ref.watch(categoriesProvider.future).then((l) => {for (final c in l) c.id!: c}),
    home: home,
    rates: rates,
  );
});
