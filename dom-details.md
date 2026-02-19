# Workday DOM Details

Reference for automating the "Enter My Time" page at `https://wd3.myworkday.com/<company>/d/task/2998$10895.htmld`.

Workday is a GWT (Google Web Toolkit) app. All custom components use `data-automation-id` attributes for identification.

## Rodney setup

- Stock rodney works — no patches needed
- We launch Chrome ourselves with `--remote-debugging-port=19222` via `scripts/start-browser.bash`
- Then `rodney connect localhost:19222` attaches to it
- This gives a visible browser window for manual login, and rodney can drive it
- Chrome data dir is `.rodney/chrome-data/` — cookies should persist between runs (untested how long Entra SSO sessions last)
- Auth is Entra SSO — done manually in the browser, at least on first run
- Port 19222 chosen to avoid conflict with the standard 9222 used by other tools

## Weekly view structure

The week view is a table-based layout inside `[data-automation-id="weeklyBody"]`.

Day column headers:
```
[data-automation-id="dayCell-1-{dayOfMonth}"]  e.g. dayCell-1-18 for the 18th
```

Hours summary row (0=Monday, 6=Sunday):
```
[data-automation-id="hoursEntered_{0-6}"]  text content like "Hours: 7,5"
```

Day column separators (vertical lines, also 0=Mon, 6=Sun):
```
[data-automation-id="nonTimedDaySeparator_{0-6}"]
```
Today's separator has `data-automation-todaycell="true"`.

Existing time entries appear as:
```
[data-automation-id="calendarevent"]
```
With attributes: `data-automation-startdate`, `data-automation-eventid`, `data-automation-allday`.

Week navigation:
```
[data-automation-id="prevMonthButton"]   — previous week
[data-automation-id="nextMonthButton"]   — next week
[data-automation-id="todayButton"]       — jump to current week
[data-automation-id="dateRangeTitle"]    — displays e.g. "16.–22. helmikuuta 2026"
```

## Opening the "Enter Time" dialog

### For a NEW entry (empty day)

**rodney's `click` command does NOT work** on the empty day column area. The calendar body has a transparent full-size overlay div (`position: absolute; height: 100%; width: 100%`) that captures clicks. Workday's GWT event handling requires a full mousedown→mouseup→click sequence dispatched via JS:

```js
(() => {
  const el = document.elementFromPoint(x, y);
  const opts = {bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0};
  el.dispatchEvent(new MouseEvent("mousedown", opts));
  el.dispatchEvent(new MouseEvent("mouseup", opts));
  el.dispatchEvent(new MouseEvent("click", opts));
  return "dispatched";
})()
```

To calculate `x` for a given day column:
- Get `left` of `nonTimedDaySeparator_{idx}` and `nonTimedDaySeparator_{idx+1}`
- `x` = midpoint between them
- For the last day (Sunday, idx=6), use right edge of scroll area

To calculate `y`:
- Get `top` of `.scroll-area` element
- Add some offset (e.g. 150px) to land in the middle of the empty area
- Tested working value: scroll-area top was 234, used y=400

**Important:** Coordinates are calculated dynamically from separator positions, so viewport size shouldn't matter in practice. The `open_entry_dialog` function in `lib/common.bash` handles this.

### For an EXISTING entry

rodney's native click works fine:
```
rodney click '[data-automation-id="calendarevent"]'
```

## "Enter Time" dialog

The dialog appears as `[data-automation-id="popUpDialog"]` with `role="dialog"`.

### Fields (new entry — minimal form)

| Field | Selector | Notes |
|-------|----------|-------|
| Date | `[data-automation-id="textView"]` inside dialog | Read-only, e.g. "18.02.2026" |
| Time Type | `[data-automation-id="multiselectInputContainer"]` inside the first `[data-automation-id="formLabelRequired"]` | Searchable picker, required |
| Hours | `[data-automation-id="numericInput"]` | `type="text"`, uses comma for decimal (Finnish locale, e.g. "7,5") |
| Comment | `[data-automation-id="textAreaField"]` | `role="textbox"`, optional |

### Fields (after Time Type selected — may show additional fields)

These appear dynamically depending on the selected project:
- **Do Not Bill** — `[data-automation-id="checkboxPanel"]`
- **Working time Type** — second `[data-automation-id="multiselectInputContainer"]`

### Buttons

| Button | Selector |
|--------|----------|
| OK | `[data-automation-id="wd-CommandButton"]` with text "OK" (inside `[data-automation-id="mtxToolbarContainer"]`) |
| Cancel | `[data-automation-id="wd-CommandButton_uic_cancelButton"]` |
| Delete | `[data-automation-id="wd-CommandButton"]` with text "Delete" (only on existing entries) |
| Close (X) | `[data-automation-id="closeButton"]` |

