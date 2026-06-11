"""Unified JazzDrive client (login, OTP, scan, share, upload, keepalive).

Thin facade over the vendored v2.0 modules so we get all their tested
behavior with no duplication. Both the scanner and the uploader use this.
Adds a stateful OTP flow with persistence so the web UI can drive it.
"""
from __future__ import annotations
import json
import logging
import os
import pickle
import base64
import sys
import time
import uuid as _uuid
import threading
from pathlib import Path
from typing import Optional

from . import config, db
from . import _legacy  # injects sys.path so internal imports resolve

def _scanner():
    from ._legacy import scanner
    return scanner

def jazzdrive_login(*args, **kwargs):
    return _scanner().jazzdrive_login(*args, **kwargs)

def jazzdrive_verify_otp(*args, **kwargs):
    return _scanner().jazzdrive_verify_otp(*args, **kwargs)

def list_folders(*args, **kwargs):
    return _scanner().list_folders(*args, **kwargs)

def list_videos(*args, **kwargs):
    return _scanner().list_videos(*args, **kwargs)

def get_or_create_share_link(*args, **kwargs):
    return _scanner().get_or_create_share_link(*args, **kwargs)

def enrich_and_save(*args, **kwargs):
    return _scanner().enrich_and_save(*args, **kwargs)

def _legacy_scan_account(*args, **kwargs):
    return _scanner().scan_account(*args, **kwargs)

def _auth_headers(tokens: dict) -> dict:
    """Standardized headers for JazzDrive requests, used by legacy modules."""
    vk = tokens.get("validationkey") or tokens.get("validation_key") or ""
    jid = tokens.get("jsessionid") or tokens.get("JSESSIONID") or ""
    msisdn = tokens.get("msisdn")
    return get_auth_headers(vk, jid, msisdn=msisdn)

def _auth_params(*args, **kwargs):
    return _scanner()._auth_params(*args, **kwargs)

def _parse_quality(*args, **kwargs):
    return _scanner()._parse_quality(*args, **kwargs)

def _parse_episode_info(*args, **kwargs):
    return _scanner()._parse_episode_info(*args, **kwargs)

CLOUD_BASE = "https://cloud.jazzdrive.com.pk"
OAUTH_BASE = "https://jazzdrive.com.pk"

# Share helpers from flix
try:
    from ._legacy.jazz_share import (  # noqa: E402
        create_folder_share_link, list_share_links, get_or_create_folder_share,
    )
except ImportError as _jazz_share_err:
    import logging as _log_jz
    _log_jz.getLogger("hub.jazzdrive").warning(
        "jazz_share import failed — folder share-link functions unavailable: %s",
        _jazz_share_err,
    )
    def create_folder_share_link(*args, **kwargs):  # type: ignore[misc]
        raise RuntimeError("jazz_share not available: " + str(_jazz_share_err))
    def list_share_links(*args, **kwargs):  # type: ignore[misc]
        raise RuntimeError("jazz_share not available: " + str(_jazz_share_err))
    def get_or_create_folder_share(*args, **kwargs):  # type: ignore[misc]
        raise RuntimeError("jazz_share not available: " + str(_jazz_share_err))

# Keepalive
try:
    from ._legacy.jazz_keepalive import *  # noqa: F401,F403
except Exception:
    pass


log = logging.getLogger("hub.jazzdrive")

SESSION_FILE = config.DATA_DIR / "jazzdrive_session.json"

# Android OAuth2 credentials — decrypted from APK (AES/CBC/PKCS7, classes2.dex C4622a / C3912s)
# Confirmed valid: POST /oauth2/refresh_token.php returns invalid_grant (not invalid_client)
ANDROID_CLIENT_ID     = "fnbroot"
ANDROID_CLIENT_SECRET = "f&rW23"
_OTP_STATE_FILE = config.TEMP_DIR / "radd_jd_otp_state.json"
_lock = threading.Lock()

# ── SAPI 401 backoff registry ─────────────────────────────────────────────────
# When all auto-refresh strategies fail (OTP re-login required), we record the
# failure time and skip *all* sapi_request auto-refresh attempts for 30 min.
# This one dict covers every caller: uploader, bulk_links, keepalive, etc.
_SAPI_BACKOFF: "dict[int, float]" = {}
_SAPI_BACKOFF_LOCK = threading.Lock()
_SAPI_BACKOFF_SECS = 1800  # 30 minutes

# ── SAPI backoff persistence (survives Flask restarts) ──────────────────────
def _backoff_file():
    try:
        from . import config as _cfg
        return _cfg.TEMP_DIR / 'sapi_backoff.json'
    except Exception:
        import pathlib, tempfile
        return pathlib.Path(tempfile.gettempdir()) / 'sapi_backoff.json'

def _load_persisted_backoff():
    """Load SAPI backoff timestamps from disk on startup."""
    try:
        import json as _json
        bf = _backoff_file()
        if bf.exists():
            data = _json.loads(bf.read_text())
            now  = __import__('time').time()
            with _SAPI_BACKOFF_LOCK:
                for k, v in data.items():
                    if now - v < _SAPI_BACKOFF_SECS:  # still valid
                        _SAPI_BACKOFF[int(k)] = v
            if _SAPI_BACKOFF:
                import logging as _lg
                _lg.getLogger('hub.jazzdrive').info(
                    'Reloaded SAPI backoff for %d account(s) from disk', len(_SAPI_BACKOFF))
    except Exception:
        pass

def _save_persisted_backoff():
    """Persist SAPI backoff timestamps to disk so restarts don't reset them."""
    try:
        import json as _json
        with _SAPI_BACKOFF_LOCK:
            data = {str(k): v for k, v in _SAPI_BACKOFF.items()}
        _backoff_file().write_text(_json.dumps(data))
    except Exception:
        pass

# Load on import (runs once per process)
_load_persisted_backoff()

# ── Per-account refresh-token lock ────────────────────────────────────────────
# JazzDrive rotates the refresh_token on every /oauth2/refresh_token.php call.
# If two threads call android_refresh_session for the same account concurrently
# (e.g., keepalive tick + trigger_heartbeat firing together after Flask restart),
# both read the same token, both POST to OAuth2, and the second one gets
# invalid_grant because the first already consumed it.
# Fix: one Lock per account — second caller waits, then detects the DB token
# has already changed and returns early without making a second network call.
_refresh_locks: "dict[int, threading.Lock]" = {}
_refresh_locks_mutex = threading.Lock()
# Cooldown: after a successful refresh, suppress all further exchange attempts
# for this many seconds. Prevents sapi_request's internal retry loop from
# burning through the refresh-token chain (token A -> B -> C -> invalid_grant).
_REFRESH_COOLDOWN_S = 180  # 3 minutes
_last_refresh_success: "dict[int, float]" = {}   # account_id -> epoch seconds
_last_refresh_lock = threading.Lock()


def _get_refresh_lock(account_id: int) -> "threading.Lock":
    """Return (creating if needed) the per-account refresh serialisation lock."""
    with _refresh_locks_mutex:
        if account_id not in _refresh_locks:
            _refresh_locks[account_id] = threading.Lock()
        return _refresh_locks[account_id]


def clear_sapi_backoff(account_id: int) -> None:
    """Clear the SAPI backoff for an account (call after new tokens are saved)."""
    with _SAPI_BACKOFF_LOCK:
        removed = _SAPI_BACKOFF.pop(account_id, None)
    if removed is not None:
        _save_persisted_backoff()  # update disk so cleared backoff survives restart
        log.info("JazzDrive account %s: session backoff lifted — auto-refresh re-enabled. Account can now upload and stream again.", account_id)


def _is_sapi_backed_off(account_id: Optional[int]) -> bool:
    """Return True if this account is suppressing auto-refresh (OTP backoff)."""
    if not account_id:
        return False
    with _SAPI_BACKOFF_LOCK:
        fail_at = _SAPI_BACKOFF.get(account_id)
    if fail_at is None:
        return False
    elapsed = time.time() - fail_at
    if elapsed >= _SAPI_BACKOFF_SECS:
        with _SAPI_BACKOFF_LOCK:
            _SAPI_BACKOFF.pop(account_id, None)
        return False
    remaining_min = int((_SAPI_BACKOFF_SECS - elapsed) / 60)
    log.debug("account %s SAPI backoff active — %dm remaining", account_id, remaining_min)
    return True


def _mark_sapi_backed_off(account_id: Optional[int]) -> None:
    """Suppress SAPI auto-refresh for this account for 30 min (OTP required)."""
    if not account_id:
        return
    with _SAPI_BACKOFF_LOCK:
        _SAPI_BACKOFF[account_id] = time.time()
    _save_persisted_backoff()  # persist so Flask restart doesn't reset this
    log.warning(
        "JazzDrive account %s is LOGGED OUT — auto-refresh suppressed for 30 min to protect the token. "
        "Action required: open the admin panel -> Settings -> JazzDrive Scan -> send OTP for this account.",
        account_id
    )



# ---------------------------------------------------------------------------
# v2 radd_flix module loader (for upload primitives)
# ---------------------------------------------------------------------------

def _flix():
    """Return the radd_flix module from v2, or None if unavailable."""
    v2_path = config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "services" / "flix"
    if not v2_path.exists():
        return None
    if str(v2_path) not in sys.path:
        sys.path.insert(0, str(v2_path))
    try:
        import importlib
        return importlib.import_module("radd_flix")
    except Exception as e:
        log.error("Cannot import radd_flix: %s", e)
        return None


# ---------------------------------------------------------------------------
# Session persistence & SAPI Request Wrapper
# ---------------------------------------------------------------------------

def _load_session() -> dict:
    try:
        if SESSION_FILE.exists():
            return json.loads(SESSION_FILE.read_text())
    except Exception as e:
        log.warning("load_session error: %s", e)
    return {}


def _save_session(data: dict):
    try:
        SESSION_FILE.parent.mkdir(parents=True, exist_ok=True)
        SESSION_FILE.write_text(json.dumps(data, indent=2))
    except Exception as e:
        log.error("save_session error: %s", e)


# ────────────────────────��────────────────────────────────────────────────────
# Proxy Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _is_replit() -> bool:
    return bool(os.environ.get("REPL_ID") or os.environ.get("REPLIT_DEPLOYMENT"))

def resolve_proxies(purpose: str = 'otp') -> Optional[dict]:
    """Always returns None — JazzDrive traffic routes via wg0 VPN at OS level.
    Raises JDVPNRequired if wg0 is not routing JD IPs.
    NEVER allows JD traffic to leak via Oracle direct IP — account would be suspended."""
    require_wg0()
    return None



def is_proxy_bypass() -> bool:
    """Always True — all JD traffic goes direct/VPN.  No proxy pool."""
    return True


# ─────────────────────────────────────────────────────────────────────────────
# VPN / Direct Fallback Helpers
# ─────────────────────────────────────────────────────────────────────────────

_JD_IPS = ["54.179.95.148", "54.254.59.168", "175.41.133.62"]
_wg0_lock = __import__('threading').Lock()


def _wg0_route_ips() -> list:
    """Return the JD IPs that currently have an explicit wg0 route."""
    try:
        import subprocess as _sp
        out = _sp.check_output(["ip", "route", "show", "dev", "wg0"],
                               text=True, timeout=2)
        return [ip for ip in _JD_IPS if ip in out]
    except Exception:
        return []


def _wg0_alive() -> bool:
    """Quick TCP probe: can we reach any JD IP on port 443 via wg0 in < 3 s?"""
    import socket as _sock
    for ip in _JD_IPS:
        try:
            s = _sock.create_connection((ip, 443), timeout=3)
            s.close()
            return True
        except OSError:
            pass
    return False


def _remove_wg0_routes(ips: list) -> None:
    """Temporarily delete wg0 routes so traffic uses the default interface."""
    import subprocess as _sp
    for ip in ips:
        _sp.run(["sudo", "ip", "route", "del", ip, "dev", "wg0"],
                capture_output=True, timeout=3)


def _restore_wg0_routes(ips: list) -> None:
    """Re-add wg0 routes after a direct-fallback attempt."""
    import subprocess as _sp
    for ip in ips:
        _sp.run(["sudo", "ip", "route", "add", ip, "dev", "wg0", "scope", "link"],
                capture_output=True, timeout=3)

# ─────────────────────────────────────────────────────────────────────────────
# wg0 VPN Enforcement — hard-fail if JD IPs are not routed via wg0
# ─────────────────────────────────────────────────────────────────────────────

