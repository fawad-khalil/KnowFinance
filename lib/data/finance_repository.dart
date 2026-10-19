import 'package:sqflite/sqflite.dart';

import '../models/category.dart';
import '../models/entry.dart';
import '../models/entry_filter.dart';
import '../models/enums.dart';
import 'app_database.dart';

class FinanceRepository {
  FinanceRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  // Categories

  Future<List<Category>> categories({EntryKind? kind, bool includeArchived = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (!includeArchived) where.add('archived = 0');
    final rows = await _db.query(
      'categories',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'kind, bucket, name COLLATE NOCASE',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<int> saveCategory(Category c) async {
    final map = c.toMap()..remove('id');
    if (c.id == null) return _db.insert('categories', map);
    await _db.update('categories', map, where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  /// Categories still used by entries are archived instead of deleted so
  /// history keeps its labels.
  Future<void> deleteCategory(int id) async {
    final used = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM entries WHERE category_id = ?',
          [id],
        )) ??
        0;
    if (used > 0) {
      await _db.update('categories', {'archived': 1}, where: 'id = ?', whereArgs: [id]);
    } else {
      await _db.delete('categories', where: 'id = ?', whereArgs: [id]);
    }
  }

  // Entries

  Future<int> saveEntry(Entry e) async {
    final map = e.toMap()..remove('id');
    if (e.id == null) return _db.insert('entries', map);
    await _db.update('entries', map, where: 'id = ?', whereArgs: [e.id]);
    return e.id!;
  }

  Future<void> deleteEntry(int id) =>
      _db.delete('entries', where: 'id = ?', whereArgs: [id]);

  Future<List<Entry>> entries(EntryFilter filter, {DateTime? now}) async {
    final where = <String>[];
    final args = <Object?>[];
    final range = filter.effectiveRange(now: now);
    if (range.start != null) {
      where.add('e.date >= ?');
      args.add(dateKey(range.start!));
    }
    if (range.end != null) {
      where.add('e.date <= ?');
      args.add(dateKey(range.end!));
    }
    if (filter.kind != null) {
      where.add('e.kind = ?');
      args.add(filter.kind!.name);
    }
    if (filter.bucket != null) {
      where.add('c.bucket = ?');
      args.add(filter.bucket!.name);
    }
    if (filter.categoryId != null) {
      where.add('e.category_id = ?');
      args.add(filter.categoryId);
    }
    final q = filter.noteQuery.trim();
    if (q.isNotEmpty) {
      // instr + lower keeps the match case-insensitive without LIKE's
      // wildcard characters getting in the way.
      where.add('instr(lower(e.note), ?) > 0');
      args.add(q.toLowerCase());
    }
    final rows = await _db.rawQuery(
      'SELECT e.* FROM entries e JOIN categories c ON c.id = e.category_id'
      '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
      ' ORDER BY e.date DESC, e.id DESC',
      args,
    );
    return rows.map(Entry.fromMap).toList();
  }

  Future<List<Entry>> entriesNeedingRate(String homeCurrency) async {
    final rows = await _db.query(
      'entries',
      where: 'fx_rate IS NULL OR home_currency != ?',
      whereArgs: [homeCurrency],
    );
    return rows.map(Entry.fromMap).toList();
  }

  /// Distinct non-empty notes, for autocomplete while typing.
  Future<List<String>> recentNotes({int limit = 50}) async {
    final rows = await _db.rawQuery(
      "SELECT note FROM entries WHERE note != '' GROUP BY lower(note)"
      ' ORDER BY MAX(date) DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['note'] as String).toList();
  }

  // Cached exchange rates

  Future<double?> cachedRate(String date, String from, String to) async {
    final rows = await _db.query(
      'fx_rates',
      columns: ['rate'],
      where: 'date = ? AND from_currency = ? AND to_currency = ?',
      whereArgs: [date, from, to],
    );
    return rows.isEmpty ? null : (rows.first['rate'] as num).toDouble();
  }

  Future<void> cacheRate(String date, String from, String to, double rate) =>
      _db.insert(
        'fx_rates',
        {'date': date, 'from_currency': from, 'to_currency': to, 'rate': rate},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
