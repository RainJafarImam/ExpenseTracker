import 'package:flutter/material.dart';

import '../services/currency.dart';

// Dates are stored as plain ASCII YYYY-MM-DD, never localised, so the data
// stays identical to the PC version on any phone language.
String _two(int v) => v.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
String ym(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}';
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
String monthStartKey(DateTime d) => ymd(DateTime(d.year, d.month, 1));
String monthEndKey(DateTime d) => ymd(DateTime(d.year, d.month + 1, 0));

/// Accepts "1250", "1,250.50", "12,50" (decimal comma) and similar.
double? parseAmount(String input) {
  var t = input.trim().replaceAll(' ', '');
  if (RegExp(r'^\d+,\d{1,2}$').hasMatch(t)) {
    t = t.replaceAll(',', '.'); // 12,50 -> 12.50
  } else {
    t = t.replaceAll(',', ''); // 1,250 -> 1250
  }
  return double.tryParse(t);
}

void showMessage(BuildContext context, String text, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    action: action,
    duration: const Duration(seconds: 5),
  ));
}

/// "< March 2026 >" style switcher.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            tooltip: 'Previous',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left)),
        SizedBox(
          width: 170,
          child: Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
            tooltip: 'Next',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

/// Dialog to choose a currency from the common list, or type any ISO code.
Future<String?> pickCurrency(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CurrencyDialog(current: current),
  );
}

class _CurrencyDialog extends StatefulWidget {
  const _CurrencyDialog({this.current});
  final String? current;

  @override
  State<_CurrencyDialog> createState() => _CurrencyDialogState();
}

class _CurrencyDialogState extends State<_CurrencyDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final matches = kCurrencies.entries
        .where((e) =>
            q.isEmpty ||
            e.key.toLowerCase().contains(q) ||
            e.value.toLowerCase().contains(q))
        .toList();
    final typed = _query.trim().toUpperCase();
    final canUseTyped =
        RegExp(r'^[A-Z]{3}$').hasMatch(typed) && !kCurrencies.containsKey(typed);

    return AlertDialog(
      title: const Text('Choose currency'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          children: [
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search or type a 3-letter code',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (canUseTyped)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text('Use $typed'),
                      onTap: () => Navigator.pop(context, typed),
                    ),
                  for (final e in matches)
                    ListTile(
                      dense: true,
                      title: Text('${e.key}  ·  ${e.value}'),
                      trailing: e.key == widget.current
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
