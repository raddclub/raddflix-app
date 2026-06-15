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
    raw_at = tokens.get("raw_accesstoken")
    rt = tokens.get("refresh_token") or tokens.get("refreshtoken") or ""
    return get_auth_headers(vk, jid, msisdn=msisdn, raw_accesstoken=raw_at, refresh_token=rt)

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

# -- JazzDrive activity log
def _setup_jd_activity_log():
    """Install a [JD:]-filtered RotatingFileHandler on the ROOT logger.
    Must be called AFTER config.setup_logging() so it is not cleared by
    the root.handlers[:] = [h] reset that setup_logging performs.
    """
    import logging.handlers as _lhh
    _root = logging.getLogger()
    # Guard: only add once (marker attribute prevents duplicates)
    if any(getattr(_h, "_jd_activity_marker", False) for _h in _root.handlers):
        return
    try:
        _fh = _lhh.RotatingFileHandler(
            "/opt/jazzmax/jazzdrive_activity.log",
            maxBytes=5*1024*1024, backupCount=5, encoding="utf-8")
        _fh._jd_activity_marker = True
        _fh.setLevel(logging.DEBUG)
        _fh.setFormatter(logging.Formatter("%(asctime)s  %(message)s", "%Y-%m-%d %H:%M:%S"))
        # Filter: only write lines that contain [JD: prefix
        class _JDFilter(logging.Filter):
            def filter(self, r): return "[JD:" in r.getMessage()
        _fh.addFilter(_JDFilter())
        _root.addHandler(_fh)
        logging.getLogger("hub.jazzdrive").setLevel(logging.DEBUG)
    except Exception as _fh_e:
        import sys
        print("[JD-LOG-SETUP] FAILED to attach activity log:", _fh_e, file=sys.stderr)
try:
    _setup_jd_activity_log()
except Exception:
    pass

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

# ── JazzDrive Master Kill Switch ──────────────────────────────────────────────
# When JAZZDRIVE_ENABLED=0 in DB settings, ALL JD network activity must stop —
# no SAPI calls, no OAuth2 refreshes, no uploads, no keepalive pings.
# This is enforced at every network chokepoint via require_jd_active().

class JDDisabled(RuntimeError):
    """Raised when the JazzDrive master kill switch is OFF."""
    pass

def is_jd_enabled() -> bool:
    """Return True if JazzDrive master switch is ON (default: ON)."""
    return db.setting("JAZZDRIVE_ENABLED", "1") == "1"

