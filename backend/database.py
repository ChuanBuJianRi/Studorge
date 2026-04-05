"""SQLite database for topics and learning nodes."""
import sqlite3
import os
import platform as _platform


def _default_data_dir() -> str:
    """Return the OS-appropriate user data directory for Studorge."""
    system = _platform.system()
    if system == "Windows":
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, "Studorge", "data")
    elif system == "Darwin":
        return os.path.join(os.path.expanduser("~"), "Library", "Application Support", "Studorge", "data")
    else:
        xdg = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
        return os.path.join(xdg, "Studorge", "data")


# STUDORGE_DATA_DIR env-var overrides the default (used by macOS .app launcher).
_DATA_DIR = os.environ.get("STUDORGE_DATA_DIR") or _default_data_dir()
DB_PATH = os.path.join(_DATA_DIR, "learning.db")


def get_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS topics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            parent_id INTEGER,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            topic_id INTEGER NOT NULL,
            parent_id INTEGER,
            question TEXT NOT NULL,
            answer TEXT NOT NULL,
            node_type TEXT NOT NULL DEFAULT 'question',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE CASCADE,
            FOREIGN KEY (parent_id) REFERENCES nodes(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
    """)
    # Migrations
    for migration in [
        "ALTER TABLE topics ADD COLUMN parent_id INTEGER",
        "ALTER TABLE nodes ADD COLUMN title TEXT",
        "ALTER TABLE topics ADD COLUMN source_node_id INTEGER",
        "ALTER TABLE topics ADD COLUMN folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL",
    ]:
        try:
            conn.execute(migration)
            conn.commit()
        except Exception:
            pass
    conn.commit()
    conn.close()


def get_setting(key: str) -> str | None:
    conn = get_db()
    row = conn.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
    conn.close()
    return row["value"] if row else None


def set_setting(key: str, value: str):
    conn = get_db()
    conn.execute(
        "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, datetime('now'))",
        (key, value),
    )
    conn.commit()
    conn.close()


def delete_setting(key: str):
    conn = get_db()
    conn.execute("DELETE FROM settings WHERE key = ?", (key,))
    conn.commit()
    conn.close()


def dict_from_row(row):
    return dict(row) if row else None


def dict_from_rows(rows):
    return [dict(r) for r in rows]
