from fastmcp import FastMCP
import csv
import json
import math
import os
import re
import sqlite3
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "expenses.db")
CATEGORIES_PATH = os.path.join(BASE_DIR, "categories.json")
EXPORT_DIR = os.path.join(BASE_DIR, "exports")
BACKUP_DIR = os.path.join(BASE_DIR, "backups")

# A budget warning is raised once spending reaches this share of the limit.
BUDGET_WARN_RATIO = 0.8
# Budget category value that means "all spending combined".
TOTAL_BUDGET = "*"
# export_csv returns the CSV text inline only up to this many rows.
CSV_INLINE_MAX_ROWS = 500

mcp = FastMCP("ExpenseTracker")


# ----------------------------------------------------------------------------
# Database setup
# ----------------------------------------------------------------------------
def init_db():
    with sqlite3.connect(DB_PATH) as c:
        c.execute("""
            CREATE TABLE IF NOT EXISTS expenses(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                amount REAL NOT NULL,
                category TEXT NOT NULL,
                subcategory TEXT DEFAULT '',
                note TEXT DEFAULT '',
                currency TEXT NOT NULL DEFAULT 'INR'
            )
        """)
        # Migrate older databases that were created before currency existed
        cols = [r[1] for r in c.execute("PRAGMA table_info(expenses)")]
        if "currency" not in cols:
            c.execute("ALTER TABLE expenses ADD COLUMN currency TEXT NOT NULL DEFAULT 'INR'")
        c.execute("CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        c.execute("INSERT OR IGNORE INTO settings(key, value) VALUES ('home_currency', 'INR')")
        # Monthly budget limit. category '*' = overall budget for all spending;
        # empty subcategory = the whole category.
        c.execute("""
            CREATE TABLE IF NOT EXISTS budgets(
                category TEXT NOT NULL,
                subcategory TEXT NOT NULL DEFAULT '',
                currency TEXT NOT NULL,
                monthly_limit REAL NOT NULL,
                PRIMARY KEY (category, subcategory, currency)
            )
        """)
        # Migrate the first version of the budgets table (no subcategory column)
        bcols = [r[1] for r in c.execute("PRAGMA table_info(budgets)")]
        if "subcategory" not in bcols:
            c.execute("ALTER TABLE budgets RENAME TO budgets_old")
            c.execute("""
                CREATE TABLE budgets(
                    category TEXT NOT NULL,
                    subcategory TEXT NOT NULL DEFAULT '',
                    currency TEXT NOT NULL,
                    monthly_limit REAL NOT NULL,
                    PRIMARY KEY (category, subcategory, currency)
                )
            """)
            c.execute(
                "INSERT INTO budgets(category, subcategory, currency, monthly_limit) "
                "SELECT category, '', currency, monthly_limit FROM budgets_old"
            )
            c.execute("DROP TABLE budgets_old")


init_db()


# ----------------------------------------------------------------------------
# Helpers and validation (helpers raise ValueError with a readable message)
# ----------------------------------------------------------------------------
def _err(message):
    return {"status": "error", "message": message}


def _home_currency(c):
    row = c.execute("SELECT value FROM settings WHERE key = 'home_currency'").fetchone()
    return row[0] if row else "INR"


def _check_date(value, field="date"):
    if not isinstance(value, str):
        raise ValueError(f"{field} must be text in YYYY-MM-DD format")
    try:
        # Normalise (e.g. 2026-1-5 -> 2026-01-05) so text comparison in SQL stays correct
        return datetime.strptime(value.strip(), "%Y-%m-%d").strftime("%Y-%m-%d")
    except ValueError:
        raise ValueError(f"{field} '{value}' is not a valid date. Use YYYY-MM-DD, e.g. 2026-11-15")


def _check_range(start_date, end_date):
    start = _check_date(start_date, "start_date")
    end = _check_date(end_date, "end_date")
    if start > end:
        raise ValueError("start_date must not be after end_date")
    return start, end


def _check_amount(value, field="amount"):
    try:
        amount = float(value)
    except (TypeError, ValueError):
        raise ValueError(f"{field} must be a number")
    if not math.isfinite(amount) or amount <= 0:
        raise ValueError(f"{field} must be a positive number")
    return amount


def _check_currency(code):
    code = (code or "").strip().upper()
    if len(code) != 3 or not code.isalpha():
        raise ValueError("currency must be a 3-letter ISO code like INR, USD or EUR")
    return code


def _check_text(value, field, required=False):
    value = (value or "").strip()
    if required and not value:
        raise ValueError(f"{field} must not be empty")
    return value


def _check_month(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", value.strip()):
        raise ValueError("month must be in YYYY-MM format, e.g. 2026-11")
    return value.strip()


def _category_warning(category, subcategory):
    """Soft check against categories.json. Returns a warning string or None."""
    try:
        with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
            cats = json.load(f)
    except (OSError, ValueError):
        return None
    if category not in cats:
        return f"category '{category}' is not in categories.json"
    if subcategory and subcategory not in cats[category]:
        return f"subcategory '{subcategory}' is not listed under '{category}' in categories.json"
    return None


def _month_spent(c, category, subcategory, currency, month):
    """Spent in a month. category '*' = all spending; empty subcategory = whole category."""
    query = ("SELECT COALESCE(SUM(amount), 0) FROM expenses "
             "WHERE currency = ? AND substr(date, 1, 7) = ?")
    params = [currency, month]
    if category != TOTAL_BUDGET:
        query += " AND category = ?"
        params.append(category)
        if subcategory:
            query += " AND subcategory = ?"
            params.append(subcategory)
    return c.execute(query, params).fetchone()[0]


def _budget_label(category, subcategory):
    if category == TOTAL_BUDGET:
        return "overall spending"
    return f"{category}/{subcategory}" if subcategory else category


def _budget_state(spent, limit):
    if spent > limit:
        return "over"
    if spent >= limit * BUDGET_WARN_RATIO:
        return "warning"
    return "ok"


def _budget_warnings(c, category, subcategory, currency, month):
    """Warnings for every budget that applies to an expense: overall, its category, its subcategory."""
    scopes = [(TOTAL_BUDGET, ""), (category, "")]
    if subcategory:
        scopes.append((category, subcategory))
    warnings = []
    for cat, sub in scopes:
        row = c.execute(
            "SELECT monthly_limit FROM budgets WHERE category = ? AND subcategory = ? AND currency = ?",
            (cat, sub, currency),
        ).fetchone()
        if not row:
            continue
        limit = row[0]
        spent = _month_spent(c, cat, sub, currency, month)
        state = _budget_state(spent, limit)
        label = _budget_label(cat, sub)
        if state == "over":
            warnings.append(f"Over budget for {label} in {month}: spent {spent:g} of {limit:g} {currency}")
        elif state == "warning":
            warnings.append(f"Close to budget for {label} in {month}: spent {spent:g} "
                            f"of {limit:g} {currency} ({spent / limit:.0%})")
    return warnings


def _rows(cur):
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


# ----------------------------------------------------------------------------
# Expense tools
# ----------------------------------------------------------------------------
@mcp.tool()
def add_expense(date: str, amount: float, category: str, subcategory: str = "",
                note: str = "", currency: str | None = None):
    '''Add a new expense entry to the database. date is YYYY-MM-DD and amount must be positive. currency is an optional ISO code such as INR, USD, EUR; if omitted, the user's home currency is used.'''
    try:
        date = _check_date(date)
        amount = _check_amount(amount)
        category = _check_text(category, "category", required=True)
        subcategory = _check_text(subcategory, "subcategory")
        note = _check_text(note, "note")
        with sqlite3.connect(DB_PATH) as c:
            code = _check_currency(currency) if currency else _home_currency(c)
            cur = c.execute(
                "INSERT INTO expenses(date, amount, category, subcategory, note, currency) VALUES (?,?,?,?,?,?)",
                (date, amount, category, subcategory, note, code),
            )
            result = {"status": "ok", "id": cur.lastrowid}
            warnings = [w for w in [_category_warning(category, subcategory)]
                        + _budget_warnings(c, category, subcategory, code, date[:7]) if w]
            if warnings:
                result["warnings"] = warnings
            return result
    except ValueError as e:
        return _err(str(e))


@mcp.tool()
def update_expense(id: int, date: str | None = None, amount: float | None = None,
                   category: str | None = None, subcategory: str | None = None,
                   note: str | None = None, currency: str | None = None):
    '''Edit an existing expense by ID. Only the fields you pass are changed; pass an empty string for subcategory or note to clear it.'''
    try:
        with sqlite3.connect(DB_PATH) as c:
            row = c.execute(
                "SELECT date, amount, category, subcategory, note, currency FROM expenses WHERE id = ?",
                (id,),
            ).fetchone()
            if not row:
                return _err(f"No expense found with id {id}")
            new = {
                "date": _check_date(date) if date is not None else row[0],
                "amount": _check_amount(amount) if amount is not None else row[1],
                "category": _check_text(category, "category", required=True) if category is not None else row[2],
                "subcategory": _check_text(subcategory, "subcategory") if subcategory is not None else row[3],
                "note": _check_text(note, "note") if note is not None else row[4],
                "currency": _check_currency(currency) if currency is not None else row[5],
            }
            c.execute(
                "UPDATE expenses SET date=?, amount=?, category=?, subcategory=?, note=?, currency=? WHERE id=?",
                (new["date"], new["amount"], new["category"], new["subcategory"],
                 new["note"], new["currency"], id),
            )
            result = {"status": "ok", "id": id, "expense": new}
            warnings = [w for w in [_category_warning(new["category"], new["subcategory"])]
                        + _budget_warnings(c, new["category"], new["subcategory"],
                                           new["currency"], new["date"][:7]) if w]
            if warnings:
                result["warnings"] = warnings
            return result
    except ValueError as e:
        return _err(str(e))


@mcp.tool()
def list_expenses(start_date: str, end_date: str):
    '''List expense entries within an inclusive date range (YYYY-MM-DD).'''
    try:
        start, end = _check_range(start_date, end_date)
    except ValueError as e:
        return _err(str(e))
    with sqlite3.connect(DB_PATH) as c:
        cur = c.execute(
            """
            SELECT id, date, amount, currency, category, subcategory, note
            FROM expenses
            WHERE date BETWEEN ? AND ?
            ORDER BY id ASC
            """,
            (start, end),
        )
        return _rows(cur)


@mcp.tool()
def delete_expense(id: int):
    '''Delete an expense entry by its ID.'''
    with sqlite3.connect(DB_PATH) as c:
        cur = c.execute("DELETE FROM expenses WHERE id = ?", (id,))
        if cur.rowcount == 0:
            return _err(f"No expense found with id {id}")
        return {"status": "ok", "deleted_id": id}


# ----------------------------------------------------------------------------
# Reports
# ----------------------------------------------------------------------------
@mcp.tool()
def summarize(start_date: str, end_date: str, category: str | None = None):
    '''Summarize expenses by category within an inclusive date range. Totals are kept separate per currency.'''
    try:
        start, end = _check_range(start_date, end_date)
    except ValueError as e:
        return _err(str(e))
    with sqlite3.connect(DB_PATH) as c:
        query = (
            """
            SELECT category, currency, SUM(amount) AS total_amount
            FROM expenses
            WHERE date BETWEEN ? AND ?
            """
        )
        params = [start, end]
        if category:
            query += " AND category = ?"
            params.append(category)
        query += " GROUP BY category, currency ORDER BY category ASC, currency ASC"
        return _rows(c.execute(query, params))


@mcp.tool()
def monthly_summary(year: int, month: int | None = None, category: str | None = None):
    '''Total spending per month, per category, per currency. Pass only a year for all 12 months, or year and month (1-12) for a single month.'''
    if not 1900 <= year <= 2200:
        return _err("year must be between 1900 and 2200")
    if month is not None and not 1 <= month <= 12:
        return _err("month must be between 1 and 12")
    prefix = f"{year:04d}-{month:02d}" if month else f"{year:04d}"
    with sqlite3.connect(DB_PATH) as c:
        query = (
            """
            SELECT substr(date, 1, 7) AS month, category, currency, SUM(amount) AS total_amount
            FROM expenses
            WHERE substr(date, 1, ?) = ?
            """
        )
        params = [len(prefix), prefix]
        if category:
            query += " AND category = ?"
            params.append(category)
        query += " GROUP BY month, category, currency ORDER BY month ASC, category ASC, currency ASC"
        return _rows(c.execute(query, params))


@mcp.tool()
def export_csv(start_date: str, end_date: str, filename: str | None = None):
    '''Export expenses in an inclusive date range to a CSV file in the exports folder, ready to attach to an email or share. Returns the file path and, for up to 500 rows, the CSV text.'''
    try:
        start, end = _check_range(start_date, end_date)
    except ValueError as e:
        return _err(str(e))
    with sqlite3.connect(DB_PATH) as c:
        cur = c.execute(
            """
            SELECT id, date, amount, currency, category, subcategory, note
            FROM expenses
            WHERE date BETWEEN ? AND ?
            ORDER BY date ASC, id ASC
            """,
            (start, end),
        )
        header = [d[0] for d in cur.description]
        rows = cur.fetchall()

    name = os.path.basename((filename or "").strip()) or f"expenses_{start}_to_{end}.csv"
    if not name.lower().endswith(".csv"):
        name += ".csv"
    os.makedirs(EXPORT_DIR, exist_ok=True)
    path = os.path.join(EXPORT_DIR, name)
    # utf-8-sig so Excel shows symbols such as the rupee sign correctly
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

    result = {"status": "ok", "path": path, "row_count": len(rows)}
    if len(rows) <= CSV_INLINE_MAX_ROWS:
        with open(path, "r", encoding="utf-8-sig") as f:
            result["csv"] = f.read()
    return result


# ----------------------------------------------------------------------------
# Budgets
# ----------------------------------------------------------------------------
def _check_budget_scope(category, subcategory):
    """No category = overall budget for all spending. A subcategory needs a category."""
    category = (category or "").strip()
    subcategory = (subcategory or "").strip()
    if not category:
        if subcategory:
            raise ValueError("A subcategory budget needs a category too")
        return TOTAL_BUDGET, ""
    if category == TOTAL_BUDGET:
        raise ValueError("Leave category empty for an overall budget")
    return category, subcategory


@mcp.tool()
def set_budget(monthly_limit: float, category: str | None = None,
               subcategory: str | None = None, currency: str | None = None):
    '''Set or change a monthly budget limit. Leave category empty for an overall budget on all spending; pass a category for that category; pass category and subcategory for one subcategory. currency defaults to the home currency.'''
    try:
        limit = _check_amount(monthly_limit, "monthly_limit")
        category, subcategory = _check_budget_scope(category, subcategory)
        with sqlite3.connect(DB_PATH) as c:
            code = _check_currency(currency) if currency else _home_currency(c)
            c.execute(
                "INSERT OR REPLACE INTO budgets(category, subcategory, currency, monthly_limit) VALUES (?,?,?,?)",
                (category, subcategory, code, limit),
            )
        result = {"status": "ok", "scope": _budget_label(category, subcategory),
                  "currency": code, "monthly_limit": limit}
        if category != TOTAL_BUDGET:
            warning = _category_warning(category, subcategory)
            if warning:
                result["warnings"] = [warning]
        return result
    except ValueError as e:
        return _err(str(e))


@mcp.tool()
def list_budgets():
    '''List every budget that has been set (overall, per category and per subcategory).'''
    with sqlite3.connect(DB_PATH) as c:
        rows = c.execute(
            "SELECT category, subcategory, currency, monthly_limit FROM budgets "
            "ORDER BY (category = ?) DESC, category, subcategory, currency",
            (TOTAL_BUDGET,),
        ).fetchall()
    return [
        {"scope": _budget_label(cat, sub), "category": None if cat == TOTAL_BUDGET else cat,
         "subcategory": sub or None, "currency": cur, "monthly_limit": lim}
        for cat, sub, cur, lim in rows
    ]


@mcp.tool()
def delete_budget(category: str | None = None, subcategory: str | None = None,
                  currency: str | None = None):
    '''Remove a monthly budget. Leave category empty to remove the overall budget; pass category (and optionally subcategory) to remove that one. currency defaults to the home currency.'''
    try:
        category, subcategory = _check_budget_scope(category, subcategory)
        with sqlite3.connect(DB_PATH) as c:
            code = _check_currency(currency) if currency else _home_currency(c)
            cur = c.execute(
                "DELETE FROM budgets WHERE category = ? AND subcategory = ? AND currency = ?",
                (category, subcategory, code),
            )
            label = _budget_label(category, subcategory)
            if cur.rowcount == 0:
                return _err(f"No budget found for {label} in {code}")
            return {"status": "ok", "scope": label, "currency": code}
    except ValueError as e:
        return _err(str(e))


@mcp.tool()
def budget_status(month: str | None = None):
    '''Show spent vs limit for every budget in a month (YYYY-MM, default = current month). Status is ok, warning (80% or more used) or over.'''
    try:
        month = _check_month(month) if month else datetime.now().strftime("%Y-%m")
    except ValueError as e:
        return _err(str(e))
    with sqlite3.connect(DB_PATH) as c:
        budgets = c.execute(
            "SELECT category, subcategory, currency, monthly_limit FROM budgets "
            "ORDER BY (category = ?) DESC, category, subcategory, currency",
            (TOTAL_BUDGET,),
        ).fetchall()
        report = []
        for category, subcategory, currency, limit in budgets:
            spent = _month_spent(c, category, subcategory, currency, month)
            report.append({
                "scope": _budget_label(category, subcategory),
                "currency": currency,
                "monthly_limit": limit,
                "spent": spent,
                "remaining": limit - spent,
                "percent_used": round(spent / limit * 100, 1),
                "status": _budget_state(spent, limit),
            })
        return {"month": month, "budgets": report}


# ----------------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------------
@mcp.tool()
def get_home_currency():
    '''Get the user's home currency (used when an expense has no currency specified).'''
    with sqlite3.connect(DB_PATH) as c:
        return {"home_currency": _home_currency(c)}


@mcp.tool()
def set_home_currency(currency: str):
    '''Set the user's home currency using a 3-letter ISO code, e.g. INR, USD, EUR, JPY.'''
    try:
        code = _check_currency(currency)
    except ValueError:
        return _err("Use a 3-letter ISO currency code like INR or USD")
    with sqlite3.connect(DB_PATH) as c:
        c.execute("INSERT OR REPLACE INTO settings(key, value) VALUES ('home_currency', ?)", (code,))
    return {"status": "ok", "home_currency": code}


# ----------------------------------------------------------------------------
# Backup
# ----------------------------------------------------------------------------
@mcp.tool()
def backup_database():
    '''Save a timestamped copy of expenses.db into the backups folder. Run this before any big change.'''
    os.makedirs(BACKUP_DIR, exist_ok=True)
    dest = os.path.join(BACKUP_DIR, f"expenses_{datetime.now():%Y%m%d_%H%M%S}.db")
    src = sqlite3.connect(DB_PATH)
    dst = sqlite3.connect(dest)
    try:
        with dst:
            src.backup(dst)
    finally:
        src.close()
        dst.close()
    return {"status": "ok", "path": dest, "size_bytes": os.path.getsize(dest)}


# ----------------------------------------------------------------------------
# Resources
# ----------------------------------------------------------------------------
@mcp.resource("expense://categories", mime_type="application/json")
def categories():
    # Read fresh each time so you can edit the file without restarting
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        return f.read()


if __name__ == "__main__":
    mcp.run()
