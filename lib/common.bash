#!/usr/bin/env bash
# Shared helpers for workday automation scripts
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_ROOT/config.bash"

RODNEY="rodney"
DEBUG_DIR="$SCRIPT_ROOT/debug"
mkdir -p "$DEBUG_DIR"

log() { echo "[$(date +%H:%M:%S)] $*"; }

die() { log "ERROR: $*"; screenshot_debug "error"; exit 2; }

screenshot_debug() {
  local name="${1:-debug}"
  $RODNEY screenshot "$DEBUG_DIR/${name}-$(date +%s).png" 2>/dev/null || true
}

ensure_browser() {
  $RODNEY status &>/dev/null || die "Browser not running. Start with: ./scripts/start-browser.bash"
}

# Wait for an element to NOT exist (up to $2 seconds, default 10)
wait_gone() {
  local selector="$1"
  local timeout="${2:-10}"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    $RODNEY exists "$selector" &>/dev/null || return 0
    sleep 0.5
  done
  return 1
}

nav_and_wait() {
  log "Navigating to $1"
  $RODNEY open "$1"
  $RODNEY waitload
  $RODNEY waitstable
  $RODNEY waitidle
  log "Page ready: $($RODNEY title)"
}

# Navigate to the week containing a given date.
navigate_to_week() {
  local target_date="$1"
  local dom
  dom=$(date -d "$target_date" +%-d)

  if $RODNEY exists "[data-automation-id=\"dayCell-1-${dom}\"]" &>/dev/null; then
    log "Already on correct week"
    return 0
  fi

  # Determine direction from the first visible dayCell, not from wall clock
  local displayed_date direction
  displayed_date=$($RODNEY js '
(() => {
  const cell = document.querySelector("[data-automation-id^=\"dayCell-1-\"]");
  if (!cell) return "";
  const txt = cell.textContent.trim();
  const m = txt.match(/(\d+)\.(\d+)\./);
  if (!m) return "";
  const title = document.querySelector("[data-automation-id=\"dateRangeTitle\"]").textContent;
  const ym = title.match(/(\d{4})/);
  return ym[1] + "-" + m[2].padStart(2,"0") + "-" + m[1].padStart(2,"0");
})()
')
  local target_ts displayed_ts
  target_ts=$(date -d "$target_date" +%s)
  displayed_ts=$(date -d "$displayed_date" +%s)
  direction="nextMonthButton"
  (( target_ts < displayed_ts )) && direction="prevMonthButton"

  for _ in $(seq 1 20); do
    $RODNEY click "[data-automation-id=\"${direction}\"]"
    $RODNEY waitstable
    if $RODNEY exists "[data-automation-id=\"dayCell-1-${dom}\"]" &>/dev/null; then
      log "Navigated to correct week"
      return 0
    fi
  done
  die "Could not navigate to week containing $target_date"
}

# NOTE: JS template variables (search, match, comment, hours) are interpolated
# directly into JS strings. Don't pass values containing single quotes.

# Click empty day column to open Enter Time dialog.
# $1 = day index (0=Mon, 6=Sun)
open_entry_dialog() {
  local day_idx="$1"
  local result
  result=$($RODNEY js "
(() => {
  const sep = document.querySelector('[data-automation-id=\"nonTimedDaySeparator_${day_idx}\"]');
  const scrollArea = document.querySelector('.scroll-area');
  if (!sep || !scrollArea) return 'elements not found';
  const left = sep.getBoundingClientRect().left;
  const nextSep = document.querySelector('[data-automation-id=\"nonTimedDaySeparator_$((day_idx + 1))\"]');
  const right = nextSep ? nextSep.getBoundingClientRect().left : scrollArea.getBoundingClientRect().right;
  const x = (left + right) / 2;
  const y = scrollArea.getBoundingClientRect().top + 150;
  const el = document.elementFromPoint(x, y);
  const opts = {bubbles:true, cancelable:true, clientX:x, clientY:y, button:0};
  el.dispatchEvent(new MouseEvent('mousedown', opts));
  el.dispatchEvent(new MouseEvent('mouseup', opts));
  el.dispatchEvent(new MouseEvent('click', opts));
  return 'clicked at ' + Math.round(x) + ',' + Math.round(y);
})()
")
  log "Open dialog: $result"
  $RODNEY wait '[data-automation-id="popUpDialog"]' || die "Enter Time dialog did not open"
  log "Dialog opened"
}

# Select Time Type (project) in the open dialog.
# $1 = search term (e.g. "PROJ-XXXXX")
# $2 = match substring in result (e.g. "Development > AWS pilvi")
select_time_type() {
  local search="$1"
  local match="$2"
  local result
  result=$($RODNEY js "
(() => {
  const input = document.querySelector('[data-automation-id=\"popUpDialog\"] input[placeholder=\"Search\"]');
  if (!input) return 'search input not found';

  const tryType = () => {
    input.focus();
    input.click();
    document.execCommand('insertText', false, '${search}');
    return input.value.length > 0;
  };

  const pressEnter = () => {
    input.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true, cancelable:true}));
    input.dispatchEvent(new KeyboardEvent('keypress', {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true, cancelable:true}));
    input.dispatchEvent(new KeyboardEvent('keyup', {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true, cancelable:true}));
  };

  const findMatch = () => {
    return [...document.querySelectorAll('[data-automation-id=\"promptOption\"]')].find(e => e.offsetParent !== null && e.textContent.includes('${match}'));
  };

  return new Promise((resolve) => {
    const startSearch = () => {
      let searchTriggered = false;
      const observer = new MutationObserver(() => {
        if (!searchTriggered) {
          const expanded = document.querySelector('[data-automation-id=\"promptAriaInstruction\"]');
          if (expanded && expanded.textContent.includes('Options Expanded')) {
            searchTriggered = true;
            pressEnter();
          }
          return;
        }
        const hit = findMatch();
        if (hit) {
          observer.disconnect();
          hit.click();
          resolve('selected: ' + hit.textContent.substring(0, 100));
        }
      });
      observer.observe(document.body, {childList: true, subtree: true});
      setTimeout(() => {
        observer.disconnect();
        const hit = findMatch();
        if (hit) { hit.click(); resolve('selected: ' + hit.textContent.substring(0, 100)); }
        else {
          const all = [...document.querySelectorAll('[data-automation-id=\"promptOption\"]')].filter(e => e.offsetParent !== null).map(e => e.textContent.substring(0,60));
          resolve('no match. visible options: ' + JSON.stringify(all));
        }
      }, 10000);
    };

    const attempt = (retries) => {
      if (tryType()) { startSearch(); return; }
      if (retries > 0) { setTimeout(() => attempt(retries - 1), 300); return; }
      resolve('insertText failed');
    };
    attempt(5);
  });
})()
")
  log "Time Type: $result"
  [[ "$result" == selected:* ]] || die "Failed to select Time Type: $result"
  # Wait for form to settle — selecting a Time Type may add/remove fields (Do Not Bill, Working time Type, etc.)
  $RODNEY waitstable
}

