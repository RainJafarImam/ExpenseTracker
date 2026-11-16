# ExpenseTracker

A private, offline expense tracker in two parts that share the same tools, the same database layout and the same currency rules:

1. **MCP server (Python)**: lets an AI assistant such as Claude log and report your expenses by chat ("add 120 for lunch", "how much did I spend on food in March?"). Data is a SQLite file on your own computer.
2. **Android app (Flutter)**: the same features in a normal app, fully offline. Your data stays on your phone and the app never uses the internet.

No accounts, no cloud, no tracking. You own your data.

## Features

- Log, edit, delete and list expenses (date, amount, category, subcategory, note)
- **Multi-currency**: one home currency, plus any ISO currency per expense. Totals are never mixed across currencies and nothing is converted.
- Monthly and yearly summaries per category and currency
- **Budgets**: an overall monthly limit, or per category or subcategory, with warnings at 80% and when exceeded
- CSV export for any date range (share or email it)
- Backup and restore
- A ready-made category list that you can edit (`categories.json`)

## Repository layout

```
main.py             MCP server (FastMCP + SQLite)
categories.json     category and subcategory list
android_app/        Flutter Android app (see android_app/README.md)
ANDROID_DESIGN.md   design of the Android app
ROADMAP.txt         plan and status
```

## MCP server

Requires Python 3.13+ and [uv](https://docs.astral.sh/uv/).

```bash
git clone https://github.com/RainJafarImam/ExpenseTracker.git
cd ExpenseTracker
uv sync
uv run main.py
```

### Connect it to Claude Desktop

Add this to `claude_desktop_config.json` (use the real path to the folder), then restart Claude Desktop:

```json
{
  "mcpServers": {
    "ExpenseTracker": {
      "command": "uv",
      "args": ["--directory", "/path/to/ExpenseTracker", "run", "main.py"]
    }
  }
}
```

On Windows write the path with doubled backslashes, for example `C:\\Users\\you\\ExpenseTracker`. Any other MCP client that supports local (stdio) servers works the same way.

Your data is saved in `expenses.db` inside the project folder. It is created on first run and is excluded from git.

### Tools

| Tool | What it does |
|---|---|
| `add_expense(date, amount, category, subcategory, note, currency)` | Log an expense. Returns the new `id`, plus warnings if the category is unknown or a budget is nearly used up. |
| `update_expense(id, ...)` | Edit any field of an existing expense. Only the fields you pass change. |
| `delete_expense(id)` | Delete an expense by id. |
| `list_expenses(start_date, end_date)` | List expenses in an inclusive date range. |
| `summarize(start_date, end_date, category)` | Totals per category and currency for a date range. |
| `monthly_summary(year, month, category)` | Totals per month, category and currency. Omit `month` for the whole year. |
| `export_csv(start_date, end_date, filename)` | Write a CSV to `exports/`. |
| `set_budget(monthly_limit, category, subcategory, currency)` | Set a monthly budget. No category = overall budget; a category = that category; a category plus subcategory = that subcategory. |
| `list_budgets()` | List every budget that has been set. |
| `delete_budget(category, subcategory, currency)` | Remove a budget (no category = the overall budget). |
| `budget_status(month)` | Spent vs limit for each budget (`ok`, `warning` at 80%, `over`). |
| `get_home_currency()` / `set_home_currency(currency)` | Read or change the home currency. |
| `backup_database()` | Save a timestamped copy of the database to `backups/`. |

Resource: `expense://categories` returns `categories.json`. Edit that file to change the category list; no restart needed.

### Currency rules

1. Each user has one **home currency** (default `INR`, change it with `set_home_currency`).
2. An expense uses the home currency unless another ISO code is given, for example a `$5 coffee` while travelling is logged with `currency="USD"`.
3. Totals are **never mixed across currencies**. Every report and budget groups by currency.
4. There is no currency conversion.

### Input rules

- Dates must be `YYYY-MM-DD` and are stored in that exact format.
- Amounts must be positive numbers.
- Currency must be a 3-letter code.
- An unknown category or subcategory is accepted but returns a warning.

## Android app

Built with Flutter, same schema and tools as the server. It works fully offline.

### Install it (no developer tools needed)

1. On your phone, open this repository's **Releases** page and download `app-release.apk` from the latest release.
2. Open the downloaded file. Android will ask you to allow installing from this source ("install unknown apps"); allow it for your browser or file manager.
3. If Google Play Protect warns about an unrecognized developer, choose "Install anyway". The app isn't on the Play Store, and the full source code is in this repository.
4. Open **Expense Tracker**. Your home currency is picked from your phone's region and you can change it in Settings.

### Build it yourself

Requires Flutter and Android Studio. See [android_app/README.md](android_app/README.md). On Windows, run `android_app/setup_android.bat`; it does the whole setup and builds the APK.

### For maintainers: publishing a release

Pushing a version tag makes GitHub build the APK automatically and attach it to a Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

(see `.github/workflows/build-apk.yml`).

## Privacy

- Everything is stored locally: `expenses.db` on your computer, or the app's database on your phone.
- Nothing is sent anywhere by this project.
- Back up regularly. A lost phone or deleted file means lost data.
- Never commit your own `expenses.db`, `backups/` or `exports/` to a public repository. They are already in `.gitignore`.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

[MIT](LICENSE)