class JDVPNRequired(RuntimeError):
    """Raised when a JazzDrive network call is blocked because wg0 is not
    routing the JazzDrive IPs.  NEVER allow JD traffic via Oracle's direct IP
    — account suspension risk."""
    pass


def require_wg0() -> None:
    """Hard-fail if wg0 is not currently routing ALL JazzDrive IPs.

    Must be called at the entry point of every function that makes a JazzDrive
    network request.  If any JD IP route is missing (VPN down / peer unreachable),
    we raise JDVPNRequired instead of letting the request fall through to Oracle's
    direct IP — which would expose a non-PK IP to JazzDrive and risk account suspension.

    This is a zero-tolerance rule: no JD call ever goes out without wg0.
    """
    routed = _wg0_route_ips()
    missing = [ip for ip in _JD_IPS if ip not in routed]
    if missing:
        msg = (
            f"wg0 VPN not routing JazzDrive IPs {missing} — "
            f"JazzDrive call BLOCKED (refusing to leak via Oracle direct IP, "
            f"account suspension risk)"
        )
        log.error("require_wg0: %s", msg)
        raise JDVPNRequired(msg)
    log.debug("require_wg0: OK — all JD IPs routed via wg0 %s", routed)


# ─────────────────────────────────────────────────────────────────────────────
# Auth Helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_x_deviceid(msisdn: Optional[str] = None, account_id: Optional[int] = None) -> str:
    """Return the X-deviceid for this account.

    Priority:
      1. Stored device_id in accounts table (set via admin or from real APK login).
      2. Deterministic fallback: android-{last10_msisdn} — looks like a real Android app ID.

    Jazz ties sessions to device_id — keeping it stable prevents session invalidation.
    """
    # 1. Per-account stored device_id
    if account_id:
        try:
            with db.conn() as _c:
                row = _c.execute(
                    "SELECT device_id FROM accounts WHERE id=?", (account_id,)
                ).fetchone()
                if row and row["device_id"]:
                    return row["device_id"]
        except Exception:
            pass
    # 2. Try by MSISDN
    m = str(msisdn or db.setting("JAZZDRIVE_MSISDN") or "").strip()
    m = m.replace("+", "").replace(" ", "").replace("-", "")
    if m:
        try:
            with db.conn() as _c:
                row = _c.execute(
                    "SELECT device_id FROM accounts WHERE msisdn=?", (m,)
                ).fetchone()
                if row and row and row["device_id"]:
                    return row["device_id"]
        except Exception:
            pass
    # 3. Global default set via admin panel (DEFAULT_ANDROID_ID setting)
    default_did = db.setting("DEFAULT_ANDROID_ID") or ""
    if default_did:
        return default_did
    # 4. Deterministic fallback — looks like real Android device ID format
    suffix = m[-10:] if len(m) >= 10 else "raddhub"
    return f"android-{suffix}"


def get_x_devicename(msisdn: Optional[str] = None, account_id: Optional[int] = None) -> str:
    """Return X-devicename for this account.

    Default: InfinixInfinix X680F (the real registered Android device from My Devices page).
    Can be overridden per-account via the device_name column.
    """
    # 1. Per-account stored device_name
    if account_id:
        try:
            with db.conn() as _c:
                row = _c.execute(
                    "SELECT device_name FROM accounts WHERE id=?", (account_id,)
                ).fetchone()
                if row and row["device_name"]:
                    return row["device_name"]
        except Exception:
            pass
    # 2. Try by MSISDN
    m = str(msisdn or db.setting("JAZZDRIVE_MSISDN") or "").strip().replace("+","").replace(" ","").replace("-","")
    if m:
        try:
            with db.conn() as _c:
                row = _c.execute(
                    "SELECT device_name FROM accounts WHERE msisdn=?", (m,)
                ).fetchone()
                if row and row["device_name"]:
                    return row["device_name"]
        except Exception:
            pass
    # 3. Global setting override
    override = db.setting("JAZZDRIVE_DEVICE_NAME") or ""
    if override:
        return override
    # 4. Default: real registered Android device name from My Devices screenshot
    return "InfinixInfinix X680F"

def get_auth_headers(vk: str, jid: str, msisdn: Optional[str] = None,
                    account_id: Optional[int] = None) -> dict:
    """Return standard headers for any SAPI/Cloud request.

    Device identity is sourced from the accounts table (device_id / device_name columns).
    Defaults to the real registered device observed in My Devices:
      - X-devicename:  InfinixInfinix X680F  (Android: {manufacturer}{model})
      - User-Agent:    Dalvik/2.1.0 ... Infinix X680F (matching the real phone)
      - X-deviceid:    stored per-account or android-{last10_msisdn}
      - X-request-id:  fresh UUID per request (logged by Jazz servers)

    Headers confirmed from Windows binary strings analysis (Jazz Drive.exe, 2025).
    """
    return {
        "Accept":           "application/json, text/plain, */*",
        "Accept-Language":  "en-US,en;q=0.9",
        "User-Agent":       "Dalvik/2.1.0 (Linux; U; Android 12; Infinix X680F Build/SP1A.210812.016)",
        "X-deviceid":       get_x_deviceid(msisdn, account_id=account_id),
        "X-devicename":     get_x_devicename(msisdn, account_id=account_id),
        "X-Requested-With": "com.jazz.drive",
        "X-request-id":     _uuid.uuid4().hex,
        "Cookie":           f"JSESSIONID={jid}",
        "validation_key":   vk,
    }


def refresh_jsessionid(validation_key: str,
                       raw_accesstoken: str = "") -> tuple[Optional[str], Optional[dict]]:
    """Use the stored raw_accesstoken to silently obtain a fresh JSESSIONID."""
    import requests as _req
    import urllib.parse as _up
    import base64 as _b64

    # Resolve Proxy — SAPI endpoint may be geo-restricted; use dedicated SAPI proxy slot
    proxies = resolve_proxies(purpose='sapi')

    CLOUD_BASE = "https://cloud.jazzdrive.com.pk"
    msisdn = str(db.setting('JAZZDRIVE_MSISDN') or "")
    dev_suffix = msisdn[-10:] if len(msisdn) >= 10 else _uuid.uuid4().hex[:10]

    # Find account_id for this msisdn so device_id/device_name are correctly resolved
    _aid_for_refresh = None
    try:
        with db.conn() as _c:
            _ar = _c.execute("SELECT id FROM accounts WHERE msisdn=?", (m,)).fetchone()
            if _ar:
                _aid_for_refresh = _ar["id"]
    except Exception:
        pass
    headers = get_auth_headers("", "", msisdn=msisdn, account_id=_aid_for_refresh)
    headers.pop("Cookie", None)
    headers.pop("validation_key", None)
    headers.update({
        "Accept": "application/json, text/javascript, */*",
        "Origin": CLOUD_BASE,
        "Referer": CLOUD_BASE + "/",
    })

    candidates = []

    # Primary: raw_accesstoken (verified working — returns HTTP 200)
    at = (raw_accesstoken or "").strip()
    if at:
        at_json  = json.dumps({"data": {"accesstoken": at}})
        at_b64   = _b64.b64encode(at_json.encode()).decode()
        at_b64_q = _up.quote(at_b64, safe='')
        candidates.append(
            f"{CLOUD_BASE}/sapi/login/oauth?action=login&platform=Android"
            f"&keytype=accesstoken&key={at_b64_q}"
        )

    if not candidates:
        log.debug("refresh_jsessionid: no raw_accesstoken stored — OTP re-login required")
        return None, None

    r = None
    try:
        for url_candidate in candidates:
            try:
                r = _req.get(url_candidate, headers=headers, timeout=20, proxies=proxies)
                log.debug("refresh_jsessionid: HTTP %d @ %s", r.status_code, url_candidate[:90])
                if r.status_code == 200:
                    try:
                        body = r.json()
                        d    = body.get("data", body) if isinstance(body, dict) else {}
                        jsid = (d.get("jsessionid") or d.get("JSESSIONID")
                                or r.cookies.get("JSESSIONID") or "")
                    except Exception:
                        body = None
                        jsid = r.cookies.get("JSESSIONID") or ""
                    if jsid:
                        log.info("refresh_jsessionid: fresh JSESSIONID obtained via raw_accesstoken")
                        return jsid, body
                    log.debug("refresh_jsessionid: 200 but no JSESSIONID in response")
                else:
                    log.debug("refresh_jsessionid: HTTP %d — credentials rejected or session dead",
                              r.status_code)
            except Exception as _e:
                log.debug("refresh_jsessionid candidate error: %s", _e)

        return None, None
    except Exception as e:
        log.debug("refresh_jsessionid error: %s", e)
        return None, None


def rename_video(account_id: int, video_id: int, new_name: str,
                 folder_id: Optional[int] = None,
                 media_type: str = "video") -> dict:
    """Rename a media file on JazzDrive.

    Verified live from bundle analysis: POST /sapi/upload/{mediatype}?action=save-metadata
    Body: JSON {"data": {"id": file_id, "name": "new_name.mkv", "folderid": folder_id}}

    NOTE: The old endpoint (POST /sapi/media/video?action=rename) silently returns
    HTTP 200 with an empty body but does NOT actually rename the file — confirmed bug.
    This endpoint (/sapi/upload/%1?action=save-metadata) is what the web UI uses.

    Args:
        account_id: JazzDrive account ID.
        video_id: Remote file ID to rename.
        new_name: New filename including extension (e.g. "Inception (2010).mkv").
        folder_id: Optional folder ID the file lives in (included in payload for safety).
        media_type: JazzDrive media type — "video", "file", "picture", or "audio".
    """
    payload: dict = {"data": {"id": video_id, "name": new_name}}
    if folder_id is not None:
        payload["data"]["folderid"] = folder_id
    return sapi_request(
        endpoint=f"/upload/{media_type}",
        action="save-metadata",
        method="POST",
        json_data=payload,
        account_id=account_id,
    )

def delete_video(account_id: int, video_id: int) -> dict:
    """Move a video file to the JazzDrive trash (soft delete).

    Uses the per-type soft-delete endpoint (softdelete=true).
    Trashed videos appear in GET /sapi/media/video/trash (use get_file_trash()).
    """
    return trash_files(account_id, [video_id], media_type="video")


def trash_files(account_id: int, file_ids: list, media_type: str = "file") -> dict:
    """Move one or more files to the JazzDrive trash (soft delete).

    Verified live: POST /sapi/media/{type}?action=delete&softdelete=true
    Returns e.g. {"success": "Files soft deleted successfully"} on success.

    Trashed files appear in GET /sapi/media/video/trash — use get_file_trash().
    They do NOT appear in the folder trash (get_trash()).

    IMPORTANT — do NOT use POST /sapi/media?action=delete; that permanently
    deletes files and is the correct endpoint for the trash-page "hard delete".

    media_type: "file" (default), "video", "picture", "audio"
    """
    valid = {"file", "video", "picture", "audio"}
    mtype = media_type if media_type in valid else "file"
    return sapi_request(
        endpoint=f"/media/{mtype}",
        action="delete",
        method="POST",
        json_data={"data": {"ids": [int(fid) for fid in file_ids]}},
        params={"softdelete": "true"},
        account_id=account_id
    )


def delete_files_permanent(account_id: int, file_ids: list) -> dict:
    """Permanently delete one or more files from JazzDrive (IRREVERSIBLE).

    Verified from bundle trash module: POST /sapi/media?action=delete
    WARNING: This permanently deletes files — they are NOT moved to trash.
    Use trash_files() to soft-delete (recoverable) instead.
    """
    return sapi_request(
        endpoint="/media",
        action="delete",
        method="POST",
        json_data={"data": {"ids": [int(fid) for fid in file_ids]}},
        account_id=account_id
    )


def list_all_files_in_folder(account_id: int, folder_id: int) -> list:
    """List all non-video files (mediatype=file) in a JazzDrive folder.

    Uses /media/file?action=get — the correct endpoint for .txt/.json uploads.
    /media/video ONLY returns video-type items and will miss non-video uploads.

    Returns list of dicts: {"id": int, "name": str, "size": int}
    Only includes non-softdeleted items whose folder matches folder_id.
    """
    data = sapi_request(
        endpoint="/media/file",
        action="get",
        params={"parentId": folder_id, "folderId": folder_id},
        account_id=account_id,
        tokens=None,
    )
    files = (data.get("data") or {}).get("files") or []
    result = []
    for f in files:
        item_folder = f.get("folder")
        if item_folder is not None and int(item_folder) != int(folder_id):
            continue
        if f.get("softdeleted"):
            continue
        fid = f.get("id")
        if fid:
            result.append({
                "id":   int(fid),
                "name": f.get("name") or "",
                "size": int(f.get("size") or 0),
            })
    return result


