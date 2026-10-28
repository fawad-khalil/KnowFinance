import '../models/category.dart';
import '../models/entry.dart';
import '../models/enums.dart';
import 'analytics.dart';

/// Someone money came from or went to, with their bank when alerts showed it.
class Contact {
  Contact(this.key, this.name);

  final String key;
  final String name;
  double sent = 0;
  double received = 0;
  int sentCount = 0;
  int receivedCount = 0;
  final Map<String, int> _banks = {};

  int get count => sentCount + receivedCount;
  double get total => sent + received;

  /// Money went both ways, so this is someone the user deals with rather
  /// than a shop or an employer.
  bool get twoWay => sentCount > 0 && receivedCount > 0;

  /// The bank seen most often for them.
  String? get bank => _banks.isEmpty ? null : (_banks.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

  void _add(Entry e) {
    if (e.kind == EntryKind.income) {
      received += e.homeAmount!;
      receivedCount++;
    } else {
      sent += e.homeAmount!;
      sentCount++;
    }
    final b = e.counterpartyBank;
    if (b != null) _banks[b] = (_banks[b] ?? 0) + 1;
  }
}

/// What share of a total one bank, channel or category has.
class Portion {
  const Portion(this.label, this.total, this.of, {this.count = 0});

  final String label;
  final double total;
  final double of;
  final int count;

  double get pct => of <= 0 ? 0 : total / of * 100;
}

/// Raast transfers in the window.
class RaastSummary {
  const RaastSummary({
    required this.sent,
    required this.sentCount,
    required this.received,
    required this.receivedCount,
    required this.contacts,
    required this.newContacts,
    required this.byWeekday,
    required this.byHour,
    required this.timed,
  });

  final double sent;
  final int sentCount;
  final double received;
  final int receivedCount;

  /// Everyone sent to or received from, most transfers first.
  final List<Contact> contacts;

  /// Of [contacts], the keys of those with no Raast transfer before the window.
  final Set<String> newContacts;

  /// Transfers on each weekday, Monday first.
  final List<int> byWeekday;

  /// Transfers in each hour of the day, for the [timed] ones.
  final List<int> byHour;
  final int timed;

  int get count => sentCount + receivedCount;
  int get repeatCount => contacts.length - newContacts.length;

  /// The closest contacts: two-way ones first, then by how often.
  List<Contact> get innerCircle =>
      ([...contacts]..sort((a, b) => a.twoWay != b.twoWay ? (a.twoWay ? -1 : 1) : b.count.compareTo(a.count))).take(5).toList();

  /// Raast money sent and received through each bank or wallet the
  /// circle uses, most first; [Portion.count] is how many people use it.
  List<Portion> get circleBanks {
    final by = <String, (double, int)>{};
    for (final c in contacts) {
      final b = c.bank ?? 'Bank not shown';
      final (t, n) = by[b] ?? (0, 0);
      by[b] = (t + c.total, n + 1);
    }
    return [
      for (final MapEntry(:key, :value) in by.entries) Portion(key, value.$1, sent + received, count: value.$2),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }
}

/// The "last 30 days" snapshot: who pays the user, where it goes, how long
/// it stays, which banks matter and how Raast is used.
///
/// [all] should reach back before the window: holding time follows money
/// from when it arrived, and new Raast contacts are told from returning
/// ones by earlier transfers. Loans are included, since they move money
/// through the same accounts, but left out of income and spending.
class MoneyInsights {
  MoneyInsights(List<Entry> all, this.categories, this.home, {required DateTime end, this.days = 30})
      : end = DateTime(end.year, end.month, end.day),
        start = DateTime(end.year, end.month, end.day - (days - 1)),
        _all = all.where((e) => e.homeCurrency == home && e.fxRate != null).toList()
          ..sort((a, b) {
            final d = a.date.compareTo(b.date);
            if (d != 0) return d;
            // Money arrives before it is spent on the same day.
            if (a.kind != b.kind) return a.kind == EntryKind.income ? -1 : 1;
            return (a.minuteOfDay ?? 0).compareTo(b.minuteOfDay ?? 0);
          });

  final Map<int, Category> categories;
  final String home;
  final int days;
  final DateTime start;
  final DateTime end;
  final List<Entry> _all;

  bool _inWindow(Entry e) => !e.date.isBefore(start) && !e.date.isAfter(end);

  /// Every entry in the window, loans included.
  late final List<Entry> window = _all.where(_inWindow).toList();

  late final List<Entry> _income = window.where((e) => !e.isLoan && e.kind == EntryKind.income).toList();
  late final List<Entry> _spending = window.where((e) => !e.isLoan && e.kind == EntryKind.expense).toList();

  double get income => _sum(_income);
  double get spending => _sum(_spending);

  static double _sum(Iterable<Entry> list) => list.fold(0, (a, e) => a + e.homeAmount!);

