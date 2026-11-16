import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/validation.dart';
import '../models/models.dart';
import '../services/currency.dart';
import 'common.dart';

/// Add tab. Also used (with [editing] set) to edit an existing expense.
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key, required this.app, this.editing});

  final AppState app;
  final Expense? editing;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _category;
  String? _subcategory;
  DateTime _date = DateTime.now();
  String _currency = 'INR';
  String _home = 'INR';
  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _amount.text = e.amount.toString();
      _note.text = e.note;
      _category = e.category;
      _subcategory = e.subcategory.isEmpty ? null : e.subcategory;
      _date = DateTime.tryParse(e.date) ?? DateTime.now();
      _currency = e.currency;
    }
    _loadHome();
    if (!_isEdit) widget.app.addListener(_loadHome);
  }

  Future<void> _loadHome() async {
    final home = await widget.app.repo.getHomeCurrency();
    if (!mounted) return;
    setState(() {
      // Follow the home currency unless the user picked another one.
      if (!_isEdit && _currency == _home) _currency = home;
      _home = home;
    });
  }

  @override
  void dispose() {
    if (!_isEdit) widget.app.removeListener(_loadHome);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  List<String> get _categoryKeys {
    final keys = widget.app.categories.keys.toList();
    if (_category != null && !keys.contains(_category)) keys.add(_category!);
    return keys;
  }

  List<String> get _subKeys {
    final subs = [...?widget.app.categories[_category]];
    if (_subcategory != null && !subs.contains(_subcategory)) {
      subs.add(_subcategory!);
    }
    return subs;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCurrency() async {
    final code = await pickCurrency(context, current: _currency);
    if (code != null) setState(() => _currency = code);
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseAmount(_amount.text);
    if (_category == null) {
      showMessage(context, 'Choose a category');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = widget.app.repo;
      final SaveResult result;
      if (_isEdit) {
        result = await repo.updateExpense(
          widget.editing!.id!,
          date: ymd(_date),
          amount: amount ?? double.nan, // NaN is rejected with a clear message
          category: _category,
          subcategory: _subcategory ?? '',
          note: _note.text,
          currency: _currency,
        );
      } else {
        result = await repo.addExpense(
          date: ymd(_date),
          amount: amount ?? double.nan,
          category: _category!,
          subcategory: _subcategory ?? '',
          note: _note.text,
          currency: _currency,
        );
      }
      widget.app.changed();
      if (!mounted) return;
      final text = result.warnings.isEmpty
          ? 'Saved'
          : 'Saved. ${result.warnings.join('\n')}';
      if (_isEdit) {
        showMessage(context, text); // show before leaving this screen
        Navigator.pop(context);
        return;
      }
      setState(() {
        _amount.clear();
        _note.clear();
        _subcategory = null;
        // Keep category, date and currency: handy for several similar entries.
      });
      showMessage(context, text);
    } on ValidationException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subs = _subKeys;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit expense' : 'Add expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amount,
            autofocus: !_isEdit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: InputDecoration(
              labelText: 'Amount',
              border: const OutlineInputBorder(),
              prefixText: '${NumberFormat.simpleCurrency(name: _currency).currencySymbol} ',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.currency_exchange, size: 18),
              label: Text(_currency == _home ? '$_currency (home)' : _currency),
              onPressed: _pickCurrency,
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
                labelText: 'Category', border: OutlineInputBorder()),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _category,
                hint: const Text('Choose a category'),
                items: [
                  for (final c in _categoryKeys)
                    DropdownMenuItem(value: c, child: Text(pretty(c))),
                ],
                onChanged: (v) => setState(() {
                  _category = v;
                  _subcategory = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
                labelText: 'Subcategory (optional)',
                border: OutlineInputBorder()),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _subcategory,
                hint: Text(_category == null
                    ? 'Choose a category first'
                    : 'Choose a subcategory'),
                items: [
                  for (final s in subs)
                    DropdownMenuItem(value: s, child: Text(pretty(s))),
                ],
                onChanged: subs.isEmpty
                    ? null
                    : (v) => setState(() => _subcategory = v),
              ),
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today)),
              child: Text(DateFormat.yMMMEd().format(_date)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(_isEdit ? 'Save changes' : 'Save expense'),
          ),
        ],
      ),
    );
  }
}