def get_file_trash(account_id: int, max_items: int = 200) -> dict:
    """Fetch trashed media files (videos, files, pictures, audio).

    Verified live: GET /sapi/media/video/trash?action=get
    Despite the URL containing "video", this endpoint returns ALL trashed media
    types (files, videos, pictures, audio) — the name is a JazzDrive misnomer.

    Files trashed with trash_files() appear here, NOT in get_trash() (folder trash).
    Response: {"data": {"media": [{"id": N, "mediatype": "file"|"video", ...}]}}
    """
    return sapi_request(
        endpoint="/media/video/trash",
        action="get",
        method="GET",
        params={"max-page-size": max_items},
        account_id=account_id
    )


def trash_folder(account_id: int, folder_ids: list) -> dict:
    """Move one or more folders to the JazzDrive trash (soft delete).

    Verified live: POST /sapi/media/folder?action=softdelete + {"data": {"ids": [...]}}
    Returns {"success": "Folders have been softdeleted"} on success.
    """
    return sapi_request(
        endpoint="/media/folder",
        action="softdelete",
        method="POST",
        json_data={"data": {"ids": [int(fid) for fid in folder_ids]}},
        account_id=account_id
    )


def delete_folder_permanent(account_id: int, folder_ids: list) -> dict:
    """Permanently delete one or more folders (irreversible).

    Verified from bundle: POST /sapi/media/folder?action=delete + {"data": {"folders": [...]}}
    WARNING: This is irreversible. Items are NOT moved to trash.
    """
    return sapi_request(
        endpoint="/media/folder",
        action="delete",
        method="POST",
        json_data={"data": {"folders": [int(fid) for fid in folder_ids]}},
        account_id=account_id
    )


def get_trash(account_id: int, max_items: int = 200) -> dict:
    """Fetch the folder-trash contents (trashed folders only).

    Verified live: POST /sapi/media/trash?action=get + {"data": {"max-page-size": N}}
    Response: {"data": {"entries": [{"type": "folder", "id": N, "name": "..."}]}}

    NOTE: Trashed media FILES appear in get_file_trash() (/sapi/media/video/trash),
    not here. This endpoint only returns folder-level trash entries.
    """
    return sapi_request(
        endpoint="/media/trash",
        action="get",
        method="POST",
        json_data={"data": {"max-page-size": max_items}},
        account_id=account_id
    )


def empty_trash(account_id: int) -> dict:
    """Permanently delete ALL items currently in the JazzDrive trash.

    Verified live: POST /sapi/media/trash?action=empty
    WARNING: Irreversible — all trashed files and folders are gone permanently.
    """
    return sapi_request(
        endpoint="/media/trash",
        action="empty",
        method="POST",
        json_data={},
        account_id=account_id
    )


def restore_files(account_id: int, file_ids: list, media_type: str = "video") -> dict:
    """Restore one or more files from the JazzDrive trash.

    Verified live: POST /sapi/media?action=restore + {"data": {"<type>s": [id, ...]}}
    media_type: "video", "file", "picture", or "audio" (pluralized automatically).
    """
    type_map = {"video": "videos", "file": "files", "picture": "pictures", "audio": "audios"}
    key = type_map.get(media_type, "files")
    return sapi_request(
        endpoint="/media",
        action="restore",
        method="POST",
        json_data={"data": {key: [int(fid) for fid in file_ids]}},
        account_id=account_id
    )


def restore_folder(account_id: int, folder_id: int) -> dict:
    """Restore a single folder from the JazzDrive trash.

    From bundle: POST /sapi/trash/folder?action=restore + {"data": {"id": folder_id}}
    The JazzDrive web UI restores folders one at a time.
    """
    return sapi_request(
        endpoint="/trash/folder",
        action="restore",
        method="POST",
        json_data={"data": {"id": int(folder_id)}},
        account_id=account_id
    )


def create_folder(account_id: int, name: str, parent_id: int) -> dict:
    """Create a new folder on JazzDrive.

    Verified live: POST /sapi/media/folder?action=save + JSON body (no id = create new).
    Returns: {"data": {"folder": {"id": N, "name": "...", "lastupdate": ts}}}
    """
    return sapi_request(
        endpoint="/media/folder",
        action="save",
        method="POST",
        json_data={"data": {"magic": False, "offline": False,
                            "name": name, "parentid": int(parent_id)}},
        account_id=account_id
    )


def move_folder(account_id: int, folder_id: int, folder_name: str,
                new_parent_id: int) -> dict:
    """Move a folder to a different parent on JazzDrive.

    Verified live: POST /sapi/media/folder?action=save + form-encoded body
    Body: data=URL_ENCODED_JSON({"data": {"id": N, "parentid": P, "name": "..."}})
    """
    import urllib.parse as _up
    payload = json.dumps({"data": {
        "id":       int(folder_id),
        "parentid": int(new_parent_id),
        "name":     folder_name,
    }})
    body_str = "data=" + _up.quote(payload, safe="")
    return sapi_request(
        endpoint="/media/folder",
        action="save",
        method="POST",
        data=body_str,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        account_id=account_id
    )


def move_files(account_id: int, file_ids: list,
               from_folder_id: int, to_folder_id: int) -> dict:
    """Move multiple files from one JazzDrive folder to another.

    Uses add-item then remove-item (JazzDrive has no single bulk-move endpoint).
    Returns the remove-item response, or the add-item response on failure.
    """
    add_r = add_item_to_folder(account_id, file_ids, to_folder_id)
    if add_r.get("error"):
        return add_r
    return remove_item_from_folder(account_id, file_ids, from_folder_id)


def add_item_to_folder(account_id: int, file_ids: list, folder_id: int) -> dict:
    """Add one or more files to a JazzDrive folder (first half of a move)."""
    return sapi_request(
        endpoint="/media/folder",
        action="add-item",
        method="POST",
        json_data={"data": {"items": file_ids, "folderid": int(folder_id)}},
        account_id=account_id
    )

def remove_item_from_folder(account_id: int, file_ids: list, folder_id: int) -> dict:
    """Remove one or more files from a JazzDrive folder (second half of a move)."""
    return sapi_request(
        endpoint="/media/folder",
        action="remove-item",
        method="POST",
        json_data={"data": {"items": file_ids, "folderid": int(folder_id)}},
        account_id=account_id
    )

def move_video(account_id: int, file_id: int, from_folder_id: int, to_folder_id: int) -> dict:
    """Move a video from one JazzDrive folder to another.

    JazzDrive has no single move endpoint; this calls add-item then remove-item.
    Returns the remove-item response, or the add-item response if add-item failed.
    """
    add_r = add_item_to_folder(account_id, [file_id], to_folder_id)
    if add_r.get("error"):
        return add_r
    return remove_item_from_folder(account_id, [file_id], from_folder_id)

def rename_folder(account_id: int, folder_id: int, new_name: str,
                  parent_id: Optional[int] = None) -> dict:
    """Rename a folder on JazzDrive.

    Verified live: POST /sapi/media/folder?action=save + JSON with id + name.
    parent_id is sent to the API (required field); defaults to magic root (1719700).
    """
    pid = int(parent_id) if parent_id else 1719700  # JazzDrive magic root default
    return sapi_request(
        endpoint="/media/folder",
        action="save",
        method="POST",
        json_data={"data": {"id": int(folder_id), "name": new_name, "parentid": pid}},
        account_id=account_id
    )


# ---------------------------------------------------------------------------
# Startup handshake - real JazzDrive app sequence on login / session restore
# ---------------------------------------------------------------------------

def startup_handshake(vk: str, jid: str, msisdn=None, account_id=None) -> dict:
    import time as _t, random as _r, requests as _req
    results = {}
    hdrs = get_auth_headers(vk, jid, msisdn=msisdn, account_id=account_id)
    px = resolve_proxies()

    def _get(endpoint, action=None, extra=""):
        params = ("action=" + action) if action else ""
        if extra:
            params += ("&" if params else "") + extra
        url = CLOUD_BASE + "/sapi" + endpoint + ("?" + params if params else "")
        try:
            _t.sleep(_r.uniform(0.4, 1.2))
            r = _req.get(url, headers=hdrs, timeout=15, proxies=px, verify=False)
            return r.json() if r.status_code == 200 else {"_http": r.status_code}
        except Exception as e:
            return {"_error": str(e)}

    results["features"]     = _get("/features")
    results["profile"]      = _get("/profile", action="get")
    results["subscription"] = _get("/subscription", action="get")
    results["storage"]      = _get("/media", action="get-storage-space", extra="softdeleted=true")
    # Real app also loads folder tree and checks for app updates on startup
    results["folder_root"]  = _get("/media/folder/root", action="get")
    results["folder_list"]  = _get("/media/folder", action="get")
    results["client_info"]  = _get("/profile/client",
                                   action="get-update-info",
                                   extra="component=android")

    ok_count = sum(1 for v in results.values() if "_error" not in v and "_http" not in v)
    log.info("startup_handshake done: %d/%d endpoints OK", ok_count, len(results))
    return results


# ---------------------------------------------------------------------------
# Post-upload validation polling
# ---------------------------------------------------------------------------

def post_upload_validate(vk: str, jid: str, msisdn=None, account_id=None,
                         max_polls: int = 8, poll_interval: float = 3.0) -> dict:
    import time as _t, random as _r, requests as _req
    hdrs = get_auth_headers(vk, jid, msisdn=msisdn, account_id=account_id)
    url  = CLOUD_BASE + "/sapi/media?action=get-validation-status"
    px   = resolve_proxies()

    log.info("post_upload_validate: polling max=%d interval=%.1fs", max_polls, poll_interval)
    for poll_num in range(1, max_polls + 1):
        _t.sleep(poll_interval + _r.uniform(0, 1.0))
        try:
            r = _req.get(url, headers=hdrs, timeout=15, proxies=px, verify=False)
            if r.status_code != 200:
                break
            data  = r.json()
            items = data.get("data") or data.get("items") or []
            if isinstance(items, list) and len(items) == 0:
                log.info("post_upload_validate: complete after %d poll(s)", poll_num)
                return {"ok": True, "polls": poll_num}
            status = data.get("status") or ""
            if status in ("done", "complete", "finished"):
                return {"ok": True, "polls": poll_num, "status": status}
        except Exception as e:
            log.debug("post_upload_validate poll %d error: %s", poll_num, e)
            break
    return {"ok": True, "polls": max_polls, "note": "max polls reached"}


