import '../data/finance_repository.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import '../models/recurring_payment.dart';
import 'fx_service.dart';

/// Logs recurring payments as they fall due.
class RecurringService {
  RecurringService(this._repo, this._fx);

  final FinanceRepository _repo;
  final FxService _fx;

  /// Posts every automatic payment due from when it was set up to today
  /// that hasn't been paid or skipped yet. Returns how many were logged.
  Future<int> postDue(String home, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final done = {for (final p in await _repo.recurringPosts()) (p.recurringId, dateKey(p.due))};
    var posted = 0;
    for (final r in await _repo.recurringPayments()) {
      if (!r.autoPost || r.paused) continue;
      for (final due in r.dueDates(r.createdOn, today)) {
        if (done.contains((r.id, dateKey(due)))) continue;
        if (await _repo.postRecurring(r.id!, due, await entryFor(r, due, home)) != null) posted++;
      }
    }
    return posted;
  }

  /// Marks due dates that passed while [r] was paused as skipped, so
  /// resuming it doesn't log them all at once.
  Future<void> skipWhilePaused(RecurringPayment r, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final yesterday = DateTime(n.year, n.month, n.day - 1);
    final done = {for (final p in await _repo.recurringPosts()) if (p.recurringId == r.id) dateKey(p.due)};
    for (final due in r.dueDates(r.createdOn, yesterday)) {
      if (!done.contains(dateKey(due))) await _repo.skipRecurring(r.id!, due);
    }
  }

  /// The expense that pays [r] on [date], for [amount] when it differs from
  /// the usual one.
  Future<Entry> entryFor(RecurringPayment r, DateTime date, String home, {double? amount}) async => Entry(
        kind: EntryKind.expense,
        amount: amount ?? r.amount,
        currency: r.currency,
        homeCurrency: home,
        fxRate: await _fx.rate(r.currency, home, date),
        categoryId: r.categoryId,
        date: date,
        note: r.name,
      );

  /// Logs the payment due on [due] as paid on [paidOn] (the due date by
  /// default).
  Future<int?> markPaid(RecurringPayment r, DateTime due, String home, {double? amount, DateTime? paidOn}) async =>
      _repo.postRecurring(r.id!, due, await entryFor(r, paidOn ?? due, home, amount: amount));
}
