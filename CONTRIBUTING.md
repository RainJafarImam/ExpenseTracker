# Contributing

Thanks for helping. This project has two parts that must stay in step: the Python MCP server (`main.py`) and the Flutter Android app (`android_app/`).

## Ground rules

1. **Privacy first.** Never add network calls, analytics or anything that sends user data off the device.
2. **Keep the two parts in sync.** The tools, validation rules, currency rules and database schema are the same on the server and in the app. If you change behaviour in one, change the other, or open an issue explaining why they differ.
3. **Never change database schema version 1 without a migration.** Existing users have data in it.
   - Server: add a migration in `init_db()` in `main.py`.
   - App: raise `kSchemaVersion` in `android_app/lib/data/database.dart` and add a numbered step in `_onUpgrade`, with a test that opens an old database and upgrades it.
4. **Totals are never mixed across currencies**, and there is no automatic currency conversion.
5. **Never include real personal data** (`expenses.db`, backups, exports, screenshots of your own spending) in a commit, issue or pull request.

## Setup

Server:

```bash
uv sync
uv run main.py
```

App (needs Flutter and Android Studio, see `android_app/README.md`):

```bash
cd android_app
flutter pub get
flutter analyze
flutter test
```

## Pull requests

- Keep each pull request focused on one change.
- Run `flutter analyze` and `flutter test` for app changes, and try your server changes against a throwaway database.
- Describe what changed and how you tested it. Add screenshots for UI changes (with fake data).
- New user-facing text should be short and plain.

## Reporting bugs

Open an issue with: what you did, what you expected, what happened, and your phone model and Android version (for the app) or Python and `fastmcp` versions (for the server). Remove any personal data from logs and screenshots first.

## Ideas that fit

Optional currency conversion in reports, more export formats, recurring expenses, translations, cloud sync as an opt-in extra, and offline natural-language entry (see `ROADMAP.txt`).
