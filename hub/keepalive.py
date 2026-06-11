"""JazzDrive session keep-alive loop with automatic token refresh.

Every ``interval_min`` minutes:
  1. Iterates all active JazzDrive accounts.
  2. If the token is expiring within 24 h AND a refresh_token is stored,
     silently calls /sapi/login?keytype=refreshtoken to get fresh tokens —
     no OTP needed. This is exactly what the Jazz Drive Android app does
     to stay logged in for months.
  3. Uploads a 1 KB heartbeat file to /Heartbeat/, then deletes it.
  4. On heartbeat failure, tries a token refresh before giving up.
  5. Tracks last-ok / last-fail timestamps and error messages in memory.
  6. Notifies WhatsApp admins when things go wrong.
"""
from __future__ import annotations
import time
import logging
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from . import db, config, jazzdrive

log = logging.getLogger("hub.keepalive")

_CLOUD_BASE = "https://cloud.jazzdrive.com.pk"


def _heartbeat_filename() -> str:
    """Return a static heartbeat filename. Overwriting the same file
    keeps the session alive while keeping the remote folder clean.
    """
    return "radd_hub_heartbeat.txt"


def _generate_payload(path: Path) -> int:
    """Write a ~1 KB heartbeat file. Returns byte count."""
    ts_utc   = datetime.now(timezone.utc).isoformat(timespec="seconds")
    ts_local = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    body = (
        f"Radd-Hub JazzDrive Connection Heartbeat\n"
        f"========================================\n"
        f"Generated : {ts_local} (local) / {ts_utc} (UTC)\n"
        f"Purpose   : Confirms that Radd-Hub is connected to JazzDrive via Flix.\n"
        f"            Each file in this folder = one successful 15-min heartbeat.\n"
        f"Note      : Do NOT delete this folder — it keeps the session alive.\n"
        + ("." * 600)
    ).encode("utf-8")
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
    log.info("JazzDrive keep-alive worker started (interval: %d min)", interval_min)

    while True:
        if db.setting("KEEPALIVE_ENABLED", "1") != "1":
            log.debug("keepalive: KEEPALIVE_ENABLED=0 — sleeping")
            if stop_event.wait(60):
                break
            continue
        try:
            accounts = db.list_accounts(hide_secrets=False)
            for acct in accounts:
                if not acct.get("is_active"):
                    continue
                # Respect per-service on/off toggles — if a service is disabled
                # we stop sending periodic heartbeats so JazzDrive doesn't see
                # constant traffic from an account that isn't in active use.
                role = acct.get("role", "")
                if role == "scan" and db.setting("SCAN_ENABLED", "1") != "1":
                    log.debug("keepalive: skipping scan account %s (SCAN_ENABLED=0)",
                              acct.get("msisdn"))
                    continue
                if role == "flix" and db.setting("UPLOAD_ENABLED", "1") != "1":
                    log.debug("keepalive: skipping flix account %s (UPLOAD_ENABLED=0)",
                              acct.get("msisdn"))
                    continue
                _run_heartbeat(acct)
        except Exception as e:
            log.warning("keepalive_loop error: %s", e)
        if stop_event.wait(interval_min * 60):
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
    # For web-OAuth accounts (no refresh_token), the JSESSIONID is kept alive
    # by the heartbeat upload itself acting as a session ping every 15 min.
    # We only need to attempt a token exchange when the session is truly dead.
    # "expiring_soon" is NOT a hard stop — we continue and let the heartbeat
    # prove the session is still alive, then roll token_expires_at forward.
    if tok_status == "expired":
        log.info("Token EXPIRED for %s — attempting silent refresh before giving up",
                 msisdn)
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
        # Try a soft refresh but DO NOT abort if it fails — the heartbeat itself
        # will prove whether the session is still alive and will roll the expiry.
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

        # 1. Verify session is alive via folder-list probe
        if not _up.verify_jd_session(vk, jsid, account_id=aid):
            # Session probe failed — try one token refresh before giving up
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
            # Re-fetch anyway in case it was rotated during verify_jd_session's internal sapi_request call
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

        # 2. Ensure Radd-Heartbeat folder exists (kept permanently — do not delete)
        folder_id = _up._get_or_create_folder(sess, vk, jsid, "Radd-Heartbeat", parent_id=0, account_id=aid)
        if not folder_id:
            raise RuntimeError("Could not find or create /Radd-Heartbeat/ folder")

        # 3. Upload heartbeat file with date-time stamped name
        #    Each file stays in the folder so you can see the connection history
        #    in JazzDrive and verify Radd-Hub → Flix → JazzDrive is working.
        hb_name  = _heartbeat_filename()
        tmp_path = config.CACHE_DIR / hb_name
        config.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        _generate_payload(tmp_path)
        resp = _up._upload_file(sess, vk, jsid, tmp_path, parent_id=folder_id, account_id=aid)

        # Accept ok=True (empty-body 200) as session-alive proof.
        if isinstance(resp, dict):
            if resp.get("id") is not None:
                log.debug("heartbeat: file uploaded (id=%s, name=%s)", resp["id"], hb_name)
            elif resp.get("ok"):
                log.debug("heartbeat: empty-body 200 — upload confirmed (name=%s)", hb_name)
            else:
                raise RuntimeError(f"upload returned no id: {resp!r}")
        else:
            raise RuntimeError(f"upload returned unexpected type: {resp!r}")

        # Clean up local temp file only — the remote file is kept permanently
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)

        # ── Success ────────────────────────────────────────────────────────────
        # Roll token_expires_at forward: the heartbeat upload proved the JSESSIONID
        # is alive RIGHT NOW. JSESSIONID idle timeout is 3600 s (verified 2026-05-07).
        # If we have a refresh_token, we can roll the expiry to 30 days.
        # Otherwise, we roll to 55 min until the next heartbeat.
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