  /// The name to group by: who the alert named, or the note for entries
  /// typed in by hand.
  static String nameOf(Entry e) => (e.counterparty.trim().isNotEmpty ? e.counterparty : e.note).trim();

  static List<Contact> _contacts(Iterable<Entry> list) {
    final map = <String, Contact>{};
    for (final e in list) {
      final name = nameOf(e);
      final key = normalizeNote(name);
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => Contact(key, name))._add(e);
    }
    return map.values.toList();
  }

  /// Who sent the most money, largest first.
  List<Contact> topSenders() => _contacts(_income)..sort((a, b) => b.received.compareTo(a.received));

  /// Spending by type, largest first.
  List<Portion> spendingByType() {
    final total = spending;
    final by = <int, (double, int)>{};
    for (final e in _spending) {
      final (t, n) = by[e.categoryId] ?? (0, 0);
      by[e.categoryId] = (t + e.homeAmount!, n + 1);
    }
    return [
      for (final MapEntry(:key, :value) in by.entries)
        Portion(categories[key]?.name ?? 'Unknown', value.$1, total, count: value.$2),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  /// How many days it takes spending to catch up with money that comes in:
  /// for each income from the 30 days before the window to its end, the
  /// days until spending since it arrived adds up to its amount. Weighted
  /// by amount; income not yet matched by spending isn't counted. Null with
  /// nothing to measure.
  ({double avgDays, double withinWeekPct})? holdingTime() {
    final flows = _all.where((e) => !e.isLoan).toList();
    final from = DateTime(start.year, start.month, start.day - days);
    double weighted = 0, measured = 0, withinWeek = 0;
    for (var i = 0; i < flows.length; i++) {
      final e = flows[i];
      if (e.kind != EntryKind.income || e.date.isBefore(from) || e.date.isAfter(end)) continue;
      var spent = 0.0;
      for (final x in flows.skip(i + 1)) {
        if (x.date.isAfter(end)) break;
        if (x.kind != EntryKind.expense) continue;
        spent += x.homeAmount!;
        if (spent >= e.homeAmount!) {
          final held = x.date.difference(e.date).inDays;
          weighted += e.homeAmount! * held;
          measured += e.homeAmount!;
          if (held <= 7) withinWeek += e.homeAmount!;
          break;
        }
      }
    }
    if (measured <= 0) return null;
    return (avgDays: weighted / measured, withinWeekPct: withinWeek / measured * 100);
  }

  /// Income by the bank it arrived in, largest first. The first one's
  /// share is how much the user depends on that bank.
  List<Portion> incomeByBank() => _byBank(_income, (e) => e.homeAmount!, income);

  /// Transactions of every kind by bank: the bank used most is the user's
  /// real financial home, whichever one their salary lands in.
  List<Portion> activityByBank() => _byBank(window, (_) => 1, window.length.toDouble());

  static List<Portion> _byBank(Iterable<Entry> list, double Function(Entry) measure, double of) {
    final by = <String, (double, int)>{};
    for (final e in list) {
      final b = e.bank;
      if (b == null) continue;
      final (t, n) = by[b] ?? (0, 0);
      by[b] = (t + measure(e), n + 1);
    }
    return [
      for (final MapEntry(:key, :value) in by.entries) Portion(key, value.$1, of, count: value.$2),
    ]..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Spending by how it was paid: digital (Raast, transfers, cards,
  /// wallets) against cash (ATM withdrawals and cash). [unknown] is
  /// spending with no channel, typed in without one.
  ({double digital, double cash, double unknown}) moneyStyle() {
    double digital = 0, cash = 0, unknown = 0;
    for (final e in _spending) {
      final c = e.channel;
      if (c == null) {
        unknown += e.homeAmount!;
      } else if (c.isCash) {
        cash += e.homeAmount!;
      } else {
        digital += e.homeAmount!;
      }
    }
    return (digital: digital, cash: cash, unknown: unknown);
  }

  RaastSummary raast() {
    final raast = window.where((e) => e.channel == PayChannel.raast).toList();
    final contacts = _contacts(raast)..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : b.total.compareTo(a.total));
    final before = {
      for (final e in _all)
        if (e.channel == PayChannel.raast && e.date.isBefore(start)) normalizeNote(nameOf(e)),
    };
    final weekdays = List.filled(7, 0), hours = List.filled(24, 0);
    var timed = 0;
    for (final e in raast) {
      weekdays[e.date.weekday - 1]++;
      if (e.minuteOfDay != null) {
        hours[e.minuteOfDay! ~/ 60]++;
        timed++;
      }
    }
    final sent = raast.where((e) => e.kind == EntryKind.expense), received = raast.where((e) => e.kind == EntryKind.income);
    return RaastSummary(
      sent: _sum(sent),
      sentCount: sent.length,
      received: _sum(received),
      receivedCount: received.length,
      contacts: contacts,
      newContacts: {for (final c in contacts) if (!before.contains(c.key)) c.key},
      byWeekday: weekdays,
      byHour: hours,
      timed: timed,
    );
  }
}
