# workrod

Automate Workday time entry using [rodney](https://github.com/simonw/rodney) and bash.

## Motivation

The Workday time entry web UI is... not universally loved. If you'd rather script your time tracking than click through the same forms every day, this is for you.

## What it does

- Opens time entry dialogs for specific dates
- Fills in project, hours, and comments
- Submits entries automatically
- Uses a persistent Chrome session so you only log in once

## Setup

1. Install [rodney](https://github.com/simonw/rodney)
2. Clone this repo
3. Copy `config.example.bash` to `config.bash` and fill in your Workday URL and default project
4. Start the browser: `./scripts/start-browser.bash`
5. Log in to Workday manually in the browser window that opens

## Usage

```bash
./scripts/enter-hours.bash today 7,5 PROJ-12345 'Development > Task' 'worked on stuff'
```

Arguments: date, hours, project search term, project match string, comment

## How it works

Rodney drives a persistent headless Chrome via the DevTools Protocol. Each script command connects to the same browser instance, so your login session persists. The scripts use DOM selectors and JavaScript execution to interact with Workday's GWT-based UI.

See `PLAN.md` and `dom-details.md` for implementation details.

## Stopping the browser

```bash
./scripts/start-browser.bash --stop
```

## License

[MIT](https://opensource.org/licenses/MIT)

## Note

All code in this project was produced by a coding assistant, with human direction and review.

## Disclaimer

Personal automation tool. Use at your own risk. Not affiliated with Workday.
