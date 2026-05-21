#!/usr/bin/env python3
"""Google Calendar OAuth helper for DankMaterialShell plugin.

Multi-account / multi-calendar support.

Subcommands:
  login           Start OAuth loopback flow ; add (or update) an account.
  fetch           Refresh tokens, fetch events from all enabled calendars,
                  write merged events.json.
  list-calendars  Refresh the calendar list for an account (or all).
  toggle-calendar Toggle the enabled flag of a calendar (args: email calId).
  create          Read event JSON from stdin and POST to the chosen calendar.
  status          List all connected accounts.
  logout          Disconnect an account (arg: email) or all accounts.
  daemon          Background process that fires checkpoint notifications.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import signal
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

PLUGIN_ID = "googleCalendar"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
EVENTS_URL_TMPL = "https://www.googleapis.com/calendar/v3/calendars/{cal}/events"
CALLIST_URL = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
SCOPES = [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "openid",
    "email",
]

PLUGIN_DIR = Path(__file__).resolve().parent
CONFIG_DIR = Path.home() / ".config" / "DankMaterialShell"


# ── i18n (notifications) ────────────────────────────────────────────────────


def _detect_locale() -> str:
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        v = os.environ.get(var, "")
        if v.startswith("fr"):
            return "fr"
        if v.startswith("en"):
            return "en"
    return "en"


_LOCALE = _detect_locale()

_STRINGS = {
    "fr": {
        "in_min": "dans {n} min",
        "now": "maintenant",
        "ago_min": "il y a {n} min",
        "snooze_action": "Snooze 5 min",
        "stop_action": "Stop",
        "no_title": "(sans titre)",
    },
    "en": {
        "in_min": "in {n} min",
        "now": "now",
        "ago_min": "{n} min ago",
        "snooze_action": "Snooze 5 min",
        "stop_action": "Stop",
        "no_title": "(untitled)",
    },
}


def _tr(key: str, **kwargs) -> str:
    s = (_STRINGS.get(_LOCALE, {}).get(key)
         or _STRINGS["en"].get(key)
         or key)
    for k, v in kwargs.items():
        s = s.replace("{" + k + "}", str(v))
    return s
STATE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    / "DankMaterialShell"
    / "plugins"
    / PLUGIN_ID
)
TOKENS_PATH = STATE_DIR / "tokens.json"  # legacy, kept for migration
ACCOUNTS_PATH = STATE_DIR / "accounts.json"
EVENTS_PATH = STATE_DIR / "events.json"
PLUGIN_SETTINGS_PATH = CONFIG_DIR / "plugin_settings.json"


# ── Theme icon ──────────────────────────────────────────────────────────────


def _get_theme_primary_hex() -> str:
    candidates = [
        Path.home() / ".config" / "hypr" / "dms" / "colors.conf",
        Path.home() / ".config" / "niri" / "dms" / "colors.conf",
    ]
    for p in candidates:
        try:
            text = p.read_text()
        except (FileNotFoundError, OSError):
            continue
        m = re.search(r"\$primary\s*=\s*rgb\(([0-9a-fA-F]{6})\)", text)
        if m:
            return "#" + m.group(1).lower()
    return "#1a73e8"


def _ensure_icon() -> Path:
    color = _get_theme_primary_hex()
    suffix = color.lstrip("#")
    icon_path = PLUGIN_DIR / f"icon-{suffix}.svg"
    if not icon_path.exists():
        svg = (
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-8 -8 40 40" '
            'width="256" height="256">\n'
            f'  <path fill="{color}" d="M19 4h-1V2h-2v2H8V2H6v2H5c-1.11 0-1.99.9'
            "-1.99 2L3 20c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 "
            "16H5V10h14v10zm0-12H5V6h14v2zm-7 5h5v5h-5z\"/>\n"
            "</svg>\n"
        )
        icon_path.write_text(svg)
        for old in PLUGIN_DIR.glob("icon-*.svg"):
            if old != icon_path:
                try:
                    old.unlink()
                except OSError:
                    pass
    return icon_path


# ── Settings / accounts storage ─────────────────────────────────────────────


def _load_plugin_settings() -> dict[str, Any]:
    if not PLUGIN_SETTINGS_PATH.exists():
        return {}
    try:
        data = json.loads(PLUGIN_SETTINGS_PATH.read_text())
    except json.JSONDecodeError:
        return {}
    return data.get(PLUGIN_ID, {}) or {}


def _load_accounts() -> list[dict[str, Any]]:
    if ACCOUNTS_PATH.exists():
        try:
            data = json.loads(ACCOUNTS_PATH.read_text())
            if isinstance(data, list):
                return data
        except json.JSONDecodeError:
            return []
    return _migrate_legacy_tokens()


def _save_accounts(accounts: list[dict[str, Any]]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    ACCOUNTS_PATH.write_text(json.dumps(accounts, indent=2))
    try:
        os.chmod(ACCOUNTS_PATH, 0o600)
    except OSError:
        pass


def _migrate_legacy_tokens() -> list[dict[str, Any]]:
    if not TOKENS_PATH.exists():
        return []
    try:
        old = json.loads(TOKENS_PATH.read_text())
    except json.JSONDecodeError:
        return []
    email = old.get("email") or ""
    if not old.get("refresh_token"):
        return []
    account = {
        "email": email,
        "tokens": old,
        "calendars": [
            {
                "id": "primary",
                "summary": email or "(default)",
                "primary": True,
                "enabled": True,
            }
        ],
    }
    accounts = [account]
    _save_accounts(accounts)
    return accounts


# ── HTTP ────────────────────────────────────────────────────────────────────


def _http_json(
    url: str,
    *,
    method: str = "GET",
    data: dict[str, str] | None = None,
    headers: dict[str, str] | None = None,
    body_bytes: bytes | None = None,
) -> dict[str, Any]:
    if body_bytes is not None:
        body = body_bytes
    else:
        body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Accept", "application/json")
    if data and "Content-Type" not in (headers or {}):
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        return json.loads(resp.read().decode())


# ── OAuth ───────────────────────────────────────────────────────────────────


class _CallbackHandler(BaseHTTPRequestHandler):
    received: dict[str, str] = {}

    def log_message(self, *args, **kwargs):
        pass

    def do_GET(self):  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(parsed.query)
        _CallbackHandler.received = {k: v[0] for k, v in qs.items()}
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        ok = "code" in qs
        body = (
            "<html><body style='font-family:sans-serif;padding:40px;"
            "background:#1e1e2e;color:#cdd6f4;text-align:center'>"
            f"<h2>{'Compte Google connecté ✓' if ok else 'Échec de l’authentification'}</h2>"
            "<p>Tu peux fermer cet onglet et revenir à DankMaterialShell.</p>"
            "</body></html>"
        )
        self.wfile.write(body.encode())


def _pick_free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _open_browser(url: str) -> None:
    for opener in ("xdg-open", "wslview", "open"):
        try:
            subprocess.Popen(
                [opener, url],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return
        except FileNotFoundError:
            continue
    print(f"Ouvre cette URL manuellement :\n{url}", file=sys.stderr)


def _ensure_access_token_for(account: dict[str, Any]) -> str:
    tokens = account.get("tokens") or {}
    expires_in = tokens.get("expires_in", 0)
    obtained_at = tokens.get("obtained_at", 0)
    if obtained_at + expires_in - 60 > time.time() and tokens.get("access_token"):
        return tokens["access_token"]

    if not tokens.get("refresh_token"):
        raise RuntimeError(f"no refresh token for {account.get('email')}")

    settings = _load_plugin_settings()
    refreshed = _http_json(
        TOKEN_URL,
        method="POST",
        data={
            "client_id": settings.get("clientId", ""),
            "client_secret": settings.get("clientSecret", ""),
            "refresh_token": tokens["refresh_token"],
            "grant_type": "refresh_token",
        },
    )
    tokens.update(refreshed)
    tokens["obtained_at"] = int(time.time())
    account["tokens"] = tokens
    return tokens["access_token"]


def _fetch_calendar_list(account: dict[str, Any]) -> list[dict[str, Any]]:
    token = _ensure_access_token_for(account)
    data = _http_json(CALLIST_URL, headers={"Authorization": f"Bearer {token}"})
    items = data.get("items", [])
    out = []
    for it in items:
        out.append(
            {
                "id": it["id"],
                "summary": it.get("summary", it["id"]),
                "primary": it.get("primary", False),
                "backgroundColor": it.get("backgroundColor", ""),
                "foregroundColor": it.get("foregroundColor", ""),
                "accessRole": it.get("accessRole", ""),
            }
        )
    return out


def _merge_calendars(
    existing: list[dict[str, Any]], fetched: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    enabled_map = {c["id"]: c.get("enabled", False) for c in existing}
    out = []
    for f in fetched:
        cal = dict(f)
        # Default new calendars: primary is enabled, others off
        cal["enabled"] = enabled_map.get(f["id"], bool(f.get("primary")))
        out.append(cal)
    return out


def cmd_login() -> int:
    settings = _load_plugin_settings()
    client_id = settings.get("clientId", "").strip()
    client_secret = settings.get("clientSecret", "").strip()
    if not client_id or not client_secret:
        print("Configure clientId/clientSecret first.", file=sys.stderr)
        return 2

    port = _pick_free_port()
    redirect_uri = f"http://127.0.0.1:{port}/callback"
    state = secrets.token_urlsafe(24)

    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent select_account",  # force le picker pour ajouter un autre compte
        "state": state,
    }
    auth_url = AUTH_URL + "?" + urllib.parse.urlencode(params)

    _CallbackHandler.received = {}
    server = HTTPServer(("127.0.0.1", port), _CallbackHandler)
    server.timeout = 300
    _open_browser(auth_url)
    print(f"En attente du callback (port {port})…")

    deadline = time.time() + 300
    while not _CallbackHandler.received and time.time() < deadline:
        server.handle_request()

    received = _CallbackHandler.received
    if not received or received.get("state") != state or "error" in received:
        print(f"Auth failed: {received}", file=sys.stderr)
        return 1

    tok = _http_json(
        TOKEN_URL,
        method="POST",
        data={
            "code": received["code"],
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
    )
    tok["obtained_at"] = int(time.time())

    email = ""
    try:
        info = _http_json(
            USERINFO_URL,
            headers={"Authorization": f"Bearer {tok['access_token']}"},
        )
        email = info.get("email", "")
    except Exception:
        pass
    tok["email"] = email

    accounts = _load_accounts()
    existing = next((a for a in accounts if a.get("email") == email), None)
    if existing:
        existing["tokens"] = tok
        account = existing
    else:
        account = {"email": email, "tokens": tok, "calendars": []}
        accounts.append(account)

    # Fetch calendar list right after login
    try:
        fetched = _fetch_calendar_list(account)
        account["calendars"] = _merge_calendars(account.get("calendars", []), fetched)
    except Exception as e:
        print(f"calendar list fetch failed: {e}", file=sys.stderr)

    _save_accounts(accounts)
    print(f"OK — connecté: {email or '(unknown)'}")
    return 0


def cmd_list_calendars(email_arg: str | None = None) -> int:
    accounts = _load_accounts()
    if not accounts:
        print("Aucun compte connecté.", file=sys.stderr)
        return 1
    changed = False
    for account in accounts:
        if email_arg and account.get("email") != email_arg:
            continue
        try:
            fetched = _fetch_calendar_list(account)
        except Exception as e:
            print(f"list-calendars failed for {account.get('email')}: {e}", file=sys.stderr)
            continue
        account["calendars"] = _merge_calendars(account.get("calendars", []), fetched)
        changed = True
    if changed:
        _save_accounts(accounts)
    print("OK")
    return 0


def cmd_toggle_calendar(email_arg: str, cal_id: str) -> int:
    accounts = _load_accounts()
    for account in accounts:
        if account.get("email") != email_arg:
            continue
        for cal in account.get("calendars", []):
            if cal["id"] == cal_id:
                cal["enabled"] = not cal.get("enabled", False)
                _save_accounts(accounts)
                print(f"OK — {cal_id} = {'on' if cal['enabled'] else 'off'}")
                return 0
    print("not found", file=sys.stderr)
    return 1


def cmd_fetch() -> int:
    accounts = _load_accounts()
    if not accounts:
        print("Aucun compte connecté.", file=sys.stderr)
        return 1

    settings = _load_plugin_settings()
    past_days = int(settings.get("windowPastDays", 2) or 2)
    future_days = int(settings.get("windowFutureDays", 21) or 21)

    now_ts = time.time()
    time_min = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ts - past_days * 86400))
    time_max = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ts + future_days * 86400))

    all_events: list[dict[str, Any]] = []
    enabled_count = 0
    for account in accounts:
        try:
            token = _ensure_access_token_for(account)
        except Exception as e:
            print(f"refresh failed for {account.get('email')}: {e}", file=sys.stderr)
            continue
        for cal in account.get("calendars", []):
            if not cal.get("enabled"):
                continue
            enabled_count += 1
            params = urllib.parse.urlencode(
                {
                    "timeMin": time_min,
                    "timeMax": time_max,
                    "maxResults": 250,
                    "singleEvents": "true",
                    "orderBy": "startTime",
                }
            )
            url = (
                EVENTS_URL_TMPL.format(cal=urllib.parse.quote(cal["id"], safe=""))
                + "?"
                + params
            )
            try:
                data = _http_json(url, headers={"Authorization": f"Bearer {token}"})
            except Exception as e:
                print(f"fetch failed for {cal['id']}: {e}", file=sys.stderr)
                continue
            for it in data.get("items", []):
                start = it.get("start", {})
                end = it.get("end", {})

                # Extract Google Meet link from conferenceData ou hangoutLink (legacy)
                meet_link = ""
                cdata = it.get("conferenceData") or {}
                for ep in cdata.get("entryPoints") or []:
                    if ep.get("entryPointType") == "video" and ep.get("uri"):
                        meet_link = ep["uri"]
                        break
                if not meet_link:
                    meet_link = it.get("hangoutLink") or ""

                attendees = []
                for a in it.get("attendees") or []:
                    attendees.append(
                        {
                            "email": a.get("email", ""),
                            "displayName": a.get("displayName", ""),
                            "responseStatus": a.get("responseStatus", ""),
                            "self": a.get("self", False),
                            "organizer": a.get("organizer", False),
                        }
                    )

                all_events.append(
                    {
                        "id": f"{account.get('email','')}|{it.get('id','')}",
                        "title": it.get("summary", "(sans titre)"),
                        "description": it.get("description", ""),
                        "location": it.get("location", ""),
                        "htmlLink": it.get("htmlLink", ""),
                        "start": start.get("dateTime") or start.get("date"),
                        "end": end.get("dateTime") or end.get("date"),
                        "allDay": "date" in start and "dateTime" not in start,
                        "meetLink": meet_link,
                        "attendees": attendees,
                        "organizer": (it.get("organizer") or {}).get("email", ""),
                        "calendarId": cal["id"],
                        "calendarSummary": cal.get("summary", ""),
                        "calendarColor": cal.get("backgroundColor", ""),
                        "accountEmail": account.get("email", ""),
                    }
                )

    all_events.sort(key=lambda e: e["start"] or "")
    _save_accounts(accounts)  # persist any token refreshes

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"fetchedAt": int(now_ts), "events": all_events}
    EVENTS_PATH.write_text(json.dumps(payload, indent=2))
    print(
        f"OK — {len(all_events)} events de {enabled_count} calendrier(s) sur "
        f"{len(accounts)} compte(s)"
    )
    return 0


def cmd_create() -> int:
    """Read event JSON from stdin and POST to chosen calendar.

    The payload may include a top-level `__target` = {accountEmail, calendarId}.
    If absent, posts to the first enabled primary calendar."""
    raw = sys.stdin.read()
    if not raw.strip():
        print("empty payload", file=sys.stderr)
        return 1
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"invalid JSON: {e}", file=sys.stderr)
        return 1

    target = payload.pop("__target", None) or {}
    target_email = target.get("accountEmail")
    target_cal = target.get("calendarId")

    accounts = _load_accounts()
    if not accounts:
        print("Aucun compte connecté.", file=sys.stderr)
        return 1

    account = None
    if target_email:
        account = next((a for a in accounts if a.get("email") == target_email), None)
    if account is None:
        account = accounts[0]
    if target_cal is None:
        # primary of this account, fallback to "primary"
        for c in account.get("calendars", []):
            if c.get("primary"):
                target_cal = c["id"]
                break
        if target_cal is None:
            target_cal = "primary"

    token = _ensure_access_token_for(account)
    _save_accounts(accounts)

    url = EVENTS_URL_TMPL.format(cal=urllib.parse.quote(target_cal, safe=""))
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        result = json.loads(resp.read().decode())
    print(result.get("htmlLink") or result.get("id") or "OK")
    return 0


def cmd_status() -> int:
    accounts = _load_accounts()
    if not accounts:
        print("not_authenticated")
        return 1
    for a in accounts:
        cals = a.get("calendars", [])
        enabled = sum(1 for c in cals if c.get("enabled"))
        print(f"authenticated\t{a.get('email','')}\t{enabled}/{len(cals)} calendars")
    return 0


def cmd_logout(email_arg: str | None = None) -> int:
    if email_arg in (None, "", "all"):
        if ACCOUNTS_PATH.exists():
            ACCOUNTS_PATH.unlink()
        if TOKENS_PATH.exists():
            TOKENS_PATH.unlink()
        if EVENTS_PATH.exists():
            EVENTS_PATH.unlink()
        print("OK — tous les comptes déconnectés.")
        return 0
    accounts = _load_accounts()
    new_accounts = [a for a in accounts if a.get("email") != email_arg]
    if len(new_accounts) == len(accounts):
        print(f"not found: {email_arg}", file=sys.stderr)
        return 1
    if new_accounts:
        _save_accounts(new_accounts)
    else:
        if ACCOUNTS_PATH.exists():
            ACCOUNTS_PATH.unlink()
    print(f"OK — {email_arg} déconnecté.")
    return 0


# ─── Notification daemon ─────────────────────────────────────────────────────

CHECKPOINTS = [15, 5, 0]
SNOOZE_SECONDS = 5 * 60
NOTIF_STATE_PATH = STATE_DIR / "notif_state.json"
PIDFILE_PATH = STATE_DIR / "daemon.pid"
_state_lock = threading.Lock()


def _load_notif_state() -> dict[str, Any]:
    if not NOTIF_STATE_PATH.exists():
        return {}
    try:
        return json.loads(NOTIF_STATE_PATH.read_text())
    except json.JSONDecodeError:
        return {}


def _save_notif_state(state: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    NOTIF_STATE_PATH.write_text(json.dumps(state, indent=2))


def _parse_iso(s: str | None) -> float | None:
    if not s:
        return None
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(s).timestamp()
    except Exception:
        return None


def _fmt_hhmm(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%H:%M")


def _fire_notification(ev: dict[str, Any], checkpoint: int) -> None:
    def worker():
        start_ts = _parse_iso(ev.get("start"))
        if start_ts is None:
            return
        end_ts = _parse_iso(ev.get("end")) or start_ts
        delta_min = round((start_ts - time.time()) / 60)
        if delta_min > 0:
            when_text = _tr("in_min", n=delta_min)
        elif delta_min == 0:
            when_text = _tr("now")
        else:
            when_text = _tr("ago_min", n=-delta_min)
        title = ev.get("title") or _tr("no_title")
        summary = f"{title} — {when_text}"
        body_lines = [f"{_fmt_hhmm(start_ts)} – {_fmt_hhmm(end_ts)}"]
        if ev.get("calendarSummary"):
            body_lines.append("📅 " + ev["calendarSummary"])
        if ev.get("location"):
            body_lines.append(ev["location"])
        body = "\n".join(body_lines)

        try:
            result = subprocess.run(
                [
                    "notify-send",
                    "--app-name=Google Calendar",
                    f"--icon={_ensure_icon()}",
                    "--urgency=normal",
                    f"--action=snooze={_tr('snooze_action')}",
                    f"--action=stop={_tr('stop_action')}",
                    summary,
                    body,
                ],
                capture_output=True,
                text=True,
                timeout=3600,
            )
        except subprocess.TimeoutExpired:
            return
        except FileNotFoundError:
            print("notify-send not found — install libnotify", file=sys.stderr)
            return

        action = (result.stdout or "").strip()
        ev_id = ev.get("id")
        if not ev_id:
            return

        with _state_lock:
            state = _load_notif_state()
            ev_state = state.setdefault(ev_id, {})
            if action == "snooze":
                ev_state["firedCheckpoints"] = sorted(CHECKPOINTS)
                ev_state["snoozeUntil"] = int(time.time()) + SNOOZE_SECONDS
                ev_state["snoozeFromCheckpoint"] = checkpoint
            elif action == "stop":
                ev_state["firedCheckpoints"] = sorted(CHECKPOINTS)
                ev_state["stopped"] = True
            _save_notif_state(state)

    threading.Thread(target=worker, daemon=True).start()


def _next_wakeup_seconds(state: dict[str, Any], events: list, now: float) -> float | None:
    """Compute seconds until the next un-fired checkpoint or snooze expiry."""
    min_wait: float | None = None
    for ev in events:
        ev_id = ev.get("id")
        if not ev_id or ev.get("allDay"):
            continue
        start_ts = _parse_iso(ev.get("start"))
        if start_ts is None:
            continue
        end_ts = _parse_iso(ev.get("end")) or start_ts
        if end_ts < now - 3600:
            continue
        ev_state = state.get(ev_id, {})
        if ev_state.get("stopped"):
            continue
        snooze_until = ev_state.get("snoozeUntil")
        if snooze_until and snooze_until > now:
            wait = snooze_until - now
            if min_wait is None or wait < min_wait:
                min_wait = wait
            continue
        fired = set(ev_state.get("firedCheckpoints", []))
        for cp in CHECKPOINTS:
            if cp in fired:
                continue
            cp_time = start_ts - cp * 60
            wait = cp_time - now
            if wait > 0 and (min_wait is None or wait < min_wait):
                min_wait = wait
    return min_wait


def _check_and_notify() -> None:
    if not EVENTS_PATH.exists():
        return
    try:
        data = json.loads(EVENTS_PATH.read_text())
    except json.JSONDecodeError:
        return
    events = data.get("events", [])
    now = time.time()

    with _state_lock:
        state = _load_notif_state()

    current_ids: set[str] = set()
    for ev in events:
        ev_id = ev.get("id")
        if not ev_id:
            continue
        if ev.get("allDay"):
            continue
        start_ts = _parse_iso(ev.get("start"))
        if start_ts is None:
            continue
        end_ts = _parse_iso(ev.get("end")) or start_ts
        if end_ts < now - 3600:
            continue

        current_ids.add(ev_id)
        ev_state = state.get(ev_id, {})
        if ev_state.get("stopped"):
            continue

        snooze_until = ev_state.get("snoozeUntil")
        if snooze_until:
            if now >= snooze_until:
                _fire_notification(ev, ev_state.get("snoozeFromCheckpoint", 0))
                ev_state.pop("snoozeUntil", None)
                ev_state.pop("snoozeFromCheckpoint", None)
                state[ev_id] = ev_state
            continue

        fired = set(ev_state.get("firedCheckpoints", []))
        for cp in CHECKPOINTS:
            if cp in fired:
                continue
            cp_time = start_ts - cp * 60
            if cp_time <= now < cp_time + 14 * 60:
                _fire_notification(ev, cp)
                fired.add(cp)
                ev_state["lastFiredCheckpoint"] = cp

        if fired:
            ev_state["firedCheckpoints"] = sorted(fired)
            state[ev_id] = ev_state

    for stale_id in list(state.keys()):
        if stale_id not in current_ids:
            del state[stale_id]

    with _state_lock:
        _save_notif_state(state)


def _is_daemon_alive(pid: int) -> bool:
    try:
        with open(f"/proc/{pid}/cmdline") as f:
            cmdline = f.read()
    except FileNotFoundError:
        return False
    return "auth.py" in cmdline


def cmd_daemon() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)

    if PIDFILE_PATH.exists():
        try:
            old_pid = int(PIDFILE_PATH.read_text().strip())
            if _is_daemon_alive(old_pid):
                print(f"daemon already running (pid={old_pid})", file=sys.stderr)
                return 0
        except (ValueError, OSError):
            pass
        try:
            PIDFILE_PATH.unlink()
        except FileNotFoundError:
            pass

    PIDFILE_PATH.write_text(str(os.getpid()))

    def _cleanup(*_):
        try:
            PIDFILE_PATH.unlink()
        except FileNotFoundError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    try:
        while True:
            try:
                _check_and_notify()
            except Exception as e:
                print(f"daemon: {e}", file=sys.stderr)
            sleep_for = 60.0
            try:
                with _state_lock:
                    state = _load_notif_state()
                events: list = []
                if EVENTS_PATH.exists():
                    events = json.loads(EVENTS_PATH.read_text()).get("events", [])
                next_wait = _next_wakeup_seconds(state, events, time.time())
                if next_wait is not None:
                    sleep_for = min(60.0, max(1.0, next_wait + 0.5))
            except Exception:
                pass
            time.sleep(sleep_for)
    finally:
        try:
            PIDFILE_PATH.unlink()
        except FileNotFoundError:
            pass
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=[
            "login",
            "fetch",
            "create",
            "status",
            "logout",
            "daemon",
            "list-calendars",
            "toggle-calendar",
        ],
    )
    parser.add_argument("args", nargs="*")
    args = parser.parse_args()
    try:
        if args.command == "login":
            return cmd_login()
        elif args.command == "fetch":
            return cmd_fetch()
        elif args.command == "create":
            return cmd_create()
        elif args.command == "status":
            return cmd_status()
        elif args.command == "logout":
            return cmd_logout(args.args[0] if args.args else None)
        elif args.command == "daemon":
            return cmd_daemon()
        elif args.command == "list-calendars":
            return cmd_list_calendars(args.args[0] if args.args else None)
        elif args.command == "toggle-calendar":
            if len(args.args) < 2:
                print("usage: toggle-calendar <email> <calendarId>", file=sys.stderr)
                return 2
            return cmd_toggle_calendar(args.args[0], args.args[1])
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode()
        except Exception:
            pass
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
