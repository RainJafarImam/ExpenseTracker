import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Schema version stored in SQLite's PRAGMA user_version.
/// Version 1 = the schema of the PC MCP server (expenses, settings, budgets).
/// Never change version 1. Every future change is a new step in _onUpgrade
/// that keeps user data.
const int kSchemaVersion = 1;
const String kDbFileName = 'expenses.db';

Future<String> appDatabasePath() async =>
    p.join(await getDatabasesPath(), kDbFileName);

/// Opens (and creates or upgrades) the database.
/// Pass [path] for tests (for example inMemoryDatabasePath).
Future<Database> openAppDatabase({String? path}) async {
  final dbPath = path ?? await appDatabasePath();
  return openDatabase(
    dbPath,
    version: kSchemaVersion,
    onCreate: (db, version) => createSchemaV1(db),
    onUpgrade: _onUpgrade,
  );
}

/// IF NOT EXISTS on purpose: a database copied from the PC server has
/// user_version 0, so sqflite calls onCreate on it. Existing tables and data
/// are left untouched; only missing tables are added.
Future<void> createSchemaV1(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS expenses(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL,
      subcategory TEXT DEFAULT '',
      note TEXT DEFAULT '',
      currency TEXT NOT NULL DEFAULT 'INR'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS budgets(
      category TEXT NOT NULL,
      subcategory TEXT NOT NULL DEFAULT '',
      currency TEXT NOT NULL,
      monthly_limit REAL NOT NULL,
      PRIMARY KEY (category, subcategory, currency)
    )
  ''');
}

/// Future schema changes go here, one numbered step at a time, for example:
///   if (oldVersion < 2) { ...migrate 1 -> 2 without dropping data... }
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  // No upgrades yet: version 1 is the first release.
}
