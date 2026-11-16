import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'validation.dart';

typedef CategoryMap = Map<String, List<String>>;

/// Loads the bundled category list (same file as the PC server).
Future<CategoryMap> loadCategories() async {
  final raw = await rootBundle.loadString('assets/categories.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map(
    (k, v) => MapEntry(k, (v as List<dynamic>).cast<String>()),
  );
}

/// One method per MCP tool of the PC server, using the same SQL and checks.
class ExpenseRepository {
  ExpenseRepository(this.db, this.categories);

  final Database db;
  final CategoryMap categories;

  static const String totalBudget = '*';
  static const double warnRatio = 0.8;

  // --------------------------------------------------------------- settings
  Future<String?> getSetting(String key) async {
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// get_home_currency
  Future<String> getHomeCurrency() async =>
      await getSetting('home_currency') ?? 'INR';

  /// set_home_currency
  Future<String> setHomeCurrency(String code) async {
    final c = checkCurrency(code);
    await setSetting('home_currency', c);
    return c;
  }

  /// First launch: store the currency detected from the phone's region.
  /// Does nothing if a home currency already exists (for example after a
  /// restore).
  Future<void> initHomeCurrency(String detected) async {
    if (await getSetting('home_currency') == null) {
      await setSetting('home_currency', checkCurrency(detected));
    }
  }

  // --------------------------------------------------------------- expenses
  /// add_expense
  Future<SaveResult> addExpense({
    required String date,
    required double amount,
    required String category,
    String subcategory = '',
    String note = '',
    String? currency,
  }) async {
    final d = checkDate(date);
    final a = checkAmount(amount);
    final cat = checkText(category, 'category', required: true);
    final sub = checkText(subcategory, 'subcategory');
    final n = checkText(note, 'note');
    final code = (currency == null || currency.trim().isEmpty)
        ? await getHomeCurrency()
        : checkCurrency(currency);
    final id = await db.insert('expenses', {
      'date': d,
      'amount': a,
      'category': cat,
      'subcategory': sub,
      'note': n,
      'currency': code,
    });
    return SaveResult(id, await _warningsFor(cat, sub, code, d));
  }

  /// update_expense: only the fields you pass are changed.
  Future<SaveResult> updateExpense(
    int id, {
    String? date,
    double? amount,
    String? category,
    String? subcategory,
    String? note,
    String? currency,
  }) async {
    final rows = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw ValidationException('No expense found with id $id');
    final old = Expense.fromMap(rows.first);
    final updated = Expense(
      id: id,
      date: date != null ? checkDate(date) : old.date,
      amount: amount != null ? checkAmount(amount) : old.amount,
      category: category != null
          ? checkText(category, 'category', required: true)
          : old.category,
      subcategory:
          subcategory != null ? checkText(subcategory, 'subcategory') : old.subcategory,
      note: note != null ? checkText(note, 'note') : old.note,
      currency: currency != null ? checkCurrency(currency) : old.currency,
    );
    await db.update('expenses', updated.toMap(), where: 'id = ?', whereArgs: [id]);
    return SaveResult(id,
        await _warningsFor(updated.category, updated.subcategory, updated.currency, updated.date));
  }

  /// delete_expense. Returns false if the id does not exist.
  Future<bool> deleteExpense(int id) async =>
      await db.delete('expenses', where: 'id = ?', whereArgs: [id]) > 0;

  /// Puts a deleted expense back with its old id (used by "Undo").
  Future<void> restoreExpense(Expense e) =>
      db.insert('expenses', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// list_expenses (inclusive date range). Newest first by default.
  Future<List<Expense>> listExpenses(String startDate, String endDate,
      {bool newestFirst = true}) async {
    final (s, e) = checkRange(startDate, endDate);
    final rows = await db.query(
      'expenses',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [s, e],
      orderBy: newestFirst ? 'date DESC, id DESC' : 'date ASC, id ASC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<bool> hasAnyExpense() async {
    final rows = await db.rawQuery('SELECT 1 FROM expenses LIMIT 1');
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------- reports
  /// summarize: totals per category and currency for a date range.
  Future<List<CategoryTotal>> summarize(String startDate, String endDate,
      {String? category}) async {
    final (s, e) = checkRange(startDate, endDate);
    final sql = StringBuffer(
        'SELECT category, currency, SUM(amount) AS total FROM expenses '
        'WHERE date BETWEEN ? AND ?');
    final args = <Object?>[s, e];
    if (category != null && category.isNotEmpty) {
      sql.write(' AND category = ?');
      args.add(category);
    }
    sql.write(' GROUP BY category, currency ORDER BY category ASC, currency ASC');
    final rows = await db.rawQuery(sql.toString(), args);
    return rows
        .map((r) => CategoryTotal(r['category'] as String,
            r['currency'] as String, (r['total'] as num).toDouble()))
        .toList();
  }

  /// monthly_summary: totals per month, category and currency.
  Future<List<MonthlyTotal>> monthlySummary(int year,
      {int? month, String? category}) async {
    if (year < 1900 || year > 2200) {
      throw ValidationException('year must be between 1900 and 2200');
    }
    if (month != null && (month < 1 || month > 12)) {
      throw ValidationException('month must be between 1 and 12');
    }
    final prefix = month != null
        ? '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}'
        : year.toString().padLeft(4, '0');
    final sql = StringBuffer(
        'SELECT substr(date, 1, 7) AS month, category, currency, '
        'SUM(amount) AS total FROM expenses WHERE substr(date, 1, ?) = ?');
    final args = <Object?>[prefix.length, prefix];
    if (category != null && category.isNotEmpty) {
      sql.write(' AND category = ?');
      args.add(category);
    }
    sql.write(' GROUP BY month, category, currency '
        'ORDER BY month ASC, category ASC, currency ASC');
    final rows = await db.rawQuery(sql.toString(), args);
    return rows
        .map((r) => MonthlyTotal(r['month'] as String, r['category'] as String,
            r['currency'] as String, (r['total'] as num).toDouble()))
        .toList();
  }

  /// export_csv: returns the CSV text (header + rows, oldest first).
  Future<String> exportCsv(String startDate, String endDate) async {
    final rows = await listExpenses(startDate, endDate, newestFirst: false);
    return buildCsv(rows);
  }

  static String buildCsv(List<Expense> rows) {
    String esc(String v) => (v.contains(',') ||
            v.contains('"') ||
            v.contains('\n') ||
            v.contains('\r'))
        ? '"${v.replaceAll('"', '""')}"'
        : v;
    final b = StringBuffer('id,date,amount,currency,category,subcategory,note\n');
    for (final e in rows) {
      b.write([
        e.id.toString(),
        e.date,
        e.amount.toString(),
        e.currency,
        esc(e.category),
        esc(e.subcategory),
        esc(e.note),
      ].join(','));
      b.write('\n');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------- budgets
  /// set_budget. Leave [category] empty for the overall budget.
  Future<BudgetItem> setBudget(double monthlyLimit,
      {String? category, String? subcategory, String? currency}) async {
    final limit = checkAmount(monthlyLimit, 'monthly_limit');
    final (cat, sub) = _budgetScope(category, subcategory);
    final code = (currency == null || currency.trim().isEmpty)
        ? await getHomeCurrency()
        : checkCurrency(currency);
    await db.insert(
      'budgets',
      {
        'category': cat,
        'subcategory': sub,
        'currency': code,
        'monthly_limit': limit,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return BudgetItem(
        category: cat, subcategory: sub, currency: code, monthlyLimit: limit);
  }

  /// list_budgets: overall first, then by category.
  Future<List<BudgetItem>> listBudgets() async {
    final rows = await db.rawQuery(
        'SELECT category, subcategory, currency, monthly_limit FROM budgets '
        'ORDER BY (category = ?) DESC, category, subcategory, currency',
        [totalBudget]);
    return rows
        .map((r) => BudgetItem(
              category: r['category'] as String,
              subcategory: r['subcategory'] as String,
              currency: r['currency'] as String,
              monthlyLimit: (r['monthly_limit'] as num).toDouble(),
            ))
        .toList();
  }

  /// delete_budget. Returns false if no such budget exists.
  Future<bool> deleteBudget(BudgetItem b) async =>
      await db.delete(
        'budgets',
        where: 'category = ? AND subcategory = ? AND currency = ?',
        whereArgs: [b.category, b.subcategory, b.currency],
      ) >
      0;

  /// budget_status for a month (YYYY-MM).
  Future<List<BudgetStatus>> budgetStatus(String month) async {
    final m = checkMonth(month);
    final result = <BudgetStatus>[];
    for (final b in await listBudgets()) {
      final spent = await _monthSpent(b.category, b.subcategory, b.currency, m);
      result.add(BudgetStatus(b, spent, _state(spent, b.monthlyLimit)));
    }
    return result;
  }

  (String, String) _budgetScope(String? category, String? subcategory) {
    final cat = (category ?? '').trim();
    final sub = (subcategory ?? '').trim();
    if (cat.isEmpty) {
      if (sub.isNotEmpty) {
        throw ValidationException('A subcategory budget needs a category too');
      }
      return (totalBudget, '');
    }
    if (cat == totalBudget) {
      throw ValidationException('Leave category empty for an overall budget');
    }
    return (cat, sub);
  }

  BudgetState _state(double spent, double limit) {
    if (spent > limit) return BudgetState.over;
    if (spent >= limit * warnRatio) return BudgetState.warning;
    return BudgetState.ok;
  }

  Future<double> _monthSpent(
      String category, String subcategory, String currency, String month) async {
    final sql = StringBuffer(
        'SELECT COALESCE(SUM(amount), 0) AS s FROM expenses '
        'WHERE currency = ? AND substr(date, 1, 7) = ?');
    final args = <Object?>[currency, month];
    if (category != totalBudget) {
      sql.write(' AND category = ?');
      args.add(category);
      if (subcategory.isNotEmpty) {
        sql.write(' AND subcategory = ?');
        args.add(subcategory);
      }
    }
    final rows = await db.rawQuery(sql.toString(), args);
    return (rows.first['s'] as num).toDouble();
  }

  // --------------------------------------------------------------- warnings
  String _g(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Soft check against the category list. Unknown values are accepted.
  String? _categoryWarning(String category, String subcategory) {
    final subs = categories[category];
    if (subs == null) return "category '$category' is not in the category list";
    if (subcategory.isNotEmpty && !subs.contains(subcategory)) {
      return "subcategory '$subcategory' is not listed under '$category'";
    }
    return null;
  }

  Future<List<String>> _warningsFor(
      String category, String subcategory, String currency, String date) async {
    final warnings = <String>[];
    final catWarn = _categoryWarning(category, subcategory);
    if (catWarn != null) warnings.add(catWarn);

    final month = date.substring(0, 7);
    final scopes = <(String, String)>[
      (totalBudget, ''),
      (category, ''),
      if (subcategory.isNotEmpty) (category, subcategory),
    ];
    for (final (cat, sub) in scopes) {
      final rows = await db.query(
        'budgets',
        columns: ['monthly_limit'],
        where: 'category = ? AND subcategory = ? AND currency = ?',
        whereArgs: [cat, sub, currency],
      );
      if (rows.isEmpty) continue;
      final limit = (rows.first['monthly_limit'] as num).toDouble();
      final spent = await _monthSpent(cat, sub, currency, month);
      final label = BudgetItem(
              category: cat, subcategory: sub, currency: currency, monthlyLimit: limit)
          .label
          .toLowerCase();
      switch (_state(spent, limit)) {
        case BudgetState.over:
          warnings.add(
              'Over budget for $label in $month: spent ${_g(spent)} of ${_g(limit)} $currency');
        case BudgetState.warning:
          warnings.add(
              'Close to budget for $label in $month: spent ${_g(spent)} of ${_g(limit)} $currency (${(spent / limit * 100).round()}%)');
        case BudgetState.ok:
          break;
      }
    }
    return warnings;
  }
}
