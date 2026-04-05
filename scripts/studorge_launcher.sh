#!/usr/bin/env bash
# Internal launcher — lives inside Studorge.app/Contents/Resources/
# Handles first-run setup, then starts the server and opens the browser.

set -euo pipefail

# ── Extend PATH immediately (macOS .app bundles get a stripped PATH) ──────────
export PATH="/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
PY_FW="/Library/Frameworks/Python.framework/Versions"
for _v in 3.13 3.12 3.11 3.10; do
    [ -d "$PY_FW/$_v/bin" ] && export PATH="$PY_FW/$_v/bin:$PATH"
done
export PATH="$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH"

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_SUPPORT="$HOME/Library/Application Support/Studorge"
VENV="$APP_SUPPORT/venv"
SRC="$SCRIPT_DIR/app"          # bundled source code
DEST="$APP_SUPPORT/app"        # working copy (writable)
PID_FILE="$APP_SUPPORT/server.pid"
LOG_FILE="$APP_SUPPORT/server.log"
PORT=8000
URL="http://localhost:$PORT"

mkdir -p "$APP_SUPPORT"

# ── Helper: simple macOS dialog ───────────────────────────────────────────────
dialog() { osascript -e "display dialog \"$1\" buttons {\"OK\"} default button 1 with title \"Studorge\"" &>/dev/null || true; }
notify() { osascript -e "display notification \"$1\" with title \"Studorge\"" &>/dev/null || true; }

# ── Stop any previous instance on this port ──────────────────────────────────
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$PID_FILE"
fi
# Also clear port just in case
lsof -ti ":$PORT" | xargs kill -9 2>/dev/null || true

# ── Find Python 3.10+ (search all common macOS install locations) ─────────────

PYTHON=""
for candidate in \
    "$PY_FW/3.13/bin/python3" \
    "$PY_FW/3.12/bin/python3" \
    "$PY_FW/3.11/bin/python3" \
    "$PY_FW/3.10/bin/python3" \
    /opt/homebrew/bin/python3.13 \
    /opt/homebrew/bin/python3.12 \
    /opt/homebrew/bin/python3.11 \
    /opt/homebrew/bin/python3.10 \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3.12 \
    /usr/local/bin/python3.11 \
    /usr/local/bin/python3.10 \
    /usr/local/bin/python3 \
    python3.12 python3.11 python3.10 python3; do
    if [ -x "$candidate" ] || command -v "$candidate" &>/dev/null 2>&1; then
        REAL=$(command -v "$candidate" 2>/dev/null || echo "$candidate")
        VER=$("$REAL" -c "import sys; print(sys.version_info >= (3,10))" 2>/dev/null || echo "False")
        if [ "$VER" = "True" ]; then
            PYTHON="$REAL"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    dialog "Python 3.10 or later is required.\n\nPlease install it from https://python.org and relaunch Studorge."
    exit 1
fi

# ── Sync source to writable location ─────────────────────────────────────────
rsync -a --delete "$SRC/" "$DEST/"

# Copy .env template if user hasn't created one yet
if [ ! -f "$APP_SUPPORT/.env" ]; then
    cp "$DEST/.env.example" "$APP_SUPPORT/.env" 2>/dev/null || true
fi
# Symlink .env into working dir
ln -sf "$APP_SUPPORT/.env" "$DEST/.env" 2>/dev/null || true

# ── First-run: create virtualenv + install deps ───────────────────────────────
NEEDS_INSTALL=false
if [ ! -d "$VENV" ]; then
    NEEDS_INSTALL=true
elif [ "$SRC/requirements.txt" -nt "$VENV/.installed_at" ] 2>/dev/null; then
    NEEDS_INSTALL=true
fi

if [ "$NEEDS_INSTALL" = true ]; then
    # Show a progress window via Terminal
    osascript <<'APPLESCRIPT' &
tell application "Terminal"
    activate
    set w to do script ""
    set w's custom title to "Studorge — Installing dependencies…"
end tell
APPLESCRIPT
    TERM_PID=$!

    notify "Installing dependencies (this only happens once)…"

    "$PYTHON" -m venv "$VENV" --clear
    "$VENV/bin/pip" install --upgrade pip --quiet
    "$VENV/bin/pip" install -r "$DEST/requirements.txt" --quiet

    touch "$VENV/.installed_at"

    # Close the terminal window we opened
    kill $TERM_PID 2>/dev/null || true
    osascript -e 'tell application "Terminal" to close (windows whose name contains "Installing dependencies")' &>/dev/null || true

    notify "Setup complete! Starting Studorge…"
fi

# ── Start the server ──────────────────────────────────────────────────────────
cd "$DEST"
nohup "$VENV/bin/python" run.py > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

# ── Wait for server to be ready, then open browser ───────────────────────────
for i in $(seq 1 50); do
    sleep 0.3
    if curl -s --max-time 1 "$URL" > /dev/null 2>&1; then
        open "$URL"
        exit 0
    fi
done

# Fallback open even if health-check timed out
open "$URL"
