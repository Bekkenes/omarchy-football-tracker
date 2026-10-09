# Football Tracker

An [Omarchy](https://omarchy.org/) shell plugin that tracks your favorite
football teams from the bar:

- A bar widget showing your next kickoff, or a live score while a favorite
  team is playing.
- Desktop notifications: the day a favorite team plays, 15 minutes before
  kickoff, at kickoff, and for every goal / card / substitution during the
  match — each with a colored icon (green goal, yellow/red card, blue sub).
- A popup (click the bar widget) listing recent match events as cards and
  upcoming fixtures.
- Works with any team [API-Football](https://www.api-football.com/) knows
  about — Premier League and Eliteserien/Tippeligaen (Norway) both work out
  of the box, pick any team by name.
- Built-in settings form in the popup itself (API key + favorite teams) —
  no editing config files by hand.

## Install

```
omarchy plugin add https://github.com/bekkenes/omarchy-football-tracker.git --enable
```

Or by hand:

```
git clone https://github.com/bekkenes/omarchy-football-tracker.git \
  ~/.config/omarchy/plugins/io.github.bekkenes.football-tracker
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.bekkenes.football-tracker
```

## Setup

Click the bar widget (it shows a plain ball icon until configured) → **Settings**.

You'll need a free API key from **API-Football**:

1. Go to https://dashboard.api-football.com/register
2. Sign up (free) and confirm your email.
3. Copy the "API-KEY" value from your dashboard.
4. Paste it into the API key field in the popup and hit **Save**.

The free plan gives 100 requests/day. This plugin's live-match polling
(every 3 minutes by default) is designed to comfortably stay within that.

Then type your favorite teams into the "Favorite teams" field, comma
separated (e.g. `Liverpool, Rosenborg`), and **Save**. Each name is matched
against API-Football's team search; you'll get a notification confirming
what was matched (or if nothing was found). Editing the field later and
saving again replaces the list — remove a name to stop tracking that team.

For more precise team picking (a live search with multiple results to
choose from, useful for ambiguous names), use the **Search teams
(terminal)** button in the same popup, or run directly:

```
~/.config/omarchy/plugins/io.github.bekkenes.football-tracker/bin/setup.sh
```

## How it works

- `bin/poll.sh`, run every minute by a systemd `--user` timer
  (`omarchy-football-tracker.timer`), checks your favorite teams' cached
  fixtures, fires day-of/15-min/kickoff notifications from the cache alone
  (no API call needed), and only calls the API when a match is actually in
  its live window — fetching the live score and any new events (goals,
  cards, subs), diffing against previously-seen events so each one notifies
  exactly once.
- It writes `~/.local/state/omarchy-football-tracker/state.json`, which
  `BarWidget.qml` reads (and live-reloads) to render the bar indicator and
  popup. The widget itself never talks to the network directly — all API
  calls happen in the bash backend.
- Config lives in `~/.config/omarchy-football-tracker/config.json`
  (favorite teams, poll interval, whether a key is set) and
  `~/.config/omarchy-football-tracker/api_key` (mode 600, plain text,
  never committed or synced anywhere by this plugin).
- Icons are bundled, recolored SVGs derived from
  [Lucide](https://lucide.dev/) (ISC license — see `THIRD_PARTY_NOTICES.md`).

## Testing without waiting for a real match

```
~/.config/omarchy/plugins/io.github.bekkenes.football-tracker/bin/poll.sh --simulate
```

Seeds a fake live match with a goal and a card, firing one notification per
step and updating the bar widget — no API key or real match required. Good
for checking the icons/notifications look right after any changes.

## Troubleshooting

- `systemctl --user status omarchy-football-tracker.timer` — confirm the
  poller is scheduled.
- `journalctl --user -u omarchy-football-tracker.service` — see the last
  poll runs.
- `~/.config/omarchy/plugins/io.github.bekkenes.football-tracker/bin/poll.sh`
  (no flags) — run a poll manually and watch its stderr output live.

## Remove

```
omarchy plugin remove io.github.bekkenes.football-tracker
systemctl --user disable --now omarchy-football-tracker.timer
rm -f ~/.config/systemd/user/omarchy-football-tracker.{service,timer}
rm -rf ~/.config/omarchy-football-tracker ~/.local/state/omarchy-football-tracker
```

## Tests

```
test/run.sh
```

Requires `bash`, `jq` (or a compatible implementation) and `node` 18+ for the
`Model.js` unit tests. Nothing in the suite touches the network, your real
plugin config or the running shell: `poll.sh` runs in a throwaway `$HOME` with
stub `curl` and `omarchy` commands, so an API call would show up as a failure
instead of spending your API-Football quota.

- `test/model.test.js` — the widget's pure formatting helpers, including the
  `Tomorrow `/weekday prefix that keeps a fixture from looking like it is today.
- `test/lib.test.sh` — `ft_write_state()` refusing empty or non-object state,
  `ft_curl_config()` and `--api-key-stdin` keeping the key out of command
  lines, the config round trip, and the event icon mapping.
- `test/poll.test.sh` — a full poll against a generated fixture cache: no API
  traffic while the cache is fresh, `_bookkeeping` surviving a failed state
  write, and the "play today" notification firing once rather than on every
  poll.

## License

[MIT](LICENSE). Bundled icons are derived from Lucide (ISC) — see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). This plugin is an
independent project and is not affiliated with API-Football or Omarchy.
