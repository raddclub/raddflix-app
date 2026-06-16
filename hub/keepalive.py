"""JazzDrive session keep-alive — dual-interval SAPI ping + file-upload heartbeat.

Two independent per-account timers run inside a 60-second tick loop:

PING  (default every 20 min, DB key: ``ping_interval_min``)
  GET /sapi/system/information?action=get with full APK-matching headers.
  Prevents JSESSIONID idle-timeout (3600 s confirmed on JazzDrive servers).
  The JazzDrive web SPA does the same thing to keep sessions alive.
  Uses jazzdrive.sapi_request() so all APK headers flow through automatically.

HEARTBEAT  (default every 360 min, DB key: ``keepalive_interval_min``)
  Upload + delete a probe file in /Radd-Heartbeat/.
  Proves end-to-end storage access and rolls the OAuth2 token expiry window.
  On failure, tries a silent token refresh before giving up.
  Token refresh path: POST /oauth2/refresh_token.php (Android OAuth2).
  NOTE: /sapi/login?keytype=refreshtoken does NOT exist in JazzDrive API
        (confirmed APK research). Use /oauth2/refresh_token.php only.

Active hours: 08:00–23:00 PKT only (UTC+5) — mirrors real user behaviour.
Outside this window both timers pause; the loop sleeps in 60 s chunks so
stop_event is always responsive within 60 s.

Human-like behaviour rules:
  - Interval jitter: ping ±10%, heartbeat ±25% — never perfectly mechanical.
  - 8% probabilistic skip per ping cycle.
  - Variable payload size (800–1400 bytes) and filename each heartbeat run.
  - 2–8 s random "app startup" delay before each heartbeat upload.
  - Per-account timers — multiple accounts never fire in lock-step.

DB settings (all live-readable without Flask restart):
  ``ping_interval_min``      — seconds between SAPI pings (default: 20)
  ``keepalive_interval_min`` — minutes between heartbeat uploads (default: 360)
  ``KEEPALIVE_ENABLED``      — "0" to pause all keepalive activity
  ``JAZZDRIVE_ENABLED``      — "0" master kill switch
"""
from __future__ import annotations
import json
import random
import time
import logging
import threading
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional
from . import db, config, jazzdrive

log = logging.getLogger("hub.keepalive")

# NOTE: JazzDrive cloud URL is managed by jazzdrive.py (CLOUD_BASE / OAUTH_BASE).
# sapi_request() and refresh_session() own the base URL — do NOT hardcode it here.

# ── Pakistan Standard Time ────────────────────────────────────────────────────
_PKT = timezone(timedelta(hours=5))
_ACTIVE_HOUR_START = 8   # 8am PKT — when a real user might open the app
_ACTIVE_HOUR_END   = 23  # 11pm PKT — last reasonable activity window


def _is_active_hours() -> bool:
    """True if current PKT time is within human-active hours (8am–11pm)."""
    h = datetime.now(_PKT).hour
    return _ACTIVE_HOUR_START <= h < _ACTIVE_HOUR_END


def _seconds_until_active() -> float:
    """Return seconds until the next 8am PKT window."""
    now_pkt = datetime.now(_PKT)
    h = now_pkt.hour
    if h < _ACTIVE_HOUR_START:
        # Same day — wait until 8am
        target = now_pkt.replace(hour=_ACTIVE_HOUR_START, minute=0, second=0, microsecond=0)
    else:
        # Past 11pm — wait until 8am tomorrow
        target = (now_pkt + timedelta(days=1)).replace(
            hour=_ACTIVE_HOUR_START, minute=0, second=0, microsecond=0
        )
    return max(0.0, (target - now_pkt).total_seconds())


# ── Heartbeat file helpers ────────────────────────────────────────────────────

_HB_FILENAMES = [
    "sync_note.txt",
    "backup_list.txt",
    "my_files.txt",
    "radd_sync.txt",
    "session_note.txt",
    "drive_check.txt",
]

_HB_MESSAGES = [
    "JazzDrive session active. Last sync: {ts}.",
    "Sync OK — {ts}.",
    "Connected to JazzDrive at {ts}.",
    "Session alive. Checked: {ts}.",
    "Auto-sync completed at {ts}.",
]


