import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../import/alert_parser.dart';
import '../models/category.dart';
import '../models/enums.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 6;

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
    await _createInvestments(db);
    await _addQuantities(db);
    await _addPaymentDetails(db);

    final batch = db.batch();
    for (final c in defaultCategories) {
      batch.insert('categories', c.toMap()..remove('id')..remove('system'));
    }
    await batch.commit(noResult: true);
    // After the defaults, so their ids stay as they were.
    await _createLoans(db);
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _createImports(db);
    if (from < 3) await _createInvestments(db);
    if (from < 4) await _addQuantities(db);
    if (from < 5) await _createLoans(db);
    if (from < 6) {
      await _addPaymentDetails(db);
      await _backfillPaymentDetails(db);
    }
  }

  /// Which bank, who, their bank, how and when: what money insights group
  /// by. Imports keep them until accepted, then they move to the entry.
  static Future<void> _addPaymentDetails(Database db) async {
    for (final col in ['bank TEXT', "counterparty TEXT NOT NULL DEFAULT ''", 'counterparty_bank TEXT', 'channel TEXT', 'minute_of_day INTEGER']) {
      await db.execute('ALTER TABLE entries ADD COLUMN $col');
    }
    for (final col in ['counterparty_bank TEXT', 'channel TEXT', 'minute_of_day INTEGER']) {
      await db.execute('ALTER TABLE imports ADD COLUMN $col');
    }
  }

  /// Reads the alerts already imported again, so their entries get the new
  /// details too.
  static Future<void> _backfillPaymentDetails(Database db) async {
    const parser = AlertParser();
    final rows = await db.query('imports', columns: ['id', 'raw', 'source', 'date', 'counterparty', 'bank', 'entry_id']);
    final batch = db.batch();
    for (final r in rows) {
      final t = parser.parse(r['raw'] as String,
          receivedAt: DateTime.parse(r['date'] as String), source: EntrySource.fromName(r['source'] as String));
      if (t == null) continue;
      final details = {'counterparty_bank': t.counterpartyBank, 'channel': t.channel?.name, 'minute_of_day': t.minuteOfDay};
      batch.update('imports', {...details, 'bank': t.bank ?? r['bank']}, where: 'id = ?', whereArgs: [r['id']]);
      if (r['entry_id'] != null) {
        batch.update('entries', {...details, 'bank': t.bank ?? r['bank'], 'counterparty': r['counterparty']},
            where: 'id = ?', whereArgs: [r['entry_id']]);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Payables and receivables. Loan entries use the app's own "Loan" types
  /// so they never show up as income or spending.
  static Future<void> _createLoans(Database db) async {
    await db.execute('''
      CREATE TABLE loans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        direction TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        due_date TEXT
      )''');
    await db.execute('ALTER TABLE entries ADD COLUMN loan_id INTEGER REFERENCES loans(id) ON DELETE SET NULL');
    await db.execute('CREATE INDEX entries_loan ON entries(loan_id)');
    await db.execute('ALTER TABLE categories ADD COLUMN system TEXT');
    for (final kind in EntryKind.values) {
      await db.insert('categories', {'name': 'Loan', 'kind': kind.name, 'archived': 0, 'system': 'loan'});
    }
  }

  /// Assets counted by amount held (grams, shares, barrels) and priced from
  /// a market feed; entries record how much they bought or sold.
  static Future<void> _addQuantities(Database db) async {
    for (final col in [
      'unit TEXT',
      'price_symbol TEXT',
      'market_price REAL',
      'market_currency TEXT',
      'market_price_on TEXT',
    ]) {
      await db.execute('ALTER TABLE investments ADD COLUMN $col');
    }
    await db.execute('ALTER TABLE entries ADD COLUMN quantity REAL');
  }

  /// Holdings that entries can be linked to, so buys and costs can be set
  /// against sales and dividend or rent income.
  static Future<void> _createInvestments(Database db) async {
    await db.execute('''
      CREATE TABLE investments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        current_value REAL,
        value_currency TEXT,
        valued_on TEXT,
        closed INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('ALTER TABLE entries ADD COLUMN investment_id INTEGER REFERENCES investments(id) ON DELETE SET NULL');
    await db.execute('ALTER TABLE entries ADD COLUMN investment_flow TEXT');
    await db.execute('CREATE INDEX entries_investment ON entries(investment_id)');
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