def sapi_request(endpoint: str, action: str, 
                 method: str = "GET", 
                 params: Optional[dict] = None, 
                 json_data: Optional[dict] = None,
                 data: Optional[any] = None,
                 headers: Optional[dict] = None,
                 account_id: Optional[int] = None,
                 tokens: Optional[dict] = None,
                 timeout: int = 30,
                 _retry_count: int = 0) -> dict:
    """Centralized SAPI request helper with SEC-1003 auto-rotation.
    
    This is the core of the "Infinite Session" upgrade. It:
    1. Injects validationkey and JSESSIONID.
    2. Detects SEC-1003 (key rotated) and automatically retries with new key.
    3. Handles 401 by attempting a JSESSIONID refresh if validationkey exists.
    4. Support global proxy via JAZZDRIVE_PROXY setting.
    """
    import requests as _req
    import urllib.parse as _up

    if _retry_count > 3:
        return {"error": {"code": "AUTH-ERR", "message": "Max retries exceeded"}}

    # Resolve Proxy
    proxies = resolve_proxies(purpose="sapi")

    # 1. Resolve tokens
    if not tokens:
        if account_id:
            try:
                with db.conn() as _c:
                    row = _c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
                    if row:
                        row_dict = dict(row)
                        tokens = {
                            "validationkey": row_dict["validation_key"],
                            "jsessionid": row_dict["jsessionid"],
                            "refresh_token": row_dict["refresh_token"],
                            "raw_accesstoken": row_dict.get("raw_accesstoken"),
                            "msisdn": row_dict["msisdn"]
                        }
                    else:
                        return {"error": {"code": "AUTH-002", "message": f"Account {account_id} not found in DB"}}
            except Exception as _e:
                return {"error": {"code": "DB-ERR", "message": str(_e)}}
        
        # Fallback to global session ONLY if no account_id was requested
        if not tokens and not account_id:
            s = _load_session()
            tokens = {
                "validationkey": s.get("validationkey"),
                "jsessionid": s.get("jsessionid"),
                "refresh_token": s.get("refresh_token"),
                "raw_accesstoken": s.get("raw_accesstoken"),
                "msisdn": s.get("msisdn")
            }
            
    if not tokens or not tokens.get("validationkey"):
        return {"error": {"code": "AUTH-001", "message": "No validationkey available for this request"}}

    # 2. Build URL & Headers
    vk  = tokens.get("validationkey") or ""
    jid = tokens.get("jsessionid") or ""
    url = f"https://cloud.jazzdrive.com.pk/sapi/{endpoint.lstrip('/')}"
    req_params = params.copy() if params else {}
    if action:
        req_params["action"] = action
    req_params["validationkey"] = vk
    
    req_headers = get_auth_headers(vk, jid or "", msisdn=tokens.get("msisdn"), account_id=account_id)
    if not jid:
        req_headers.pop("Cookie", None)
    if headers:
        req_headers.update(headers)

    # 3. Execute request
    # proxies is always None (VPN handled at OS routing level)
    _req_proxies = None
    try:
        r = _req.request(method, url, params=req_params, json=json_data, data=data, headers=req_headers, timeout=timeout)

        # 3b. Capture any fresh JSESSIONID issued by the server on SUCCESSFUL responses.
        # Only save on 2xx — a 401 response may carry a guest/unauthenticated JSESSIONID
        # which would break subsequent authenticated calls if saved.
        if 200 <= r.status_code < 300:
            new_jid_from_cookie = r.cookies.get("JSESSIONID")
            new_vk_from_header = r.headers.get("X-Funambol-ValidationKey")
            
            needs_update = False
            if new_jid_from_cookie and new_jid_from_cookie != jid:
                log.debug("sapi_request: server issued new JSESSIONID on success — saving")
                tokens["jsessionid"] = new_jid_from_cookie
                needs_update = True
            
            if new_vk_from_header and new_vk_from_header != vk:
                log.info("sapi_request: server rotated validationkey in header — saving")
                tokens["validationkey"] = new_vk_from_header
                vk = new_vk_from_header  # update local vk for subsequent logic
                needs_update = True
                
            if needs_update:
                _update_token_storage(account_id, tokens)

        # 4. Handle HTTP 401 (Transparent re-login)
        # Strategy A: refresh_token (Android app flow — months-long sessions)
        # Strategy B: validationKey → fresh JSESSIONID via web re-login endpoint
        if r.status_code == 401 and vk:
            log.warning("JazzDrive: session rejected (401) for account %s — trying auto-refresh (no OTP needed)...", account_id)

            # Skip costly refresh attempts if account is already in OTP backoff.
            # This prevents uploader/bulk_links/keepalive from hammering JazzDrive
            # with 8 failed API calls every 40 s when the session is dead.
            if _is_sapi_backed_off(account_id):
                log.debug("JazzDrive: account %s is in OTP backoff — auto-refresh suppressed (waiting for manual OTP)", account_id)
                log.warning(
                    "JazzDrive ACCOUNT LOGGED OUT — account %s: session expired, OTP re-login required. "
                    "Auto-refresh is paused for 30 min to prevent token burn. "
                    "Go to Settings -> JazzDrive Scan -> Send OTP.",
                    account_id)
            else:
                # Strategy A: use refresh_token (Android approach)
                try:
                    refresh_result = refresh_session(account_id)
                    if refresh_result.get("ok"):
                        log.info("JazzDrive: session auto-renewed for account %s via refresh_token — logged in OK", account_id)
                        new_tokens = tokens.copy()
                        if account_id:
                            try:
                                with db.conn() as _rc:
                                    row = _rc.execute(
                                        "SELECT * FROM accounts WHERE id=?", (account_id,)
                                    ).fetchone()
                                    if row:
                                        new_tokens = {
                                            "validationkey": row["validation_key"],
                                            "jsessionid":    row["jsessionid"],
                                            "refresh_token": row["refresh_token"],
                                        }
                            except Exception:
                                pass
                        return sapi_request(endpoint, action, method, params, json_data, data,
                                            headers, account_id, new_tokens, timeout, _retry_count + 1)
                except Exception as _re:
                    log.debug("refresh_session fallback failed: %s", _re)

                # Strategy B: validationKey → fresh JSESSIONID (web re-login, no OTP needed)
                new_jid_b, _ = refresh_jsessionid(vk, raw_accesstoken=tokens.get("raw_accesstoken", ""))
                if new_jid_b:
                    log.info("JazzDrive: session auto-renewed for account %s via validationKey — logged in OK", account_id)
                    tokens["jsessionid"] = new_jid_b
                    _update_token_storage(account_id, tokens)
                    return sapi_request(endpoint, action, method, params, json_data, data, headers, account_id, tokens, timeout, _retry_count + 1)

                log.warning(
                    "JazzDrive ACCOUNT LOGGED OUT — account %s: both auto-refresh strategies failed. "
                    "Manual OTP re-login required: go to Settings -> JazzDrive Scan -> Send OTP.",
                    account_id)
                _mark_sapi_backed_off(account_id)

        # 5. Handle JSON responses
        try:
            resp_data = r.json()
        except Exception:
            if 200 <= r.status_code < 300:
                return {"ok": True, "text": r.text[:1000]}
            return {"error": {"code": "HTTP-" + str(r.status_code), "message": r.text[:200]}}

        # 6. Handle SEC-1003 (Rolling Key Rotation)
        err = resp_data.get("error")
        if isinstance(err, dict) and err.get("code") == "SEC-1003":
            new_vk = err.get("data") or err.get("validationkey")
            if new_vk:
                log.info("SEC-1003: validationKey rotated. Updating and retrying...")
                tokens["validationkey"] = new_vk
                # Also capture a fresh JSESSIONID the server may have included
                sec_jid = r.cookies.get("JSESSIONID")
                if sec_jid:
                    tokens["jsessionid"] = sec_jid
                _update_token_storage(account_id, tokens)
                return sapi_request(endpoint, action, method, params, json_data, data, headers, account_id, tokens, timeout, _retry_count + 1)

        return resp_data

    except Exception as e:
        import requests as _rq_exc
        _is_conn = isinstance(e, (_rq_exc.ConnectionError, _rq_exc.Timeout))
        if _is_conn:
            # VPN-with-direct fallback: wg0 may be UP but tunnel peer unreachable.
            # Temporarily remove wg0 routes so the default interface is used, retry
            # the request once, then restore the routes.
            with _wg0_lock:
                _routed = _wg0_route_ips()
                if _routed:
                    log.warning("sapi_request: connection failed via wg0 (%s) — retrying direct", str(e)[:80])
                    _remove_wg0_routes(_routed)
                    try:
                        r = _req.request(method, url, params=req_params, json=json_data,
                                         data=data, headers=req_headers, timeout=timeout)
                        log.info("sapi_request: direct fallback succeeded (HTTP %d)", r.status_code)
                        # Don't return here — fall through to normal response handling below
                        # by re-raising so the outer retry loop in callers picks it up.
                        # Actually parse and return directly since we're past the try block.
                        try:
                            resp_data = r.json()
                        except Exception:
                            resp_data = {"_raw": r.text, "_status": r.status_code}
                        return resp_data
                    except Exception as e2:
                        log.error("sapi_request: direct fallback also failed: %s", e2)
                        return {"error": {"code": "EXC", "message": str(e2)}}
                    finally:
                        _restore_wg0_routes(_routed)
        log.error("sapi_request exception: %s", e)
        return {"error": {"code": "EXC", "message": str(e)}}


def _update_token_storage(account_id: Optional[int], tokens: dict):
    """Helper to update tokens in both DB and session file.

    Preserves the existing refresh_token if the caller doesn't supply a new one.
    Uses MAX() for token_expires_at so we never accidentally shorten a long-lived session.
    """
    vk  = tokens.get("validationkey")
    jid = tokens.get("jsessionid")
    rt  = tokens.get("refresh_token")  # may be None if caller didn't supply

    # After a SEC-1003 rotation or JSESSIONID refresh the key is still valid for
    # at least 15 more days per the research; we also never go below 24h.
    expires_offset = 86400 * 15

    if account_id:
        try:
            with _lock:
                with db.conn() as _c:
                    # Preserve refresh_token if we don't have a new one
                    if rt is not None:
                        _c.execute(
                            "UPDATE accounts SET validation_key=?, jsessionid=?, "
                            "refresh_token=?, "
                            "token_expires_at=MAX(COALESCE(token_expires_at,0), ?) WHERE id=?",
                            (vk, jid, rt, int(time.time() + expires_offset), account_id)
                        )
                    else:
                        _c.execute(
                            "UPDATE accounts SET validation_key=?, jsessionid=?, "
                            "token_expires_at=MAX(COALESCE(token_expires_at,0), ?) WHERE id=?",
                            (vk, jid, int(time.time() + expires_offset), account_id)
                        )
        except Exception as e:
            log.warning("Failed to update account tokens in DB: %s", e)

    s = _load_session()
    s.update({"validationkey": vk, "jsessionid": jid})
    if rt is not None:
        s["refresh_token"] = rt
    s["expires_at"] = max(s.get("expires_at", 0), time.time() + expires_offset)
    _save_session(s)


def get_status() -> dict:
    """Return current JazzDrive session status.

    Checks both the local session file expiry AND the DB account status
    (updated by the keepalive worker) so the indicator is accurate.
    """
    s = _load_session()
    msisdn = db.setting("JAZZDRIVE_MSISDN") or ""
    
    # 1. Check DB first for the most accurate state
    db_acct = None
    if msisdn:
        try:
            with db.conn() as _c:
                row = _c.execute("SELECT * FROM accounts WHERE msisdn=? LIMIT 1", (msisdn,)).fetchone()
                if row:
                    db_acct = dict(row)
        except Exception:
            pass

    if not s and not db_acct:
        return {"status": "logged_out", "msisdn": msisdn, "detail": "No session saved — complete OTP login"}

    # Use the DB expiry if available, otherwise session file
    expires = 0
    if db_acct:
        expires = db_acct.get("token_expires_at", 0)
    elif s:
        expires = s.get("expires_at", 0)

    if expires and time.time() > expires:
        # If DB says it's expired, check if keepalive can still save it
        # (This avoids false "expired" states if the worker is about to run)
        if not db_acct or db_acct.get("is_active"):
             pass # continue to liveness check
        else:
            return {"status": "expired", "msisdn": msisdn, "detail": "Session expired — re-login required"}

    # 2. Cross-check with live keepalive results.
    try:
        from . import keepalive as _ka
        ka = _ka.get_status()
        
        # Find the status for our MSISDN in the keepalive registry
        acct_st = None
        if db_acct:
            acct_st = ka.get("accounts", {}).get(str(db_acct["id"]))
        
        if acct_st:
            cf = acct_st.get("consecutive_failures", 0)
            if cf >= 2:
                return {
                    "status": "dead",
                    "msisdn": msisdn,
                    "detail": f"Session dead — keepalive failed {cf}× (re-login required)",
                    "expires_at": expires,
                    "consecutive_failures": cf,
                }
            if cf >= 1:
                return {
                    "status": "warn",
                    "msisdn": msisdn,
                    "detail": "Session unreachable — keepalive failing (may need re-login)",
                    "expires_at": expires,
                    "consecutive_failures": cf,
                }
        elif db_acct and not db_acct.get("is_active"):
            return {"status": "expired", "msisdn": msisdn, "detail": "Account disabled"}
            
    except Exception:
        pass

    if expires and time.time() > expires:
         return {"status": "expired", "msisdn": msisdn, "detail": "Session expired — re-login required"}

    return {
        "status": "connected",
        "msisdn": msisdn,
        "detail": "Session active",
        "expires_at": expires,
        "validationkey_prefix": (db_acct or s).get("validation_key", (db_acct or s).get("validationkey", ""))[:12] + "...",
    }


# ---------------------------------------------------------------------------
# OTP flow
# ---------------------------------------------------------------------------