def _heartbeat_filename() -> str:
    """Return a varied heartbeat filename that doesn't look mechanical."""
    return random.choice(_HB_FILENAMES)


def _generate_payload(path: Path) -> int:
    """Write a naturally-sized heartbeat file (800–1400 bytes). Returns byte count."""
    ts_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    msg = random.choice(_HB_MESSAGES).format(ts=ts_local)
    # Pad to a random size so file sizes vary naturally
    pad_size = random.randint(600, 1200)
    body = (msg + "\n" + " " * pad_size).encode("utf-8")
    path.write_bytes(body)
    return len(body)


def _delete_remote_file(sess, vk: str, jsid: str, file_id: int) -> bool:
    """Delete a file from JazzDrive by remote ID. Returns True on success.

    NOTE: ``sess`` is accepted for API compatibility with callers that pass a
    requests.Session, but is NOT used — this function delegates entirely to
    jazzdrive.sapi_request() which manages its own session and proxy logic.
    """
    try:
        data = jazzdrive.sapi_request(
            endpoint="/file",
            action="delete",
            method="POST",
            json_data={"data": {"ids": [int(file_id)]}},
            tokens={"validationkey": vk, "jsessionid": jsid},
            timeout=20
        )
        if not data.get("error"):
            return True
    except Exception as exc:
        log.debug("delete POST failed: %s", exc)
    return False


def _sapi_ping(acct: dict) -> bool:
    """Lightweight SAPI ping — GET /sapi/system/information?action=get.

    Fires every ~20 min (``ping_interval_min`` DB setting) to keep the
    JazzDrive session alive.  JazzDrive's JSESSIONID idle-timeout is 3600 s;
    without regular activity the session goes cold and the next upload fails
    with SEC-1003 / 401.

    ENDPOINT NOTES (confirmed live, 2026-06-16):
      • Correct:   /sapi/system/information?action=get
        Returns: sapiversion, production-environment, devid, mod, fwv.
      • Wrong:     action=None / action=info / action=ping / action=information
        All return COM-1005 "Unsupported operation".

    Uses jazzdrive.sapi_request() so all APK-matching headers flow through:
      Accept: application/json
      X-deviceid: fac-<id>         (always fac- prefixed)
      X-devicename: Infinix Hot 9 Play
      X-Requested-With: com.jazz.drive
      Authorization: oauth <base64(cred_JSON)>
      User-Agent: omh android client

    Returns True when the server responds with no "error" field.
    """
    aid    = acct["id"]
    msisdn = acct["msisdn"]
    vk     = (acct.get("validation_key") or "").strip()
    jsid   = (acct.get("jsessionid") or "").strip()

    if not vk or not jsid:
        log.debug("ping: no tokens for %s — skipping", msisdn)
        return False

    # Master kill switch propagates cleanly through require_jd_active()
    jazzdrive.require_jd_active()

    try:
        # action='get' confirmed working (returns sapiversion, production-environment, etc.)
        # action=None returns COM-1005 "Unsupported operation"
        data = jazzdrive.sapi_request(
            endpoint="/system/information",
            action="get",
            method="GET",
            account_id=aid,
            tokens={"validationkey": vk, "jsessionid": jsid},
            timeout=10,
        )
        ok = not data.get("error")
        now_ts = int(time.time())
        if ok:
            log.debug("ping OK for %s (/system/information)", msisdn)
            _set_status(aid, last_ping_at=now_ts, ping_status="ok")
        else:
            log.warning("ping: server error for %s: %s", msisdn, str(data)[:100])
            _set_status(aid, last_ping_at=now_ts, ping_status="error")
        return ok
    except Exception as exc:
        log.debug("ping exception for %s: %s", msisdn, exc)
        _set_status(aid, last_ping_at=int(time.time()), ping_status="error")
        return False

# ── In-memory status + event log ──────────────────────────────────────────────
_STATUS: dict[int, dict] = {}
_STATUS_LOCK = threading.Lock()
_started_at: Optional[float] = None

# Load any persisted events from last run on import
_EVENTS: list[dict] = []
try:
    _persisted = db.setting("KEEPALIVE_EVENT_LOG")
    if _persisted:
        _EVENTS = json.loads(_persisted)[-_MAX_EVENTS:]
except Exception:
    pass
_EVENTS_LOCK = threading.Lock()
_MAX_EVENTS = 100


