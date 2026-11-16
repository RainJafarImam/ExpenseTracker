import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../services/backup.dart';
import '../services/currency.dart';
import 'database.dart';
import 'expense_repository.dart';

/// Holds the open database and repository. Screens listen to it and refresh
/// whenever data changes (call [changed] after any write).
class AppState extends ChangeNotifier {
  AppState._(this._db, this.categories) {
    repo = ExpenseRepository(_db, categories);
  }

  Database _db;
  late ExpenseRepository repo;
  final CategoryMap categories;

  Database get db => _db;

  static Future<AppState> create() async {
    final categories = await loadCategories();
    final db = await openAppDatabase();
    final state = AppState._(db, categories);
    await state._firstRunSetup();
    return state;
  }

  /// Home currency from the phone's region, and a starting point for the
  /// 30-day backup reminder. Does nothing for values that already exist
  /// (for example after a restore).
  Future<void> _firstRunSetup() async {
    await repo.initHomeCurrency(detectHomeCurrency());
    if (await repo.getSetting('last_backup') == null) {
      await repo.setSetting('last_backup', DateTime.now().toIso8601String());
    }
  }

  void changed() => notifyListeners();

  /// Restores a backup file. Saves a safety copy of the current data first.
  /// Returns the path of the safety copy.
  Future<String> restoreFrom(String backupPath) async {
    final safety = await createSafetyCopy(_db);
    await _db.close();
    try {
      await replaceDatabaseFile(backupPath);
    } finally {
      // Always reopen, even if the copy failed, so the app keeps working.
      _db = await openAppDatabase();
      repo = ExpenseRepository(_db, categories);
      await _firstRunSetup();
      notifyListeners();
    }
    return safety;
  }
}
