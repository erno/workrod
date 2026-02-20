# workrod

Personal workday automation tool built on top of [rodney](https://github.com/simonw/rodney) — a CLI for driving a persistent headless Chrome instance via CDP.

## What is Rodney?

Rodney is a Go CLI that manages a long-running headless Chrome via DevTools Protocol. Each command is a short-lived process that connects to the same Chrome instance over WebSocket. Key capabilities we'll use:
- `connect` — attach to an existing Chrome with remote debugging
- `open`, `click`, `input`, `select`, `submit` — navigate and interact with pages
- `wait`, `waitstable`, `waitidle`, `waitload` — wait for conditions
- `js` — evaluate arbitrary JS in page context
- `text`, `html`, `attr`, `exists`, `visible` — extract info / check state
- `screenshot` — capture page state for debugging
- Exit codes: 0=success, 1=check failed, 2=error

Note: rodney's `input` command doesn't work with Workday's GWT framework. We use `document.execCommand("insertText")` via `rodney js` instead. See dom-details.md.

## Goals

Automate repetitive browser-based workday tasks (time tracking, status updates, etc.) via shell scripts that call rodney. Personal use, not production.

## Architecture

```
spare-the-rod-spoil-the-workday/
├── PLAN.md                    # this file
├── dom-details.md             # DOM selectors and interaction patterns
├── .gitignore
├── lib/
│   └── common.bash            # rodney wrappers, helpers, all Workday interaction logic
├── scripts/
│   ├── start-browser.bash     # launch Chrome + rodney connect
│   └── enter-hours.bash       # enter hours for a given date
├── debug/                     # screenshots for debugging (gitignored)
└── .rodney/                   # Chrome data dir + pid (gitignored)
```

- Bash scripts — no extra dependencies beyond stock rodney + Chrome + standard unix tools
- Chrome launched manually with `--remote-debugging-port=19222`, rodney connects to it
- Chrome data dir persists in `.rodney/chrome-data/` for session reuse
- Each script sources `lib/common.bash` for shared setup

## Shared helpers (`lib/common.bash`)

Implemented:
- `ensure_browser` — check rodney is running
- `nav_and_wait <url>` — open + waitstable + waitidle
- `navigate_to_week <date>` — navigate to the week containing a date (prev/next buttons)
- `open_entry_dialog <day_idx>` — click empty day column via JS mouse events
- `select_time_type <search> <match>` — search and select project (single JS call with MutationObserver)
- `set_hours <hours>` — set hours via execCommand
- `set_comment <comment>` — set comment via execCommand
- `click_ok` — submit and verify dialog closes
- `date_to_day_index <date>` — convert YYYY-MM-DD to 0=Mon..6=Sun
- `log`, `die`, `screenshot_debug` — logging and error handling

## Scope

### Stage 1: Hour entry
Automate entering hours for a given day/period. Input: date(s), project, hours, description. Script fills in the time tracking form.

### Stage 2: Revise existing hours
View and modify already-entered hours for a month — e.g. reassign hours to a different project, adjust descriptions or amounts.

## Target app

Workday "Enter My Time" — weekly view at `https://wd3.myworkday.com/<company>/d/task/2998$10895.htmld`

Authentication: Company Entra SSO. **Not automated** — user logs in manually via the visible Chrome window launched by `start-browser.bash`.

### "Enter Time" dialog fields

| Field             | Required | Notes                                                        |
|-------------------|----------|--------------------------------------------------------------|
| Date              | yes      | Shown as header (e.g. "16.02.2026"), selected by clicking a day cell in the week view |
| Time Type         | yes*     | Project picker (searchable). e.g. "PROJ-XXXXX Company Project..." |
| Hours             | yes*     | Decimal with comma (Finnish locale), e.g. "7,5"             |
| Do Not Bill       | no       | Checkbox, unchecked by default                               |
| Working time Type | no       | Picker, usually left empty                                   |
| Comment           | no       | Free text, e.g. "pilviasiantuntijatyö"                      |
| OK / Cancel / Delete | —     | Submit buttons at bottom                                     |

### DOM and interaction details

See [dom-details.md](dom-details.md) for full selector map, event dispatch patterns, and dialog field mappings.

Key takeaway: opening a new time entry requires dispatching mousedown+mouseup+click via JS at calculated coordinates. Existing entries can be clicked directly via rodney.

### Workflow to automate (stage 1)

1. Ensure browser is running and logged in (manual login)
2. Navigate to "Enter My Time" page
3. Navigate to correct week (prev/next buttons or check `dateRangeTitle`)
4. Calculate click coordinates for target day column
5. Dispatch mousedown+mouseup+click to open "Enter Time" dialog
6. Wait for dialog (`[dai="popUpDialog"]`)
7. Select Time Type (search & pick from dropdown) — **always first**
8. Wait for form to settle after Time Type selection
9. Fill Hours (`[dai="numericInput"]`)
10. Optionally fill Comment (`[dai="textAreaField"]`)
11. Click OK
12. Wait for dialog to close
13. Repeat for multiple days if needed

## Open questions / things to research

- [x] ~~Time Type picker~~ — solved: execCommand + MutationObserver + Enter key, all in one JS call
- [x] ~~Week navigation~~ — solved: check dayCell existence, click prev/next buttons
- [x] ~~Stock rodney compatibility~~ — solved: launch Chrome ourselves, use `rodney connect`
- [ ] Hardcoded sleeps in common.bash — replace with DOM-based waits for robustness
- [ ] Input format for batch entry — currently CLI args, could add CSV/config file support
- [ ] Multiple projects per day — untested, should work by running script twice for same date
- [ ] Error handling for duplicate entries — what happens if entry already exists for that day+project?

## Conventions

- Scripts should be idempotent where possible
- Always `waitstable` or `wait <selector>` after navigation
- Use `set -euo pipefail` in all scripts
- Exit code 2 from rodney = real error → abort immediately
- Screenshots go to a `debug/` dir (gitignored)
- **Don't use `git add -A`** — there will be stray debug files, screenshots, etc. Stage files explicitly.

## Changelog

- **2026-02-18** — Initial plan created. Rodney v0.4.0 confirmed in PATH.
- **2026-02-18** — Mapped DOM selectors. Cracked Time Type picker interaction. Built and tested working `enter-hours.bash` script. Stage 1 MVP complete.
- **2026-02-19** — Refactored to stock rodney: launch Chrome with `--remote-debugging-port`, use `rodney connect`. No patched binary needed.
- **2026-02-20** — Fixed week navigation: direction was based on wall clock (`now`) instead of the currently displayed week, causing infinite backward clicks when navigating to today from a past week. Now reads the displayed week from the DOM to determine direction.