def _log_event(event_type: str, msisdn: str, detail: str = "") -> None:
    """Append a timestamped event to the in-memory + DB-persisted event log."""
    entry = {"ts": int(time.time()), "type": event_type,
             "msisdn": msisdn, "detail": str(detail)[:200]}
    with _EVENTS_LOCK:
        _EVENTS.append(entry)
        if len(_EVENTS) > _MAX_EVENTS:
            del _EVENTS[:-_MAX_EVENTS]
    # Persist last 50 events to DB so log survives Flask restarts
    try:
        with _EVENTS_LOCK:
            snapshot = list(_EVENTS[-50:])
        db.set_setting("KEEPALIVE_EVENT_LOG", json.dumps(snapshot))
    except Exception:
        pass


def get_events(n: int = 20) -> list[dict]:
    """Return the last N keepalive events."""
    with _EVENTS_LOCK:
        return list(_EVENTS[-n:])


def _classify_error(error_str: str) -> str:
    """Classify a keepalive error for smarter handling and display.

    Returns one of:
      'device_conflict'  — another Android device kicked our session
      'session_expired'  — token expired, OTP re-login required
      'network_error'    — transient connectivity/proxy failure
      'unknown'          — unclassified
    """
    e = str(error_str).lower()
    # Device conflict — token was revoked by a new login on another device
    if any(x in e for x in [
        "invalid_grant", "another device", "device_conflict",
        "session invalidated", "forced logout", "kicked", "revoked",
    ]):
        return "device_conflict"
    # Session fully expired — needs OTP
    if any(x in e for x in [
        "otp", "re-login", "expired", "401", "unauthorized",
        "invalid_client", "session dead",
    ]):
        return "session_expired"
    # Transient network / proxy failures — do NOT alert admins
    if any(x in e for x in [
        "timeout", "connection", "refused", "network", "dns",
        "proxy", "socks", "unreachable", "connecttimeout",
    ]):
        return "network_error"
    return "unknown"


def _set_status(account_id: int, **kw) -> None:
    with _STATUS_LOCK:
        if account_id not in _STATUS:
            _STATUS[account_id] = {
                "last_ok_at":           None,
                "last_fail_at":         None,
                "last_error":           None,
                "last_error_class":     None,
                "last_conflict_at":     None,
                "consecutive_failures": 0,
                "token_expires_at":     None,
                "token_status":         "unknown",
                "msisdn":               "",
                "last_refresh_at":      None,
                "last_ping_at":         None,
                "ping_status":          "unknown",
            }
        _STATUS[account_id].update(kw)


def get_status() -> dict:
    """Return a snapshot of all account keepalive statuses + recent events."""
    with _STATUS_LOCK:
        accounts = {str(aid): dict(v) for aid, v in _STATUS.items()}
    with _EVENTS_LOCK:
        events = list(_EVENTS[-20:])
    return {
        "accounts":          accounts,
        "events":            events,
        "worker_started_at": _started_at,
        "now":               int(time.time()),
    }


# ── Token refresh helper ───────────────────────────────────────────────────────

def _try_refresh(acct: dict) -> bool:
    """Silently refresh the access token — Android OAuth2 first, web fallback.

    Priority order (mirrors refresh_session in jazzdrive.py):
      1. Android OAuth2: POST /oauth2/refresh_token.php with client_id=fnbroot.
         Uses the refresh_token from the initial Android-style OTP login.
         Gives months-long sessions — exactly what the Jazz Drive Android app does.
      2. Web raw_accesstoken: GET /sapi/login/oauth?keytype=accesstoken.
         Fallback for accounts set up before the Android OAuth2 upgrade.
         Works for ~1 h between raw_accesstoken refreshes.
         NOTE: keytype=refreshtoken does NOT exist. keytype=accesstoken re-validates
         using the raw 40-hex OTP-issued token (raw_accesstoken DB column).

    NOTE: check is BEFORE the try/except so JDDisabled propagates cleanly.

    Returns True if refresh succeeded and DB was updated.
    """
    aid    = acct["id"]
    msisdn = acct["msisdn"]
    rt     = (acct.get("refresh_token") or "").strip()
    raw_at = (acct.get("raw_accesstoken") or "").strip()
    vk     = (acct.get("validation_key") or "").strip()

    # ── Master kill switch — BEFORE try/except so JDDisabled is not swallowed ─
    jazzdrive.require_jd_active()

    if not rt and not raw_at and not vk:
        log.debug("No credentials for %s — OTP required", msisdn)
        return False

    if rt:
        log.info("Auto-refreshing JazzDrive session for %s (Android OAuth2 path) ...", msisdn)
    else:
        log.info("Auto-refreshing JazzDrive session for %s (web raw_accesstoken path) ...", msisdn)

    try:
        result = jazzdrive.refresh_session(account_id=aid)
        if result.get("ok"):
            msg = result.get("message", "")
            log.info("✓ Session refreshed for %s — %s", msisdn, msg)
            _set_status(aid, last_refresh_at=int(time.time()), token_status="ok")
            _log_event("token_refreshed", msisdn, msg[:120])
            return True
        log.warning("Session refresh failed for %s: %s", msisdn, result.get("error"))
        return False
    except Exception as e:
        log.warning("_try_refresh exception for %s: %s", msisdn, e)
        return False