def trigger_otp_flow(msisdn: Optional[str] = None) -> dict:
    """Step 1: trigger OTP via jazzdrive_login (from _legacy/scanner.py)."""
    if not msisdn:
        msisdn = db.setting("JAZZDRIVE_MSISDN") or ""

    # Normalize to 03xxxxxxxxx for the API (local format is more reliable for OTP)
    m = msisdn.strip().replace(" ", "").replace("-", "").replace("+", "")
    if m.startswith("92"):
        msisdn_local = "0" + m[2:]
    elif m.startswith("3") and len(m) == 10:
        msisdn_local = "0" + m
    else:
        msisdn_local = m

    if not msisdn_local:
        return {"ok": False, "error": "No MSISDN provided or configured"}

    require_wg0()  # Hard-fail if wg0 down — never leak OTP call via Oracle direct IP
    # Always direct — VPN (wg0) routes JD traffic at OS level.
    _proxies_chain: list = [None]

    last_err: Exception = Exception("No proxies available")
    for proxies in _proxies_chain:
        try:
            # jazzdrive_login returns (session, verify_url) or raises
            import requests as _req
            session = _req.Session()
            if proxies:
                session.proxies = proxies
            session.headers.update({
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,*/*",
            })
            # Use v2 radd_flix if available (richer implementation)
            rf = _flix()
            use_android = True  # always try Android flow to get long-lived refresh_token
            if rf:
                verify_url = rf.trigger_otp(session, msisdn_local)
            else:
                _result = jazzdrive_login(msisdn_local, use_android=use_android, proxies=proxies)
                session    = _result["session"]
                verify_url = _result["verify_url"]
                use_android = _result.get("use_android", True)

            state = {
                "verify_url":  verify_url,
                "msisdn":      msisdn_local,
                "msisdn_display": msisdn,
                "cookies":     base64.b64encode(pickle.dumps(session.cookies)).decode(),
                "created_at":  time.time(),
                "use_android": use_android,
            }
            _OTP_STATE_FILE.write_text(json.dumps(state))
            db.set_setting("JAZZDRIVE_MSISDN", msisdn)
            log.info("JazzDrive: OTP SMS sent to %s (proxy: %s) — waiting for user to submit code", msisdn, proxies.get("_url") if proxies else "direct")
            return {"ok": True, "msisdn": msisdn, "message": f"OTP sent to {msisdn}. Check SMS then submit below."}
        except Exception as e:
            last_err = e
            err_s = str(e).lower()
            is_conn = any(x in err_s for x in ('connection', 'timeout', 'refused', 'reset', 'max retries', 'newconnection'))
            if is_conn:
                log.warning("OTP: connection error (%s)", str(e)[:80])
            break

    log.error("trigger_otp error (all proxies exhausted): %s", last_err)
    return {"ok": False, "error": str(last_err)}


def resend_otp() -> dict:
    """Trigger a resend of the OTP using the official 'resendpin' POST trick."""
    if not _OTP_STATE_FILE.exists():
        return {"ok": False, "error": "No pending OTP — trigger one first"}
    try:
        state = json.loads(_OTP_STATE_FILE.read_text())
    except Exception:
        return {"ok": False, "error": "Corrupt OTP state"}

    # TTL guard: resending on an expired session confuses Jazz and wastes SMS quota.
    _resend_age = time.time() - state.get("created_at", 0)
    if _resend_age > 600:
        _OTP_STATE_FILE.unlink(missing_ok=True)
        return {"ok": False, "error": "OTP session expired (>10 min) — trigger a new OTP first"}

    require_wg0()  # Hard-fail if wg0 down — never leak OTP resend via Oracle direct IP
    # Always direct — VPN (wg0) routes JD traffic at OS level.
    _proxies_chain: list = [None]

    last_err: Exception = Exception("No proxies available")
    for proxies in _proxies_chain:
        try:
            import requests as _req
            session = _req.Session()
            if proxies:
                session.proxies = proxies
            session.headers.update({
                "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                                "AppleWebKit/537.36 (KHTML, like Gecko) "
                                "Chrome/124.0.0.0 Safari/537.36"),
            })
            session.cookies = pickle.loads(base64.b64decode(state["cookies"].encode()))

            # Official trick: POST to verify_url with resendpin= (empty)
            # This triggers a new SMS without invalidating the current session.
            r = session.post(
                state["verify_url"],
                data={"resendpin": ""},
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Referer": state["verify_url"],
                },
                timeout=30,
                proxies=proxies,
            )
            log.info("OTP resend triggered for %s via %s (status=%d)",
                     state.get("msisdn"), proxies.get("_url") if proxies else "direct", r.status_code)
            return {"ok": True, "message": "OTP resend request sent. Please check your SMS."}
        except Exception as e:
            last_err = e
            err_s = str(e).lower()
            break

    log.error("resend_otp error (all proxies exhausted): %s", last_err)
    return {"ok": False, "error": str(last_err)}


def submit_otp(otp: str) -> dict:
    """Step 2: verify OTP and persist session."""
    if not _OTP_STATE_FILE.exists():
        return {"ok": False, "error": "No pending OTP — request a new OTP first"}
    try:
        state = json.loads(_OTP_STATE_FILE.read_text())
    except Exception:
        return {"ok": False, "error": "Corrupt OTP state — request a new OTP"}
    age = time.time() - state.get("created_at", 0)
    if age > 600:
        _OTP_STATE_FILE.unlink(missing_ok=True)
        return {"ok": False, "error": "OTP expired (>10 min) — request a new OTP"}

    require_wg0()  # Hard-fail if wg0 down — never leak OTP submit via Oracle direct IP
    # Always direct — VPN (wg0) routes JD traffic at OS level.
    _sub_chain: list = [None]

    _sub_last_err: Exception = Exception("No proxies available")
    for proxies in _sub_chain:
        try:
            vk = jid = ""
            tokens: dict = {}
            import requests as _req
            session: Optional[_req.Session] = None   # only set by web flow

            # ── Strategy 1: Android OAuth2 flow (client_id=fnbroot → long-lived refresh_token) ──
            # Submits the OTP to the same verify.php page used by all flows, then exchanges
            # the resulting auth code via keytype=oauth2code with embedded fnbroot credentials.
            # The response includes a refresh_token usable with /oauth2/refresh_token.php
            # for months without OTP — the same mechanism the Android app uses.
            use_android = state.get("use_android", True)
            _UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) "
                   "Chrome/124.0.0.0 Safari/537.36")
            session = _req.Session()
            if proxies:
                session.proxies = proxies
            session.headers.update({"User-Agent": _UA})
            session.cookies = pickle.loads(base64.b64decode(state["cookies"].encode()))
            rf = _flix()
            if rf:
                try:
                    code = rf.verify_otp(session, state["verify_url"], otp.strip())
                    tokens = rf.exchange_code_for_tokens(session, code)
                    vk = tokens.get("validationkey") or tokens.get("validation_key") or ""
                    jid = tokens.get("jsessionid") or tokens.get("JSESSIONID") or ""
                    log.info("submit_otp: radd_flix OK vk=%s jid=%s", bool(vk), bool(jid))
                except Exception as _rf_e:
                    log.info("submit_otp: radd_flix failed (%s) — falling back to scanner", _rf_e)

            if not vk:
                tokens = jazzdrive_verify_otp(
                    session, state["verify_url"], otp.strip(),
                    use_android=use_android,
                    msisdn=state.get("msisdn", ""),
                    proxies=proxies,
                )

                vk  = tokens.get("validation_key", "")
                jid = tokens.get("jsessionid", "")
                log.info("submit_otp: scanner verify_otp OK use_android=%s vk=%s rt=%s",
                         use_android, bool(vk), bool(tokens.get("refresh_token")))

            # ── Extract raw_accesstoken + refresh_token from verified-guide token dict ──
            # jazzdrive_verify_otp (guide §4) returns raw_accesstoken directly (40-char hex).
            # radd_flix may return access_token as base64-JSON or raw hex — handle both.
            raw_at = tokens.get("raw_accesstoken") or ""
            rt     = (tokens.get("refresh_token") or tokens.get("refreshtoken") or "")
            # Fallback: try decoding access_token field if raw values weren't populated
            if not raw_at or not rt:
                at_b64_field = tokens.get("access_token") or ""
                if at_b64_field:
                    # Case A: already raw 40-char hex (from /oauth2/token.php or refresh)
                    import re as _re
                    if _re.match(r'^[0-9a-f]{40}$', at_b64_field, _re.IGNORECASE):
                        if not raw_at:
                            raw_at = at_b64_field
                            log.info("submit_otp: access_token is raw hex — used directly as raw_at")
                    else:
                        # Case B: base64-JSON {"data":{"accesstoken":"...","refreshtoken":"..."}}
                        try:
                            # BUG FIX: correct padding — old code used "==" unconditionally for non-0
                            # remainder which is wrong when remainder==1 (needs 3 pads) or 2 (needs 2).
                            _padding = "=" * ((4 - len(at_b64_field) % 4) % 4)
                            at_data = json.loads(
                                base64.b64decode(at_b64_field + _padding).decode()
                            ).get("data", {})
                            if not raw_at:
                                raw_at = at_data.get("accesstoken", "")
                            if not rt:
                                rt = at_data.get("refreshtoken", "")
                            log.info("submit_otp: fallback decoded access_token — raw_at=%s rt=%s",
                                     bool(raw_at), bool(rt))
                        except Exception as _at_err:
                            log.warning("submit_otp: access_token decode failed: %s", _at_err)
            log.info("submit_otp: tokens — vk=%s jid=%s raw_at=%s rt=%s",
                     bool(vk), bool(jid), bool(raw_at), bool(rt))

            # Session lifetime: JSESSIONID expires after 3600 s idle. But refresh_token lasts
            # months, so set a long expires_at when we have one — keepalive extends it anyway.
            # BUG FIX: 3300s (55 min) was too short; when keepalive missed one cycle the token
            # appeared expired and android_refresh failed, locking the user out.
            expires_offset = 86400 * 30 if rt else 3300  # 30 days with RT, else 55 min

            cookies_b64 = ""
            if session is not None:
                try:
                    cookies_b64 = base64.b64encode(pickle.dumps(session.cookies)).decode()
                except Exception:
                    pass

            save_data = {
                "validationkey":   vk,
                "jsessionid":      jid,
                "refresh_token":   rt,
                "raw_accesstoken": raw_at,
                "msisdn":          state["msisdn"],
                "created_at":      time.time(),
                "expires_at":      time.time() + expires_offset,
                "cookies":         cookies_b64,
            }
            _save_session(save_data)
            _OTP_STATE_FILE.unlink(missing_ok=True)
            # ── Sync tokens to the accounts DB table (used by uploader) ──────────
            try:
                msisdn_display = state.get("msisdn_display") or state["msisdn"]
                with _lock:
                    with db.conn() as _c:
                        existing = _c.execute(
                            "SELECT id FROM accounts WHERE msisdn=? OR msisdn=? LIMIT 1",
                            (state["msisdn"], msisdn_display)
                        ).fetchone()
                        if existing:
                            _c.execute(
                                "UPDATE accounts SET validation_key=?, jsessionid=?, "
                                "refresh_token=?, raw_accesstoken=?, "
                                "token_expires_at=?, last_scan_at=? WHERE id=?",
                                (vk, jid, rt or None, raw_at or None,
                                 int(time.time() + expires_offset),
                                 int(time.time()), existing["id"])
                            )
                            log.info("Updated accounts table for id=%s", existing["id"])
                        else:
                            _c.execute(
                                "INSERT INTO accounts (msisdn, label, validation_key, "
                                "jsessionid, refresh_token, raw_accesstoken, "
                                "token_expires_at, is_active, created_at) "
                                "VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)",
                                (state["msisdn"], f"JazzDrive {msisdn_display}",
                                 vk, jid, rt or None, raw_at or None,
                                 int(time.time() + expires_offset), int(time.time()))
                            )
                            log.info("Inserted new account for %s", state["msisdn"])
            except Exception as _dbe:
                log.warning("submit_otp: DB accounts sync failed: %s", _dbe)
            # ── Sync back to v2 config ────────────────────────────────────────────
            if rf:
                try:
                    cfg = rf.load_config()
                    cfg["msisdn"] = state["msisdn"]
                    cfg["validationkey"] = vk
                    cfg["jsessionid"] = jid
                    rf.save_config(cfg)
                except Exception:
                    pass
            log.info("JazzDrive: account %s successfully logged in — session is active and ready", state["msisdn"])
            return {"ok": True, "message": "JazzDrive connected successfully!"}
        except Exception as e:
            _sub_last_err = e
            _sub_err_s = str(e).lower()
            log.error("submit_otp error: %s", e)
            return {"ok": False, "error": str(e)}

    log.error("submit_otp: all proxies exhausted: %s", _sub_last_err)
    return {"ok": False, "error": str(_sub_last_err)}


def save_tokens_direct(validation_key: str, jsessionid: str,
                       msisdn: str | None = None,
                       refresh_token: str = "",
                       raw_accesstoken: str = "") -> dict:
    """Persist JazzDrive tokens directly (no OTP needed).

    Use this when you can copy the ``validationkey`` and ``JSESSIONID``
    from your browser's DevTools / Network tab after logging in on
    https://cloud.jazzdrive.com.pk on your phone.
    Optionally pass ``refresh_token`` or ``raw_accesstoken`` for auto-renewal.
    """
    vk  = (validation_key or "").strip()
    jid = (jsessionid or "").strip()
    rt  = (refresh_token or "").strip()
    rat = (raw_accesstoken or "").strip()
    
    if not vk or not jid:
        return {"ok": False, "error": "Both validation_key and jsessionid are required"}

    if not msisdn:
        msisdn = db.setting("JAZZDRIVE_MSISDN") or ""
    
    msisdn = db.normalize_msisdn(msisdn)
    if not msisdn:
        return {"ok": False, "error": "MSISDN is required"}

    # Initial setup gets 1000 days if we have refresh capability, else 30 days
    expires_offset = 86400 * 1000 if (rt or rat) else 86400 * 30

    # Write session JSON file
    save_data = {
        "validationkey": vk,
        "jsessionid":    jid,
        "refresh_token": rt,
        "raw_accesstoken": rat,
        "msisdn":        msisdn,
        "created_at":    time.time(),
        "expires_at":    time.time() + expires_offset,
    }
    _save_session(save_data)

    # Sync to accounts DB table
    try:
        with _lock:
            with db.conn() as _c:
                existing = _c.execute(
                    "SELECT id FROM accounts WHERE msisdn=? LIMIT 1", (msisdn,)
                ).fetchone()
                if existing:
                    _c.execute(
                        "UPDATE accounts SET validation_key=?, jsessionid=?, "
                        "refresh_token=?, raw_accesstoken=?, token_expires_at=?, last_scan_at=? WHERE id=?",
                        (vk, jid, rt or None, rat or None,
                         int(time.time() + expires_offset), int(time.time()), existing["id"])
                    )
                    log.info("save_tokens_direct: updated account id=%s", existing["id"])
                else:
                    _c.execute(
                        "INSERT INTO accounts (msisdn, label, validation_key, jsessionid, "
                        "refresh_token, raw_accesstoken, token_expires_at, is_active, created_at) VALUES (?,?,?,?,?,?,?,1,?)",
                        (msisdn, f"JazzDrive {msisdn}", vk, jid, rt or None, rat or None,
                         int(time.time() + expires_offset), int(time.time()))
                    )
                    log.info("save_tokens_direct: inserted new account for %s", msisdn)
    except Exception as e:
        log.warning("save_tokens_direct DB error: %s", e)
        return {"ok": False, "error": f"Tokens saved to file but DB update failed: {e}"}

    log.info("JazzDrive tokens saved directly for %s (refresh=%s, raw_at=%s)", 
             msisdn, bool(rt), bool(rat))
    return {"ok": True, "message": "JazzDrive tokens saved. Session is now active."}


def import_full_json(data_json: str) -> dict:
    """Parse the full JSON response from /sapi/login/oauth and save it.
    This is the safest way to ensure an infinite session.
    """
    try:
        data = json.loads(data_json)
        if "data" in data:
            data = data["data"]
            
        vk = data.get("validationkey") or data.get("validation_key")
        jid = data.get("jsessionid") or data.get("JSESSIONID")
        msisdn = data.get("msisdn")
        
        # Extract raw_at and rt from the base64 access_token field
        at_b64 = data.get("access_token") or ""
        raw_at = ""
        rt = ""
        
        if at_b64:
            try:
                import base64 as _b64
                _padding = "=" * ((4 - len(at_b64) % 4) % 4)
                decoded = json.loads(_b64.b64decode(at_b64 + _padding).decode())
                inner = decoded.get("data", {})
                raw_at = inner.get("accesstoken") or ""
                rt = inner.get("refreshtoken") or ""
            except Exception:
                # If not b64 JSON, might be raw hex
                import re
                if re.match(r'^[0-9a-f]{40}$', at_b64, re.I):
                    raw_at = at_b64
        
        if not msisdn:
            msisdn = db.setting("JAZZDRIVE_MSISDN")

        if not vk or not jid or not msisdn:
            return {"ok": False, "error": "JSON missing required fields (validationkey, jsessionid, msisdn)"}
            
        return save_tokens_direct(vk, jid, msisdn=msisdn, refresh_token=rt, raw_accesstoken=raw_at)
        
    except Exception as e:
        return {"ok": False, "error": f"Failed to parse JSON: {e}"}


# ---------------------------------------------------------------------------
# Android OAuth2 session refresh  (truly indefinite — months without OTP)
# ---------------------------------------------------------------------------

def android_refresh_session(refresh_token: str,
                             account_id: Optional[int] = None,
                             acct: Optional[dict] = None) -> dict:
    """Exchange an Android refresh_token for a fresh JSESSIONID without OTP.

    Flow:
      1. POST /oauth2/refresh_token.php  (client_id=fnbroot, client_secret=f&rW23)
         → {access_token, refresh_token, expires_in}
      2. Decode the access_token (base64 JSON) to get raw_accesstoken.
      3. POST that raw_accesstoken to /sapi/login/oauth?keytype=accesstoken
         → fresh validationkey + JSESSIONID.
      4. Persist new tokens to DB + session file.

    The Android refresh_token issued by the fnbroot OAuth client lasts months;
    this is how the Jazz Drive Android app stays logged in indefinitely.

    Returns {"ok": True, ...} on success, {"ok": False, "error": ...} otherwise.
    """
    if not refresh_token:
        return {"ok": False, "error": "No Android refresh_token provided"}

    # ── Per-account serialisation lock ────────────────────────────────────────
    # Acquire before any network I/O so a second concurrent caller for the same
    # account waits here instead of racing to POST the same refresh_token twice.
    _acct_lock = _get_refresh_lock(account_id) if account_id is not None else None
    if _acct_lock is not None:
        log.debug("android_refresh_session: acquiring per-account lock acct=%s", account_id)
        _acct_lock.acquire()
        log.debug("android_refresh_session: lock acquired acct=%s", account_id)
        # Re-read the stored refresh_token.  If another thread already completed
        # a refresh while we were waiting, the DB token will differ from the one
        # our caller read before queuing — short-circuit without a second exchange.
        try:
            with db.conn() as _pre:
                _prow = _pre.execute(
                    "SELECT refresh_token, raw_accesstoken, validation_key, jsessionid "
                    "FROM accounts WHERE id=?",
                    (account_id,),
                ).fetchone()
            if (
                _prow
                and (_prow["refresh_token"] or "").strip()
                and (_prow["refresh_token"] or "").strip() != refresh_token.strip()
            ):
                log.info(
                    "android_refresh_session: acct=%s token already rotated by a "
                    "concurrent refresh — returning cached tokens (no network call)",
                    account_id,
                )
                _acct_lock.release()
                return {
                    "ok":             True,
                    "validation_key": (_prow["validation_key"] or ""),
                    "jsessionid":     (_prow["jsessionid"] or ""),
                    "message":        "Session already refreshed by concurrent request (no-op)",
                }
        except Exception as _pre_err:
            log.debug("android_refresh_session: pre-check DB read failed: %s", _pre_err)

    # ── Cooldown guard ──────────────────────────────────────────────────────
    # If a successful refresh happened within _REFRESH_COOLDOWN_S seconds ago,
    # skip the exchange entirely and return the current DB tokens.  This stops
    # sapi_request's internal retry loop from burning token A→B→C→invalid_grant.
    if account_id is not None:
        with _last_refresh_lock:
            _last_ok = _last_refresh_success.get(account_id, 0.0)
        _age = time.time() - _last_ok
        if _age < _REFRESH_COOLDOWN_S:
            log.info(
                "android_refresh_session: acct=%s cooldown active (%.0fs ago) "
                "— returning current DB tokens without exchange",
                account_id, _age,
            )
            if _acct_lock is not None:
                _acct_lock.release()
            try:
                with db.conn() as _cd:
                    _cr = _cd.execute(
                        "SELECT validation_key, jsessionid FROM accounts WHERE id=?",
                        (account_id,)
                    ).fetchone()
                if _cr:
                    return {
                        "ok":             True,
                        "validation_key": (_cr["validation_key"] or ""),
                        "jsessionid":     (_cr["jsessionid"] or ""),
                        "message":        "Cooldown active — no exchange needed",
                    }
            except Exception:
                pass
            return {"ok": True, "message": "Cooldown active — no exchange needed"}

    try:
        return _android_refresh_session_inner(
            refresh_token=refresh_token,
            account_id=account_id,
            acct=acct,
        )
    finally:
        if _acct_lock is not None:
            _acct_lock.release()
            log.debug("android_refresh_session: lock released acct=%s", account_id)


def _android_refresh_session_inner(refresh_token: str,
                                    account_id: Optional[int],
                                    acct: Optional[dict]) -> dict:
    """Inner implementation — called only while the per-account lock is held."""
    import requests as _req
    import base64 as _b64
    import urllib.parse as _up

    require_wg0()  # Hard-fail if wg0 down — never leak OAuth2/SAPI via Oracle direct IP
    log.info("android_refresh_session: exchanging refresh_token (acct=%s)...", account_id)

    # ── Step 1: POST to /oauth2/refresh_token.php ─────────────────────────────
    # NOTE: jazzdrive.com.pk has an SSL hostname mismatch (cert issued for a
    # subdomain, not the bare domain). We suppress verification only for this
    # one internal call — all cloud.jazzdrive.com.pk calls remain verified.
    #
    # Build proxy chain (OTP/OAuth2 domain — jazzdrive.com.pk).
    # Same retry pattern as trigger_otp_flow / submit_otp: primary first,
    # Always direct — VPN (wg0) routes jazzdrive.com.pk at OS level.
    _ar_chain: list = [None]

    # sapi_proxies always None — wg0 VPN routes cloud.jazzdrive.com.pk at OS level.
    sapi_proxies = None

    import urllib3 as _urllib3
    _urllib3.disable_warnings(_urllib3.exceptions.InsecureRequestWarning)

    r = None
    _ar_last_err: Exception = Exception("No proxies available")
    for _ar_px in _ar_chain:
        try:
            r = _req.post(
                "https://jazzdrive.com.pk/oauth2/refresh_token.php",
                data={
                    "grant_type":    "refresh_token",
                    "client_id":     ANDROID_CLIENT_ID,
                    "client_secret": ANDROID_CLIENT_SECRET,
                    "refresh_token": refresh_token,
                },
                timeout=25,
                proxies=_ar_px,
                verify=False,
            )
            break  # connected — exit retry loop
        except Exception as _ar_e:
            _ar_last_err = _ar_e
            log.warning("android_refresh_session: OAuth2 refresh failed: %s", str(_ar_e)[:80])
            continue

    if r is None:
        return {"ok": False,
                "error": f"Network error on OAuth2 refresh (all proxies exhausted): {_ar_last_err}"}

    if r.status_code != 200:
        err_body = r.text[:200]
        log.warning("android_refresh_session: HTTP %d — %s", r.status_code, err_body)
        return {"ok": False,
                "error": f"OAuth2 refresh HTTP {r.status_code}: {err_body}"}

    try:
        resp = r.json()
    except Exception:
        return {"ok": False, "error": f"Non-JSON from refresh endpoint: {r.text[:200]}"}

    if resp.get("error"):
        return {"ok": False,
                "error": f"OAuth2 error: {resp['error']} — {resp.get('error_description', '')}"}

    at_raw   = resp.get("access_token", "")  # may be b64-JSON or raw hex
    new_rt   = resp.get("refresh_token") or refresh_token

    # ── Decode access_token if it's base64 JSON ───────────────────────────────
    raw_at = at_raw
    try:
        _pad = "=" * ((4 - len(at_raw) % 4) % 4)
        _dec = json.loads(_b64.b64decode(at_raw + _pad).decode())
        _inner = _dec.get("data", {})
        if _inner.get("accesstoken"):
            raw_at = _inner["accesstoken"]
            if not new_rt and _inner.get("refreshtoken"):
                new_rt = _inner["refreshtoken"]
    except Exception:
        pass  # use access_token as-is

    # ── Persist refreshed tokens early (before SAPI step that may be geo-blocked) ─
    # JazzDrive refresh_token.php rotates the token on each call.  If we wait until
    # after the SAPI login to persist, a geo-blocked SAPI step will discard the new
    # token and break the rotation chain.  Save new_rt + raw_at now so the chain
    # is never lost even if Step 2 fails.
    if account_id is not None and new_rt and new_rt != refresh_token:
        try:
            with _lock:
                with db.conn() as _c:
                    _c.execute(
                        "UPDATE accounts SET raw_accesstoken=?, refresh_token=? WHERE id=?",
                        (raw_at, new_rt, account_id),
                    )
            log.info(
                "android_refresh_session: persisted rotated refresh_token early (acct=%s)",
                account_id,
            )
            # Crash-safe backup: write to emergency file OUTSIDE the DB transaction
            # so even if the DB is corrupted/restored, the token survives
            _save_emergency_token(account_id, new_rt, raw_at or "")
        except Exception as _early_save_err:
            log.debug("android_refresh_session: early token save failed: %s", _early_save_err)

    # ── Step 2: Re-login via raw_accesstoken to get fresh JSESSIONID ──────────
    _CLOUD = "https://cloud.jazzdrive.com.pk"
    _msisdn_for_dev = ""
    if acct:
        _msisdn_for_dev = str(acct.get("msisdn") or "")
    if not _msisdn_for_dev and account_id is not None:
        try:
            with db.conn() as _dbc:
                _row = _dbc.execute("SELECT msisdn FROM accounts WHERE id=?",
                                    (account_id,)).fetchone()
                if _row:
                    _msisdn_for_dev = str(_row["msisdn"] or "")
        except Exception:
            pass
    if not _msisdn_for_dev:
        _msisdn_for_dev = str(db.setting("JAZZDRIVE_MSISDN") or "")

    _UA_ANDROID = "Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016)"
    sess = _req.Session()
    device_id = get_x_deviceid(_msisdn_for_dev)
    sess.headers.update({
        "Accept":           "application/json, text/plain, */*",
        "User-Agent":       _UA_ANDROID,
        "X-deviceid":       device_id,
        "X-Requested-With": "com.jazz.drive",
    })
    
    at_json_1    = json.dumps({"data": {"accesstoken": raw_at}})
    at_json_2    = json.dumps({"accesstoken": raw_at})
    at_b64_1     = _up.quote(_b64.b64encode(at_json_1.encode()).decode(), safe='')
    at_b64_2     = _up.quote(_b64.b64encode(at_json_2.encode()).decode(), safe='')
    
    # Android-only: consistent with Android User-Agent / X-Requested-With headers.
    # Web variants removed — platform=web with Android headers is a mismatch
    # Jazz security systems can flag as suspicious (credential stuffing).
    # Max 2 attempts: Android-Nested first (real app format), Android-Flat only
    # if server returns HTTP 5xx (Jazz server glitch). 401/403 stops immediately.
    candidates = [
        (f"{_CLOUD}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64_1}", "Android-Nested"),
        (f"{_CLOUD}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64_2}", "Android-Flat"),
    ]
    
    # Always direct — wg0 routes cloud.jazzdrive.com.pk at OS level.
    _s2_chain: list = [None]

    last_err = "No candidates tried"
    sr = None
    _s2_auth_failed = False  # 401/403 = token invalid; stop all retries immediately
    for _s2_px in _s2_chain:
        if _s2_auth_failed:
            break
        _s2_conn_errs = 0
        for url, label in candidates:
            try:
                log.info("android_refresh_session: trying %s @ %s", label, url[:100])
                sr = sess.get(url, timeout=30, proxies=_s2_px)
                if sr.status_code == 200:
                    log.info("✓ %s login succeeded", label)
                    break
                last_err = f"[{label}] HTTP {sr.status_code}: {sr.text[:200]}"
                if sr.status_code in (401, 403):
                    log.debug("android_refresh_session: %s auth error — token invalid, no more retries", label)
                    _s2_auth_failed = True
                    sr = None
                    break  # token bad — Android-Flat won't help either
                log.debug("android_refresh_session: %s failed (HTTP 5xx) — trying next format", label)
            except Exception as _se:
                last_err = str(_se)
                _s2_conn_errs += 1
                log.debug("android_refresh_session: %s network error: %s", label, last_err)
        if sr and sr.status_code == 200:
            break  # success — stop trying proxies
        if _s2_auth_failed:
            break
        if _s2_conn_errs == len(candidates):
            log.warning("android_refresh_session: all SAPI URL formats failed with connection errors")
        sr = None  # reset for next proxy

    if not sr or sr.status_code != 200:
        return {"ok": False, "error": f"SAPI re-login failed: {last_err}"}

    try:
        sbody = sr.json()
        sdata = sbody.get("data", sbody) if isinstance(sbody, dict) else sbody
        new_vk  = (sdata.get("validationkey") or sdata.get("validation_key")
                   or sdata.get("ValidationKey") or "")
        new_jid = (sdata.get("jsessionid") or sdata.get("JSESSIONID")
                   or sr.cookies.get("JSESSIONID", "") or "")
        # Refresh raw_at from SAPI response if available
        _new_at_b64 = sdata.get("access_token") or ""
        if _new_at_b64:
            try:
                _pad2 = "==" if len(_new_at_b64) % 4 else ""
                _d2 = json.loads(_b64.b64decode(_new_at_b64 + _pad2).decode())
                _i2 = _d2.get("data", {})
                if _i2.get("accesstoken"):
                    raw_at = _i2["accesstoken"]
                if not new_rt and _i2.get("refreshtoken"):
                    new_rt = _i2["refreshtoken"]
            except Exception:
                pass
    except Exception as _pe:
        return {"ok": False, "error": f"Could not parse SAPI re-login response: {_pe}"}

    if not new_jid:
        return {"ok": False,
                "error": "Android OAuth2 refresh: SAPI returned 200 but no JSESSIONID"}

    # With a refresh_token we can silently renew for months — set 30-day window.
    expires_offset = 86400 * 30 if new_rt else 3300

    # ── Persist new tokens ────────────────────────────────────────────────────
    if acct is None and account_id is not None:
        try:
            with db.conn() as _c:
                row = _c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
                acct = dict(row) if row else None
        except Exception:
            pass

    if acct and acct.get("id") is not None:
        with _lock:
            with db.conn() as _c:
                _c.execute(
                    "UPDATE accounts SET validation_key=?, jsessionid=?, "
                    "raw_accesstoken=?, refresh_token=?, token_expires_at=? WHERE id=?",
                    (new_vk, new_jid, raw_at, new_rt,
                     int(time.time() + expires_offset), acct["id"])
                )
        log.info("android_refresh_session: DB updated account id=%s rt_rotated=%s",
                 acct["id"], new_rt != refresh_token)
    # Record successful refresh — cooldown window starts now
    if account_id is not None:
        with _last_refresh_lock:
            _last_refresh_success[account_id] = time.time()
        log.info("android_refresh_session: acct=%s cooldown started (%ds)",
                 account_id, _REFRESH_COOLDOWN_S)

    old_sess = _load_session()
    old_sess.update({
        "validationkey":   new_vk,
        "jsessionid":      new_jid,
        "raw_accesstoken": raw_at,
        "refresh_token":   new_rt,
        "created_at":      time.time(),
        "expires_at":      time.time() + expires_offset,
    })
    _save_session(old_sess)

    log.info("android_refresh_session: OK for acct=%s (new_jid=%s rt_rotated=%s)",
             account_id, bool(new_jid), new_rt != refresh_token)
    return {"ok": True, "validation_key": new_vk, "jsessionid": new_jid,
            "message": "Android OAuth2 session refreshed (no OTP required)"}