# Set the "Do Not Bill" checkbox. $1 = desired state ("True"/"true" or "False"/"false")
set_do_not_bill() {
  local desired
  [[ "${1,,}" == "true" ]] && desired="true" || desired="false"
  local result
  result=$($RODNEY js "
(() => {
  const dlg = document.querySelector('[data-automation-id=\"popUpDialog\"]');
  const cb = dlg.querySelector('[data-automation-id=\"checkboxPanel\"] input[type=\"checkbox\"]');
  if (!cb) return 'no checkbox';
  if (cb.checked === ${desired}) return 'already ' + cb.checked;
  cb.click();
  return 'set to ' + cb.checked;
})()
")
  log "Do Not Bill: $result"
}

# Set hours in the open dialog. $1 = hours (e.g. "7,5")
set_hours() {
  local hours="$1"
  local result
  result=$($RODNEY js "
(() => {
  const input = document.querySelector('[data-automation-id=\"popUpDialog\"] [data-automation-id=\"numericInput\"]');
  if (!input) return 'hours input not found';
  input.focus();
  input.click();
  document.execCommand('selectAll');
  document.execCommand('delete');
  document.execCommand('insertText', false, '${hours}');
  return 'set: ' + input.value;
})()
")
  log "Hours: $result"
}

# Set comment in the open dialog. $1 = comment text
set_comment() {
  local comment="$1"
  [[ -z "$comment" ]] && return 0
  local result
  result=$($RODNEY js "
(() => {
  const ta = document.querySelector('[data-automation-id=\"popUpDialog\"] [data-automation-id=\"textAreaField\"]');
  if (!ta) return 'comment field not found';
  ta.focus();
  ta.click();
  document.execCommand('insertText', false, '${comment}');
  return 'set: ' + ta.value;
})()
")
  log "Comment: $result"
}

# Click OK to submit the entry
click_ok() {
  $RODNEY waitstable
  local result
  result=$($RODNEY js "
(() => {
  document.activeElement && document.activeElement.blur();
  const btns = [...document.querySelectorAll('[data-automation-id=\"popUpDialog\"] [data-automation-id=\"wd-CommandButton\"]')];
  const ok = btns.find(b => b.textContent.trim() === 'OK');
  if (ok) { ok.click(); return 'clicked'; }
  return 'OK button not found';
})()
")
  log "OK: $result"
  [[ "$result" == "clicked" ]] || die "Failed to click OK: $result"
  if ! wait_gone '[data-automation-id="popUpDialog"]' 10; then
    screenshot_debug "ok-failed"
    die "Dialog still open after clicking OK"
  fi
  log "Entry submitted"
}

# Get the day-of-week index (0=Mon..6=Sun) for a date string (YYYY-MM-DD)
date_to_day_index() {
  local dow
  dow=$(date -d "$1" +%u)  # 1=Mon, 7=Sun
  echo $((dow - 1))
}

# Get calendar event IDs for a date, optionally filtered by text match.
# $1 = date (YYYY-MM-DD), $2 = match substring (optional)
# Outputs one event ID per line.
get_entry_ids() {
  local date="$1"
  local match="${2:-}"
  local month day startdate
  month=$(date -d "$date" +%-m)
  day=$(date -d "$date" +%-d)
  startdate="${month}-${day}-0-0"
  $RODNEY js "
(() => {
  const events = [...document.querySelectorAll('[data-automation-id=\"calendarevent\"]')];
  return events
    .filter(e => e.getAttribute('data-automation-startdate') === '${startdate}')
    .filter(e => !e.textContent.includes('Balance (generated automatically)'))
    .filter(e => '${match}' === '' || e.textContent.includes('${match}'))
    .map(e => e.getAttribute('data-automation-eventid'))
    .join('\n');
})()
" | sed '/^$/d'
}

# Open an existing entry by event ID.
open_existing_entry() {
  local eventid="$1"
  $RODNEY click "[data-automation-id=\"calendarevent\"][data-automation-eventid=\"${eventid}\"]"
  $RODNEY wait '[data-automation-id="popUpDialog"]' || die "Dialog did not open for event $eventid"
}

# Parse a date range string. Outputs one YYYY-MM-DD per line.
# Accepts: YYYY-MM-DD (single), YYYY-MM-DD..YYYY-MM-DD (range), "today", "this-week"
expand_dates() {
  local spec="$1"
  case "$spec" in
    today) date +%Y-%m-%d ;;
    this-week)
      local mon
      mon=$(date -d "last monday" +%Y-%m-%d 2>/dev/null)
      # If today is monday, "last monday" gives last week
      [[ "$(date +%u)" == "1" ]] && mon=$(date +%Y-%m-%d)
      for i in $(seq 0 4); do date -d "$mon + $i days" +%Y-%m-%d; done
      ;;
    *..*)
      local start="${spec%..*}" end="${spec#*..}"
      local cur="$start"
      while [[ "$cur" < "$end" || "$cur" == "$end" ]]; do
        echo "$cur"
        cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
      done
      ;;
    *) echo "$spec" ;;
  esac
}

