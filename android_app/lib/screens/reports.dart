import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/validation.dart';
import '../models/models.dart';
import '../services/currency.dart';
import 'common.dart';

String _budgetLabel(BudgetItem b) {
  if (b.isOverall) return 'Overall spending';
  return b.subcategory.isEmpty
      ? pretty(b.category)
      : '${pretty(b.category)} / ${pretty(b.subcategory)}';
}

/// Reports tab: monthly or yearly totals per currency, and budgets.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.app});
  final AppState app;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _yearView = false;
  DateTime _month = monthStart(DateTime.now());
  int _year = DateTime.now().year;
  List<MonthlyTotal>? _totals;
  List<BudgetStatus> _budgets = const [];

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
    final totals = _yearView
        ? await repo.monthlySummary(_year)
        : await repo.monthlySummary(_month.year, month: _month.month);
    final budgets =
        _yearView ? <BudgetStatus>[] : await repo.budgetStatus(ym(_month));
    if (!mounted) return;
    setState(() {
      _totals = totals;
      _budgets = budgets;
    });
  }

  void _reload(VoidCallback change) {
    setState(() {
      change();
      _totals = null;
    });
    _load();
  }

  Color _stateColor(BudgetState s) => switch (s) {
        BudgetState.ok => Theme.of(context).colorScheme.primary,
        BudgetState.warning => Colors.amber.shade800,
        BudgetState.over => Theme.of(context).colorScheme.error,
      };

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Month')),
                ButtonSegment(value: true, label: Text('Year')),
              ],
              selected: {_yearView},
              onSelectionChanged: (s) => _reload(() => _yearView = s.first),
            ),
          ),
          if (_yearView)
            PeriodSwitcher(
              label: '$_year',
              onPrevious: () => _reload(() => _year--),
              onNext: () => _reload(() => _year++),
            )
          else
            PeriodSwitcher(
              label: DateFormat.yMMMM().format(_month),
              onPrevious: () =>
                  _reload(() => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () =>
                  _reload(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          if (totals == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (totals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text(_yearView
                      ? 'No spending this year'
                      : 'No spending this month')),
            )
          else if (_yearView)
            ..._yearContent(totals)
          else
            ..._monthContent(totals),
          if (!_yearView && totals != null) ..._budgetSection(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ month view
  List<Widget> _monthContent(List<MonthlyTotal> totals) {
    final byCurrency = <String, List<MonthlyTotal>>{};
    for (final t in totals) {
      byCurrency.putIfAbsent(t.currency, () => []).add(t);
    }
    return [
      for (final entry in byCurrency.entries) _currencyCard(entry.key, entry.value),
    ];
  }

  Widget _currencyCard(String currency, List<MonthlyTotal> rows) {
    final sorted = [...rows]..sort((a, b) => b.total.compareTo(a.total));
    final sum = sorted.fold<double>(0, (s, t) => s + t.total);
    final maxTotal = sorted.first.total;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total ($currency)',
                style: Theme.of(context).textTheme.labelLarge),
            Text(formatMoney(sum, currency),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            for (final t in sorted) ...[
              Row(
                children: [
                  Expanded(child: Text(pretty(t.category))),
                  Text(formatMoney(t.total, currency)),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: maxTotal == 0 ? 0 : t.total / maxTotal,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- year view
  List<Widget> _yearContent(List<MonthlyTotal> totals) {
    final perMonth = <String, Map<String, double>>{};
    final perYear = <String, double>{};
    for (final t in totals) {
      final m = perMonth.putIfAbsent(t.month, () => {});
      m[t.currency] = (m[t.currency] ?? 0) + t.total;
      perYear[t.currency] = (perYear[t.currency] ?? 0) + t.total;
    }
    final months = perMonth.keys.toList()..sort();
    return [
      Card(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Year total', style: Theme.of(context).textTheme.labelLarge),
              for (final e in perYear.entries)
                Text(formatMoney(e.value, e.key),
                    style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
      for (final m in months)
        ListTile(
          title: Text(DateFormat.MMMM()
              .format(DateTime(int.parse(m.substring(0, 4)), int.parse(m.substring(5, 7))))),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final e in perMonth[m]!.entries)
                Text(formatMoney(e.value, e.key)),
            ],
          ),
        ),
    ];
  }

  // --------------------------------------------------------------- budgets
  List<Widget> _budgetSection() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
        child: Row(
          children: [
            Expanded(
                child: Text('Budgets',
                    style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: () => _editBudget(null),
              icon: const Icon(Icons.add),
              label: const Text('Add budget'),
            ),
          ],
        ),
      ),
      if (_budgets.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
              'No budgets yet. Set a monthly limit for all spending, a category or a subcategory.'),
        ),
      for (final s in _budgets) _budgetTile(s),
    ];
  }

  Widget _budgetTile(BudgetStatus s) {
    final b = s.budget;
    final color = _stateColor(s.state);
    final status = switch (s.state) {
      BudgetState.over => 'Over by ${formatMoney(-s.remaining, b.currency)}',
      BudgetState.warning =>
        '${(s.fractionUsed * 100).round()}% used, ${formatMoney(s.remaining, b.currency)} left',
      BudgetState.ok => '${formatMoney(s.remaining, b.currency)} left',
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ListTile(
        onTap: () => _editBudget(b),
        title: Text(_budgetLabel(b)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${formatMoney(s.spent, b.currency)} of ${formatMoney(b.monthlyLimit, b.currency)}'),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: s.fractionUsed.clamp(0.0, 1.0).toDouble(),
              color: color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 4),
            Text(status, style: TextStyle(color: color)),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Delete budget',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await widget.app.repo.deleteBudget(b);
            widget.app.changed();
          },
        ),
      ),
    );
  }

  Future<void> _editBudget(BudgetItem? existing) => showDialog<void>(
        context: context,
        builder: (_) => _BudgetDialog(app: widget.app, existing: existing),
      );
}

enum _Scope { overall, category, subcategory }

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.app, this.existing});
  final AppState app;
  final BudgetItem? existing;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _limit = TextEditingController();
  _Scope _scope = _Scope.overall;
  String? _category;
  String? _subcategory;
  String _currency = 'INR';
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _scope = b.isOverall
          ? _Scope.overall
          : (b.subcategory.isEmpty ? _Scope.category : _Scope.subcategory);
      _category = b.isOverall ? null : b.category;
      _subcategory = b.subcategory.isEmpty ? null : b.subcategory;
      _currency = b.currency;
      _limit.text = b.monthlyLimit.toString();
    } else {
      widget.app.repo.getHomeCurrency().then((c) {
        if (mounted) setState(() => _currency = c);
      });
    }
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_scope != _Scope.overall && _category == null) {
      setState(() => _error = 'Choose a category');
      return;
    }
    if (_scope == _Scope.subcategory && _subcategory == null) {
      setState(() => _error = 'Choose a subcategory');
      return;
    }
    try {
      await widget.app.repo.setBudget(
        parseAmount(_limit.text) ?? double.nan,
        category: _scope == _Scope.overall ? null : _category,
        subcategory: _scope == _Scope.subcategory ? _subcategory : null,
        currency: _currency,
      );
      widget.app.changed();
      if (mounted) Navigator.pop(context);
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.app.categories;
    final subs = cats[_category] ?? const <String>[];
    return AlertDialog(
      title: Text(_isEdit ? 'Edit budget' : 'New monthly budget'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_Scope>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Scope.overall, label: Text('All')),
                ButtonSegment(value: _Scope.category, label: Text('Category')),
                ButtonSegment(value: _Scope.subcategory, label: Text('Sub')),
              ],
              selected: {_scope},
              onSelectionChanged:
                  _isEdit ? null : (s) => setState(() => _scope = s.first),
            ),
            const SizedBox(height: 12),
            if (_scope != _Scope.overall)
              DropdownButton<String>(
                isExpanded: true,
                value: _category,
                hint: const Text('Category'),
                items: [
                  for (final c in cats.keys)
                    DropdownMenuItem(value: c, child: Text(pretty(c))),
                ],
                onChanged: _isEdit
                    ? null
                    : (v) => setState(() {
                          _category = v;
                          _subcategory = null;
                        }),
              ),
            if (_scope == _Scope.subcategory)
              DropdownButton<String>(
                isExpanded: true,
                value: _subcategory,
                hint: const Text('Subcategory'),
                items: [
                  for (final s in subs)
                    DropdownMenuItem(value: s, child: Text(pretty(s))),
                ],
                onChanged:
                    _isEdit ? null : (v) => setState(() => _subcategory = v),
              ),
            TextField(
              controller: _limit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monthly limit'),
            ),
            const SizedBox(height: 8),
            ActionChip(
              avatar: const Icon(Icons.currency_exchange, size: 18),
              label: Text(_currency),
              onPressed: _isEdit
                  ? null
                  : () async {
                      final c = await pickCurrency(context, current: _currency);
                      if (c != null) setState(() => _currency = c);
                    },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
