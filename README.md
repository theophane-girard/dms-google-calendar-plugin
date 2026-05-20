# Google Calendar — plugin for DankMaterialShell

A Google Calendar widget for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
that displays events from one or more Google accounts in the bar, with a
keyboard-friendly popout, event creation, event details (including Google
Meet links) and desktop notifications before events.

OAuth is handled locally with the standard "loopback" flow (same approach as
`gcalcli` or `khal`). Tokens never leave the user's machine — there is no
third-party server involved.

## Features

- **Multi-account / multi-calendar** — connect several Google accounts and
  toggle individual calendars on/off. Events are tagged with the calendar's
  color in the UI.
- **Popout views**
  - **List**: 1-day or 3-day view, with day headers, all-day banners, and a
    Google-Calendar-style cluster layout for overlapping events (tile height
    proportional to duration, side-by-side lanes for collisions).
  - **Now indicator**: red line placed precisely where the current time sits
    inside today, with HH:MM label on the left.
  - **Details**: time, location, calendar source, attendee counts, description,
    and a prominent *Join Google Meet* button when a video link is attached.
  - **Form**: create a new event with title, date, all-day toggle, start/end
    times and optional location.
- **Notifications** — a background daemon fires desktop notifications at
  T-15 min, T-5 min and at event start, with two actions
  (*Snooze 5 min* / *Stop*).
- **Keyboard navigation** — vim-style (`h/j/k/l`) and `Tab` work in every view.
- **i18n** — French and English, auto-detected from the system locale.
- **Theme-aware notification icon** — regenerated from the DMS `Theme.primary`
  color (as exposed by matugen).

## Requirements