# ── Main loop ─────────────────────────────────────────────────────────────────

def loop(stop_event: threading.Event, interval_min: int = 360) -> None:
    """Keep-alive loop with dual-interval scheduling.

    Two independent per-account timers run concurrently:

    PING  (default every 20 min, DB key: ping_interval_min)
      GET /sapi/system/information with full APK-matching headers.
      Prevents JSESSIONID idle-timeout (3600 s confirmed).  The JazzDrive
      web SPA does the same to stay alive between user interactions.

    HEARTBEAT  (default every 360 min, DB key: keepalive_interval_min)
      Upload + delete a small probe file in /Radd-Heartbeat/.
      Proves end-to-end storage access and rolls the session expiry window.
      Also triggers silent token refresh when tokens are near expiry.

    Active hours: 08:00–23:00 PKT only — mirrors real user behaviour.
    Outside this window the loop sleeps in 60 s chunks until active.
    All intervals carry ±10 % (ping) or ±25 % (heartbeat) jitter so
    traffic never looks perfectly mechanical.
    """
    global _started_at
    _started_at = time.time()
    log.info(
        "JazzDrive keep-alive worker started "
        "(dual-interval: ping every ~20 min, heartbeat every ~360 min, PKT 08:00–23:00)"
    )

    # Per-account next-fire timestamps (0 = fire on first opportunity)
    _next_ping:      dict[int, float] = {}
    _next_heartbeat: dict[int, float] = {}

    def _schedule_ping(aid: int, base_s: float) -> None:
        jitter = random.uniform(-0.10, 0.10)
        _next_ping[aid] = time.time() + base_s * (1.0 + jitter)

    def _schedule_heartbeat(aid: int, base_s: float) -> None:
        jitter = random.uniform(-0.25, 0.25)
        _next_heartbeat[aid] = time.time() + max(3600.0, base_s * (1.0 + jitter))

    while True:
        # 60-second tick — tight enough for accurate interval tracking without
        # busy-spinning; stop_event lets us exit cleanly within 1 minute.
        if stop_event.wait(60):
            break

        # ── Master kill switches ──────────────────────────────────────────────
        if db.setting("JAZZDRIVE_ENABLED", "1") != "1":
            log.debug("keepalive: JAZZDRIVE_ENABLED=0 (master OFF)")
            continue
        if db.setting("KEEPALIVE_ENABLED", "1") != "1":
            log.debug("keepalive: KEEPALIVE_ENABLED=0")
            continue

        # ── Active-hours gate ─────────────────────────────────────────────────
        if not _is_active_hours():
            secs = _seconds_until_active() + random.uniform(60, 1200)
            pkt_now = datetime.now(_PKT).strftime("%H:%M PKT")
            log.info(
                "keepalive: quiet hours (%s) — sleeping %.0f min until active window",
                pkt_now, secs / 60,
            )
            # Chunked sleep so stop_event is checked at least every 60 s
            sleep_end = time.time() + secs
            while time.time() < sleep_end:
                if stop_event.wait(min(60.0, sleep_end - time.time())):
                    return
            continue

        # ── Read intervals from DB so admin changes take effect immediately ───
        _ping_interval_s = float(int(db.setting("ping_interval_min") or 20) * 60)
        _hb_interval_s   = float(int(db.setting("keepalive_interval_min")
                                     or interval_min or 360) * 60)

        now = time.time()

        try:
            accounts = db.list_accounts(hide_secrets=False)
            for acct in accounts:
                if not acct.get("is_active"):
                    continue

                role = acct.get("role", "")
                if role == "scan" and db.setting("SCAN_ENABLED", "1") != "1":
                    continue
                if role == "flix" and db.setting("UPLOAD_ENABLED", "1") != "1":
                    continue

                aid = acct["id"]

                # Initialise timers on first sight of this account
                if aid not in _next_heartbeat:
                    # Stagger first heartbeat by 0–5 min so multiple accounts
                    # don't all fire at once on startup
                    _next_heartbeat[aid] = now + random.uniform(0, 300)
                if aid not in _next_ping:
                    # Stagger first ping by 0–60 s
                    _next_ping[aid] = now + random.uniform(0, 60)

                # ── Full heartbeat (file upload) ──────────────────────────────
                if now >= _next_heartbeat[aid]:
                    _run_heartbeat(acct)
                    _schedule_heartbeat(aid, _hb_interval_s)
                    _schedule_ping(aid, _ping_interval_s)   # heartbeat counts as ping
                    log.debug(
                        "keepalive: next heartbeat for %s in %.0f min",
                        acct.get("msisdn"), (_next_heartbeat[aid] - time.time()) / 60,
                    )

                # ── Lightweight SAPI ping ─────────────────────────────────────
                elif now >= _next_ping[aid]:
                    # 8% natural skip — real users occasionally miss an interaction
                    if random.random() >= 0.08:
                        _sapi_ping(acct)
                    _schedule_ping(aid, _ping_interval_s)
                    log.debug(
                        "keepalive: next ping for %s in %.0f min",
                        acct.get("msisdn"), (_next_ping[aid] - time.time()) / 60,
                    )

        except Exception as e:
            log.warning("keepalive_loop error: %s", e)


