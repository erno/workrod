#!/usr/bin/env bash
# Enter hours for a given date
#
# Usage: ./scripts/enter-hours.bash DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]
#
# Examples:
#   ./scripts/enter-hours.bash 2026-02-18 7,5 "pilviasiantuntijatyö"
#   ./scripts/enter-hours.bash today 7,5 PROJ-XXXXX "Development > Other" "custom comment"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.bash"

# Parse args - use config defaults if not provided
DATE="${1:?Usage: $0 DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]}"
HOURS="${2:?Usage: $0 DATE HOURS [PROJECT_SEARCH] [PROJECT_MATCH] [COMMENT]}"
SEARCH="${3:-$PROJECT_SEARCH}"
MATCH="${4:-$PROJECT_MATCH}"
COMMENT="${5:-}"

# Resolve "today" etc
[[ "$DATE" == "today" ]] && DATE=$(date +%Y-%m-%d)

log "Entering $HOURS hours on $DATE for $SEARCH"

ensure_browser
nav_and_wait "$WORKDAY_URL"
navigate_to_week "$DATE"

DAY_IDX=$(date_to_day_index "$DATE")
log "Day index: $DAY_IDX"

open_entry_dialog "$DAY_IDX"
select_time_type "$SEARCH" "$MATCH"
set_hours "$HOURS"
set_comment "$COMMENT"
click_ok

log "Done! $HOURS hours entered for $DATE"
