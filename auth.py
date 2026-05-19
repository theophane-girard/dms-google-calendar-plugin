#!/usr/bin/env python3
"""Google Calendar OAuth helper for DankMaterialShell plugin.

Subcommands:
  login    Open browser, run OAuth loopback flow, save tokens.
  fetch    Refresh token if needed, fetch events, write events.json.
  status   Print 'authenticated' / 'not_authenticated' (+ email if known).
  logout   Delete saved tokens.

Config is read from plugin_settings.json (DMS) and from a small JSON in the
state dir. Tokens never leave the user's machine.
"""

from __future__ import annotations

import argparse
import json
import os
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
SCOPES = [
    "https://www.googleapis.com/auth/calendar.events",
    "openid",
    "email",
]

CONFIG_DIR = Path.home() / ".config" / "DankMaterialShell"
STATE_DIR = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    / "DankMaterialShell"
    / "plugins"
    / PLUGIN_ID
)
TOKENS_PATH = STATE_DIR / "tokens.json"
EVENTS_PATH = STATE_DIR / "events.json"
PLUGIN_SETTINGS_PATH = CONFIG_DIR / "plugin_settings.json"


def _load_plugin_settings() -> dict[str, Any]:
    if not PLUGIN_SETTINGS_PATH.exists():
        return {}
    try:
        data = json.loads(PLUGIN_SETTINGS_PATH.read_text())
    except json.JSONDecodeError:
        return {}
    return data.get(PLUGIN_ID, {}) or {}


def _read_tokens() -> dict[str, Any]:
    if not TOKENS_PATH.exists():
        return {}
    try:
        return json.loads(TOKENS_PATH.read_text())
    except json.JSONDecodeError:
        return {}


def _write_tokens(tokens: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    TOKENS_PATH.write_text(json.dumps(tokens, indent=2))
    os.chmod(TOKENS_PATH, 0o600)


def _http_json(
    url: str,
    *,
    method: str = "GET",
    data: dict[str, str] | None = None,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
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


class _CallbackHandler(BaseHTTPRequestHandler):
    received: dict[str, str] = {}

    def log_message(self, *args, **kwargs):  # silence default logging
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


def cmd_login() -> int:
    settings = _load_plugin_settings()
    client_id = settings.get("clientId", "").strip()
    client_secret = settings.get("clientSecret", "").strip()
    if not client_id or not client_secret:
        print(
            "Configure d'abord clientId/clientSecret dans les réglages du plugin "
            "(voir README pour créer l'OAuth client).",
            file=sys.stderr,
        )
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
        "prompt": "consent",
        "state": state,
    }
    auth_url = AUTH_URL + "?" + urllib.parse.urlencode(params)

    server = HTTPServer(("127.0.0.1", port), _CallbackHandler)
    server.timeout = 300

    _open_browser(auth_url)
    print(f"Navigateur ouvert sur Google. En attente du callback (port {port})…")

    deadline = time.time() + 300
    while not _CallbackHandler.received and time.time() < deadline:
        server.handle_request()

    received = _CallbackHandler.received
    if not received:
        print("Timeout: aucune réponse.", file=sys.stderr)
        return 1
    if received.get("state") != state:
        print("State mismatch — possible CSRF, abandon.", file=sys.stderr)
        return 1
    if "error" in received:
        print(f"Erreur Google: {received['error']}", file=sys.stderr)
        return 1

    code = received["code"]
    tok = _http_json(
        TOKEN_URL,
        method="POST",
        data={
            "code": code,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
    )
    tok["obtained_at"] = int(time.time())

    try:
        info = _http_json(
            USERINFO_URL,
            headers={"Authorization": f"Bearer {tok['access_token']}"},
        )
        tok["email"] = info.get("email", "")
    except Exception:
        pass

    _write_tokens(tok)
    print(f"OK — connecté en tant que {tok.get('email') or 'compte Google'}.")
    return 0


def _ensure_access_token() -> str:
    tokens = _read_tokens()
    if not tokens:
        raise SystemExit("not_authenticated")
    expires_in = tokens.get("expires_in", 0)
    obtained_at = tokens.get("obtained_at", 0)
    if obtained_at + expires_in - 60 > time.time() and tokens.get("access_token"):
        return tokens["access_token"]

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
    _write_tokens(tokens)
    return tokens["access_token"]


def cmd_fetch() -> int:
    settings = _load_plugin_settings()
    calendar_id = settings.get("calendarId", "primary") or "primary"
    # Window: 2 days back (to allow nav to past) → 21 days forward.
    past_days = int(settings.get("windowPastDays", 2) or 2)
    future_days = int(settings.get("windowFutureDays", 21) or 21)

    access_token = _ensure_access_token()

    now_ts = time.time()
    time_min = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ts - past_days * 86400))
    time_max = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ts + future_days * 86400))

    params = urllib.parse.urlencode(
        {
            "timeMin": time_min,
            "timeMax": time_max,
            "maxResults": 250,
            "singleEvents": "true",
            "orderBy": "startTime",
        }
    )
    url = EVENTS_URL_TMPL.format(cal=urllib.parse.quote(calendar_id, safe="")) + "?" + params

    data = _http_json(url, headers={"Authorization": f"Bearer {access_token}"})
    items = data.get("items", [])

    simplified = []
    for it in items:
        start = it.get("start", {})
        end = it.get("end", {})
        simplified.append(
            {
                "id": it.get("id"),
                "title": it.get("summary", "(sans titre)"),
                "location": it.get("location", ""),
                "htmlLink": it.get("htmlLink", ""),
                "start": start.get("dateTime") or start.get("date"),
                "end": end.get("dateTime") or end.get("date"),
                "allDay": "date" in start and "dateTime" not in start,
            }
        )

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {"fetchedAt": int(time.time()), "events": simplified}
    EVENTS_PATH.write_text(json.dumps(payload, indent=2))
    print(f"OK — {len(simplified)} événements écrits dans {EVENTS_PATH}")
    return 0