def trigger_heartbeat(account_id: int) -> None:
    """Immediately run a heartbeat for the given account in a background thread."""
    acct = db.get_account(account_id)
    if acct:
        threading.Thread(target=_run_heartbeat, args=(acct,), daemon=True).start()


# ── Heartbeat ─────────────────────────────────────────────────────────────────

def _run_heartbeat(acct: dict) -> None:
    # ── Master kill switch — BEFORE try/except so JDDisabled is not swallowed ─
    jazzdrive.require_jd_active()

    aid    = acct["id"]
    msisdn = acct["msisdn"]
    exp_at = acct.get("token_expires_at")
    now    = int(time.time())

    # ── Determine OAuth2 token-expiry status ────────────────────────────────────
    # token_expires_at tracks OAUTH2 TOKEN expiry (NOT the JSESSIONID idle timeout).
    #
    # The two timeouts are completely separate:
    #   • JSESSIONID idle timeout = 3600 s — kept alive by _sapi_ping() (every ~20 min)
    #   • OAuth2 refresh_token expiry = ~30 days — tracked here via token_expires_at
    #   • raw_accesstoken (web path) = ~1 h — refreshed via keytype=accesstoken
    #
    # We trigger a silent refresh when < 600 s remain on the stored token_expires_at
    # window so we stay ahead of the OAuth2 expiry deadline.
    if exp_at:
        secs_left = exp_at - now
        if secs_left <= 0:
            tok_status = "expired"
        elif secs_left < 600:           # < 10 min — proactively renew
            tok_status = "expiring_soon"
        else:
            tok_status = "ok"
    else:
        tok_status = "unknown"

    _set_status(aid, msisdn=msisdn, token_expires_at=exp_at, token_status=tok_status)

    # ── Skip if no tokens at all ───────────────────────────────────────────────
    if not acct.get("validation_key") or not acct.get("jsessionid"):
        log.debug("Skipping heartbeat for %s (no tokens)", msisdn)
        return

    # ── Proactively refresh when token has fully expired ──────────────────────
    if tok_status == "expired":
        log.info("Token EXPIRED for %s — attempting silent refresh before giving up", msisdn)
        refreshed = _try_refresh(acct)
        if refreshed:
            try:
                with db.conn() as c:
                    row = c.execute("SELECT * FROM accounts WHERE id=?", (aid,)).fetchone()
                    if row:
                        acct      = dict(row)
                        tok_status = "ok"
            except Exception:
                pass
        else:
            log.warning("Token EXPIRED for %s and silent refresh failed — OTP required", msisdn)
            _notify_admins(
                f"⚠️ JazzDrive session EXPIRED for {msisdn} and auto-refresh failed. "
                f"Please re-login via Settings → JazzDrive Scan."
            )
            _set_status(aid,
                        last_error="token_expired_refresh_failed",
                        last_fail_at=now,
                        consecutive_failures=_STATUS.get(aid, {}).get("consecutive_failures", 0) + 1)
            return
    elif tok_status == "expiring_soon":
        log.info("Token expiring soon for %s — attempting silent refresh (non-blocking)", msisdn)
        _try_refresh(acct)

    log.debug("Running heartbeat for %s (token_status=%s) …", msisdn, tok_status)

    tokens = {
        "validation_key": acct["validation_key"],
        "jsessionid":     acct["jsessionid"],
        "node":           acct.get("node", ""),
    }

    try:
        from . import uploader as _up
        import requests as _req

        vk   = tokens["validation_key"]
        jsid = tokens["jsessionid"]

        # ── Simulate "app startup" delay (2–8 seconds) ────────────────────────
        # Real users take a moment to open the app; the first SAPI request doesn't
        # arrive at exactly T+0. This makes the request pattern look organic.
        time.sleep(random.uniform(2.0, 8.0))

        # 1. Verify session is alive via folder-list probe
        if not _up.verify_jd_session(vk, jsid, account_id=aid):
            log.info("Session probe failed for %s — trying silent token refresh", msisdn)
            if _try_refresh(acct):
                try:
                    with db.conn() as c:
                        row = c.execute("SELECT * FROM accounts WHERE id=?", (aid,)).fetchone()
                        if row:
                            acct = dict(row)
                            vk   = acct["validation_key"]
                            jsid = acct["jsessionid"]
                except Exception:
                    pass
                if not _up.verify_jd_session(vk, jsid, account_id=aid):
                    raise RuntimeError("Session invalid even after token refresh")
                log.info("Session recovered via token refresh for %s", msisdn)
            else:
                raise RuntimeError("JazzDrive session check failed — silent refresh failed (may need OTP re-login)")
        else:
            # Re-fetch in case validationkey was rotated during verify_jd_session
            try:
                with db.conn() as c:
                    row = c.execute("SELECT validation_key, jsessionid FROM accounts WHERE id=?", (aid,)).fetchone()
                    if row:
                        vk   = row["validation_key"]
                        jsid = row["jsessionid"]
            except Exception:
                pass

        sess = _req.Session()
        _sapi_px = jazzdrive.resolve_proxies(purpose='sapi')
        if _sapi_px:
            sess.proxies.update(_sapi_px)

        # 2. Ensure Radd-Heartbeat folder exists
        folder_id = _up._get_or_create_folder(sess, vk, jsid, "Radd-Heartbeat", parent_id=0, account_id=aid)
        if not folder_id:
            raise RuntimeError("Could not find or create /Radd-Heartbeat/ folder")

        # 3. Upload heartbeat file — varied name and size each run
        hb_name  = _heartbeat_filename()
        tmp_path = config.CACHE_DIR / hb_name
        config.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        payload_bytes = _generate_payload(tmp_path)
        resp = _up._upload_file(sess, vk, jsid, tmp_path, parent_id=folder_id, account_id=aid)

        if isinstance(resp, dict):
            if resp.get("id") is not None:
                log.debug("heartbeat: file uploaded (id=%s, name=%s, size=%d B)",
                          resp["id"], hb_name, payload_bytes)
            elif resp.get("ok"):
                log.debug("heartbeat: empty-body 200 — upload confirmed (name=%s)", hb_name)
            else:
                raise RuntimeError(f"upload returned no id: {resp!r}")
        else:
            raise RuntimeError(f"upload returned unexpected type: {resp!r}")

        # Clean up local temp file; remote file stays for connection history
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)

        # ── Success ────────────────────────────────────────────────────────────
        has_rt = bool((acct.get("refresh_token") or "").strip())
        expires_offset = 86400 * 30 if has_rt else 3300

        with db.conn() as c:
            c.execute(
                "UPDATE accounts SET last_keepalive_at=?, token_expires_at=? WHERE id=?",
                (now, now + expires_offset, aid)
            )
        _set_status(aid, last_ok_at=now, last_error=None, last_error_class=None,
                    consecutive_failures=0, token_status="ok")
        _log_event("heartbeat_ok", msisdn,
                   f"Session alive — expiry +{'30d' if has_rt else '55m'}")
        log.info("✓ Heartbeat OK for %s (session alive, expiry rolled +%s)",
                 msisdn, "30d" if has_rt else "55m")

    except Exception as e:
        prev      = _STATUS.get(aid, {}).get("consecutive_failures", 0)
        fails     = prev + 1
        err_str   = str(e)[:400]
        err_class = _classify_error(err_str)

        status_update = dict(
            last_fail_at=now,
            last_error=err_str,
            last_error_class=err_class,
            consecutive_failures=fails,
        )

        # ── Device conflict — another Android device kicked our session ───────
        if err_class == "device_conflict":
            status_update["last_conflict_at"] = now
            log.warning(
                "⚡ DEVICE CONFLICT detected for %s (#%d) — another device "
                "invalidated our JazzDrive session: %s", msisdn, fails, err_str
            )
            _log_event("device_conflict", msisdn,
                       f"Session kicked by another device: {err_str[:120]}")
            db.append_scan_log(aid, "device_conflict", err_str)
            # Auto-pause keepalive after 2 consecutive conflicts
            if fails >= 2:
                log.warning(
                    "Auto-pausing keepalive after %d device conflicts for %s",
                    fails, msisdn
                )
                try:
                    db.set_setting("KEEPALIVE_ENABLED", "0")
                    _log_event("auto_paused", msisdn,
                               f"Keepalive auto-paused after {fails} device conflicts")
                except Exception:
                    pass
                _notify_admins(
                    f"[CONFLICT] JazzDrive device conflict for {msisdn}!\n"
                    f"Another Android device invalidated our session.\n"
                    f"Keepalive AUTO-PAUSED after {fails} conflicts.\n"
                    f"Re-enable once the other device logs out."
                )
            else:
                _notify_admins(
                    f"[CONFLICT] JazzDrive device conflict for {msisdn} "
                    f"- another device took the session. (#{fails})"
                )

        # ── Session expired ────────────────────────────────────────────────────
        elif err_class == "session_expired":
            log.warning("✗ Session EXPIRED for %s (#%d): %s", msisdn, fails, err_str)
            _log_event("session_expired", msisdn, err_str[:120])
            db.append_scan_log(aid, "keepalive_fail", err_str)
            if fails >= 2:
                _notify_admins(
                    f"⚠️ JazzDrive session EXPIRED for {msisdn} after {fails} failures. "
                    f"OTP re-login required via Scan page."
                )

        # ── Transient network error ────────────────────────────────────────────
        elif err_class == "network_error":
            log.warning("✗ Network error for %s (#%d): %s", msisdn, fails, err_str)
            _log_event("network_error", msisdn, err_str[:120])
            # Don't alert admins for single network blips — only on sustained failures
            if fails >= 3:
                db.append_scan_log(aid, "keepalive_fail", err_str)
                _notify_admins(
                    f"⚠️ JazzDrive keepalive network errors ×{fails} for {msisdn}: {err_str[:100]}"
                )

        # ── Unknown error ──────────────────────────────────────────────────────
        else:
            log.warning("✗ Heartbeat FAILED for %s (#%d): %s", msisdn, fails, err_str)
            _log_event("heartbeat_fail", msisdn, err_str[:120])
            db.append_scan_log(aid, "keepalive_fail", err_str)
            if fails >= 2:
                _notify_admins(
                    f"⚠️ JazzDrive heartbeat failed {fails}× for {msisdn}: {err_str[:100]}"
                )

        _set_status(aid, **status_update)


# ── Bot notification helper ───────────────────────────────────────────────────

def _notify_admins(message: str) -> None:
    """Try to send a WhatsApp message to all admin JIDs."""
    try:
        from .bots import whatsapp as _wa
        _wa.notify_admins(message)
    except Exception as e:
        log.debug("_notify_admins: %s", e)
