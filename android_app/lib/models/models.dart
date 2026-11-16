/// Data classes. Field names match the columns of the PC server's database.

class Expense {
  const Expense({
    this.id,
    required this.date,
    required this.amount,
    required this.category,
    this.subcategory = '',
    this.note = '',
    required this.currency,
  });

  final int? id;
  final String date; // YYYY-MM-DD
  final double amount;
  final String category;
  final String subcategory;
  final String note;
  final String currency;

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: m['id'] as int?,
        date: m['date'] as String,
        amount: (m['amount'] as num).toDouble(),
        category: m['category'] as String,
        subcategory: (m['subcategory'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        currency: m['currency'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'amount': amount,
        'category': category,
        'subcategory': subcategory,
        'note': note,
        'currency': currency,
      };
}

/// Result of adding or updating an expense.
class SaveResult {
  const SaveResult(this.id, this.warnings);
  final int id;
  final List<String> warnings;
}

class CategoryTotal {
  const CategoryTotal(this.category, this.currency, this.total);
  final String category;
  final String currency;
  final double total;
}

class MonthlyTotal {
  const MonthlyTotal(this.month, this.category, this.currency, this.total);
  final String month; // YYYY-MM
  final String category;
  final String currency;
  final double total;
}

class BudgetItem {
  const BudgetItem({
    required this.category,
    required this.subcategory,
    required this.currency,
    required this.monthlyLimit,
  });

  /// '*' means the overall budget for all spending.
  final String category;
  final String subcategory;
  final String currency;
  final double monthlyLimit;

  bool get isOverall => category == '*';

  String get label {
    if (isOverall) return 'Overall spending';
    return subcategory.isEmpty ? category : '$category / $subcategory';
  }
}

enum BudgetState { ok, warning, over }

class BudgetStatus {
  const BudgetStatus(this.budget, this.spent, this.state);
  final BudgetItem budget;
  final double spent;
  final BudgetState state;

  double get remaining => budget.monthlyLimit - spent;
  double get fractionUsed =>
      budget.monthlyLimit == 0 ? 0 : spent / budget.monthlyLimit;
}
