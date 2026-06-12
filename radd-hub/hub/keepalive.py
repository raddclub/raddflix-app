"""JazzDrive session keep-alive loop with automatic token refresh.

Every ``interval_min`` minutes (with human-like jitter):
  1. Iterates all active JazzDrive accounts.
  2. Only runs during active hours (8am–11pm PKT) — mirrors real user behavior.
  3. If the token is expiring within 24 h AND a refresh_token is stored,
     silently calls /sapi/login?keytype=refreshtoken to get fresh tokens —
     no OTP needed. This is exactly what the Jazz Drive Android app does
     to stay logged in for months.
  4. Uploads a small file to /Radd-Heartbeat/, then deletes it.
  5. On heartbeat failure, tries a token refresh before giving up.
  6. Tracks last-ok / last-fail timestamps and error messages in memory.
  7. Notifies WhatsApp admins when things go wrong.

Human-like behavior rules:
  - Active hours: 8am–11pm PKT only (UTC+5). Outside this window the loop
    sleeps until the next 8am window + random 1-20 min offset.
  - Interval jitter: base interval ± 25% random, so activity never looks
    perfectly mechanical (e.g. 360 min → 270–450 min actual gap).
  - 8% probabilistic skip per account per cycle: real users don't open
    JazzDrive on a perfect schedule.
  - Variable payload size (800–1400 bytes) and filename each run.
  - 2–8 second random "app startup" delay before each heartbeat upload.
"""
from __future__ import annotations
import random
import time
import logging
import threading
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional
from . import db, config, jazzdrive

log = logging.getLogger("hub.keepalive")

_CLOUD_BASE = "https://cloud.jazzdrive.com.pk"

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
    """Delete a file from JazzDrive by remote ID. Returns True on success."""
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

# ── In-memory status registry ─────────────────────────────────────────────────
_STATUS: dict[int, dict] = {}
_STATUS_LOCK = threading.Lock()
_started_at: Optional[float] = None


def _set_status(account_id: int, **kw) -> None:
    with _STATUS_LOCK:
        if account_id not in _STATUS:
            _STATUS[account_id] = {
                "last_ok_at":           None,
                "last_fail_at":         None,
                "last_error":           None,
                "consecutive_failures": 0,
                "token_expires_at":     None,
                "token_status":         "unknown",
                "msisdn":               "",
                "last_refresh_at":      None,
            }
        _STATUS[account_id].update(kw)


