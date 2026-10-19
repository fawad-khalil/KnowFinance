import 'dart:math' as math;

import 'enums.dart';

/// Preset date ranges offered by the filter bar.
enum DatePreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3Months('Last 3 months'),
  thisYear('This year'),
  allTime('All time'),
  custom('Custom');

  const DatePreset(this.label);
  final String label;
}

class DateRange {
  const DateRange(this.start, this.end);

  /// Both ends inclusive, at day precision. Null means unbounded.
  final DateTime? start;
  final DateTime? end;

  static DateRange forPreset(DatePreset preset, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (preset) {
      case DatePreset.thisMonth:
        return DateRange(DateTime(n.year, n.month), today);
      case DatePreset.lastMonth:
        return DateRange(
          DateTime(n.year, n.month - 1),
          DateTime(n.year, n.month, 0),
        );
      case DatePreset.last3Months:
        return DateRange(DateTime(n.year, n.month - 2), today);
      case DatePreset.thisYear:
        return DateRange(DateTime(n.year), today);
      case DatePreset.allTime:
      case DatePreset.custom:
        return const DateRange(null, null);
    }
  }

  /// The span just before this one, for "vs previous period" figures. A
  /// range starting on the 1st moves back by whole months, so "this month so
  /// far" compares with the same days of last month. Null when unbounded.
  DateRange? previous() {
    final s = start, e = end;
    if (s == null || e == null) return null;
    if (s.day == 1) {
      final months = (e.year - s.year) * 12 + e.month - s.month + 1;
      final monthEnd = DateTime(e.year, e.month + 1, 0).day == e.day;
      final lastDay = DateTime(e.year, e.month - months + 1, 0).day;
      return DateRange(
        DateTime(s.year, s.month - months),
        DateTime(e.year, e.month - months, monthEnd ? lastDay : math.min(e.day, lastDay)),
      );
    }
    final days = e.difference(s).inDays + 1;
    return DateRange(DateTime(s.year, s.month, s.day - days), DateTime(s.year, s.month, s.day - 1));
  }
}

class EntryFilter {
  const EntryFilter({
    this.preset = DatePreset.thisMonth,
    this.range,
    this.kind,
    this.bucket,
    this.categoryId,
    this.noteQuery = '',
  });

  final DatePreset preset;

  /// Only used when [preset] is [DatePreset.custom].
  final DateRange? range;
  final EntryKind? kind;
  final Bucket? bucket;
  final int? categoryId;

  /// Case-insensitive substring match on the note.
  final String noteQuery;

  DateRange effectiveRange({DateTime? now}) => preset == DatePreset.custom
      ? (range ?? const DateRange(null, null))
      : DateRange.forPreset(preset, now: now);

  EntryFilter copyWith({
    DatePreset? preset,
    DateRange? range,
    EntryKind? Function()? kind,
    Bucket? Function()? bucket,
    int? Function()? categoryId,
    String? noteQuery,
  }) =>
      EntryFilter(
        preset: preset ?? this.preset,
        range: range ?? this.range,
        kind: kind != null ? kind() : this.kind,
        bucket: bucket != null ? bucket() : this.bucket,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        noteQuery: noteQuery ?? this.noteQuery,
      );
}