# ---------------------------------------------------------------------------
# Token refresh  (web fallback — used when Android refresh_token not available)
# ---------------------------------------------------------------------------

def refresh_session(account_id: Optional[int] = None) -> dict:
    """Silently obtain a fresh JSESSIONID + validationKey without OTP.

    Tries in order:
      1. Android OAuth2 refresh_token  →  POST /oauth2/refresh_token.php with
         client_id=fnbroot / client_secret=f&rW23.  This gives months-long
         sessions exactly like the Jazz Drive Android app.
      2. Web raw_accesstoken fallback  →  GET /sapi/login/oauth?keytype=accesstoken
         (verified 2026-05-07; works ~1 h between refreshes).

    Returns {"ok": True, ...} on success, {"ok": False, "error": ...} otherwise.
    """
    import requests as _req
    import urllib.parse as _up
    import base64 as _b64

    # ── Resolve account ────────────────────────────────────────────────────────
    acct = None
    if account_id is not None:
        try:
            with db.conn() as _c:
                row = _c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
                acct = dict(row) if row else None
        except Exception as e:
            return {"ok": False, "error": f"DB error: {e}"}
    else:
        s = _load_session()
        if s:
            acct = {
                "id":              None,
                "msisdn":          s.get("msisdn", ""),
                "refresh_token":   s.get("refresh_token", ""),
                "raw_accesstoken": s.get("raw_accesstoken", ""),
                "validation_key":  s.get("validationkey", ""),
                "jsessionid":      s.get("jsessionid", ""),
            }

    if not acct:
        return {"ok": False, "error": "No account found"}

    raw_at    = (acct.get("raw_accesstoken") or "").strip()
    vk_stored = (acct.get("validation_key") or acct.get("validationkey") or "").strip()
    stored_rt = (acct.get("refresh_token") or "").strip()

    # BUG FIX: DB may have raw_accesstoken=NULL even though the session file has it
    # (happens when submit_otp saved to file but DB update partially failed).
    # Always cross-check the session file when DB values are missing.
    if not raw_at or not stored_rt:
        _sf = _load_session()
        if not raw_at:
            raw_at = (_sf.get("raw_accesstoken") or "").strip()
            if raw_at:
                log.info("refresh_session: raw_accesstoken found in session file (DB was NULL)")
        if not stored_rt:
            stored_rt = (_sf.get("refresh_token") or "").strip()
            if stored_rt:
                log.info("refresh_session: refresh_token found in session file (DB was NULL)")

    # ── Strategy 1: Android OAuth2 refresh_token (months-long sessions) ───────
    # Prefer the Android flow whenever a refresh_token is available — it uses
    # POST /oauth2/refresh_token.php with client_id=fnbroot and gives a fresh
    # refresh_token back, enabling indefinite silent renewal just like the app.
    if stored_rt:
        android_result = android_refresh_session(
            refresh_token=stored_rt,
            account_id=acct.get("id"),
            acct=acct,
        )
        if android_result.get("ok"):
            log.info("refresh_session: Android OAuth2 path succeeded for %s",
                     acct.get("msisdn"))
            return android_result
        log.info("refresh_session: Android refresh failed (%s) — trying web fallback",
                 android_result.get("error"))

    # ── Strategy 2: Web raw_accesstoken fallback ──────────────────────────────
    if not raw_at:
        return {
            "ok": False,
            "error": (
                "No raw_accesstoken or refresh_token stored. "
                "Please re-login via OTP once to store the credentials."
            )
        }

    _CLOUD_BASE = "https://cloud.jazzdrive.com.pk"
    sess = _req.Session()
    device_id = get_x_deviceid(acct.get("msisdn"))
    sess.headers.update({
        "Accept":     "application/json, text/javascript, */*",
        "User-Agent": "Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016)",
        "X-deviceid": device_id,
        "X-Requested-With": "com.jazz.drive",
    })

    log.info("Refreshing JazzDrive session for %s via raw_accesstoken ...", acct.get("msisdn"))

    # Resolve Proxy — SAPI endpoint; use dedicated SAPI proxy slot
    proxies = resolve_proxies(purpose='sapi')

    at_json_1  = json.dumps({"data": {"accesstoken": raw_at}})
    at_json_2  = json.dumps({"accesstoken": raw_at})
    at_b64_1   = _up.quote(_b64.b64encode(at_json_1.encode()).decode(), safe='')
    at_b64_2   = _up.quote(_b64.b64encode(at_json_2.encode()).decode(), safe='')
    
    # We try multiple candidates to avoid HTTP 500
    # Android-only: consistent with Android User-Agent / X-Requested-With headers.
    # Web variants removed — platform=web with Android headers is a suspicious mismatch.
    # Max 2 attempts: Android-Nested first, Android-Flat only if HTTP 5xx.
    candidates = [
        (f"{_CLOUD_BASE}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64_1}", "Android-Nested"),
        (f"{_CLOUD_BASE}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64_2}", "Android-Flat"),
    ]

    last_err = "No candidates tried"
    r = None
    for url, label in candidates:
        try:
            log.info("refresh_session: trying %s @ %s", label, url[:100])
            r = sess.get(url, timeout=30, proxies=proxies)
            if r.status_code == 200:
                log.info("✓ %s login succeeded", label)
                break
            last_err = f"[{label}] HTTP {r.status_code}: {r.text[:200]}"
            if r.status_code in (401, 403):
                log.debug("refresh_session: %s auth error — token invalid, no more retries", label)
                r = None
                break  # token bad — Android-Flat won't help
            log.debug("refresh_session: %s failed (HTTP 5xx) — trying next format", label)
        except Exception as _e:
            last_err = str(_e)
            log.debug("refresh_session: %s network error: %s", label, last_err)

    if not r or r.status_code != 200:
        return {"ok": False, "error": f"Silent login failed: {last_err}"}

    try:
        body = r.json()
        data = body.get("data", body) if isinstance(body, dict) else body

        new_vk  = (data.get("validationkey") or data.get("validation_key") or vk_stored or "")
        new_jid = (data.get("jsessionid") or data.get("JSESSIONID")
                   or r.cookies.get("JSESSIONID", "") or "")

        # Decode the new access_token to refresh raw_accesstoken too
        new_raw_at = raw_at
        new_at_b64 = data.get("access_token") or ""
        if new_at_b64:
            try:
                _pad = "==" if len(new_at_b64) % 4 else ""
                _dec = json.loads(_b64.b64decode(new_at_b64 + _pad).decode())
                _inner = _dec.get("data", {}).get("accesstoken", "")
                if _inner:
                    new_raw_at = _inner
            except Exception:
                pass

        if not new_jid:
            return {"ok": False, "error": f"Refresh succeeded (200) but response missing jsessionid: {data}"}

        # Keep expires window long — raw_accesstoken is valid until rotated.
        # Fall back to 55 min only if we have no refresh path at all.
        _has_rt = bool((acct.get("refresh_token") or "").strip())
        expires_offset = 86400 * 30 if _has_rt else 3300

        # ── Persist new tokens ─────────────────────────────────────────────────
        if acct.get("id") is not None:
            with _lock:
                with db.conn() as _c:
                    _c.execute(
                        "UPDATE accounts SET validation_key=?, jsessionid=?, "
                        "raw_accesstoken=?, token_expires_at=? WHERE id=?",
                        (new_vk, new_jid, new_raw_at,
                         int(time.time() + expires_offset), acct["id"])
                    )
            log.info("refresh_session: DB updated for account id=%s", acct["id"])

        old_session = _load_session()
        old_session.update({
            "validationkey":   new_vk,
            "jsessionid":      new_jid,
            "raw_accesstoken": new_raw_at,
            "created_at":      time.time(),
            "expires_at":      time.time() + expires_offset,
        })
        _save_session(old_session)

        log.info("JazzDrive session refreshed for %s (new_jsid=%s)", acct.get("msisdn"), bool(new_jid))
        return {"ok": True, "message": "Session refreshed without OTP.",
                "validation_key": new_vk, "jsessionid": new_jid}

    except Exception as e:
        log.error("refresh_session error: %s", e)
        return {"ok": False, "error": str(e)}


