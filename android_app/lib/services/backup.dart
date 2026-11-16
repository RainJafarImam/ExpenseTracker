import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

String _stamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
}

/// Writes a consistent copy of the open database to [dest].
Future<void> writeSnapshot(Database db, String dest) async {
  final f = File(dest);
  if (await f.exists()) await f.delete();
  try {
    // Consistent copy (needs SQLite 3.27+, which is Android 11 and newer).
    await db.execute('VACUUM INTO ?', [dest]);
  } catch (_) {
    // Older phones: flush the write-ahead log, then copy the file.
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await File(db.path).copy(dest);
  }
}

/// Creates a backup file in the temp folder and returns its path.
Future<String> createBackupFile(Database db) async {
  final dir = await getTemporaryDirectory();
  final path = p.join(dir.path, 'expenses_backup_${_stamp()}.db');
  await writeSnapshot(db, path);
  return path;
}

/// Saves a safety copy in the app's documents folder before a restore.
Future<String> createSafetyCopy(Database db) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, 'safety_before_restore_${_stamp()}.db');
  await writeSnapshot(db, path);
  return path;
}

Future<void> shareFile(String path, {String? text}) async {
  await Share.shareXFiles([XFile(path)], text: text);
}

/// Writes the CSV (UTF-8 with a byte-order mark so Excel shows the rupee
/// sign correctly) and opens the share sheet.
Future<void> shareCsv(String csv, String fileName) async {
  final dir = await getTemporaryDirectory();
  final name = fileName.toLowerCase().endsWith('.csv') ? fileName : '$fileName.csv';
  final path = p.join(dir.path, name);
  await File(path).writeAsString('\uFEFF$csv', encoding: utf8, flush: true);
  await Share.shareXFiles([XFile(path, mimeType: 'text/csv')]);
}

/// Lets the user choose a backup file. Returns its path, or null if cancelled.
Future<String?> pickBackupFile() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  if (result == null || result.files.isEmpty) return null;
  return result.files.single.path;
}

/// Returns an error message if [path] is not a usable backup, else null.
/// A database copied from the PC server (user_version 0) is accepted.
Future<String?> validateBackupFile(String path) async {
  Database? test;
  try {
    test = await openDatabase(path, readOnly: true);
    final tables = (await test.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name'])
        .toSet();
    if (!tables.contains('expenses')) {
      return 'This file is not an expense database (no expenses table).';
    }
    final version =
        Sqflite.firstIntValue(await test.rawQuery('PRAGMA user_version')) ?? 0;
    if (version > kSchemaVersion) {
      return 'This backup was made by a newer version of the app. '
          'Update the app first.';
    }
    return null;
  } catch (_) {
    return 'Could not read this file as an expense database.';
  } finally {
    await test?.close();
  }
}

/// Replaces the database file with [source]. The database must be closed.
Future<void> replaceDatabaseFile(String source) async {
  final target = await appDatabasePath();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$target$suffix');
    if (await f.exists()) await f.delete();
  }
  await File(source).copy(target);
}