def require_jd_active():
    """Raise JDDisabled if the master switch is OFF.
    Call this as the very first line of any function that makes a JD network call.
    """
    if not is_jd_enabled():
        raise JDDisabled("JazzDrive master switch is OFF — all JD calls blocked")

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
        log.info("SAPI backoff cleared for account %s — auto-refresh re-enabled", account_id)


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
    log.warning(
        "account %s: SAPI auto-refresh suppressed for 30 min — OTP re-login required. "
        "Open Scan/Upload page and re-activate session via phone.",
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


# ─────────────────────────────────────────────────────────────────────────────
# WG0 VPN enforcement — ALL JazzDrive calls MUST route via wg0
# ─────────────────────────────────────────────────────────────────────────────

class JDVPNRequired(RuntimeError):
    """Raised when wg0 VPN is not routing one or more JazzDrive IPs.

    Used to hard-fail any JazzDrive network call that would otherwise leak
    via Oracle's direct IP — which risks account suspension on Jazz SIM.
    """

_JD_ROUTED_IPS = ["54.179.95.148", "54.254.59.168", "175.41.133.62"]


def require_wg0() -> None:
    """Abort (raise JDVPNRequired) if wg0 is not routing all JazzDrive IPs.

    Called at the start of every function that sends a JazzDrive network
    request so that no call can ever leak via Oracle's direct public IP.
    """
    import subprocess as _sp
    log.debug("[JD:VPN] checking wg0 for IPs: %s", _JD_ROUTED_IPS)
    try:
        out = _sp.check_output(["ip", "route", "show", "dev", "wg0"],
                               text=True, timeout=2)
    except Exception as _e:
        log.error("[JD:VPN] BLOCKED -- wg0 interface error: %s", _e)
        raise JDVPNRequired(
            f"wg0 route check failed — VPN interface may be down: {_e}"
        )
    missing = [ip for ip in _JD_ROUTED_IPS if ip not in out]
    if missing:
        log.error("[JD:VPN] BLOCKED -- wg0 NOT routing IPs: %s", missing)
        raise JDVPNRequired(
            f"wg0 is NOT routing JazzDrive IPs {missing} — "
            "refusing to leak call via Oracle direct IP"
        )
    log.debug("[JD:VPN] OK -- all JD IPs via wg0")


# ─────────────────────────────────────────────────────────────────────────────
# JAZZDRIVE_ENABLED master kill switch
# ─────────────────────────────────────────────────────────────────────────────

class JDDisabled(RuntimeError):
    """Raised when JAZZDRIVE_ENABLED=0 in DB (master kill switch is OFF).

    Any function that makes JazzDrive network calls must call
    require_jd_active() first so it hard-fails immediately instead of
    leaking a request against the Jazz account.
    """


def require_jd_active() -> None:
    """Raise JDDisabled if the master kill switch is OFF (JAZZDRIVE_ENABLED!=1).

    Call this at the top of every function that touches JazzDrive APIs so
    that toggling the switch in the admin Services panel immediately stops
    all JazzDrive activity without a Flask restart.
    """
    val = db.setting("JAZZDRIVE_ENABLED", "1")
    if val != "1":
        log.warning("[JD:MASTER] BLOCKED — JAZZDRIVE_ENABLED=%s, master switch is OFF", val)
        raise JDDisabled(
            "JAZZDRIVE_ENABLED master switch is OFF — all JazzDrive calls blocked. "
            "Enable via Admin > Services to resume."
        )



def resolve_proxies(purpose: str = 'otp') -> Optional[dict]:
    log.debug("[JD:PROXY] resolve_proxies purpose=%s", purpose)
    """Return a requests-compatible proxies dict.

    purpose='sapi' — uses the SAPI proxy POOL (auto-rotating, health-checked).
                     Falls back to JAZZDRIVE_SAPI_PROXY setting if pool empty.
    purpose='otp'  — uses the general JAZZDRIVE_PROXY slot (OTP / refresh_token).
    Always returns None on Replit because proxy traffic violates ToS."""
    require_jd_active()  # Hard-fail if master kill switch is OFF
    require_wg0()  # Hard-fail if wg0 not routing JD IPs
    log.info("[JD:PROXY] VPN enforced OK")
    if _is_replit():
        return None
    # Global proxy bypass — when JAZZDRIVE_PROXY_BYPASS=1 all traffic goes direct.
    # JazzDrive is NOT geo-blocked — it works globally.
    # Oracle's raw IP is banned by JazzDrive, but all calls go through wg0 VPN
    # (which uses a non-banned exit IP). Enable PROXY_BYPASS when you trust wg0.
    # NOTE: SAPI LOGIN (needs non-Oracle-IP path) bypasses this via direct pool access in
    # _android_refresh_session_inner._s2_chain — NOT via resolve_proxies('sapi').
    if db.setting('JAZZDRIVE_PROXY_BYPASS') == '1':
        return None
    if purpose == 'sapi':
        # Try the pool first (auto-rotating, health-checked)
        try:
            from . import proxy_pool as _pp
            px = _pp.pool.get_best()
            if px:
                return px
        except Exception:
            pass
        # Fallback to single-proxy setting
        sapi_url = (db.setting("JAZZDRIVE_SAPI_PROXY") or "").strip()
        if sapi_url:
            return {"http": sapi_url, "https": sapi_url, "_url": sapi_url}
        return None
    # OTP / general proxy — manual setting takes priority
    manual_enabled = db.setting("JAZZDRIVE_PROXY_ENABLED") == "1"
    url = (db.setting("JAZZDRIVE_PROXY") or "").strip()
    if manual_enabled and url:
        # Dead-proxy guard: if this URL was disabled by mark_fail (>= 5 fails),
        # skip it and fall through to the pool rather than hammering the same
        # broken host on every OTP request.
        _manual_alive = True
        try:
            with db.conn() as _rc:
                _pr = _rc.execute(
                    "SELECT is_enabled FROM sapi_proxies WHERE url=?", (url,)
                ).fetchone()
            if _pr is not None and not _pr["is_enabled"]:
                _manual_alive = False
                log.warning(
                    "resolve_proxies(otp): JAZZDRIVE_PROXY '%s' is disabled "
                    "(too many fails) — falling through to pool", url)
        except Exception:
            pass  # pool DB unavailable — trust the manual setting
        if _manual_alive:
            return {"http": url, "https": url, "_url": url}
    # No live manual proxy — fall back to SAPI pool automatically.
    # Fallback to SAPI proxy pool if no manual proxy is configured.
    try:
        from . import proxy_pool as _pp
        px = _pp.pool.get_best()
        if px:
            return px
        # Circuit open (>80% dead) — use the least-dead proxy as a last resort.
        # Direct connection works with the correct Android UA if no proxy is available.
        chain = _pp.pool.get_proxy_chain(n=1)
        if chain:
            log.warning("resolve_proxies(otp): circuit open — using least-dead proxy as OTP fallback")
            return chain[0]
    except Exception:
        pass
    return None



def is_proxy_bypass() -> bool:
    """Return True when JAZZDRIVE_PROXY_BYPASS=1 — all calls go direct, skip pool."""
    return db.setting("JAZZDRIVE_PROXY_BYPASS") == "1"

# ─────────────────────────────────────────────────────────────────────────────
# Auth Helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_x_deviceid(msisdn: Optional[str] = None) -> str:
    """Return the X-deviceid sent in every JazzDrive request.

    Priority:
      1. JAZZDRIVE_DEVICE_ID setting — user's real Android device ID
         (makes server appear as the same device as their phone, bypassing
         JazzDrive's single-active-Android-device limit)
      2. fac-<last-10-of-MSISDN> — original fallback
    """
    stored = (db.setting("JAZZDRIVE_DEVICE_ID") or "").strip()
    if stored:
        return stored
    m = str(msisdn or db.setting("JAZZDRIVE_MSISDN") or "").strip()
    m = m.replace("+", "").replace(" ", "").replace("-", "")
    suffix = m[-10:] if len(m) >= 10 else "raddhub"
    return f"fac-{suffix}"

def get_auth_headers(vk: str, jid: str, msisdn: Optional[str] = None,
                     raw_accesstoken: Optional[str] = None,
                     _request_id: Optional[str] = None,
                     refresh_token: Optional[str] = None) -> dict:
    """Return standard headers for any SAPI/Cloud request.

    Mirrors the 4 OkHttp interceptors in the JazzDrive Android APK exactly:
      1. x-request-id     — new UUID per request  (C30920a AddRequestIdInterceptor)
      2. User-Agent       — "omh android client"   (C30921b AddUserAgentInterceptor)
      3. X-deviceid       — fac-<suffix>           (C30924e DeviceInterceptor)
      4. X-devicename     — device model           (C30924e DeviceInterceptor)
      5. Authorization    — oauth <Base64(JSON_cred)>  (C12815c OAuth2AuthenticatorInterceptor)
       JSON = {"data":{"accesstoken":"","refreshtoken":"","platform":"android","expiresin":"","lastrefreshdate":<ms>,"msisdn":""}})
    """
    import base64 as _b64_ah
    device_name = db.setting("JAZZDRIVE_DEVICE_NAME") or "Infinix Hot 9 Play"
    headers = {
        "Accept":           "application/json, text/plain, */*",
        "User-Agent":       "omh android client",
        "x-request-id":     _request_id or str(_uuid.uuid4()),
        "X-deviceid":       get_x_deviceid(msisdn),
        "X-devicename":     device_name,
        "X-Requested-With": "com.jazz.drive",
    }
    if jid:
        headers["Cookie"] = f"JSESSIONID={jid}"
    if vk:
        headers["validation_key"] = vk
    if raw_accesstoken:
        # APK confirmed (nk/c.java OAuth2Credentials.d()): Authorization header must be
        # oauth <Base64(JSON)> where JSON = {"data":{"accesstoken":"...","refreshtoken":"...",
        # "platform":"android","expiresin":"...","lastrefreshdate":<ms>,"msisdn":"..."}}
        import json as _json_ah
        _cred_obj = {"data": {
            "accesstoken":    raw_accesstoken,
            "refreshtoken":   (refresh_token or ""),
            "platform":       "android",
            "expiresin":      "3600",
            "lastrefreshdate": int(time.time() * 1000),
            "msisdn":         (msisdn or ""),
        }}
        headers["Authorization"] = "oauth " + _b64_ah.b64encode(
            _json_ah.dumps(_cred_obj, separators=(",", ":")).encode()
        ).decode()
    return headers



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

    # ── Master kill switch — blocks ALL JD calls when switch is OFF ──────────
    require_jd_active()

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
    req_params["responsetime"] = "true"
    
    req_headers = get_auth_headers(vk, jid or "", msisdn=tokens.get("msisdn"), raw_accesstoken=tokens.get("raw_accesstoken"), refresh_token=tokens.get("refresh_token") or tokens.get("refreshtoken") or "")
    if not jid:
        req_headers.pop("Cookie", None)
    if headers:
        req_headers.update(headers)

    # 3. Execute request
    _proxy_url = (proxies or {}).get("_url") or (proxies or {}).get("https")
    # Strip private key before passing to requests
    _req_proxies = {k: v for k, v in (proxies or {}).items() if k in ("http", "https")} if proxies else None
    _t0_sapi = time.time() if _proxy_url else None
    try:
        _t0r = time.time()
        r = _req.request(method, url, params=req_params, json=json_data, data=data, headers=req_headers, timeout=timeout, proxies=_req_proxies)
        log.info("[JD:SAPI] RSP  HTTP %d  %.0fms  %s", r.status_code, (time.time()-_t0r)*1000, endpoint.lstrip("/"))

        # 3b. Capture any fresh JSESSIONID issued by the server on SUCCESSFUL responses.
        # Only save on 2xx — a 401 response may carry a guest/unauthenticated JSESSIONID
        # which would break subsequent authenticated calls if saved.
        # Mark proxy success/fail
        if _proxy_url:
            try:
                _elapsed_ms = int((time.time() - _t0_sapi) * 1000) if _t0_sapi else None
                from . import proxy_pool as _pp
                if r.status_code in (200, 400, 401, 403, 500):
                    _pp.pool.mark_success(_proxy_url, _elapsed_ms)
                else:
                    _pp.pool.mark_fail(_proxy_url)
            except Exception:
                pass
        if 200 <= r.status_code < 300:
            new_jid_from_cookie = r.cookies.get("JSESSIONID")
            new_vk_from_header = r.headers.get("X-Funambol-ValidationKey")
            
            needs_update = False
            if new_jid_from_cookie and new_jid_from_cookie != jid:
                log.info("[JD:SAPI] server issued new JSESSIONID -- saving")
                tokens["jsessionid"] = new_jid_from_cookie
                needs_update = True
            
            if new_vk_from_header and new_vk_from_header != vk:
                log.info("[JD:SAPI] server rotated validationkey in header -- saving")
                tokens["validationkey"] = new_vk_from_header
                vk = new_vk_from_header  # update local vk for subsequent logic
                needs_update = True
                
            if needs_update:
                _update_token_storage(account_id, tokens)

        # 4. Handle HTTP 401 (Transparent re-login)
        # Strategy A: refresh_token (Android app flow — months-long sessions)
        # Strategy B: validationKey → fresh JSESSIONID via web re-login endpoint
        if r.status_code == 401 and vk:
            log.info("[JD:SAPI] 401 -- starting session recovery  acct=%s", account_id)

            # Skip costly refresh attempts if account is already in OTP backoff.
            # This prevents uploader/bulk_links/keepalive from hammering JazzDrive
            # with 8 failed API calls every 40 s when the session is dead.
            if _is_sapi_backed_off(account_id):
                log.debug("SAPI 401 — account %s in OTP backoff, skipping refresh", account_id)
                log.warning("SAPI 401 — both strategies failed. OTP re-login required.")
            else:
                # Strategy A: use refresh_token (Android approach)
                try:
                    refresh_result = refresh_session(account_id)
                    if refresh_result.get("ok"):
                        log.info("[JD:SAPI] strategy A (refresh_token) succeeded -- retrying")
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

                log.error("[JD:SAPI] 401 recovery FAILED — Android refresh exhausted  acct=%s", account_id)
                log.error("[JD:SAPI] OTP re-login required")
                _mark_sapi_backed_off(account_id)

        # 5. Handle JSON responses
        try:
            resp_data = r.json()
        except Exception:
            if 200 <= r.status_code < 300:
                return {"ok": True, "text": r.text[:1000]}
            return {"error": {"code": "HTTP-" + str(r.status_code), "message": r.text[:200]}}

        # 5b. Update validationkey from response body (AbstractC12813a.m51847w).
        # The real Android app reads data.validationkey from EVERY SAPI response
        # and stores the latest — this keeps the session alive indefinitely.
        if isinstance(resp_data, dict) and 200 <= r.status_code < 300:
            _resp_d = resp_data.get("data", {})
            if isinstance(_resp_d, dict):
                _new_vk_body = (_resp_d.get("validationkey") or _resp_d.get("validation_key"))
                if _new_vk_body and _new_vk_body != vk:
                    log.debug("sapi_request: validationkey refreshed from response body")
                    tokens["validationkey"] = _new_vk_body
                    vk = _new_vk_body
                    _update_token_storage(account_id, tokens)

        # 6. Handle SEC-1003 (Rolling Key Rotation)
        err = resp_data.get("error")
        if isinstance(err, dict) and err.get("code") == "SEC-1003":
            new_vk = err.get("data") or err.get("validationkey")
            if new_vk:
                log.info("[JD:SAPI] SEC-1003 -- validationKey rotated by server, retrying")
                tokens["validationkey"] = new_vk
                # Also capture a fresh JSESSIONID the server may have included
                sec_jid = r.cookies.get("JSESSIONID")
                if sec_jid:
                    tokens["jsessionid"] = sec_jid
                _update_token_storage(account_id, tokens)
                return sapi_request(endpoint, action, method, params, json_data, data, headers, account_id, tokens, timeout, _retry_count + 1)

        return resp_data

    except Exception as e:
        log.error("sapi_request exception: %s", e)
        if _proxy_url:
            try:
                from . import proxy_pool as _pp
                _pp.pool.mark_fail(_proxy_url)
            except Exception:
                pass
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



def jd_clear_cookies(account_id: int) -> dict:
    """Clear only the JazzDrive session cookies (JSESSIONID + validationkey) for an account.

    Unlike jd_logout_account(), this keeps:
      - refresh_token  (so the app can silently obtain a new session via OTP-free refresh)
      - raw_accesstoken
      - token_expires_at
      - is_active = 1

    Use this when you want to flush a stale/dead browser session without losing the
    long-lived refresh_token.  After clearing, the keepalive will attempt a silent
    refresh on its next cycle.  If the refresh_token is also dead the user will be
    prompted to re-login with OTP.
    """
    log.info("[JD:CLEAR-COOKIES] account_id=%s", account_id)

    # 1. Read current account
    try:
        with db.conn() as _c:
            row = _c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
            row = dict(row) if row else None
    except Exception as _e:
        return {"ok": False, "error": f"DB read error: {_e}"}

    if not row:
        return {"ok": False, "error": f"Account {account_id} not found"}

    msisdn = row.get("msisdn", "")
    had_vk  = bool((row.get("validation_key") or "").strip())
    had_jid = bool((row.get("jsessionid") or "").strip())
    has_rt  = bool((row.get("refresh_token") or "").strip())

    # 2. Wipe only session cookies — keep refresh_token, raw_accesstoken, is_active
    try:
        with db.conn() as _c:
            _c.execute(
                "UPDATE accounts SET validation_key=NULL, jsessionid=NULL, node=NULL "
                "WHERE id=?",
                (account_id,)
            )
        log.info(
            "[JD:CLEAR-COOKIES] session cookies wiped for account %s (%s) "
            "— had_vk=%s had_jid=%s has_rt=%s",
            account_id, msisdn, had_vk, had_jid, has_rt,
        )
    except Exception as _de:
        return {"ok": False, "error": f"DB error: {_de}"}

    # 3. Also wipe validationkey + jsessionid from jazzdrive_session.json,
    #    but preserve refresh_token and raw_accesstoken so silent refresh works.
    try:
        if SESSION_FILE.exists():
            import json as _sj
            sess_data = _sj.loads(SESSION_FILE.read_text())
            if str(sess_data.get("msisdn") or "").replace("+92", "0") == str(msisdn).replace("+92", "0"):
                sess_data["validationkey"] = ""
                sess_data["jsessionid"]    = ""
                sess_data["node"]          = ""
                SESSION_FILE.write_text(_sj.dumps(sess_data, indent=2))
                log.info("[JD:CLEAR-COOKIES] jazzdrive_session.json cookies cleared")
    except Exception as _sf:
        log.debug("[JD:CLEAR-COOKIES] session file update skipped: %s", _sf)

    # 4. Clear in-memory SAPI backoff so the next keepalive/refresh attempt is immediate
    try:
        clear_sapi_backoff(account_id)
    except Exception:
        pass

    # 5. Clear upload refresh backoff
    try:
        from . import uploader as _up
        _up.clear_refresh_backoff(account_id)
    except Exception:
        pass

    return {
        "ok":        True,
        "msisdn":    msisdn,
        "has_refresh_token": has_rt,
        "message": (
            f"Session cookies cleared for {msisdn}. "
            + ("Keepalive will attempt a silent refresh using the stored refresh_token."
               if has_rt else
               "No refresh_token stored — you will need to re-login with OTP.")
        ),
    }


def jd_logout_account(account_id: int) -> dict:
    """Clear all JazzDrive session tokens for an account and mark it inactive.

    - Wipes validation_key, jsessionid, node, refresh_token, raw_accesstoken
    - Sets is_active=0, token_expires_at=0
    - Best-effort: tries to notify JazzDrive server to revoke the session
    - Does NOT delete the account row (use db.delete_account() for that)
    """
    import requests as _req
    log.info("[JD:LOGOUT] account_id=%s", account_id)

    # 1. Read current tokens before wiping (needed for server-side revoke)
    row = None
    try:
        with db.conn() as _c:
            row = _c.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
            if row:
                row = dict(row)
    except Exception as _e:
        log.warning("[JD:LOGOUT] could not read account: %s", _e)

    if not row:
        return {"ok": False, "error": f"Account {account_id} not found"}

    msisdn = row.get("msisdn", "")
    vk     = row.get("validation_key") or ""
    jid    = row.get("jsessionid")     or ""
    rt     = row.get("refresh_token")  or ""

    # 2. Best-effort server-side logout (fire-and-forget, never block on failure)
    if jid or rt:
        try:
            proxies = resolve_proxies(purpose="otp")
            hdrs = get_auth_headers(vk, jid, msisdn=msisdn)
            _req.post(
                f"{CLOUD_BASE}/sapi/logout",
                headers=hdrs, timeout=10, proxies=proxies
            )
            log.info("[JD:LOGOUT] server-side logout sent for %s", msisdn)
        except Exception as _le:
            log.warning("[JD:LOGOUT] server-side logout skipped (no network or session already dead): %s", _le)

    # 3. Wipe all tokens in DB, mark inactive
    try:
        with db.conn() as _c:
            _c.execute(
                "UPDATE accounts SET validation_key=NULL, jsessionid=NULL, node=NULL, "
                "refresh_token=NULL, raw_accesstoken=NULL, token_expires_at=0, is_active=0 "
                "WHERE id=?",
                (account_id,)
            )
        log.info("[JD:LOGOUT] tokens wiped for account %s (%s)", account_id, msisdn)
    except Exception as _de:
        log.error("[JD:LOGOUT] DB wipe failed: %s", _de)
        return {"ok": False, "error": f"DB error: {_de}"}

    # 4. Clear OTP state file if it belongs to this account's MSISDN
    try:
        if _OTP_STATE_FILE.exists():
            state = json.loads(_OTP_STATE_FILE.read_text())
            _norm = lambda n: str(n).strip().replace("+92","0").replace(" ","")
            if _norm(state.get("msisdn","")) == _norm(msisdn):
                _OTP_STATE_FILE.unlink(missing_ok=True)
                log.info("[JD:LOGOUT] OTP state file cleared for %s", msisdn)
    except Exception:
        pass

    # 5. FIX-JD-LOGIN-3: Clear jazzdrive_session.json — equivalent to clearing
    #    browser cookies. JazzDrive has a server-side bug: after logout, if any
    #    request is made with the old (now-dead) JSESSIONID cookie, it enters a
    #    broken state that refuses re-login. Deleting the file removes all stale
    #    pickled cookies so the next OTP login starts completely clean.
    try:
        if SESSION_FILE.exists():
            SESSION_FILE.unlink(missing_ok=True)
            log.info("[JD:LOGOUT] jazzdrive_session.json deleted (stale cookies cleared) for %s", msisdn)
    except Exception as _sf_e:
        log.debug("[JD:LOGOUT] session file delete skipped: %s", _sf_e)

    return {"ok": True, "msisdn": msisdn,
            "message": f"Logged out — session cleared for {msisdn}"}

# ---------------------------------------------------------------------------
# OTP flow
# ---------------------------------------------------------------------------

def trigger_otp_flow(msisdn: Optional[str] = None) -> dict:
    """Step 1: trigger OTP via jazzdrive_login (from _legacy/scanner.py)."""
    log.info("[JD:OTP] ==========================================")
    log.info("[JD:OTP] STEP 1 -- TRIGGER OTP")
    log.info("[JD:OTP] ==========================================")
    require_wg0()  # Hard-fail if wg0 down — never leak OTP call
    log.info("[JD:OTP] VPN check passed")
    if not msisdn:
        msisdn = db.setting("JAZZDRIVE_MSISDN") or ""
        log.info("[JD:OTP] MSISDN from DB: %s", msisdn or "(none)")

    # FIX-JD-LOGIN-4: clear jazzdrive_session.json before triggering a new OTP.
    # This is the equivalent of clearing browser cookies. JazzDrive refuses
    # re-login when it receives the old (logged-out) JSESSIONID cookie from a
    # previous session. A clean session file guarantees a fresh login flow.
    try:
        if SESSION_FILE.exists():
            SESSION_FILE.unlink(missing_ok=True)
            log.info("[JD:OTP] jazzdrive_session.json cleared before OTP trigger (clean slate)")
    except Exception as _sf_e:
        log.debug("[JD:OTP] session file pre-clear skipped: %s", _sf_e)

    # Normalize to 03xxxxxxxxx for the API (local format is more reliable for OTP)
    m = msisdn.strip().replace(" ", "").replace("-", "").replace("+", "")
    if m.startswith("92"):
        msisdn_local = "0" + m[2:]
    elif m.startswith("3") and len(m) == 10:
        msisdn_local = "0" + m
    else:
        msisdn_local = m

    log.info("[JD:OTP] MSISDN raw=%s  normalized=%s", msisdn, msisdn_local)
    if not msisdn_local:
        log.error("[JD:OTP] FAILED -- no MSISDN")
        return {"ok": False, "error": "No MSISDN provided or configured"}

    # Build proxy chain — bypass check first.
    _proxies_chain: list = []
    _seen_proxy_urls: set = set()
    if is_proxy_bypass():
        _proxies_chain = [None]  # direct via wg0 — wg0 exit IP is not banned by JazzDrive
    else:
        primary = resolve_proxies()
        if primary:
            _proxies_chain.append(primary)
            _seen_proxy_urls.add(primary.get("_url", ""))
        try:
            from . import proxy_pool as _pp
            for p in _pp.pool.get_proxy_chain(n=4):
                _p_url = p.get("_url", "")
                if _p_url and _p_url not in _seen_proxy_urls:
                    _seen_proxy_urls.add(_p_url)
                    _proxies_chain.append(p)
        except Exception:
            pass
        if not _proxies_chain:
            log.warning("trigger_otp_flow: proxy chain empty — direct connection "
                        "will likely fail (MED-1011 — Oracle raw IP is banned by JazzDrive)")
            _proxies_chain = [None]

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
            _trig_px_label = proxies.get("_url") if proxies else "direct/wg0"
            log.info("[JD:OTP] trigger attempt via: %s", _trig_px_label)
            # Use v2 radd_flix if available (richer implementation)
            rf = _flix()
            use_android = True  # always try Android flow to get long-lived refresh_token
            if rf:
                try:
                    verify_url = rf.trigger_otp(session, msisdn_local)
                except Exception as _rf_trig_e:
                    log.warning("[JD:OTP] radd_flix trigger_otp failed: %s -- falling back to scanner", _rf_trig_e)
                    rf = None
            if rf is None:
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
            _plabel = proxies.get("_url") if proxies else "direct via wg0"
            log.info("[JD:OTP] OTP triggered for %s via %s", msisdn, _plabel)
            try:
                from urllib.parse import urlparse as _urlp
                _vurl_host = _urlp(verify_url).netloc
            except Exception:
                _vurl_host = "?"
            log.info("[JD:OTP] verify_url host=%s  url=%s",
                     _vurl_host, (verify_url or "")[:90])
            log.info("[JD:OTP] ==========================================")
            return {"ok": True, "msisdn": msisdn, "message": f"OTP sent to {msisdn}. Check SMS then submit below."}
        except Exception as e:
            last_err = e
            err_s = str(e).lower()
            is_conn = any(x in err_s for x in ('connection', 'timeout', 'refused', 'reset', 'socks', 'proxy', 'max retries', 'newconnection'))
            if is_conn and proxies:
                url = proxies.get("_url") or proxies.get("https") or ""
                try:
                    from . import proxy_pool as _pp
                    if url:
                        _pp.pool.mark_fail(url)
                        log.warning("OTP: proxy %s failed (%s), trying next in chain", url, str(e)[:80])
                except Exception:
                    pass
                continue  # try next proxy in chain
            break  # non-connection error — don't retry with different proxy

    log.error("[JD:OTP] TRIGGER FAILED -- all proxies exhausted: %s", last_err)
    log.info("[JD:OTP] ==========================================")
    return {"ok": False, "error": str(last_err)}


def resend_otp() -> dict:
    """Trigger a resend of the OTP using the official 'resendpin' POST trick."""
    log.info("[JD:OTP] ==========================================")
    log.info("[JD:OTP] RESEND OTP REQUESTED")
    require_wg0()  # Hard-fail if wg0 down — never leak OTP resend
    log.info("[JD:OTP] VPN check passed")
    if not _OTP_STATE_FILE.exists():
        log.warning("[JD:OTP] No pending OTP state -- resend aborted")
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

    _resend_num = state.get("resend_count", 0) + 1
    state["resend_count"] = _resend_num
    try:
        _OTP_STATE_FILE.write_text(__import__("json").dumps(state))
    except Exception:
        pass
    log.info("[JD:OTP] ==========================================")
    log.info("[JD:OTP] RESEND #%d  MSISDN=%s  age=%.0fs since trigger",
             _resend_num, state.get("msisdn"), _resend_age)

    # Build proxy chain — bypass check first.
    _proxies_chain: list = []
    _seen_proxy_urls: set = set()
    if is_proxy_bypass():
        _proxies_chain = [None]  # direct via wg0 — wg0 exit IP is not banned by JazzDrive
    else:
        primary = resolve_proxies()
        if primary:
            _proxies_chain.append(primary)
            _seen_proxy_urls.add(primary.get("_url", ""))
        try:
            from . import proxy_pool as _pp
            for p in _pp.pool.get_proxy_chain(n=4):
                _p_url = p.get("_url", "")
                if _p_url and _p_url not in _seen_proxy_urls:
                    _seen_proxy_urls.add(_p_url)
                    _proxies_chain.append(p)
        except Exception:
            pass
        if not _proxies_chain:
            log.warning("resend_otp: proxy chain empty — direct connection "
                        "will likely fail (MED-1011 — Oracle raw IP is banned by JazzDrive)")
            _proxies_chain = [None]

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
            log.info("[JD:OTP] OTP resend sent for %s via %s  HTTP=%d",
                     state.get("msisdn"), proxies.get("_url") if proxies else "direct", r.status_code)
            _resend_body = (r.text or "").strip()[:300]
            log.info("[JD:OTP] Jazz resend response: %s", _resend_body or "(empty body)")
            if r.status_code == 200:
                log.info("[JD:OTP] RESEND OK -- SMS should be dispatched")
            else:
                log.warning("[JD:OTP] RESEND WARNING -- unexpected HTTP %d", r.status_code)
            return {"ok": True, "message": "OTP resend request sent. Please check your SMS."}
        except Exception as e:
            last_err = e
            err_s = str(e).lower()
            is_conn = any(x in err_s for x in ('connection', 'timeout', 'refused', 'reset', 'socks', 'proxy', 'max retries', 'newconnection'))
            if is_conn and proxies:
                url = proxies.get("_url") or proxies.get("https") or ""
                try:
                    from . import proxy_pool as _pp
                    if url:
                        _pp.pool.mark_fail(url)
                        log.warning("OTP resend: proxy %s failed, trying next", url)
                except Exception:
                    pass
                continue
            break

    log.error("[JD:OTP] RESEND FAILED -- all proxies exhausted: %s", last_err)
    return {"ok": False, "error": str(last_err)}


def submit_otp(otp: str) -> dict:
    """Step 2: verify OTP and persist session."""
    log.info("[JD:OTP] ==========================================")
    log.info("[JD:OTP] STEP 2 -- SUBMIT OTP  len=%d", len(otp.strip()))
    log.info("[JD:OTP] ==========================================")
    require_wg0()  # Hard-fail if wg0 down — never leak OTP submit
    log.info("[JD:OTP] VPN check passed")
    if not _OTP_STATE_FILE.exists():
        log.error("[JD:OTP] No OTP state file -- submit aborted")
        return {"ok": False, "error": "No pending OTP — request a new OTP first"}
    try:
        state = json.loads(_OTP_STATE_FILE.read_text())
    except Exception:
        log.error("[JD:OTP] OTP state file is corrupt")
        return {"ok": False, "error": "Corrupt OTP state — request a new OTP"}
    age = time.time() - state.get("created_at", 0)
    log.info("[JD:OTP] state loaded -- MSISDN=%s  age=%.0fs  use_android=%s",
             state.get("msisdn"), age, state.get("use_android"))
    if age > 600:
        log.warning("[JD:OTP] OTP expired (age=%.0fs > 600s)", age)
        _OTP_STATE_FILE.unlink(missing_ok=True)
        return {"ok": False, "error": "OTP expired (>10 min) — request a new OTP"}

    _attempt_num = state.get("submit_attempts", 0) + 1
    state["submit_attempts"] = _attempt_num
    try:
        _OTP_STATE_FILE.write_text(__import__("json").dumps(state))
    except Exception:
        pass
    _otp_masked = (otp.strip()[:1] + "*" * max(0, len(otp.strip())-1)) if otp.strip() else "(empty)"
    log.info("[JD:OTP] ==========================================")
    log.info("[JD:OTP] SUBMIT ATTEMPT #%d  code=%s  len=%d",
             _attempt_num, _otp_masked, len(otp.strip()))

    # Build proxy chain for submit_otp.
    # JazzDrive is globally accessible — no geo-restriction.
    # With PROXY_BYPASS=1, wg0 routes cloud.jazzdrive.com.pk directly; go direct.
    # Only use proxy pool in non-bypass environments.
    _sub_chain: list = []
    _sub_seen: set = set()
    if is_proxy_bypass():
        # PROXY_BYPASS=1 — wg0 routes cloud.jazzdrive.com.pk directly.
        # Skip pool entirely — proxies are unused/dead in bypass mode.
        _sub_chain = [None]
    else:
        _sub_primary = resolve_proxies()
        if _sub_primary:
            _sub_chain.append(_sub_primary)
            _sub_seen.add(_sub_primary.get("_url", ""))
        try:
            from . import proxy_pool as _pp
            for _subp in _pp.pool.get_proxy_chain(n=4):
                _subp_url = _subp.get("_url", "")
                if _subp_url and _subp_url not in _sub_seen:
                    _sub_seen.add(_subp_url)
                    _sub_chain.append(_subp)
        except Exception:
            pass
        if not _sub_chain:
            log.warning("submit_otp: proxy chain empty — using direct connection")
            _sub_chain = [None]

    _sub_last_err: Exception = Exception("No proxies available")
    for proxies in _sub_chain:
        _sub_px_label = proxies.get("_url") if proxies else "direct/wg0"
        log.info("[JD:OTP] submit via proxy: %s", _sub_px_label)
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
                log.info("[JD:OTP] strategy: radd_flix verify_otp")
                try:
                    code = rf.verify_otp(session, state["verify_url"], otp.strip())
                    tokens = rf.exchange_code_for_tokens(session, code)
                    vk = tokens.get("validationkey") or tokens.get("validation_key") or ""
                    jid = tokens.get("jsessionid") or tokens.get("JSESSIONID") or ""
                    log.info("[JD:OTP] radd_flix OK -- vk=%s  jid=%s", bool(vk), bool(jid))
                except Exception as _rf_e:
                    log.warning("[JD:OTP] radd_flix failed (%s) -- falling back to scanner", _rf_e)

            if not vk:
                tokens = jazzdrive_verify_otp(
                    session, state["verify_url"], otp.strip(),
                    use_android=use_android,
                    msisdn=state.get("msisdn", ""),
                    proxies=proxies,
                )

                vk  = tokens.get("validation_key", "")
                jid = tokens.get("jsessionid", "")
                log.info("[JD:OTP] scanner verify_otp OK  use_android=%s  vk=%s  rt=%s",
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
            log.info("[JD:OTP] tokens extracted -- vk=%s  jid=%s  raw_at=%s  rt=%s",
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
            _expiry_str = ("%dd" % (expires_offset//86400)) if expires_offset>=86400 else ("%dmin" % (expires_offset//60))
            log.info("[JD:OTP] session saved -- expires in %s", _expiry_str)
            _OTP_STATE_FILE.unlink(missing_ok=True)
            log.info("[JD:OTP] OTP state file cleared")
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
                            log.info("[JD:OTP] DB updated -- id=%s  msisdn=%s", existing["id"], state.get("msisdn"))
                            # Clear 30-min SAPI backoff immediately — new OTP tokens are live.
                            # Without this the uploader burns the fresh token within seconds.
                            try:
                                clear_sapi_backoff(existing["id"])
                            except Exception:
                                pass
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
                            log.info("[JD:OTP] DB new account -- msisdn=%s", state["msisdn"])
            except Exception as _dbe:
                log.warning("[JD:OTP] DB sync failed: %s", _dbe)
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
            log.info("[JD:OTP] ==========================================")
            log.info("[JD:OTP] LOGIN SUCCESS  MSISDN=%s  attempt=#%d",
                     state.get("msisdn"), state.get("submit_attempts", 1))
            log.info("[JD:OTP] tokens: vk_len=%d  jid_len=%d  raw_at_len=%d  rt_len=%d",
                     len(vk), len(jid), len(raw_at), len(rt))
            log.info("[JD:OTP] ==========================================")
            return {"ok": True, "message": "JazzDrive connected successfully!"}
        except Exception as e:
            _sub_last_err = e
            _sub_err_s = str(e).lower()
            _sub_is_conn = any(x in _sub_err_s for x in (
                "connection", "timeout", "refused", "reset", "socks",
                "proxy", "max retries", "newconnection", "failed to reach"))
            if _sub_is_conn and proxies:
                _sub_fail_url = proxies.get("_url") or proxies.get("https") or ""
                try:
                    from . import proxy_pool as _pp
                    if _sub_fail_url:
                        _pp.pool.mark_fail(_sub_fail_url)
                        log.warning("submit_otp: proxy %s failed (%s), trying next",
                                    _sub_fail_url, str(e)[:80])
                except Exception:
                    pass
                continue  # retry with next proxy in chain
            _sub_estr = str(e)
            _sub_el   = _sub_estr.lower()
            if any(x in _sub_el for x in ("otp", "pin", "code", "invalid", "wrong",
                                           "incorrect", "mismatch", "expired",
                                           "verification", "unauthori")):
                log.error("[JD:OTP] WRONG/INVALID OTP on attempt #%d -- %s",
                          state.get("submit_attempts", 1), _sub_estr)
            else:
                log.error("[JD:OTP] SUBMIT ERROR on attempt #%d (non-network) -- %s",
                          state.get("submit_attempts", 1), _sub_estr)
            return {"ok": False, "error": _sub_estr}

    log.error("[JD:OTP] ALL PROXIES EXHAUSTED on attempt #%d -- %s",
              state.get("submit_attempts", 1) if "_attempt_num" not in dir() else _attempt_num,
              _sub_last_err)
    log.info("[JD:OTP] ==========================================")
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

    require_jd_active()  # Hard-fail if master switch is OFF
    log.info("[JD:OAUTH2] ==========================================")
    log.info("[JD:OAUTH2] ANDROID TOKEN REFRESH  acct=%s  has_rt=%s", account_id, bool(refresh_token))
    require_wg0()  # Hard-fail if wg0 down — never leak OAuth2
    log.info("[JD:OAUTH2] VPN check passed")
    log.info("android_refresh_session: exchanging refresh_token (acct=%s)...", account_id)

    # ── Step 1: POST to /oauth2/refresh_token.php ─────────────────────────────
    # NOTE: jazzdrive.com.pk has an SSL hostname mismatch (cert issued for a
    # subdomain, not the bare domain). We suppress verification only for this
    # one internal call — all cloud.jazzdrive.com.pk calls remain verified.
    #
    # Build proxy chain (OTP/OAuth2 domain — jazzdrive.com.pk).
    # Same retry pattern as trigger_otp_flow / submit_otp: primary first,
    # then pool fallbacks, mark_fail on connection error and try the next.
    _ar_chain: list = []
    _ar_seen: set = set()
    if is_proxy_bypass():
        # VPN/direct mode — wg0 already routes jazzdrive.com.pk (54.179.95.148)
        # at OS level. No proxy needed; pool proxies are dead and waste 4×25 s.
        _ar_chain = [None]
    else:
        _ar_primary = resolve_proxies()
        if _ar_primary:
            _ar_chain.append(_ar_primary)
            _ar_seen.add(_ar_primary.get("_url", ""))
        try:
            from . import proxy_pool as _pp
            for _ar_p in _pp.pool.get_proxy_chain(n=4):
                _ar_pu = _ar_p.get("_url", "")
                if _ar_pu and _ar_pu not in _ar_seen:
                    _ar_seen.add(_ar_pu)
                    _ar_chain.append(_ar_p)
        except Exception:
            pass
        if not _ar_chain:
            log.warning("android_refresh_session: proxy chain empty — direct connection "
                        "will likely fail (MED-1011 — Oracle raw IP is banned by JazzDrive)")
            _ar_chain = [None]

    # SAPI proxy for Step 2 (cloud.jazzdrive.com.pk).
    # JazzDrive is globally accessible — no geo-restriction.
    # With PROXY_BYPASS=1, wg0 routes cloud.jazzdrive.com.pk directly; no proxy needed.
    # Only build sapi_proxies when bypass is NOT set (non-VPN environments).
    sapi_proxies = None
    if not is_proxy_bypass():
        try:
            from . import proxy_pool as _pp
            sapi_proxies = _pp.pool.get_best()
        except Exception:
            pass
        if sapi_proxies is None:
            _sapi_setting = (db.setting("JAZZDRIVE_SAPI_PROXY") or "").strip()
            if _sapi_setting:
                sapi_proxies = {"http": _sapi_setting, "https": _sapi_setting, "_url": _sapi_setting}

    import urllib3 as _urllib3
    _urllib3.disable_warnings(_urllib3.exceptions.InsecureRequestWarning)

    r = None
    _ar_last_err: Exception = Exception("No proxies available")
    for _ar_px in _ar_chain:
        try:
            r = _req.post(
                # APK strings.xml oauth2_access_token_uri = token.php (both grants).
                # refresh_token.php is proprietary (returns raw hex, not OAuth2 JSON).
                # Try standard token.php first, fall back to refresh_token.php.
                "https://jazzdrive.com.pk/oauth2/token.php",
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
            _ar_fail_url = (_ar_px.get("_url", "") if _ar_px else "")
            if _ar_fail_url:
                try:
                    from . import proxy_pool as _pp
                    _pp.pool.mark_fail(_ar_fail_url)
                    log.warning("android_refresh_session: proxy %s failed (%s), trying next",
                                _ar_fail_url, str(_ar_e)[:80])
                except Exception:
                    pass
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

    # ── Persist refreshed tokens early (before SAPI step) ───────────────────────────────
    # JazzDrive refresh_token.php rotates the token on each call.  If we wait until
    # after the SAPI login to persist, a failed SAPI step will discard the new
    # token and break the rotation chain.  Save new_rt + raw_at now so the chain
    # is never lost even if Step 2 fails.
    if account_id is not None and new_rt and new_rt != refresh_token:
        try:
            with _lock:
                with db.conn() as _c:
                    # FIX: only persist the rotated refresh_token here.
                    # Do NOT overwrite raw_accesstoken yet — the OAuth2-derived raw_at
                    # is frequently rejected by SAPI (/login/oauth?keytype=accesstoken).
                    # The OTP-issued raw_accesstoken (already in DB) is the proven working
                    # one; it will be overwritten only after SAPI login succeeds below.
                    _c.execute(
                        "UPDATE accounts SET refresh_token=? WHERE id=?",
                        (new_rt, account_id),
                    )
            log.info(
                "android_refresh_session: persisted rotated refresh_token early "
                "(raw_accesstoken preserved — acct=%s)",
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

    sess = _req.Session()
    # Use the same headers as the real Android app (all 4 OkHttp interceptors)
    _sess_headers = get_auth_headers("", "", msisdn=_msisdn_for_dev)
    # raw_at may be unusable at this point — Authorization added per-request below if needed
    _sess_headers.pop("Cookie", None)
    _sess_headers.pop("validation_key", None)
    device_id = get_x_deviceid(_msisdn_for_dev)
    sess.headers.update(_sess_headers)
    
    # Android-Nested: {"data":{"accesstoken":"<raw_at>"}} → base64 → URL-encoded
    # This is the exact format the Jazz Drive APK sends. Only one format, no fallbacks.
    at_json_1 = json.dumps({"data": {"accesstoken": raw_at}})
    at_b64_1  = _up.quote(_b64.b64encode(at_json_1.encode()).decode(), safe='')
    candidates = [
        (f"{_CLOUD}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64_1}", "Android-Nested"),
    ]
    
    # Build SAPI proxy chain for Step 2 re-login.
    # Inner loop: tries different URL formats with the same SAPI proxy.
    # Outer loop: if ALL formats fail with connection errors → mark proxy dead,
    # pick the next SAPI proxy from the pool, and retry all formats.
    _s2_chain: list = []
    _s2_seen: set = set()
    if is_proxy_bypass():
        # PROXY_BYPASS=1 — wg0 routes cloud.jazzdrive.com.pk directly.
        # JazzDrive is globally accessible; no proxy needed. Skip pool entirely.
        _s2_chain = [None]
    else:
        if sapi_proxies:
            _s2_chain.append(sapi_proxies)
            _s2_seen.add(sapi_proxies.get("_url", ""))
        try:
            from . import proxy_pool as _pp
            for _s2p in _pp.pool.get_proxy_chain(n=4):
                _s2p_url = _s2p.get("_url", "")
                if _s2p_url and _s2p_url not in _s2_seen:
                    _s2_seen.add(_s2p_url)
                    _s2_chain.append(_s2p)
        except Exception:
            pass
        if not _s2_chain:
            _s2_chain = [None]

    last_err = "No candidates tried"
    sr = None
    for _s2_px in _s2_chain:
        _s2_conn_errs = 0
        for url, label in candidates:
            try:
                log.info("[JD:OAUTH2] trying %s  url=%s", label, url[:100])
                sr = sess.get(url, timeout=30, proxies=_s2_px)
                if sr.status_code == 200:
                    log.info("[JD:OAUTH2] %s succeeded (HTTP 200)", label)
                    break
                last_err = f"[{label}] HTTP {sr.status_code}: {sr.text[:200]}"
                log.warning("[JD:OAUTH2] %s failed  HTTP=%d: %s", label, sr.status_code, sr.text[:120])
            except Exception as _se:
                last_err = str(_se)
                _s2_conn_errs += 1
                log.debug("android_refresh_session: %s network error: %s", label, last_err)
        if sr and sr.status_code == 200:
            break  # success — stop trying proxies
        # If every format failed with a connection error, this SAPI proxy is dead
        if _s2_conn_errs == len(candidates) and _s2_px:
            _s2_fail_url = _s2_px.get("_url", "")
            if _s2_fail_url:
                try:
                    from . import proxy_pool as _pp
                    _pp.pool.mark_fail(_s2_fail_url)
                    log.warning("android_refresh_session: SAPI proxy %s unreachable, trying next",
                                _s2_fail_url)
                except Exception:
                    pass
        sr = None  # reset for next proxy

    if not sr or sr.status_code != 200:
        log.error("[JD:OAUTH2] Android-Nested failed (%s) — OTP re-login required", last_err)
        log.info("[JD:OAUTH2] ==========================================")
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

    log.info("[JD:OAUTH2] TOKEN REFRESH OK  acct=%s  new_jid=%s  rt_rotated=%s",
             account_id, bool(new_jid), new_rt != refresh_token)
    return {"ok": True, "validation_key": new_vk, "jsessionid": new_jid,
            "message": "Android OAuth2 session refreshed (no OTP required)"}


# ---------------------------------------------------------------------------
# Token refresh — Android OAuth2 only (no web fallbacks)
# ---------------------------------------------------------------------------

def refresh_session(account_id: Optional[int] = None) -> dict:
    """Silently obtain a fresh JSESSIONID + validationKey without OTP.

    Uses Android OAuth2 refresh_token flow only:
      POST /oauth2/refresh_token.php with client_id=fnbroot / client_secret=f&rW23.
      Then POST /sapi/login/oauth?platform=Android&keytype=accesstoken (nested JSON format).
    If no refresh_token is stored, returns ok=False — OTP re-login required.

    Returns {"ok": True, ...} on success, {"ok": False, "error": ...} otherwise.
    """
    # ── Master kill switch ────────────────────────────────────────────────────
    if not is_jd_enabled():
        return {"ok": False, "error": "JazzDrive master switch is OFF"}

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
        log.error("refresh_session: Android OAuth2 failed (%s) — OTP re-login required",
                  android_result.get("error"))
        return {"ok": False, "error": f"Android refresh failed: {android_result.get('error')} — OTP re-login required"}

    # No refresh_token and no Android path — cannot refresh silently.
    return {
        "ok": False,
        "error": "No refresh_token stored. Please re-login via OTP to store credentials."
    }



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
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; Infinix X680F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
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
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; Infinix X680F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
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

