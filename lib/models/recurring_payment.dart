import 'entry.dart';

enum RepeatUnit {
  week('week', 'weekly'),
  month('month', 'monthly'),
  year('year', 'yearly');

  const RepeatUnit(this.label, this.adverb);
  final String label;
  final String adverb;
}

/// A bill, rent, fee or subscription paid on a schedule. Each due date is
/// logged as an expense: on its own when [autoPost] is set, otherwise when
/// the user marks it paid. What falls due in a month is budgeted for it.
class RecurringPayment {
  const RecurringPayment({
    this.id,
    required this.name,
    required this.categoryId,
    required this.amount,
    required this.currency,
    this.every = 1,
    this.unit = RepeatUnit.month,
    required this.startDate,
    this.endDate,
    this.autoPost = true,
    this.paused = false,
    required this.createdOn,
  });

  final int? id;
  final String name;
  final int categoryId;

  /// The usual amount; bills that vary can be corrected on the entry.
  final double amount;
  final String currency;

  /// Repeats every [every] [unit]s from [startDate], until [endDate] if set.
  final int every;
  final RepeatUnit unit;
  final DateTime startDate;
  final DateTime? endDate;

  final bool autoPost;
  final bool paused;

  /// Due dates before this were before the payment was set up, so they are
  /// neither posted nor shown as missed; the user logged them already.
  final DateTime createdOn;

  String get scheduleLabel => every == 1 ? unit.adverb[0].toUpperCase() + unit.adverb.substring(1) : 'Every $every ${unit.label}s';

  /// The [n]th due date (0 is [startDate]). Monthly and yearly dates keep
  /// the start's day, or the month's last day when it is shorter.
  DateTime occurrence(int n) {
    final s = startDate;
    if (unit == RepeatUnit.week) return DateTime(s.year, s.month, s.day + 7 * every * n);
    final months = (unit == RepeatUnit.year ? 12 : 1) * every * n;
    final last = DateTime(s.year, s.month + months + 1, 0).day;
    return DateTime(s.year, s.month + months, s.day > last ? last : s.day);
  }

  /// Due dates from [from] to [to], both inclusive.
  List<DateTime> dueDates(DateTime from, DateTime to) {
    final out = <DateTime>[];
    final end = endDate != null && endDate!.isBefore(to) ? endDate! : to;
    if (end.isBefore(startDate)) return out;
    // Skip ahead roughly instead of stepping from the start every time.
    var n = 0;
    if (from.isAfter(startDate)) {
      final days = from.difference(startDate).inDays;
      final step = switch (unit) { RepeatUnit.week => 7, RepeatUnit.month => 31, RepeatUnit.year => 366 } * every;
      n = (days ~/ step - 1).clamp(0, days);
    }
    for (;; n++) {
      final d = occurrence(n);
      if (d.isAfter(end)) break;
      if (!d.isBefore(from)) out.add(d);
    }
    return out;
  }

  RecurringPayment copyWith({
    String? name,
    int? categoryId,
    double? amount,
    String? currency,
    int? every,
    RepeatUnit? unit,
    DateTime? startDate,
    DateTime? Function()? endDate,
    bool? autoPost,
    bool? paused,
  }) =>
      RecurringPayment(
        id: id,
        name: name ?? this.name,
        categoryId: categoryId ?? this.categoryId,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        every: every ?? this.every,
        unit: unit ?? this.unit,
        startDate: startDate ?? this.startDate,
        endDate: endDate != null ? endDate() : this.endDate,
        autoPost: autoPost ?? this.autoPost,
        paused: paused ?? this.paused,
        createdOn: createdOn,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category_id': categoryId,
        'amount': amount,
        'currency': currency,
        'every': every,
        'unit': unit.name,
        'start_date': dateKey(startDate),
        'end_date': endDate == null ? null : dateKey(endDate!),
        'auto_post': autoPost ? 1 : 0,
        'paused': paused ? 1 : 0,
        'created_on': dateKey(createdOn),
      };

  factory RecurringPayment.fromMap(Map<String, Object?> m) => RecurringPayment(
        id: m['id'] as int,
        name: m['name'] as String,
        categoryId: m['category_id'] as int,
        amount: (m['amount'] as num).toDouble(),
        currency: m['currency'] as String,
        every: m['every'] as int,
        unit: RepeatUnit.values.byName(m['unit'] as String),
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: m['end_date'] == null ? null : DateTime.parse(m['end_date'] as String),
        autoPost: (m['auto_post'] as int) == 1,
        paused: (m['paused'] as int) == 1,
        createdOn: DateTime.parse(m['created_on'] as String),
      );
}

/// What happened to one due date: paid (with the entry logged for it, which
/// may since have been deleted) or skipped.
class RecurringPost {
  const RecurringPost({required this.recurringId, required this.due, this.entryId, this.skipped = false});

  final int recurringId;
  final DateTime due;
  final int? entryId;
  final bool skipped;

  factory RecurringPost.fromMap(Map<String, Object?> m) => RecurringPost(
        recurringId: m['recurring_id'] as int,
        due: DateTime.parse(m['due'] as String),
        entryId: m['entry_id'] as int?,
        skipped: m['status'] == 'skipped',
      );
}
