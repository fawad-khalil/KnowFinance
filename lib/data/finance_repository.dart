import 'package:sqflite/sqflite.dart';

import '../import/parsed_transaction.dart';
import '../import/pending_import.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/entry.dart';
import '../models/entry_filter.dart';
import '../models/enums.dart';
import '../models/investment.dart';
import '../models/loan.dart';
import '../models/recurring_payment.dart';
import '../services/analytics.dart';
import 'app_database.dart';

class FinanceRepository {
  FinanceRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  // Categories

  Future<List<Category>> categories({EntryKind? kind, bool includeArchived = false, bool includeSystem = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (!includeArchived) where.add('archived = 0');
    if (!includeSystem) where.add('system IS NULL');
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

  // Import inbox

  /// Adds parsed transactions to the inbox, skipping ones already seen.
  /// Returns how many were new.
  Future<int> addImports(Iterable<ParsedTransaction> items) async {
    var added = 0;
    await _db.transaction((txn) async {
      for (final t in items) {
        final id = await txn.insert('imports', PendingImport.toRow(t), conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id > 0) added++;
      }
    });
    return added;
  }

  Future<List<PendingImport>> pendingImports() async {
    final rows = await _db.query('imports', where: "status = 'pending'", orderBy: 'date DESC, id DESC');
    return rows.map(PendingImport.fromMap).toList();
  }

  Future<int> pendingImportCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM imports WHERE status = 'pending'")) ?? 0;

  /// Saves [entry] and marks the import accepted in one transaction.
  Future<void> acceptImport(int importId, Entry entry) => _db.transaction((txn) async {
        final id = await txn.insert('entries', entry.toMap()..remove('id'));
        await txn.update('imports', {'status': 'accepted', 'entry_id': id}, where: 'id = ?', whereArgs: [importId]);
      });

  Future<void> ignoreImport(int importId) =>
      _db.update('imports', {'status': 'ignored'}, where: 'id = ?', whereArgs: [importId]);

  /// Normalized note -> the category most recently used with it, so imports
  /// from a known merchant land in the same type as before.
  Future<Map<String, int>> noteCategoryHistory() async {
    final rows = await _db.query('entries', columns: ['note', 'category_id'], where: "note != ''", orderBy: 'date ASC, id ASC');
    return {for (final r in rows) normalizeNote(r['note'] as String): r['category_id'] as int};
  }

  // Investments

  Future<List<Investment>> investments() async {
    final rows = await _db.query('investments', orderBy: 'closed, name COLLATE NOCASE');
    return rows.map(Investment.fromMap).toList();
  }

  Future<int> saveInvestment(Investment i) async {
    final map = i.toMap()..remove('id');
    if (i.id == null) return _db.insert('investments', map);
    await _db.update('investments', map, where: 'id = ?', whereArgs: [i.id]);
    return i.id!;
  }

  /// Deletes the investment and unlinks its entries; the entries stay.
  Future<void> deleteInvestment(int id) => _db.transaction((txn) async {
        await txn.update('entries', {'investment_id': null, 'investment_flow': null, 'quantity': null},
            where: 'investment_id = ?', whereArgs: [id]);
        await txn.delete('investments', where: 'id = ?', whereArgs: [id]);
      });

  /// Every entry linked to any investment, oldest first.
  Future<List<Entry>> investmentEntries() async {
    final rows = await _db.query('entries', where: 'investment_id IS NOT NULL', orderBy: 'date ASC, id ASC');
    return rows.map(Entry.fromMap).toList();
  }

  /// Entries not linked to an investment that could belong to one:
  /// Savings-bucket expenses and all income, newest first.
  Future<List<Entry>> unlinkedInvestmentCandidates() async {
    final rows = await _db.rawQuery(
      'SELECT e.* FROM entries e JOIN categories c ON c.id = e.category_id'
      " WHERE e.investment_id IS NULL AND (c.bucket = 'savings' OR e.kind = 'income')"
      ' ORDER BY e.date DESC, e.id DESC',
    );
    return rows.map(Entry.fromMap).toList();
  }

  /// Links entries to [investmentId] with the given flows, or unlinks them
  /// when [investmentId] is null.
  /// [quantities] sets how much each entry bought or sold, where known.
  Future<void> linkEntries(int? investmentId, Map<int, InvestmentFlow?> flows, {Map<int, double?> quantities = const {}}) =>
      _db.transaction((txn) async {
        for (final f in flows.entries) {
          await txn.update(
            'entries',
            {
              'investment_id': investmentId,
              'investment_flow': investmentId == null ? null : f.value?.name,
              if (investmentId == null) 'quantity': null,
              if (quantities.containsKey(f.key)) 'quantity': quantities[f.key],
            },
            where: 'id = ?',
            whereArgs: [f.key],
          );
        }
      });

  // Loans

  Future<List<Loan>> loans() async {
    final rows = await _db.query('loans', orderBy: 'name COLLATE NOCASE');
    return rows.map(Loan.fromMap).toList();
  }

  Future<int> saveLoan(Loan l) async {
    final map = l.toMap()..remove('id');
    if (l.id == null) return _db.insert('loans', map);
    await _db.update('loans', map, where: 'id = ?', whereArgs: [l.id]);
    return l.id!;
  }

  /// Deletes the loan. Its entries stay but become plain income and
  /// spending again, so they are left on the "Loan" type to be re-typed.
  Future<void> deleteLoan(int id) => _db.transaction((txn) async {
        await txn.update('entries', {'loan_id': null}, where: 'loan_id = ?', whereArgs: [id]);
        await txn.delete('loans', where: 'id = ?', whereArgs: [id]);
      });

  /// The app's own "Loan" type for entries of [kind].
  Future<int> loanCategoryId(EntryKind kind) async {
    final rows = await _db.query('categories',
        columns: ['id'], where: "system = 'loan' AND kind = ?", whereArgs: [kind.name], limit: 1);
    return rows.first['id'] as int;
  }

  /// Every entry linked to a loan, oldest first.
  Future<List<Entry>> loanEntries() async {
    final rows = await _db.query('entries', where: 'loan_id IS NOT NULL', orderBy: 'date ASC, id ASC');
    return rows.map(Entry.fromMap).toList();
  }

  /// Entries not yet linked to a loan or an investment, newest first, for
  /// picking the ones that belong to a loan.
  Future<List<Entry>> unlinkedLoanCandidates() async {
    final rows = await _db.query('entries',
        where: 'loan_id IS NULL AND investment_id IS NULL', orderBy: 'date DESC, id DESC', limit: 300);
    return rows.map(Entry.fromMap).toList();
  }

  /// Links entries to [loanId] (or unlinks them when null). Linked entries
  /// move to the "Loan" type so they leave income and spending; unlinked
  /// ones keep it until the user picks a type.
  Future<void> linkLoanEntries(int? loanId, Iterable<Entry> entries) async {
    final ids = {for (final k in EntryKind.values) k: await loanCategoryId(k)};
    await _db.transaction((txn) async {
      for (final e in entries) {
        await txn.update(
          'entries',
          {'loan_id': loanId, if (loanId != null) 'category_id': ids[e.kind]},
          where: 'id = ?',
          whereArgs: [e.id],
        );
      }
    });
  }

  // Budgets

  Future<List<Budget>> budgets() async => (await _db.query('budgets')).map(Budget.fromMap).toList();

  /// Sets the monthly budget for [categoryId], or the overall one when it is
  /// null. A null or zero [amount] removes it.
  Future<void> setBudget(int? categoryId, double? amount) => _db.transaction((txn) async {
        await txn.delete('budgets',
            where: categoryId == null ? 'category_id IS NULL' : 'category_id = ?',
            whereArgs: [?categoryId]);
        if (amount != null && amount > 0) {
          await txn.insert('budgets', Budget(categoryId: categoryId, amount: amount).toMap()..remove('id'));
        }
      });

  // Recurring payments

  Future<List<RecurringPayment>> recurringPayments() async {
    final rows = await _db.query('recurring', orderBy: 'paused, name COLLATE NOCASE');
    return rows.map(RecurringPayment.fromMap).toList();
  }

  Future<int> saveRecurring(RecurringPayment r) async {
    final map = r.toMap()..remove('id');
    if (r.id == null) return _db.insert('recurring', map);
    await _db.update('recurring', map, where: 'id = ?', whereArgs: [r.id]);
    return r.id!;
  }

  /// Deletes the payment and its history; entries already logged stay.
  Future<void> deleteRecurring(int id) => _db.delete('recurring', where: 'id = ?', whereArgs: [id]);

  /// Paid and skipped due dates, optionally only those from [from] to [to].
  Future<List<RecurringPost>> recurringPosts({DateTime? from, DateTime? to}) async {
    final rows = await _db.query('recurring_posts',
        where: from == null ? null : 'due >= ? AND due <= ?', whereArgs: from == null ? null : [dateKey(from), dateKey(to!)]);
    return rows.map(RecurringPost.fromMap).toList();
  }

  /// Logs [entry] as the payment due on [due]. Returns the entry's id, or
  /// null when that date was already handled.
  Future<int?> postRecurring(int recurringId, DateTime due, Entry entry) => _db.transaction((txn) async {
        final done = await txn.query('recurring_posts',
            where: 'recurring_id = ? AND due = ?', whereArgs: [recurringId, dateKey(due)]);
        if (done.isNotEmpty) return null;
        final id = await txn.insert('entries', entry.toMap()..remove('id'));
        await txn.insert('recurring_posts', {'recurring_id': recurringId, 'due': dateKey(due), 'entry_id': id});
        return id;
      });

  Future<void> skipRecurring(int recurringId, DateTime due) => _db.insert(
        'recurring_posts',
        {'recurring_id': recurringId, 'due': dateKey(due), 'status': 'skipped'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  /// Forgets what happened on [due], so it shows as due again. The entry
  /// logged for it, if any, stays.
  Future<void> undoRecurringPost(int recurringId, DateTime due) =>
      _db.delete('recurring_posts', where: 'recurring_id = ? AND due = ?', whereArgs: [recurringId, dateKey(due)]);

  /// Removes every entry, asset, loan, import, budget and recurring payment,
  /// keeping types and cached rates. Only offered in debug builds, before loading sample data.
  Future<void> clearAll() => _db.transaction((txn) async {
        for (final t in ['recurring_posts', 'recurring', 'budgets', 'imports', 'entries', 'investments', 'loans']) {
          await txn.delete(t);
        }
      });

  /// Drops inbox records with these fingerprints, whatever their status, so
  /// the same alerts can be imported again. Entries made from them stay.
  Future<void> forgetImports(Iterable<String> fingerprints) => _db.transaction((txn) async {
        for (final f in fingerprints) {
          await txn.delete('imports', where: 'fingerprint = ?', whereArgs: [f]);
        }
      });
}