def upload_file_to_jazzdrive(file_path: str | Path) -> dict:
    """Upload a file to JazzDrive using the v3 uploader pipeline."""
    from . import uploader as _up
    file_path = Path(file_path)
    if not file_path.exists():
        return {"ok": False, "error": f"File not found: {file_path}"}
    log.info("Uploading %s to JazzDrive via v3 uploader...", file_path.name)
    try:
        result = _up.upload_to_jazzdrive(file_path)
        return result
    except Exception as e:
        log.error("upload_file_to_jazzdrive error: %s", e)
        return {"ok": False, "error": str(e)}


def generate_folder_image_link(folder_share_url: str, filename_hint: str = "poster") -> dict:
    """Fetch a direct download URL for a poster/image file inside a shared JazzDrive folder.

    Each JazzDrive folder typically contains a poster.jpg alongside the video.
    This function logs in to the folder share and calls the image media endpoint
    to return a time-limited direct URL to that image.

    Returns: {"ok": True, "url": "...", "filename": "...", "expires_at": ...}
    """
    import requests as _req
    import re as _re
    import urllib.parse

    m = _re.search(r"/(?:share-landing/f|share/f|f)/([^/?#]+)", folder_share_url)
    if not m:
        return {"ok": False, "error": "Invalid folder share URL"}

    share_key = m.group(1)
    proxies = resolve_proxies(purpose="sapi")
    base_headers = {
        "Accept": "application/json, text/plain, */*",
        "Origin": CLOUD_BASE,
        "Referer": f"{CLOUD_BASE}/share/f/{share_key}",
        "User-Agent": "Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
        "X-Requested-With": "com.jazz.drive",
    }

    try:
        sess = _req.Session()

        # 1. Login to share
        r1 = sess.post(
            f"{CLOUD_BASE}/sapi/link/login?action=login",
            json={"data": {"accesstoken": share_key}},
            headers=base_headers, timeout=20, proxies=proxies,
        )
        if r1.status_code != 200:
            return {"ok": False, "error": f"Login failed: {r1.status_code}"}
        d = r1.json()
        d = d.get("data", d)
        vk = d.get("validationkey") or d.get("validation_key")
        if not vk:
            return {"ok": False, "error": "No validation key in login response"}

        # 2. Fetch image media list
        img_url = (
            f"{CLOUD_BASE}/sapi/media/image?action=get"
            f"&shared=true&key={share_key}&validationkey={vk}"
        )
        r2 = sess.get(img_url, headers={**base_headers, "validation_key": vk},
                      timeout=20, proxies=proxies)

        records: list = []
        if r2.status_code == 200:
            try:
                res = r2.json().get("data") or r2.json()
                if isinstance(res, list):
                    records = res
                elif isinstance(res, dict):
                    for k in ("list", "items", "images", "result"):
                        if isinstance(res.get(k), list):
                            records = res[k]
                            break
            except Exception:
                pass

        if not records:
            return {"ok": False, "error": "No images found in folder"}

        # 3. Pick the best match (poster.jpg / cover.jpg by hint)
        match = None
        hint_lower = filename_hint.lower()
        for rec in records:
            name = (rec.get("name") or rec.get("filename") or "").lower()
            if hint_lower in name:
                match = rec
                break
        if not match:
            match = records[0]

        name = match.get("name") or match.get("filename") or "poster.jpg"

        def _abs(u: str) -> str:
            return (CLOUD_BASE + u) if u.startswith("/") else u

        raw_url = _abs(
            match.get("downloadUrl") or match.get("download_url") or match.get("url") or ""
        )
        if not raw_url:
            return {"ok": False, "error": "No URL in image record"}

        sep = "&" if "?" in raw_url else "?"
        final_url = (
            f"{raw_url}{sep}filename={urllib.parse.quote(name)}"
            if "filename=" not in raw_url else raw_url
        )

        return {
            "ok": True,
            "url": final_url,
            "filename": name,
            "expires_at": int(time.time() + 28800),
        }

    except Exception as e:
        log.error("generate_folder_image_link error: %s", e)
        return {"ok": False, "error": str(e)}


