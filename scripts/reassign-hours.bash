#!/usr/bin/env bash
# Reassign time entries from one project/subproject to another.
# Preserves hours and comments. Handles Do Not Bill checkbox.
#
# Usage: ./scripts/reassign-hours.bash DATE_OR_RANGE OLD_MATCH NEW_SEARCH NEW_MATCH
#
# Examples:
#   # Single day
#   ./scripts/reassign-hours.bash 2026-02-18 "Development > AWS pilvi" PROJ-009707 "Other > Solitan"
#
#   # Date range
#   ./scripts/reassign-hours.bash 2026-02-16..2026-02-20 "Development > AWS pilvi" PROJ-009707 "Other > Solitan"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.bash"

DATE_SPEC="${1:?Usage: $0 DATE_OR_RANGE OLD_MATCH NEW_SEARCH NEW_MATCH}"
OLD_MATCH="${2:?Usage: $0 DATE_OR_RANGE OLD_MATCH NEW_SEARCH NEW_MATCH}"
NEW_SEARCH="${3:?Usage: $0 DATE_OR_RANGE OLD_MATCH NEW_SEARCH NEW_MATCH}"
NEW_MATCH="${4:?Usage: $0 DATE_OR_RANGE OLD_MATCH NEW_SEARCH NEW_MATCH}"

ensure_browser
nav_and_wait "$WORKDAY_URL"

mapfile -t DATES < <(expand_dates "$DATE_SPEC")
log "Reassigning ${#DATES[@]} day(s): ${DATES[*]}"

total=0
for date in "${DATES[@]}"; do
  navigate_to_week "$date"

  mapfile -t ids < <(get_entry_ids "$date" "$OLD_MATCH")
  [[ ${#ids[@]} -eq 0 || -z "${ids[0]}" ]] && { log "No matching entries on $date, skipping"; continue; }

  for eventid in "${ids[@]}"; do
    [[ -z "$eventid" ]] && continue
    log "Processing entry $eventid on $date"

    # Read existing entry
    open_existing_entry "$eventid"
    entry_json=$(read_entry)
    hours=$(echo "$entry_json" | jq -r '.hours')
    comment=$(echo "$entry_json" | jq -r '.comment // ""')
    do_not_bill=$(echo "$entry_json" | jq -r '.doNotBill')
    log "  Read: ${hours}h, comment='${comment}', doNotBill=${do_not_bill}"

    # Delete it
    delete_entry
    $RODNEY waitidle

    # Recreate with new project
    day_idx=$(date_to_day_index "$date")
    open_entry_dialog "$day_idx"
    select_time_type "$NEW_SEARCH" "$NEW_MATCH"
    set_do_not_bill "$do_not_bill"
    set_hours "$hours"
    set_comment "$comment"
    click_ok

    log "  Reassigned: ${hours}h on $date"
    ((total++)) || true
  done
done

log "Done! Reassigned $total entries."
