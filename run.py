"""One-command launcher: starts the backend and opens the browser."""
import os
import sys
import time
import socket
import threading
import webbrowser
import urllib.request
import urllib.error

# When packaged inside Studorge.app the launcher script sets CWD to the
# writable app copy in ~/Library/Application Support/Studorge/app.
# Make sure that directory is on sys.path so backend imports work.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import uvicorn

URL = "http://localhost:8000"


def _wait_and_open():
    """Poll until the server is ready, then open the browser once."""
    for _ in range(50):          # up to ~10 s
        time.sleep(0.2)
        try:
            urllib.request.urlopen(URL, timeout=1)
            webbrowser.open(URL)
            return
        except (urllib.error.URLError, OSError):
            pass
    webbrowser.open(URL)


def _port_in_use(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(("localhost", port)) == 0


if __name__ == "__main__":
    if _port_in_use(8000):
        print("⚠️  Port 8000 already in use — opening browser directly.")
        webbrowser.open(URL)
        sys.exit(0)

    threading.Thread(target=_wait_and_open, daemon=True).start()

    print(f"🚀  Starting Studorge at {URL}")
    uvicorn.run(
        "backend.app:app",
        host="0.0.0.0",
        port=8000,
        reload=False,   # reload=False when running from bundle
    )
