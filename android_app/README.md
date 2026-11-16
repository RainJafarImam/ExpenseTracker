# Expense Tracker (Android, Flutter)

Offline expense tracker. Same tools, same database schema and same currency rules as the PC MCP server in the parent folder (see `../ANDROID_DESIGN.md`). All data stays on the phone and the app never uses the internet.

## Quick start (recommended)

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows) and Android Studio (for the Android SDK). Open Android Studio once and let it finish downloading the SDK.
2. Double-click **`setup_android.bat`** in this folder. It generates the Android files, sets the app name, installs packages, analyzes the code, runs the tests and builds the APK.
3. To use your own app id, run it from a terminal instead: `setup_android.bat -Org com.yourname` (do this **before** sharing the APK; the id can't be changed later without it counting as a different app).
4. To try the app on a USB-connected phone (USB debugging on) or an emulator: `setup_android.bat -Run`.

If anything fails, copy the red error text and send it to Claude.

The manual steps the script performs are listed below, in case you prefer to run them yourself.

## One-time setup (manual)

1. Install [Flutter](https://docs.flutter.dev/get-started/install) and Android Studio (for the Android SDK). Run `flutter doctor` and fix anything it reports under Android toolchain.
2. In this folder (`android_app`), generate the Android project files. The code in `lib/` and `test/` stays as it is:

   ```bash
   flutter create --project-name expense_tracker --org com.example --platforms android .
   ```

   - `--org` sets the app id (`com.example.expense_tracker`). Change it to your own, such as `com.yourname`, **before** you ever share the APK, because it can't be changed later without installing as a different app.
   - Delete the demo test it creates: `test/widget_test.dart`.
   - If `lib/main.dart` was replaced by the Flutter counter demo, tell Claude to restore it.
3. Open `android/app/src/main/AndroidManifest.xml` and check that the `<application ...>` tag has `android:label="Expense Tracker"` and `android:allowBackup="true"` (this lets Android Auto Backup include the database).
4. Get the packages:

   ```bash
   flutter pub get
   ```

## Check it

```bash
flutter analyze      # should report no errors
flutter test         # data layer tests (needs desktop SQLite, see the note in the test file)
flutter run          # on a USB-connected phone (USB debugging on) or an emulator
```

## Build an APK to share

```bash
flutter build apk --release
```

The file is `build/app/outputs/flutter-apk/app-release.apk`. Friends have to allow "install unknown apps" on their phone to install it.

## How it maps to the PC server

| MCP tool | Where it lives |
|---|---|
| `add_expense`, `update_expense`, `delete_expense`, `list_expenses` | `lib/data/expense_repository.dart` |
| `summarize`, `monthly_summary`, `export_csv` | `lib/data/expense_repository.dart` |
| `set_budget`, `list_budgets`, `delete_budget`, `budget_status` | `lib/data/expense_repository.dart` |
| `get_home_currency`, `set_home_currency` | `lib/data/expense_repository.dart` |
| `backup_database` | `lib/services/backup.dart` |
| Input checks | `lib/data/validation.dart` |
| Database schema version 1 and migrations | `lib/data/database.dart` |

Differences from the PC version:
- The app rejects amounts above 1 trillion (a typo guard). The PC server does not have this check yet.
- The expense list shows the newest first; the PC server lists oldest first.

## Changing the database later

Never edit schema version 1. Raise `kSchemaVersion` in `lib/data/database.dart` and add a numbered step in `_onUpgrade` that keeps user data, then add a test that opens an old database file and upgrades it.

## Layout

```
lib/
  main.dart                   app start, theme
  data/                       database, repository, validation, app state
  models/models.dart          Expense, BudgetItem, ...
  screens/                    add_expense, expenses, reports (+budgets), settings
  services/                   currency, backup/restore/share
assets/categories.json        same list as the PC version
test/repository_test.dart     data layer tests
```
