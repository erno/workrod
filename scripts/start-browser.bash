#!/usr/bin/env bash
# Launch Chrome with remote debugging and connect rodney to it.
# Usage: ./scripts/start-browser.bash [--stop]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_DIR="$PROJECT_DIR/.rodney/chrome-data"
PORT=19222
PIDFILE="$PROJECT_DIR/.rodney/chrome.pid"
CHROME="${CHROME_BIN:-google-chrome}"

mkdir -p "$PROJECT_DIR/.rodney"

stop_browser() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "Chrome stopped (PID $pid)"
    fi
    rm -f "$PIDFILE"
  fi
  rodney stop 2>/dev/null || true
}

if [[ "${1:-}" == "--stop" ]]; then
  stop_browser
  exit 0
fi

# Stop any existing instance
stop_browser

# Launch Chrome
"$CHROME" \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$DATA_DIR" \
  --no-first-run \
  --no-default-browser-check \
  &>/dev/null &

echo "$!" > "$PIDFILE"
sleep 2

# Connect rodney
rodney connect "localhost:$PORT"
echo "Ready. Log in to Workday if needed, then run scripts."
