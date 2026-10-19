import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/category.dart';
import '../models/enums.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 2;

  /// Opens the on-device database. [factory] and [path] let tests use an
  /// in-memory database through sqflite_common_ffi.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'knowfinance.db');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        bucket TEXT,
        archived INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        home_currency TEXT NOT NULL,
        fx_rate REAL,
        category_id INTEGER NOT NULL REFERENCES categories(id),
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'manual'
      )''');
    await db.execute('CREATE INDEX entries_date ON entries(date)');
    await db.execute('''
      CREATE TABLE fx_rates (
        date TEXT NOT NULL,
        from_currency TEXT NOT NULL,
        to_currency TEXT NOT NULL,
        rate REAL NOT NULL,
        PRIMARY KEY (date, from_currency, to_currency)
      )''');

    await _createImports(db);

    final batch = db.batch();
    for (final c in defaultCategories) {
      batch.insert('categories', c.toMap()..remove('id'));
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _createImports(db);
  }

  /// Transactions read from SMS, email or statements wait here until the
  /// user accepts or ignores them. The unique fingerprint stops the same
  /// message being imported twice.
  static Future<void> _createImports(Database db) async {
    await db.execute('''
      CREATE TABLE imports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint TEXT NOT NULL UNIQUE,
        source TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        date TEXT NOT NULL,
        counterparty TEXT NOT NULL DEFAULT '',
        bank TEXT,
        raw TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        entry_id INTEGER REFERENCES entries(id) ON DELETE SET NULL
      )''');
    await db.execute('CREATE INDEX imports_status ON imports(status)');
  }

  Future<void> close() => db.close();
}

const defaultCategories = <Category>[
  Category(name: 'Salary', kind: EntryKind.income),
  Category(name: 'Business', kind: EntryKind.income),
  Category(name: 'Freelance', kind: EntryKind.income),
  Category(name: 'Rental', kind: EntryKind.income),
  Category(name: 'Remittance', kind: EntryKind.income),
  Category(name: 'Profit & dividends', kind: EntryKind.income),
  Category(name: 'Other income', kind: EntryKind.income),
  Category(name: 'Rent', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Groceries', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Utilities', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Fuel & transport', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Health', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Education', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Mobile & internet', kind: EntryKind.expense, bucket: Bucket.needs),
  Category(name: 'Dining out', kind: EntryKind.expense, bucket: Bucket.wants),
  Category(name: 'Shopping', kind: EntryKind.expense, bucket: Bucket.wants),
  Category(name: 'Entertainment', kind: EntryKind.expense, bucket: Bucket.wants),
  Category(name: 'Travel', kind: EntryKind.expense, bucket: Bucket.wants),
  Category(name: 'Subscriptions', kind: EntryKind.expense, bucket: Bucket.wants),
  Category(name: 'Savings deposit', kind: EntryKind.expense, bucket: Bucket.savings),
  Category(name: 'Investments', kind: EntryKind.expense, bucket: Bucket.savings),
  Category(name: 'Committee (BC)', kind: EntryKind.expense, bucket: Bucket.savings),
];
