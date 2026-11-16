import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/validation.dart';
import '../models/models.dart';
import '../services/currency.dart';
import 'actions.dart';
import 'add_expense.dart';
import 'common.dart';

/// Expenses tab: one month at a time, grouped by day. Tap to edit,
/// swipe to delete (with Undo).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.app});
  final AppState app;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = monthStart(DateTime.now());
  List<Expense>? _items;
  int? _backupDays;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.app.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = widget.app.repo;
    final items =
        await repo.listExpenses(monthStartKey(_month), monthEndKey(_month));
    final days = await daysSinceBackup(widget.app);
    if (!mounted) return;
    setState(() {
      _items = items;
      _backupDays = days;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _items = null;
    });
    _load();
  }

  Future<void> _delete(Expense e) async {
    setState(() => _items = _items?.where((x) => x.id != e.id).toList());
    try {
      await widget.app.repo.deleteExpense(e.id!);
      widget.app.changed();
    } on ValidationException catch (err) {
      if (mounted) showMessage(context, err.message);
      return;
    }
    if (!mounted) return;
    showMessage(
      context,
      'Expense deleted',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await widget.app.repo.restoreExpense(e);
          widget.app.changed();
        },
      ),
    );
  }

  Future<void> _edit(Expense e) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AddExpenseScreen(app: widget.app, editing: e),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      body: Column(
        children: [
          PeriodSwitcher(
            label: DateFormat.yMMMM().format(_month),
            onPrevious: () => _changeMonth(-1),
            onNext: () => _changeMonth(1),
          ),
          if (_backupDays != null && _backupDays! >= kBackupReminderDays)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text('Last backup was $_backupDays days ago'),
                subtitle: const Text('A lost phone means lost data.'),
                trailing: TextButton(
                  onPressed: () => backupFlow(context, widget.app),
                  child: const Text('Back up'),
                ),
              ),
            ),
          Expanded(
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(child: Text('No expenses this month'))
                    : _buildList(items),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Expense> items) {
    final children = <Widget>[];
    String? currentDay;
    for (final e in items) {
      if (e.date != currentDay) {
        currentDay = e.date;
        final parsed = DateTime.tryParse(e.date);
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            parsed == null ? e.date : DateFormat('EEE, d MMM').format(parsed),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ));
      }
      final sub = e.subcategory.isEmpty ? '' : ' · ${pretty(e.subcategory)}';
      children.add(Dismissible(
        key: ValueKey('expense-${e.id}'),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Theme.of(context).colorScheme.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_outline),
        ),
        onDismissed: (_) => _delete(e),
        child: ListTile(
          title: Text(e.note.isEmpty ? pretty(e.category) : e.note),
          subtitle: Text('${pretty(e.category)}$sub'),
          trailing: Text(
            formatMoney(e.amount, e.currency),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          onTap: () => _edit(e),
        ),
      ));
    }
    return ListView(children: children);
  }
}
