import '../models/entry.dart';
import '../models/enums.dart';
import '../models/loan.dart';

/// Where one loan stands: what was borrowed or lent, what has come back
/// or been paid off, and what is still outstanding.
class LoanBalance {
  LoanBalance(this.loan);

  final Loan loan;
  final List<Entry> entries = [];

  /// Borrowed (payable) or lent (receivable).
  double opened = 0;

  /// Repaid (payable) or got back (receivable).
  double settled = 0;

  /// Entries in another currency without a rate; left out of the sums.
  int skipped = 0;
  DateTime? last;

  double get outstanding => opened - settled;

  /// Share paid off, 0 to 1.
  double get progress => opened <= 0 ? 0 : (settled / opened).clamp(0, 1);

  /// Paid off, allowing for rounding.
  bool get isSettled => opened > 0 && outstanding.abs() < 1;

  bool get isOverdue => !isSettled && loan.dueDate != null && loan.dueDate!.isBefore(DateTime.now());
}

/// Loan money moving in a period, split by what it did.
class LoanFlows {
  double borrowed = 0;
  double repaid = 0;
  double lent = 0;
  double gotBack = 0;

  bool get isEmpty => borrowed == 0 && repaid == 0 && lent == 0 && gotBack == 0;

  /// Cash in from loans minus cash out to them.
  double get net => borrowed + gotBack - repaid - lent;
}

/// Payables and receivables from loans and their linked entries.
class LoanAnalytics {
  LoanAnalytics(List<Loan> loans, List<Entry> linked, this.home) {
    final byId = {for (final l in loans) l.id!: LoanBalance(l)};
    for (final e in linked) {
      final b = byId[e.loanId];
      if (b == null) continue;
      b.entries.add(e);
      final amt = e.homeCurrency == home ? e.homeAmount : null;
      if (amt == null) {
        b.skipped++;
        continue;
      }
      if (e.kind == b.loan.direction.openingKind) {
        b.opened += amt;
      } else {
        b.settled += amt;
      }
      if (b.last == null || e.date.isAfter(b.last!)) b.last = e.date;
    }
    balances = byId.values.toList()..sort((a, b) => b.outstanding.abs().compareTo(a.outstanding.abs()));
    _byId = byId;
  }

  final String home;
  late final List<LoanBalance> balances;
  late final Map<int, LoanBalance> _byId;

  LoanBalance? operator [](int id) => _byId[id];

  List<LoanBalance> get payables => balances.where((b) => b.loan.direction == LoanDirection.payable).toList();
  List<LoanBalance> get receivables => balances.where((b) => b.loan.direction == LoanDirection.receivable).toList();

  /// What the user still owes, counting only loans not overpaid.
  double get totalPayable => payables.fold(0, (t, b) => t + (b.outstanding > 0 ? b.outstanding : 0));

  /// What the user is still owed.
  double get totalReceivable => receivables.fold(0, (t, b) => t + (b.outstanding > 0 ? b.outstanding : 0));

  /// Owed to the user minus what the user owes.
  double get net => totalReceivable - totalPayable;

  /// Loan money that moved between [start] and [end], inclusive.
  LoanFlows flows({DateTime? start, DateTime? end}) {
    final f = LoanFlows();
    for (final b in balances) {
      for (final e in b.entries) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        if ((start != null && d.isBefore(start)) || (end != null && d.isAfter(end))) continue;
        final amt = e.homeCurrency == home ? e.homeAmount : null;
        if (amt == null) continue;
        switch ((b.loan.direction, e.kind)) {
          case (LoanDirection.payable, EntryKind.income):
            f.borrowed += amt;
          case (LoanDirection.payable, EntryKind.expense):
            f.repaid += amt;
          case (LoanDirection.receivable, EntryKind.expense):
            f.lent += amt;
          case (LoanDirection.receivable, EntryKind.income):
            f.gotBack += amt;
        }
      }
    }
    return f;
  }
}