# Read fields from an open entry dialog. Outputs JSON.
read_entry() {
  $RODNEY js '
(() => {
  const dlg = document.querySelector("[data-automation-id=\"popUpDialog\"]");
  if (!dlg) return JSON.stringify({error: "no dialog"});
  const hours = dlg.querySelector("[data-automation-id=\"numericInput\"]");
  const comment = dlg.querySelector("[data-automation-id=\"textAreaField\"]");
  const cb = dlg.querySelector("[data-automation-id=\"checkboxPanel\"] input[type=\"checkbox\"]");
  return JSON.stringify({
    hours: hours ? hours.value : null,
    comment: comment ? (comment.value ?? comment.textContent ?? null) : null,
    doNotBill: cb ? cb.checked : null
  });
})()
'
}

# Delete the currently open entry (clicks Delete, confirms).
delete_entry() {
  local result
  result=$($RODNEY js '
(() => {
  const btns = [...document.querySelectorAll("[data-automation-id=\"popUpDialog\"] [data-automation-id=\"wd-CommandButton\"]")];
  const del = btns.find(b => b.textContent.trim() === "Delete");
  if (del) { del.click(); return "clicked"; }
  return "no delete button";
})()
')
  log "Delete: $result"
  [[ "$result" == "clicked" ]] || die "Failed to click Delete: $result"
  $RODNEY wait '[data-automation-id="wd-CommandButton_uic_okButton"]' || die "Delete confirmation did not appear"
  $RODNEY click '[data-automation-id="wd-CommandButton_uic_okButton"]'
  $RODNEY waitstable
  if ! wait_gone '[data-automation-id="popUpDialog"]' 10; then
    screenshot_debug "delete-failed"
    die "Dialog still open after delete confirmation"
  fi
  log "Entry deleted"
}
