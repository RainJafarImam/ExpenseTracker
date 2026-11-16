import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/validation.dart';
import '../services/backup.dart';
import 'common.dart';

/// Days after which the app reminds the user to make a backup.
const int kBackupReminderDays = 30;

Future<void> exportCsvFlow(BuildContext context, AppState app) async {
  final now = DateTime.now();
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDateRange: DateTimeRange(start: monthStart(now), end: now),
    helpText: 'Export expenses from / to',
  );
  if (range == null || !context.mounted) return;
  try {
    final start = ymd(range.start);
    final end = ymd(range.end);
    final csv = await app.repo.exportCsv(start, end);
    final rows = '\n'.allMatches(csv).length - 1; // minus the header line
    if (rows <= 0) {
      if (context.mounted) showMessage(context, 'No expenses in that date range');
      return;
    }
    await shareCsv(csv, 'expenses_${start}_to_$end.csv');
  } on ValidationException catch (e) {
    if (context.mounted) showMessage(context, e.message);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Could not create the CSV file');
  }
}

Future<void> backupFlow(BuildContext context, AppState app) async {
  try {
    final path = await createBackupFile(app.db);
    await app.repo.setSetting('last_backup', DateTime.now().toIso8601String());
    app.changed();
    await shareFile(path,
        text: 'Expense Tracker backup. Save it somewhere safe '
            '(Drive, email, files) so you can restore it later.');
  } catch (_) {
    if (context.mounted) showMessage(context, 'Could not create the backup');
  }
}

Future<void> restoreFlow(BuildContext context, AppState app) async {
  final path = await pickBackupFile();
  if (path == null || !context.mounted) return;

  final problem = await validateBackupFile(path);
  if (problem != null) {
    if (context.mounted) showMessage(context, problem);
    return;
  }
  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: const Text(
          'This replaces all expenses and budgets on this phone with the '
          'contents of the backup file. A safety copy of your current data '
          'is saved first.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await app.restoreFrom(path);
    if (context.mounted) showMessage(context, 'Backup restored');
  } catch (_) {
    if (context.mounted) {
      showMessage(context, 'Restore failed. Your previous data was kept in a safety copy.');
    }
  }
}

/// Days since the last backup, or null if the user has no expenses yet.
Future<int?> daysSinceBackup(AppState app) async {
  if (!await app.repo.hasAnyExpense()) return null;
  final raw = await app.repo.getSetting('last_backup');
  final last = raw == null ? null : DateTime.tryParse(raw);
  if (last == null) return null;
  return DateTime.now().difference(last).inDays;
}
