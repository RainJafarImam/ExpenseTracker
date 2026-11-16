// Run with: flutter test
//
// These tests run the real repository on a desktop SQLite (sqflite_common_ffi).
// If they fail with "sqlite3.dll not found" on Windows, install SQLite for
// desktop or run the app on a phone/emulator instead.

import 'dart:io';

import 'package:expense_tracker/data/database.dart';
import 'package:expense_tracker/data/expense_repository.dart';
import 'package:expense_tracker/data/validation.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const categories = {
    'food': ['dining_out', 'snacks', 'other'],
    'shopping': ['other'],
  };

  late Database db;
  late ExpenseRepository repo;

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = ExpenseRepository(db, categories);
    await repo.initHomeCurrency('INR');
  });

  tearDown(() async => db.close());

  group('validation', () {
    test('rejects impossible dates, bad amounts and bad currencies', () {
      expect(() => repo.addExpense(date: '2026-02-30', amount: 5, category: 'food'),
          throwsA(isA<ValidationException>()));
      expect(() => repo.addExpense(date: '15-11-2026', amount: 5, category: 'food'),
          throwsA(isA<ValidationException>()));
      expect(() => repo.addExpense(date: '2026-03-05', amount: -5, category: 'food'),
          throwsA(isA<ValidationException>()));
      expect(() => repo.addExpense(date: '2026-03-05', amount: 0, category: 'food'),
          throwsA(isA<ValidationException>()));
      expect(() => repo.addExpense(date: '2026-03-05', amount: 1e15, category: 'food'),
          throwsA(isA<ValidationException>()));
      expect(
          () => repo.addExpense(
              date: '2026-03-05', amount: 5, category: 'food', currency: 'RUPEES'),
          throwsA(isA<ValidationException>()));
      expect(() => repo.listExpenses('2026-03-05', '2026-03-01'),
          throwsA(isA<ValidationException>()));
    });

    test('normalises dates and uses the home currency by default', () async {
      await repo.addExpense(date: '2026-3-5', amount: 10, category: 'food');
      final rows = await repo.listExpenses('2026-03-01', '2026-03-31');
      expect(rows.single.date, '2026-03-05');
      expect(rows.single.currency, 'INR');
    });
  });

  group('expenses', () {
    test('add, update, delete, restore', () async {
      final added = await repo.addExpense(
          date: '2026-03-05', amount: 40, category: 'food', subcategory: 'snacks');
      await repo.updateExpense(added.id, amount: 55, note: 'chips');
      var rows = await repo.listExpenses('2026-03-01', '2026-03-31');
      expect(rows.single.amount, 55);
      expect(rows.single.note, 'chips');
      expect(rows.single.subcategory, 'snacks'); // untouched field kept

      expect(await repo.deleteExpense(added.id), isTrue);
      expect(await repo.deleteExpense(added.id), isFalse);
      await repo.restoreExpense(rows.single);
      rows = await repo.listExpenses('2026-03-01', '2026-03-31');
      expect(rows.single.id, added.id);
    });

    test('unknown category is saved with a warning', () async {
      final r = await repo.addExpense(
          date: '2026-03-05', amount: 10, category: 'spaceships');
      expect(r.warnings.single, contains('spaceships'));
    });
  });

  group('reports', () {
    test('totals are never mixed across currencies', () async {
      await repo.addExpense(date: '2026-11-15', amount: 100, category: 'food');
      await repo.addExpense(
          date: '2026-11-15', amount: 5, category: 'food', currency: 'USD');
      final monthly = await repo.monthlySummary(2026, month: 11);
      expect(monthly.length, 2);
      expect(monthly.firstWhere((t) => t.currency == 'INR').total, 100);
      expect(monthly.firstWhere((t) => t.currency == 'USD').total, 5);

      final range = await repo.summarize('2026-11-01', '2026-11-30');
      expect(range.length, 2);
    });

    test('csv has the same columns as the PC version and quotes commas', () async {
      await repo.addExpense(
          date: '2026-03-05',
          amount: 120,
          category: 'food',
          subcategory: 'dining_out',
          note: 'Lunch, with "friends"');
      final csv = await repo.exportCsv('2026-03-01', '2026-03-31');
      final lines = csv.trim().split('\n');
      expect(lines.first, 'id,date,amount,currency,category,subcategory,note');
      expect(lines[1], '1,2026-03-05,120.0,INR,food,dining_out,"Lunch, with ""friends"""');
    });
  });

  group('budgets', () {
    test('overall, category and subcategory budgets raise warnings', () async {
      await repo.setBudget(1000); // overall
      await repo.setBudget(500, category: 'food', subcategory: 'dining_out');

      var r = await repo.addExpense(
          date: '2026-03-05',
          amount: 900,
          category: 'shopping',
          subcategory: 'other');
      expect(r.warnings.single, contains('overall spending')); // 90% used

      r = await repo.addExpense(
          date: '2026-03-06',
          amount: 600,
          category: 'food',
          subcategory: 'dining_out');
      expect(r.warnings.any((w) => w.contains('Over budget for overall spending')), isTrue);
      expect(r.warnings.any((w) => w.contains('Over budget for food / dining_out')), isTrue);

      final status = await repo.budgetStatus('2026-03');
      expect(status.first.budget.isOverall, isTrue); // overall is listed first
      expect(status.every((s) => s.state == BudgetState.over), isTrue);
    });

    test('budget scope rules', () async {
      expect(() => repo.setBudget(100, subcategory: 'dining_out'),
          throwsA(isA<ValidationException>()));
      expect(() => repo.setBudget(100, category: '*'),
          throwsA(isA<ValidationException>()));
      final b = await repo.setBudget(100, category: 'food');
      expect(await repo.deleteBudget(b), isTrue);
      expect(await repo.deleteBudget(b), isFalse);
    });

    test('budgets are per currency', () async {
      await repo.setBudget(100); // INR
      final r = await repo.addExpense(
          date: '2026-03-05', amount: 500, category: 'food', currency: 'USD');
      expect(r.warnings, isEmpty);
    });
  });

  group('database files', () {
    test('a database copied from the PC server keeps its data', () async {
      final dir = Directory.systemTemp.createTempSync('expense_test_');
      final path = p.join(dir.path, 'pc.db');
      try {
        // Build a database exactly like the PC server leaves it:
        // no PRAGMA user_version, no settings or budgets rows yet.
        final pc = await databaseFactoryFfi.openDatabase(path);
        await pc.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL, amount REAL NOT NULL, category TEXT NOT NULL,
            subcategory TEXT DEFAULT '', note TEXT DEFAULT '',
            currency TEXT NOT NULL DEFAULT 'INR')
        ''');
        await pc.insert('expenses', {
          'date': '2026-03-03',
          'amount': 40.0,
          'category': 'food',
          'subcategory': 'fruits_vegetables',
          'note': 'bananas',
          'currency': 'INR',
        });
        await pc.close();

        final opened = await openAppDatabase(path: path);
        final repo2 = ExpenseRepository(opened, categories);
        final rows = await repo2.listExpenses('2026-03-01', '2026-03-31');
        expect(rows.single.note, 'bananas');
        expect(await repo2.listBudgets(), isEmpty); // table was added
        expect(await repo2.getHomeCurrency(), 'INR');
        final version =
            (await opened.rawQuery('PRAGMA user_version')).first.values.first;
        expect(version, kSchemaVersion);
        await opened.close();
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