def get_status() -> dict:
    """Return a snapshot of all account keepalive statuses."""
    with _STATUS_LOCK:
        return {
            "accounts":          {str(aid): dict(v) for aid, v in _STATUS.items()},
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
         Works for ~1 h between refreshes (keepalive fires every 15 min so OK).

    Returns True if refresh succeeded and DB was updated.
    """
    aid    = acct["id"]
    msisdn = acct["msisdn"]
    rt     = (acct.get("refresh_token") or "").strip()
    raw_at = (acct.get("raw_accesstoken") or "").strip()
    vk     = (acct.get("validation_key") or "").strip()

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
            return True
        log.warning("Session refresh failed for %s: %s", msisdn, result.get("error"))
        return False
    except Exception as e:
        log.warning("_try_refresh exception for %s: %s", msisdn, e)
        return False


# ── Main loop ─────────────────────────────────────────────────────────────────

def loop(stop_event: threading.Event, interval_min: int = 15) -> None:
    global _started_at
    _started_at = time.time()
    log.info("JazzDrive keep-alive worker started (human-like mode, PKT active hours 08:00–23:00)")

    while True:
        # ── Master kill switch — checked before all per-service toggles ──────
        if db.setting("JAZZDRIVE_ENABLED", "1") != "1":
            log.debug("keepalive: JAZZDRIVE_ENABLED=0 (master OFF), sleeping 60s")
            if stop_event.wait(60):
                break
            continue
        # ── Enabled gate ──────────────────────────────────────────────────────
        if db.setting("KEEPALIVE_ENABLED", "1") != "1":
            log.debug("keepalive: KEEPALIVE_ENABLED=0, sleeping 60s")
            if stop_event.wait(60):
                break
            continue
        # ── Active-hours gate ─────────────────────────────────────────────────
        if not _is_active_hours():
            secs = _seconds_until_active()
            # Add a random 1–20 min offset so start time varies each day
            secs += random.uniform(60, 1200)
            pkt_now = datetime.now(_PKT).strftime("%H:%M PKT")
            log.info(
                "keepalive: quiet hours (%s) — sleeping %.0f min until active window",
                pkt_now, secs / 60,
            )
            if stop_event.wait(secs):
                break
            continue

        # ── Read interval from DB each iteration so admin changes take effect ─
        _base_min = int(db.setting("keepalive_interval_min") or interval_min or 360)

        # ── Run heartbeat for all active accounts ─────────────────────────────
        try:
            accounts = db.list_accounts(hide_secrets=False)
            for acct in accounts:
                if not acct.get("is_active"):
                    continue

                # Respect per-service on/off toggles
                role = acct.get("role", "")
                if role == "scan" and db.setting("SCAN_ENABLED", "1") != "1":
                    log.debug("keepalive: skipping scan account %s (SCAN_ENABLED=0)",
                              acct.get("msisdn"))
                    continue
                if role == "flix" and db.setting("UPLOAD_ENABLED", "1") != "1":
                    log.debug("keepalive: skipping flix account %s (UPLOAD_ENABLED=0)",
                              acct.get("msisdn"))
                    continue

                # 8% probabilistic skip — real users don't open the app on a
                # perfect schedule; occasional gaps look natural
                if random.random() < 0.08:
                    log.debug(
                        "keepalive: natural skip for %s this cycle (probabilistic)",
                        acct.get("msisdn"),
                    )
                    continue

                _run_heartbeat(acct)

        except Exception as e:
            log.warning("keepalive_loop error: %s", e)

        # ── Jittered sleep ────────────────────────────────────────────────────
        # Apply ±25% random jitter so the interval never looks perfectly mechanical.
        # E.g. base=360 min → actual sleep 270–450 min.
        # Clamped to [60 min, base×1.5] for safety.
        jitter   = random.uniform(-0.25, 0.25)
        sleep_min = _base_min * (1.0 + jitter)
        sleep_min = max(60.0, min(sleep_min, _base_min * 1.5))
        log.debug(
            "keepalive: sleeping %.0f min (base=%d min, jitter=%.0f%%)",
            sleep_min, _base_min, jitter * 100,
        )
        if stop_event.wait(sleep_min * 60):
            break


def trigger_heartbeat(account_id: int) -> None:
    """Immediately run a heartbeat for the given account in a background thread."""
    acct = db.get_account(account_id)
    if acct:
        threading.Thread(target=_run_heartbeat, args=(acct,), daemon=True).start()


# ── Heartbeat ─────────────────────────────────────────────────────────────────

def _run_heartbeat(acct: dict) -> None:
    aid    = acct["id"]
    msisdn = acct["msisdn"]
    exp_at = acct.get("token_expires_at")
    now    = int(time.time())

    # ── Determine token-expiry status ──────────────────────────────────────────
    # JSESSIONID idle timeout = 3600 s (verified 2026-05-07). Trigger proactive
    # refresh when less than 10 minutes remain so we stay ahead of the deadline.
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
        _set_status(aid, last_ok_at=now, last_error=None, consecutive_failures=0,
                    token_status="ok")
        log.info("✓ Heartbeat OK for %s (session alive, expiry rolled +%s)",
                 msisdn, "30d" if has_rt else "55m")

    except Exception as e:
        prev  = _STATUS.get(aid, {}).get("consecutive_failures", 0)
        fails = prev + 1
        _set_status(aid, last_fail_at=now, last_error=str(e)[:200],
                    consecutive_failures=fails)
        log.warning("✗ Heartbeat FAILED for %s (#%d): %s", msisdn, fails, e)
        db.append_scan_log(aid, "keepalive_fail", str(e))

        if fails >= 2:
            _notify_admins(f"⚠️ JazzDrive heartbeat failed {fails}× for {msisdn}: {e}")


# ── Bot notification helper ───────────────────────────────────────────────────

def _notify_admins(message: str) -> None:
    """Try to send a WhatsApp message to all admin JIDs."""
    try:
        from .bots import whatsapp as _wa
        _wa.notify_admins(message)
    except Exception as e:
        log.debug("_notify_admins: %s", e)