def generate_direct_link(share_url: str, target_filename: str = "", remote_id: int = 0) -> dict:
    """Port of bots/whatsapp/direct_link_generator.js to Python.
    Generates a time-limited direct download/stream URL from a share URL.
    """
    import requests
    import re
    import urllib.parse
    
    # 1. Extract Share Key
    m = re.search(r"/(?:share-landing/f|share/f|f)/([^/?#]+)", share_url)
    if not m:
        return {"ok": False, "error": "Invalid share URL"}
    
    share_key = m.group(1)
    proxies = resolve_proxies(purpose="sapi")
    
    base_headers = {
        "Accept": "application/json, text/plain, */*",
        "Origin": CLOUD_BASE,
        "Referer": f"{CLOUD_BASE}/share/f/{share_key}",
        "User-Agent": "Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
        "X-Requested-With": "com.jazz.drive"
    }

    try:
        sess = requests.Session()
        # 2. Login to the share
        login_url = f"{CLOUD_BASE}/sapi/link/login?action=login"
        login_data = {"data": {"accesstoken": share_key}}
        
        r1 = sess.post(login_url, json=login_data, headers=base_headers, timeout=20, proxies=proxies)
        if r1.status_code != 200:
            return {"ok": False, "error": f"Login failed: {r1.status_code}"}
        
        data1 = r1.json()
        d = data1.get("data", data1)
        vk = d.get("validationkey") or d.get("validation_key")
        if not vk:
            return {"ok": False, "error": "No validation key in login response"}
        
        # 3. Get Media List
        # Note: shared=true is critical here
        media_url = f"{CLOUD_BASE}/sapi/media/video?action=get&shared=true&key={share_key}&validationkey={vk}"
        r2 = sess.get(media_url, headers={**base_headers, "validation_key": vk}, timeout=20, proxies=proxies)
        
        if r2.status_code != 200:
            return {"ok": False, "error": f"Media fetch failed: {r2.status_code}"}
        
        data2 = r2.json()
        records = []
        res = data2.get("data") or data2
        if isinstance(res, list): records = res
        elif isinstance(res, dict):
            for k in ("list", "items", "videos", "result"):
                if isinstance(res.get(k), list):
                    records = res[k]
                    break
        
        if not records:
            return {"ok": False, "error": "No videos found in share"}
        
        # 4. Find the best match
        # Pass 0: match by remote_id (JazzDrive file ID) — most reliable, filename-independent.
        # Pass 1-3: filename-based fallback (kept for legacy callers without remote_id).
        match = None
        if remote_id:
            for _r in records:
                _rid = _r.get("id") or _r.get("fileId") or _r.get("file_id") or 0
                try:
                    if int(_rid) == int(remote_id):
                        match = _r
                        break
                except (ValueError, TypeError):
                    pass
        if not match and target_filename:
            import re as _re2

            def _norm_fn(s: str) -> str:
                """Normalise: replace dots/underscores/hyphens with spaces, lowercase."""
                return _re2.sub(r'[._\-]+', ' ', s).lower().strip()

            tf_norm = _norm_fn(target_filename)
            # Stem without extension for broader match
            tf_stem = _re2.sub(r'\.[\w]{2,5}$', '', tf_norm).strip()
            # Episode code e.g. s01e04
            ep_m = _re2.search(r's\d{1,2}e\d{1,2}', target_filename, _re2.I)
            ep_code = ep_m.group().lower() if ep_m else ""

            # Pass 1: exact substring (clean name on JazzDrive — the common case)
            for r in records:
                name = r.get("name") or r.get("filename") or ""
                if target_filename.lower() in name.lower():
                    match = r
                    break

            # Pass 2: normalised match (handles scene-release dirty names with dots vs spaces)
            if not match:
                for r in records:
                    name = r.get("name") or r.get("filename") or ""
                    n_norm = _norm_fn(name)
                    if tf_stem and tf_stem in n_norm:
                        match = r
                        break

            # Pass 3: episode-code match — S01E04 anywhere in the filename (most robust)
            if not match and ep_code:
                for r in records:
                    name = r.get("name") or r.get("filename") or ""
                    if ep_code in _norm_fn(name):
                        match = r
                        break

        if not match:
            match = records[0]
            
        # 5. Build final URLs
        # downloadUrl / download_url → original MKV (best quality, aria2 downloads)
        # url → transcoded stream (HLS/MP4, browser-compatible)
        raw_download = match.get("downloadUrl") or match.get("download_url") or ""
        raw_stream   = match.get("url") or ""

        # Normalise relative paths
        def _abs(u: str) -> str:
            return (CLOUD_BASE + u) if u.startswith("/") else u

        raw_download = _abs(raw_download)
        raw_stream   = _abs(raw_stream)

        final_base = raw_download or raw_stream
        if not final_base:
            return {"ok": False, "error": "No media URL found in record"}

        name = match.get("name") or match.get("filename") or "video.mkv"

        def _add_filename(url: str) -> str:
            if not url:
                return url
            sep = "&" if "?" in url else "?"
            return f"{url}{sep}filename={urllib.parse.quote(name)}" if "filename=" not in url else url

        direct_link = _add_filename(final_base)
        stream_url  = _add_filename(raw_stream) if raw_stream else direct_link

        # Extract poster from thumbnails (zero-rated JazzDrive-hosted image)
        poster_url = ""
        thumbnails = match.get("thumbnails") or []
        if thumbnails:
            turl = (thumbnails[0].get("url") or "")
            if turl:
                poster_url = _abs(turl)

        return {
            "ok": True,
            "direct_link": direct_link,   # original MKV — best for downloads
            "stream_url":  stream_url,    # transcoded — best for browser <video>
            "filename": name,
            "size_bytes": match.get("size") or match.get("filesize") or 0,
            "poster_url": poster_url,
            "vk": vk,
            "expires_at": int(time.time() + 28800),
        }

    except Exception as e:
        log.error("generate_direct_link error: %s", e)
        return {"ok": False, "error": str(e)}

