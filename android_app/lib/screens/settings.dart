import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/validation.dart';
import 'actions.dart';
import 'common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.app});
  final AppState app;

  Future<void> _changeCurrency(BuildContext context) async {
    final current = await app.repo.getHomeCurrency();
    if (!context.mounted) return;
    final code = await pickCurrency(context, current: current);
    if (code == null) return;
    try {
      await app.repo.setHomeCurrency(code);
      app.changed();
      if (context.mounted) {
        showMessage(context, 'Home currency set to $code. It applies to new expenses.');
      }
    } on ValidationException catch (e) {
      if (context.mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          children: [
            const _Header('Currency'),
            FutureBuilder<String>(
              future: app.repo.getHomeCurrency(),
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: const Text('Home currency'),
                subtitle: Text(
                    '${snap.data ?? '...'}  ·  used when an expense has no other currency'),
                onTap: () => _changeCurrency(context),
              ),
            ),
            const _Header('Your data'),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export to CSV'),
              subtitle: const Text('Share or email a report for a date range'),
              onTap: () => exportCsvFlow(context, app),
            ),
            FutureBuilder<String?>(
              future: app.repo.getSetting('last_backup'),
              builder: (context, snap) {
                final last =
                    snap.data == null ? null : DateTime.tryParse(snap.data!);
                return ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Back up'),
                  subtitle: Text(last == null
                      ? 'Save a copy of your data to Drive, email or files'
                      : 'Last backup: ${DateFormat.yMMMd().format(last)}'),
                  onTap: () => backupFlow(context, app),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore from backup'),
              subtitle: const Text('Replace the data on this phone with a backup file'),
              onTap: () => restoreFlow(context, app),
            ),
            const _Header('About'),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Privacy'),
              subtitle: Text(
                  'Your expenses are stored only on this phone. The app never '
                  'sends your data anywhere. Back up regularly: if the phone '
                  'is lost, the data is lost.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