def cmd_create() -> int:
    """Read a Google-formatted event payload from stdin and POST it."""
    raw = sys.stdin.read()
    if not raw.strip():
        print("empty payload", file=sys.stderr)
        return 1
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"invalid JSON: {e}", file=sys.stderr)
        return 1

    settings = _load_plugin_settings()
    calendar_id = settings.get("calendarId", "primary") or "primary"
    access_token = _ensure_access_token()

    url = EVENTS_URL_TMPL.format(cal=urllib.parse.quote(calendar_id, safe=""))
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {access_token}")
    req.add_header("Content-Type", "application/json")
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
        result = json.loads(resp.read().decode())
    print(result.get("htmlLink") or result.get("id") or "OK")
    return 0


def cmd_status() -> int:
    tokens = _read_tokens()
    if not tokens.get("refresh_token"):
        print("not_authenticated")
        return 1
    print(f"authenticated\t{tokens.get('email', '')}")
    return 0


def cmd_logout() -> int:
    if TOKENS_PATH.exists():
        TOKENS_PATH.unlink()
    if EVENTS_PATH.exists():
        EVENTS_PATH.unlink()
    print("OK — déconnecté.")
    return 0


# ─── Notification daemon ─────────────────────────────────────────────────────

CHECKPOINTS = [15, 5, 0]  # minutes avant le start
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
    """Spawn notify-send (--wait) in a worker thread and apply the action."""

    def worker():
        start_ts = _parse_iso(ev.get("start"))
        if start_ts is None:
            return
        end_ts = _parse_iso(ev.get("end")) or start_ts
        delta_min = round((start_ts - time.time()) / 60)

        if delta_min > 0:
            when_text = f"dans {delta_min} min"
        elif delta_min == 0:
            when_text = "maintenant"
        else:
            when_text = f"il y a {-delta_min} min"

        title = ev.get("title") or "(sans titre)"
        summary = f"{title} — {when_text}"
        body_lines = [f"{_fmt_hhmm(start_ts)} – {_fmt_hhmm(end_ts)}"]
        if ev.get("location"):
            body_lines.append(ev["location"])
        body = "\n".join(body_lines)

        try:
            result = subprocess.run(
                [
                    "notify-send",
                    "--app-name=Google Calendar",
                    "--icon=x-office-calendar",
                    "--urgency=normal",
                    "--action=snooze=Snooze 5 min",
                    "--action=stop=Stop",
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
                # Snooze fait taire tous les checkpoints restants pour cet event
                # et programme un seul refire 5 min plus tard.
                ev_state["firedCheckpoints"] = sorted(CHECKPOINTS)
                ev_state["snoozeUntil"] = int(time.time()) + SNOOZE_SECONDS
                ev_state["snoozeFromCheckpoint"] = checkpoint
            elif action == "stop":
                ev_state["firedCheckpoints"] = sorted(CHECKPOINTS)
                ev_state["stopped"] = True
            _save_notif_state(state)

    threading.Thread(target=worker, daemon=True).start()


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

        # GC: skip events ended > 1h ago
        if end_ts < now - 3600:
            continue

        current_ids.add(ev_id)
        ev_state = state.get(ev_id, {})

        if ev_state.get("stopped"):
            continue

        # Snooze refire
        snooze_until = ev_state.get("snoozeUntil")
        if snooze_until:
            if now >= snooze_until:
                _fire_notification(ev, ev_state.get("snoozeFromCheckpoint", 0))
                ev_state.pop("snoozeUntil", None)
                ev_state.pop("snoozeFromCheckpoint", None)
                state[ev_id] = ev_state
            continue

        # Regular checkpoints
        fired = set(ev_state.get("firedCheckpoints", []))
        for cp in CHECKPOINTS:
            if cp in fired:
                continue
            cp_time = start_ts - cp * 60
            # Window: don't fire if we missed it by > 14 min (avoid spam on restart)
            if cp_time <= now < cp_time + 14 * 60:
                _fire_notification(ev, cp)
                fired.add(cp)
                ev_state["lastFiredCheckpoint"] = cp

        if fired:
            ev_state["firedCheckpoints"] = sorted(fired)
            state[ev_id] = ev_state

    # Drop state for events out of the current window
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
            time.sleep(60)
    finally:
        try:
            PIDFILE_PATH.unlink()
        except FileNotFoundError:
            pass
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command", choices=["login", "fetch", "create", "status", "logout", "daemon"]
    )
    args = parser.parse_args()
    try:
        return {
            "login": cmd_login,
            "fetch": cmd_fetch,
            "create": cmd_create,
            "status": cmd_status,
            "logout": cmd_logout,
            "daemon": cmd_daemon,
        }[args.command]()
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode()
        except Exception:
            pass
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
