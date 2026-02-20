#!/usr/bin/env bash
# Enter hours for a given date
#
# Usage: ./scripts/enter-hours.bash [--no-bill] DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]
#
# Examples:
#   ./scripts/enter-hours.bash 2026-02-18 7,5
#   ./scripts/enter-hours.bash --no-bill 2026-02-18 1 PROJ-009707 "Other > Solitan" "internal work"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.bash"

NO_BILL=false
[[ "${1:-}" == "--no-bill" ]] && { NO_BILL=true; shift; }

DATE="${1:?Usage: $0 [--no-bill] DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]}"
HOURS="${2:?Usage: $0 [--no-bill] DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]}"
SEARCH="${3:-$PROJECT_SEARCH}"
MATCH="${4:-$PROJECT_MATCH}"
COMMENT="${5:-}"

[[ "$DATE" == "today" ]] && DATE=$(date +%Y-%m-%d)

log "Entering $HOURS hours on $DATE for $SEARCH (no-bill=$NO_BILL)"

ensure_browser
nav_and_wait "$WORKDAY_URL"
navigate_to_week "$DATE"

DAY_IDX=$(date_to_day_index "$DATE")
log "Day index: $DAY_IDX"

open_entry_dialog "$DAY_IDX"
select_time_type "$SEARCH" "$MATCH"
$NO_BILL && set_do_not_bill true
set_hours "$HOURS"
set_comment "$COMMENT"
click_ok

log "Done! $HOURS hours entered for $DATE"