### Critical behavior: fill order matters

1. **Select Time Type FIRST** — the form fields are dynamic and depend on the selected project
2. **Changing Time Type can reset already-filled fields** — never change it after filling Hours/Comment
3. **Fill order: Time Type → (wait for form to settle) → Hours → Comment → OK**

## Time Type picker interaction

**Tested and working (2026-02-18).**

The picker is a Workday multiselect with search. Every step must happen in a **single `rodney js` call** because each rodney command creates a new CDP connection, which causes focus loss and closes the dropdown.

### Flow

1. Focus + click the search input: `input[placeholder="Search"]` inside `[data-automation-id="multiselectInputContainer"]`
2. Type search term via `document.execCommand("insertText", false, "PROJ-XXXXX")`
3. Wait for dropdown to appear — detected by `[data-automation-id="promptAriaInstruction"]` containing "Options Expanded"
4. Dispatch Enter key events on the input to trigger the actual search:
   ```js
   input.dispatchEvent(new KeyboardEvent("keydown",  {key:"Enter", code:"Enter", keyCode:13, which:13, bubbles:true, cancelable:true}));
   input.dispatchEvent(new KeyboardEvent("keypress", {key:"Enter", code:"Enter", keyCode:13, which:13, bubbles:true, cancelable:true}));
   input.dispatchEvent(new KeyboardEvent("keyup",    {key:"Enter", code:"Enter", keyCode:13, which:13, bubbles:true, cancelable:true}));
   ```
5. Wait ~3s for search results to load
6. Find and click the matching `[data-automation-id="promptOption"]` element

### Dropdown categories (before search)

When the dropdown first opens it shows category headers (`role="option"`, `data-automation-id="menuItem"`):
- Most Recently Used
- Default Projects
- Projects
- Project Plan Tasks
- Absence

After pressing Enter with a search term, it shows filtered results as `[data-automation-id="promptOption"]` elements with full project paths like:
```
PROJ-XXXXX Company Project (Person Name) > Development > Task Description (01.03.2025 - 29.01.2029)
```

### Key gotchas

- **rodney's `input` command doesn't work** — it types text but doesn't trigger Workday's framework change detection
- **`document.execCommand("insertText")`** is the only reliable way to type — it triggers native input events that the framework picks up
- **Every rodney command (including `screenshot`) closes the dropdown** because it creates a new CDP connection causing focus loss
- **All dropdown interaction must happen in one `rodney js` Promise** — use `MutationObserver` to detect dropdown appearance, `setTimeout` for delays

### Full working example: select Time Type

```bash
rodney --local js '
(() => {
  const input = document.querySelector("[data-automation-id=\"popUpDialog\"] input[placeholder=\"Search\"]");
  input.focus();
  input.click();
  document.execCommand('insertText', false, 'PROJ-XXXXX');

  return new Promise((resolve) => {
    const observer = new MutationObserver(() => {
      const expanded = document.querySelector("[data-automation-id=\"promptAriaInstruction\"]");
      if (expanded && expanded.textContent.includes("Options Expanded")) {
        observer.disconnect();
        // Press Enter to trigger search
        input.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true}));
        input.dispatchEvent(new KeyboardEvent("keypress", {key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true}));
        input.dispatchEvent(new KeyboardEvent("keyup", {key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true}));

        // Wait for search results, then click matching option
        setTimeout(() => {
          const match = [...document.querySelectorAll("[data-automation-id=\"promptOption\"]")].find(e => e.offsetParent !== null && e.textContent.includes("Development > AWS pilvi"));
          if (match) {
            match.click();
            resolve("selected: " + match.textContent.substring(0, 100));
          } else {
            resolve("no match found");
          }
        }, 3000);
      }
    });
    observer.observe(document.body, {childList: true, subtree: true, attributes: true});
    setTimeout(() => { observer.disconnect(); resolve("timeout"); }, 10000);
  });
})()
'
```

## "Discard Changes?" confirmation dialog

Appears when cancelling/closing the Enter Time dialog after making changes (e.g. selecting a Time Type).

| Button | Selector | Action |
|--------|----------|--------|
| Discard | `[data-automation-id="wd-CommandButton_uic_genericYesButton"]` | Discards changes, closes both dialogs |
| Continue | `[data-automation-id="uic_genericNoButton"]` | Returns to the Enter Time dialog |

## JS evaluation quirks with rodney

- rodney wraps expressions in `() => { return (expr); }`
- Multi-statement JS needs to be wrapped in an IIFE: `(() => { ...; return result; })()`
- `var` declarations cause syntax errors — use `let`/`const` or IIFE
- Strings with nested quotes need careful escaping in shell
