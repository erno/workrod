#!/usr/bin/env bash
# Enter hours for a given date
#
# Usage: ./scripts/enter-hours.bash [--set-billable yes|no] DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]
#
# Examples:
#   ./scripts/enter-hours.bash 2026-02-18 7,5
#   ./scripts/enter-hours.bash --set-billable yes 2026-02-18 1 PROJ-009707 "Other > Solitan" "internal work"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.bash"

SET_BILLABLE=""
if [[ "${1:-}" == "--set-billable" ]]; then
  SET_BILLABLE="${2:?--set-billable requires yes or no}"
  [[ "$SET_BILLABLE" == "yes" || "$SET_BILLABLE" == "no" ]] || { echo "Error: --set-billable must be yes or no"; exit 1; }
  shift 2
fi

DATE="${1:?Usage: $0 [--set-billable yes|no] DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]}"
HOURS="${2:?Usage: $0 [--set-billable yes|no] DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]}"
SEARCH="${3:-$PROJECT_SEARCH}"
MATCH="${4:-$PROJECT_MATCH}"
[[ "$SEARCH" == "default" ]] && SEARCH="$PROJECT_SEARCH"
[[ "$MATCH" == "default" ]] && MATCH="$PROJECT_MATCH"
COMMENT="${5:-$DEFAULT_COMMENT}"
[[ "$COMMENT" == "default" ]] && COMMENT="$DEFAULT_COMMENT"

[[ "$DATE" == "today" ]] && DATE=$(date +%Y-%m-%d)

log "Entering $HOURS hours on $DATE for $SEARCH"

ensure_browser
nav_and_wait "$WORKDAY_URL"
navigate_to_week "$DATE"

DAY_IDX=$(date_to_day_index "$DATE")
log "Day index: $DAY_IDX"

open_entry_dialog "$DAY_IDX"
select_time_type "$SEARCH" "$MATCH"
# billable = yes means Do Not Bill = false, and vice versa
[[ -n "$SET_BILLABLE" ]] && set_do_not_bill "$( [[ "$SET_BILLABLE" == "yes" ]] && echo false || echo true )"
set_hours "$HOURS"
set_comment "$COMMENT"
click_ok

log "Done! $HOURS hours entered for $DATE"
