# Android App Design (Phase 4)

Offline expense tracker for Android. Same tools, same database schema and same currency rules as the PC MCP server in this folder. All data stays on the phone.

## 1. Framework: Flutter

| | Flutter | Kotlin |
|---|---|---|
| Codebase | One, also gives iOS later | Android only |
| Learning curve | Easier | Steeper |
| Local SQLite | `sqflite` runs the same SQL as the PC server | Room or raw SQLite |
| On-device AI (Phase 6) | Possible through plugins, less mature | Best support |

**Decision: Flutter.** Phase 6 is optional. If it becomes the main goal, only the AI layer would need a native (Kotlin) bridge; the rest of the app stays.

Packages:
- `sqflite` + `path` + `path_provider`: database
- `intl`: currency symbols, number and date formatting, region lookup
- `csv`: CSV export
- `share_plus`: share or email a CSV or backup file
- `file_picker`: choose a backup file to restore

## 2. Data model (identical to the PC server)

Schema version 1 is exactly what `main.py` creates today. Do not rename or retype anything.

```sql
CREATE TABLE expenses(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,                 -- YYYY-MM-DD
    amount REAL NOT NULL,               -- positive
    category TEXT NOT NULL,
    subcategory TEXT DEFAULT '',
    note TEXT DEFAULT '',
    currency TEXT NOT NULL DEFAULT 'INR'
);

CREATE TABLE settings(
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL                 -- 'home_currency' => 'INR'
);

CREATE TABLE budgets(
    category TEXT NOT NULL,             -- '*' = overall budget
    subcategory TEXT NOT NULL DEFAULT '',
    currency TEXT NOT NULL,
    monthly_limit REAL NOT NULL,
    PRIMARY KEY (category, subcategory, currency)
);
```

Categories come from a bundled `categories.json` (same file as the PC version), loaded from the app's assets.

**Amount storage.** `REAL` is kept for exact parity, so amounts are rounded to the currency's decimals when shown. Floating point error is possible in long sums. Storing minor units (paise, cents) would be safer but would break schema parity, so it would need its own migration later.

### Tool parity

Every MCP tool becomes a method in one `ExpenseRepository` class using the same SQL and the same validation rules.

| MCP tool | Repository method |
|---|---|
| `add_expense` | `addExpense(...)` |
| `update_expense` | `updateExpense(id, ...)` |
| `delete_expense` | `deleteExpense(id)` |
| `list_expenses` | `listExpenses(start, end)` |
| `summarize` | `summarize(start, end, category?)` |
| `monthly_summary` | `monthlySummary(year, month?, category?)` |
| `export_csv` | `exportCsv(start, end)` |
| `set_budget` / `list_budgets` / `delete_budget` / `budget_status` | same names |
| `get_home_currency` / `set_home_currency` | same names |
| `backup_database` | `backupDatabase()` |

Validation (identical): real `YYYY-MM-DD` date, positive finite amount, 3-letter currency code, non-empty category, start date not after end date. An unknown category is accepted with a warning.

## 3. Currency

1. **First launch:** read the phone's region (`PlatformDispatcher.locale.countryCode`) and map it to a currency with `intl`'s `NumberFormat.simpleCurrency(locale: ...)`. India gives INR, USA gives USD, Japan gives JPY. If the region is unknown, fall back to INR. Save it as `home_currency`.
2. **Settings screen:** the user can change it at any time (searchable list of ISO codes).
3. **Per expense:** the add screen has a currency chip showing the home currency; tapping it picks another one (for example while travelling).
4. **Display:** format with `intl` so the symbol and decimals are right: `₹1,250.00`, `$5.00`, `¥500` (JPY has no decimals).
5. **Totals are never mixed.** Every report and budget groups by currency. There is no conversion.

## 4. Screens

Bottom navigation with four tabs.

1. **Add** (home tab): amount (large, numeric keypad), category then subcategory pickers, date (defaults to today), note, currency chip. Save shows any budget warnings in a snackbar.
2. **Expenses:** list grouped by day, month picker at the top. Tap to edit; swipe to delete with undo.
3. **Reports:**
   - Month view: total per category, one section per currency, simple bar list.
   - Year view: totals per month.
   - **Budgets** section: overall, category and subcategory budgets with progress bars (green under 80%, amber at 80% or more, red over). Add and edit budgets here.
4. **Settings:** home currency, export CSV (date range then share), backup, restore, about and privacy note.

Edit Expense reuses the Add screen with the fields filled in.

## 5. Data safety

- **Android Auto Backup:** enabled in the manifest so the database is included in the user's Google backup when they have it on. It can't be relied on alone.
- **Manual backup:** Settings > Backup copies `expenses.db` using SQLite's backup (a consistent copy) and opens the share sheet to save it to Drive, email or files.
- **Restore:** pick a `.db` file, then check that it has the `expenses`, `settings` and `budgets` tables and a compatible `user_version`. Take an automatic safety copy of the current database first, then replace it. Refuse files from a newer app version.
- **CSV export:** same columns as the PC version (`id,date,amount,currency,category,subcategory,note`), written as UTF-8 with a byte-order mark so Excel shows the rupee sign.
- A reminder to back up after 30 days without one.

## 6. Updates and migrations

- The app stores a schema number using SQLite's `PRAGMA user_version` (sqflite's `version` parameter).
- **Version 1** = the schema above.
- Every future change is a numbered step in `onUpgrade` (1 to 2, 2 to 3, and so on) that never drops user data. Anything destructive copies to a new table first.
- A migration test per step: open a version N database file with sample data, upgrade, check the data is intact.
- Restore applies the same upgrade path to older backups.
- The PC database has no `user_version` set. When importing a PC database into the app, treat it as version 1.

## 7. Project structure

```
lib/
  main.dart
  data/        database.dart (open, migrate), expense_repository.dart, categories.dart
  models/      expense.dart, budget.dart
  screens/     add_expense.dart, expenses.dart, reports.dart, budgets.dart, settings.dart
  services/    currency.dart, csv_export.dart, backup.dart
assets/categories.json
test/          repository_test.dart, migration_test.dart
```

## 8. Open decisions for Phase 5

- App name and package id (for example `com.yourname.expensetracker`).
- Light and dark theme (follow the system by default).
- Whether CSV export should also offer a monthly summary sheet.