- DankMaterialShell ≥ 1.2.0
- Python 3.10 or later (only the standard library is used — no `pip install`)
- `notify-send` (provided by the `libnotify` package on most distros)
- A Google account and access to [Google Cloud Console](https://console.cloud.google.com/)
  to create your own OAuth client (free)

## Installation

Clone the plugin into your DMS plugins directory:

```bash
git clone https://github.com/<your-fork>/dms-google-calendar \
    ~/.config/DankMaterialShell/plugins/googleCalendar
```

Then restart the shell so DMS picks it up:

```bash
dms restart
```

Enable the widget:

```bash
dms ipc call plugins enable googleCalendar
```

And add it to your bar from DMS Settings → Bar, or via IPC.

## Configuring an OAuth client (5 min, one-time)

Like any desktop app that talks to the Google API, the plugin needs its own
OAuth client. There is no shared backend, so you provide the credentials.

1. Go to <https://console.cloud.google.com/> and create (or reuse) a project.
2. **APIs & Services → Library** → search for **Google Calendar API** →
   click **Enable**.
3. **APIs & Services → OAuth consent screen**
   - User type: **External**
   - App name: anything (e.g. `dms-calendar`)
   - User support email: your email
   - Scopes: leave empty (scopes are requested at runtime by the plugin)
   - Test users: **add every Google account** you plan to connect later.
     Without this, Google refuses the OAuth flow until the app is verified.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**
   - Application type: **Desktop app**
   - Name: e.g. `DMS Google Calendar`
   - Copy the resulting **Client ID** and **Client secret**.
5. Open DMS → Settings → Plugins → Google Calendar → paste both into the
   *OAuth Client* section.
6. Click **"+ Connect account"**. A browser tab opens for Google's consent
   screen. Approve, and the tab confirms the connection.
7. (Optional) Click **"+ Connect account"** again to add another Google
   account. Calendars from all connected accounts appear in the list and can
   be toggled individually.

> ⚠️ The OAuth `client_secret` for a "Desktop app" is not a real secret —
> Google explicitly documents this. The plugin stores it in plain text in
> `~/.config/DankMaterialShell/plugin_settings.json`. Avoid committing that
> file to a public repo.

### OAuth scopes used

- `https://www.googleapis.com/auth/calendar.events` — read & create events
- `https://www.googleapis.com/auth/calendar.calendarlist.readonly` — list
  calendars per account
- `openid email` — identify which account a token belongs to

## Usage

### Bar pill

| Input | Action |
|---|---|
| Left click | Open the popout |
| Right click | Refresh now |

A suggested Hyprland binding for opening the popout from anywhere:

```ini
bindd = SUPER, G, Google Calendar, exec, dms ipc call widget toggle googleCalendar
```

### Popout — list mode

| Key | Action |
|---|---|
| `j` / `Tab` | Next focusable item |
| `k` / `Shift+Tab` | Previous focusable item |
| `h` | Previous day (by current scope) |
| `l` | Next day (by current scope) |
| `Space` / `Enter` | Activate the focused item |
| `n` / `+` | Switch to new-event form |
| `Esc` | Close popout |

When opened, focus lands on the next upcoming event of the current day if
there is one; otherwise on the toolbar.

### Popout — details mode

| Key | Action |
|---|---|
| `j` / `l` / `Tab` | Next button (Back → Meet → Open GCal) |
| `k` / `h` / `Shift+Tab` | Previous button |
| `Space` / `Enter` | Activate the focused button (Meet by default) |
| `Esc` | Back to list |

### Popout — new event form

| Key | Action |
|---|---|
| `Tab` / `Shift+Tab` | Traverse fields and buttons |
| `Space` (on "All day") | Toggle the checkbox |
| `Enter` (on Create) | Submit |
| `Esc` | Back to list |

## Configuration

Configurable from DMS → Settings → Plugins → Google Calendar:

| Setting | Default | Description |
|---|---|---|
| Client ID / Secret | *(empty)* | OAuth credentials from your Google Cloud project |
| Refresh interval (min) | `5` | How often the plugin queries Google for events |
| Event reminders | `true` | Enable / disable the notification daemon |

Per-calendar enabled/disabled state is stored alongside the tokens and toggled
from the *Calendars* section of each account.

## Refresh cadence

Every `refreshMinutes` (default 5), the widget runs `auth.py fetch`, which:

1. Refreshes the OAuth access token of each account if it has expired.
2. For each enabled calendar, pulls events from `now - 2 days` to `now +
   21 days`.
3. Writes the merged set to `events.json`.

The popout watches that file and re-renders on change. Right-click the pill
or use the refresh button in the toolbar to trigger a fetch immediately.

## Notifications

A background Python process (`auth.py daemon`) runs while the plugin is
loaded *and* "Event reminders" is enabled in Settings. It:

- Polls `events.json` every 60 seconds.
- For each non-all-day event, fires `notify-send` at T-15, T-5 and T-0, with
  two actions:
  - **Snooze 5 min** — fires the same reminder again 5 min later and
    suppresses every remaining checkpoint for that event.
  - **Stop** — permanently dismisses every checkpoint for that event.
- Maintains a single instance via a PID file; cleans up on SIGTERM.
- Uses a theme-colored calendar icon (regenerated automatically when the DMS
  primary color changes).

## Storage

| Path | Purpose |
|---|---|
| `~/.local/state/DankMaterialShell/plugins/googleCalendar/accounts.json` | Per-account OAuth tokens + calendar list (chmod 600) |
| `~/.local/state/DankMaterialShell/plugins/googleCalendar/events.json` | Cached events from all enabled calendars |
| `~/.local/state/DankMaterialShell/plugins/googleCalendar/notif_state.json` | Notification daemon state |
| `~/.local/state/DankMaterialShell/plugins/googleCalendar/daemon.pid` | Single-instance lock for the daemon |
| `~/.config/DankMaterialShell/plugin_settings.json` | `googleCalendar` settings (client id/secret, intervals, toggles) |

## Languages

The plugin auto-detects French or English from the system locale:

- **QML side**: `Qt.locale().name` starting with `fr` → French, otherwise English.
- **Python daemon**: reads `LC_ALL`, then `LC_MESSAGES`, then `LANG`.

To add another language, extend `DICT.xx` in `i18n.js` and `_STRINGS["xx"]` in
`auth.py`, then update the locale matchers in both.

## Troubleshooting

- **"Sign-in failed"** — either `clientId` / `clientSecret` is missing in
  Settings, or the Google account being connected is not listed under
  *Test users* of the OAuth consent screen.
- **`Access blocked: This app's request is invalid`** — the OAuth client was
  created as a "Web application" instead of "Desktop app". Recreate it.
- **`HTTP 403` while listing calendars** — the account was authenticated
  before the `calendar.calendarlist.readonly` scope was required. Remove the
  account and reconnect it.
- **No events shown despite being connected** — run the fetch manually and
  inspect stderr:
  ```bash
  python3 ~/.config/DankMaterialShell/plugins/googleCalendar/auth.py fetch
  ```
- **No notifications fire** — verify the daemon is running:
  ```bash
  pgrep -af "auth.py daemon"
  ```
  Toggle *Event reminders* off and on in Settings to restart it.

## Command-line interface

`auth.py` exposes every operation:

```bash
python3 auth.py login              # add a new account
python3 auth.py logout EMAIL       # remove a single account
python3 auth.py logout all         # remove every account
python3 auth.py status             # list connected accounts
python3 auth.py list-calendars     # refresh the calendar list
python3 auth.py toggle-calendar EMAIL CALENDAR_ID
python3 auth.py fetch              # pull events into events.json
python3 auth.py daemon             # run the notification daemon
python3 auth.py create < event.json
```

## Hot reload after editing the plugin

```bash
dms ipc call plugins reload googleCalendar
```

Or, if a new file was added or `plugin.json` changed:

```bash
rm -rf /run/user/$(id -u)/quickshell/qmlcache
dms restart
```

## Project layout

```
googleCalendar/
├── plugin.json
├── auth.py                 # OAuth + fetch + create + notification daemon (stdlib only)
├── i18n.js                 # FR/EN strings + helpers
├── icon-XXXXXX.svg         # theme-colored calendar icon (generated)
├── GoogleCalendar.qml      # plugin shell: pill, I/O, processes
├── PopoutMain.qml          # popout root: state, key handling, layout
├── PopoutToolbar.qml       # prev / today / next / scope / refresh / +
├── PopoutDayList.qml       # day list, clusters, tiles, now indicator
├── PopoutForm.qml          # new-event form
├── PopoutDetails.qml       # event detail view, Meet button
├── Settings.qml            # configuration page
└── README.md
```

## License

MIT (see `plugin.json`).
