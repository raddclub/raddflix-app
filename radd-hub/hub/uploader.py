"""Watch-folder uploader to JazzDrive.

Native v3 implementation — uploads files directly to JazzDrive via its
Funambol SAPI REST protocol using the session tokens stored in the DB accounts
table.  No v2 radd_flix dependency required.

Pipeline (triggered after every successful download):
  1. upload_to_jazzdrive()  — POST multipart to /sapi/media/video?action=upload
  2. _create_share_link()   — create/fetch a public share link
  3. db.upsert_file()       — record remote_id, share_url, is_ready=1
  4. local file deleted automatically when auto_delete=True (default)

v3.0 additions ported from v1.0 radd_flix.py:
  - ThrottledFileWrapper      — streaming upload wrapper with bandwidth throttle
  - _streaming_multipart()    — generator-based multipart builder (no RAM buffer)
  - _safe_filename()          — RFC 5987 filename*= fix for emoji/non-ASCII names
  - _fingerprint_file()       — retries on PermissionError (Windows file locks)
  - Upload config: parallel_uploads, skip_extensions, max_file_size_gb,
                   bandwidth_limit_mbps, chunk_size_mb, max_retries
"""
from __future__ import annotations
import hashlib
import logging
import threading
import time
import uuid as _uuid
import urllib.parse
from pathlib import Path
from typing import Optional, Callable

try:
    import requests as _requests
    _REQUESTS_OK = True
except ImportError:
    _REQUESTS_OK = False

from . import config, db, jazzdrive, mirror

log = logging.getLogger("hub.uploader")

CLOUD_BASE     = "https://cloud.jazzdrive.com.pk"
_UPLOAD_TIMEOUT = 3600

# ─────────────────────────────────────────────────────────────────────────────
# In-memory log ring buffer — streamed to the UI via SSE
# ─────────────────────────────────────────────────────────────────────────────

import collections as _collections

_LOG_RING: "collections.deque[dict]" = _collections.deque(maxlen=500)
_LOG_RING_LOCK = threading.Lock()
_LOG_SEQ = 0

# ── Refresh backoff registry ──────────────────────────────────────────────────
# When OTP re-login is required (all auto-refresh strategies fail), we record
# the failure time and skip further refresh attempts for 30 minutes.  This
# prevents hammering JazzDrive with hundreds of failed calls per hour while
# the session is waiting for a phone re-activation.
_REFRESH_BACKOFF: "dict[int, float]" = {}
_REFRESH_BACKOFF_LOCK = threading.Lock()
_REFRESH_BACKOFF_SECS = 1800  # 30 minutes


def clear_refresh_backoff(account_id: int) -> None:
    """Clear the refresh backoff for an account.
    Call this immediately after new tokens are saved via phone activation
    so uploads resume without waiting 30 min.
    """
    with _REFRESH_BACKOFF_LOCK:
        _REFRESH_BACKOFF.pop(account_id, None)
    log.info("Refresh backoff cleared for account %s — resuming uploads", account_id)


def _is_refresh_backed_off(account_id: int) -> bool:
    """Return True if this account is in OTP backoff (suppress retry)."""
    with _REFRESH_BACKOFF_LOCK:
        fail_at = _REFRESH_BACKOFF.get(account_id)
    if fail_at is None:
        return False
    elapsed = time.time() - fail_at
    if elapsed >= _REFRESH_BACKOFF_SECS:
        with _REFRESH_BACKOFF_LOCK:
            _REFRESH_BACKOFF.pop(account_id, None)
        return False
    remaining_min = int((_REFRESH_BACKOFF_SECS - elapsed) / 60)
    log.debug("account %s OTP-backoff active — %dm remaining", account_id, remaining_min)
    return True


def _mark_refresh_backed_off(account_id: int) -> None:
    """Record that OTP is required — suppress refresh retries for 30 min."""
    with _REFRESH_BACKOFF_LOCK:
        _REFRESH_BACKOFF[account_id] = time.time()
    log.warning(
        "account %s: OTP re-login required — all auto-refresh strategies failed. "
        "Suppressing retries for 30 min. Open Scan page and re-activate via phone.",
        account_id
    )



class _RingHandler(logging.Handler):
    """Appends formatted log records to the shared ring buffer."""
    LEVEL_MAP = {
        logging.DEBUG:   "debug",
        logging.INFO:    "info",
        logging.WARNING: "warn",
        logging.ERROR:   "error",
        logging.CRITICAL:"error",
    }

    def emit(self, record: logging.LogRecord) -> None:
        global _LOG_SEQ
        try:
            with _LOG_RING_LOCK:
                _LOG_SEQ += 1
                _LOG_RING.append({
                    "seq":     _LOG_SEQ,
                    "ts":      record.created,
                    "level":   self.LEVEL_MAP.get(record.levelno, "info"),
                    "logger":  record.name,
                    "msg":     self.format(record),
                })
        except Exception:
            pass


def _install_ring_handler() -> None:
    """Attach the ring handler to all hub loggers once at startup."""
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s",
                            datefmt="%I:%M:%S %p")
    h = _RingHandler()
    h.setFormatter(fmt)
    for name in ("hub.uploader", "hub.keepalive", "hub.jazzdrive",
                 "hub.scanner", "hub.downloader"):
        lg = logging.getLogger(name)
        lg.setLevel(logging.INFO)  # Ensure messages flow to the handler
        if not any(isinstance(x, _RingHandler) for x in lg.handlers):
            lg.addHandler(h)


_install_ring_handler()


def get_log_entries(since_seq: int = 0) -> list:
    """Return log entries with seq > since_seq."""
    with _LOG_RING_LOCK:
        return [e for e in _LOG_RING if e["seq"] > since_seq]

# Upload config defaults — all can be overridden via DB settings
_DEFAULT_UPLOAD_CFG = {
    "parallel_uploads":      1,
    "skip_extensions":       [],
    "max_file_size_gb":      0,
    "bandwidth_limit_mbps":  0,
    "chunk_size_mb":         4,
    "max_retries":           3,
    "retry_base_delay":      2,
    "auto_delete":           True,
}

# Import shared extension sets — single source of truth for both scanner and uploader
from .media_naming import (
    MEDIA_EXTENSIONS      as _MEDIA_EXTENSIONS,
    ALWAYS_SKIP_EXTENSIONS as _ALWAYS_SKIP_EXT_MN,
    NON_MEDIA_EXTENSIONS  as _NON_MEDIA_EXTENSIONS,
)

# Merge with any uploader-only always-skip extensions (incomplete downloads etc.)
ALWAYS_SKIP_EXTENSIONS: frozenset[str] = _ALWAYS_SKIP_EXT_MN | _NON_MEDIA_EXTENSIONS


def _load_upload_cfg() -> dict:
    """Load upload config keys from the DB settings table, falling back to defaults."""
    cfg = dict(_DEFAULT_UPLOAD_CFG)
    try:
        for key, default in _DEFAULT_UPLOAD_CFG.items():
            val = db.setting(f"upload_{key}")
            if val is not None:
                if isinstance(default, list):
                    import json as _json
                    try:
                        cfg[key] = _json.loads(val)
                    except Exception:
                        cfg[key] = [x.strip() for x in val.split(",") if x.strip()]
                elif isinstance(default, bool):
                    cfg[key] = str(val).lower() in ("1", "true", "yes")
                elif isinstance(default, int):
                    cfg[key] = int(val)
                elif isinstance(default, float):
                    cfg[key] = float(val)
                else:
                    cfg[key] = val
    except Exception as e:
        log.debug("_load_upload_cfg: %s", e)
    return cfg


# ─────────────────────────────────────────────────────────────────────────────
# v1.0 port: ThrottledFileWrapper — streaming upload with bandwidth throttle
# ─────────────────────────────────────────────────────────────────────────────

class ThrottledFileWrapper:
    """Wraps a file object to enforce a bandwidth cap (max_bps bytes/sec)
    and report progress.  Ported from v1.0 radd_flix.py.

    Using this instead of requests' files= parameter means the file is
    never buffered entirely into RAM — each 64 KB chunk is read and sent
    incrementally, keeping memory usage flat regardless of file size.
    """
    def __init__(self, file_obj, total_size: int,
                 max_bps: float = 0,
                 progress_callback: Optional[Callable] = None,
                 cancel_event: Optional[threading.Event] = None):
        self.file_obj       = file_obj
        self.total_size     = total_size
        self.max_bps        = max_bps
        self.bytes_read     = 0
        self.callback       = progress_callback
        self.cancel_event   = cancel_event
        self._window_start  = time.time()
        self._window_bytes  = 0

    def read(self, size: int = -1) -> bytes:
        if self.cancel_event and self.cancel_event.is_set():
            return b""
        data = self.file_obj.read(size)
        if not data:
            return data
        if self.max_bps and self.max_bps > 0:
            self._window_bytes += len(data)
            elapsed  = time.time() - self._window_start
            expected = self._window_bytes / self.max_bps
            if expected > elapsed:
                time.sleep(expected - elapsed)
            if time.time() - self._window_start >= 1.0:
                self._window_start = time.time()
                self._window_bytes = 0
        self.bytes_read += len(data)
        if self.callback:
            self.callback(self.bytes_read, self.total_size)
        return data

    def __len__(self) -> int:
        return self.total_size

    def __iter__(self):
        while True:
            chunk = self.read(64 * 1024)
            if not chunk:
                break
            yield chunk

    def seek(self, pos: int, whence: int = 0):
        self.file_obj.seek(pos, whence)
        self.bytes_read = self.file_obj.tell()

    def tell(self) -> int:
        return self.file_obj.tell()


# ─────────────────────────────────────────────────────────────────────────────
# v1.0 port: _streaming_multipart — generator multipart (no RAM buffering)
# ─────────────────────────────────────────────────────────────────────────────

def _safe_filename(name: str) -> tuple[str, str]:
    """Return (ascii_fallback, rfc5987_param) for a Content-Disposition header.

    If the name is pure ASCII, rfc5987_param is empty string.
    If it contains non-ASCII (emoji, Arabic, Urdu, etc.), the caller must append
    the rfc5987_param so Jazz Drive doesn't return HTTP 400.
    Ported from v1.0 radd_flix.py bug-fix section.
    """
    ascii_name = name.encode("ascii", errors="replace").decode("ascii")
    ascii_name = ascii_name.replace("\\", "\\\\").replace('"', '\\"')
    if ascii_name == name:
        return ascii_name, ""
    encoded = urllib.parse.quote(name.encode("utf-8"), safe="")
    return ascii_name, f"filename*=UTF-8''{encoded}"


def _streaming_multipart(file_path: Path, mime: str, parent_id: int,
                         max_bps: float = 0,
                         progress_cb: Optional[Callable] = None,
                         cancel_event: Optional[threading.Event] = None,
                         override_name: Optional[str] = None):
    """Build a streaming multipart/form-data body as a generator.

    Unlike requests' files= parameter (which reads the whole file into memory
    before sending), this streams 64 KB chunks directly.  Safe for multi-GB files.

    Returns (generator, content_type_header, content_length).
    Ported from v1.0 radd_flix.py _streaming_multipart().
    """
    import json as _json_mod
    boundary = ("----RaddHubBoundary" + _uuid.uuid4().hex[:16]).encode()
    file_size = file_path.stat().st_size
    
    final_name = override_name or file_path.name
    ascii_name, rfc5987 = _safe_filename(final_name)

    if rfc5987:
        disposition = (
            f'Content-Disposition: form-data; name="file"; '
            f'filename="{ascii_name}"; {rfc5987}\r\n'
        )
    else:
        disposition = (
            f'Content-Disposition: form-data; name="file"; '
            f'filename="{ascii_name}"\r\n'
        )

    # Use folderid (lowercase) — critical for server version 31.0.0.17
    # Always send the integer value: 0 means root folder on JazzDrive.
    # Sending null/None causes the server to pick a default location.
    data_json = _json_mod.dumps({
        "data": {
            "name": final_name,
            "size": file_size,
            "contenttype": mime,
            "folderid": int(parent_id),
        }
    }).encode("utf-8")
    part1 = (
        b"--" + boundary + b"\r\n" +
        b"Content-Disposition: form-data; name=\"data\"\r\n\r\n" +
        data_json + b"\r\n"
    )
    part2_hdr = (
        b"--" + boundary + b"\r\n" +
        disposition.encode("ascii") +
        f"Content-Type: {mime}\r\n\r\n".encode()
    )
    closing = b"\r\n--" + boundary + b"--\r\n"
    content_length = len(part1) + len(part2_hdr) + file_size + len(closing)
    ct_header = f"multipart/form-data; boundary={boundary.decode()}"

    def _gen():
        yield part1
        yield part2_hdr
        bytes_sent = 0
        _bw_start = time.time()
        _bw_bytes = 0
        with open(str(file_path), "rb") as fh:
            while True:
                if cancel_event and cancel_event.is_set():
                    return
                chunk = fh.read(65536)
                if not chunk:
                    break
                if max_bps and max_bps > 0:
                    _bw_bytes += len(chunk)
                    elapsed  = time.time() - _bw_start
                    expected = _bw_bytes / max_bps
                    if expected > elapsed:
                        time.sleep(expected - elapsed)
                    if time.time() - _bw_start >= 1.0:
                        _bw_start = time.time()
                        _bw_bytes = 0
                bytes_sent += len(chunk)
                if progress_cb:
                    progress_cb(bytes_sent, file_size)
                yield chunk
        yield closing

    return _gen(), ct_header, content_length


# ─────────────────────────────────────────────────────────────────────────────
# Auth helpers
# ─────────────────────────────────────────────────────────────────────────────

def _auth_headers(vk: str, jsid: str, account_id: Optional[int] = None) -> dict:
    msisdn = None
    raw_accesstoken = None
    if account_id:
        try:
            with db.conn() as c:
                row = c.execute(
                    "SELECT msisdn, raw_accesstoken FROM accounts WHERE id=?",
                    (account_id,)
                ).fetchone()
                if row:
                    msisdn          = row["msisdn"]
                    raw_accesstoken = row["raw_accesstoken"]
        except Exception:
            pass
    return jazzdrive.get_auth_headers(vk, jsid, msisdn=msisdn, raw_accesstoken=raw_accesstoken)


def _auth_qs(vk: str) -> str:
    return f"validationkey={urllib.parse.quote(vk, safe='')}"


def _build(path: str, vk: str) -> str:
    sep = "&" if "?" in path else "?"
    return f"{CLOUD_BASE}{path}{sep}{_auth_qs(vk)}"


# ─────────────────────────────────────────────────────────────────────────────
# Session check
# ─────────────────────────────────────────────────────────────────────────────

def verify_jd_session(vk: str, jsid: str, account_id: Optional[int] = None) -> bool:
    """Return True if the JD session has full media access (folder list probe).

    Note: /sapi/system/information returns 200 even for a stale JSESSIONID
    (validation_key check only).  The folder list requires a live session cookie,
    so we probe that endpoint to catch cookie-expiry failures accurately.
    Falls back to system/information if folder returns 401, so a stale session
    does NOT appear valid.
    """
    if not _REQUESTS_OK or not vk or not jsid:
        return False
    # Primary check: media folder list requires a live JSESSIONID
    try:
        data = jazzdrive.sapi_request(
            endpoint="/media/folder",
            action="get",
            params={"parentId": 0},
            account_id=account_id,
            tokens={"validationkey": vk, "jsessionid": jsid},
            timeout=15
        )
        return not data.get("error")
    except Exception as e:
        log.debug("verify_jd_session error: %s", e)
        return False


def get_active_account() -> Optional[dict]:
    """Return the first active JD account with tokens, prioritizing role='flix'.

    If the account's token is expired but a refresh_token is available,
    automatically refreshes before returning — so callers always get
    a live session without manual OTP intervention.
    """
    try:
        with db.conn() as c:
            # Prioritize role='flix', then by id
            row = c.execute(
                "SELECT * FROM accounts WHERE is_active=1 "
                "AND jsessionid!='' ORDER BY (CASE WHEN role='flix' THEN 0 ELSE 1 END), id LIMIT 1"
            ).fetchone()
        if not row:
            return None
        acct = dict(row)
        # Check if token has expired — try silent refresh if we have a refresh_token
        exp_at = acct.get("token_expires_at") or 0
        now    = int(__import__("time").time())
        if exp_at and exp_at < now:
            rt = (acct.get("refresh_token") or "").strip()
            if rt:
                log.info("Active account %s token expired — attempting silent refresh",
                         acct.get("msisdn"))
                try:
                    from . import jazzdrive as _jd
                    result = _jd.refresh_session(account_id=acct["id"])
                    if result.get("ok"):
                        log.info("get_active_account: silent refresh succeeded for %s",
                                 acct.get("msisdn"))
                        # Re-fetch with fresh tokens
                        with db.conn() as c2:
                            row2 = c2.execute(
                                "SELECT * FROM accounts WHERE id=?", (acct["id"],)
                            ).fetchone()
                            if row2:
                                acct = dict(row2)
                    else:
                        log.warning("get_active_account: refresh failed: %s",
                                    result.get("error"))
                except Exception as e:
                    log.debug("get_active_account refresh error: %s", e)
        return acct
    except Exception:
        return None


# ─────────────────────────────────────────────────────────────────────────────
# Folder helpers
# ─────────────────────────────────────────────────────────────────────────────

# Thread-safe cache for the real root folder ID (account-specific, not 0).
# JazzDrive's root is NOT id=0; the real ID is returned by parentid=0 list.
_root_folder_id_cache: dict = {}
_root_folder_cache_lock = threading.Lock()

# Per-folder-name lock to prevent race condition where two concurrent upload
# threads both see a folder is missing and both call _create_folder(), ending
# up with two JazzDrive folders of the same name for the same show/season.
# Key: (parent_id, name) — value: threading.Lock()
_folder_create_locks: dict = {}
_folder_create_locks_meta = threading.Lock()

def _get_folder_create_lock(parent_id: int, name: str) -> threading.Lock:
    """Return a lock unique to (parent_id, name) for safe folder creation."""
    k = (int(parent_id), name)
    with _folder_create_locks_meta:
        if k not in _folder_create_locks:
            _folder_create_locks[k] = threading.Lock()
        return _folder_create_locks[k]


def _get_root_folder_id(sess, vk: str, jsid: str, account_id: Optional[int] = None) -> int:
    """Fetch and cache the real root folder ID for this session.

    GET /sapi/media/folder?action=get&parentid=0 returns the root folder
    whose name is '/'.  Its 'id' field is the real root folder ID used for
    all subsequent parent references.  We cache by JSESSIONID prefix so
    each session fetches the root ID only once.
    """
    cache_key = jsid[:16] if jsid else ""
    with _root_folder_cache_lock:
        if cache_key and cache_key in _root_folder_id_cache:
            return _root_folder_id_cache[cache_key]

        try:
            data = jazzdrive.sapi_request(
                endpoint="/media/folder",
                action="get",
                params={"parentid": 0},
                account_id=account_id,
                tokens={"validationkey": vk, "jsessionid": jsid},
                timeout=30
            )
            if data.get("error"):
                raise RuntimeError(f"API Error: {data['error']}")
            
            folders = data.get("data", {}).get("folders", [])
            for f in folders:
                if isinstance(f, dict) and f.get("name") == "/":
                    root_id = int(f["id"])
                    if cache_key:
                        _root_folder_id_cache[cache_key] = root_id
                    log.debug("Root folder ID resolved: %s", root_id)
                    return root_id
            raise RuntimeError(f"No root folder '/' found in response: {data!r}")
        except Exception as exc:
            raise RuntimeError(f"Could not fetch root folder ID: {exc}") from exc


def _to_int_safe(v) -> object:
    try:
        return int(v)
    except (TypeError, ValueError):
        return v


def _list_folders(sess, vk: str, jsid: str, parent_id: int = 0, account_id: Optional[int] = None) -> list:
    """List direct child folders of parent_id.
    """
    try:
        if parent_id == 0:
            real_parent = _get_root_folder_id(sess, vk, jsid, account_id=account_id)
        else:
            real_parent = int(parent_id)

        data = jazzdrive.sapi_request(
            endpoint="/media/folder",
            action="get",
            params={"parentid": real_parent},
            account_id=account_id,
            tokens={"validationkey": vk, "jsessionid": jsid},
            timeout=30
        )
        if data.get("error"):
            log.debug("_list_folders API error for real_parent=%s: %s", real_parent, data["error"])
            return []
        
        body = data
        all_folders = body.get("data", {}).get("folders", [])
        if not isinstance(all_folders, list):
            return []
        # Filter client-side: only direct children of real_parent.
        # Compare as ints to handle API returning parentid as string.
        direct = [
            f for f in all_folders
            if isinstance(f, dict)
            and f.get("name") != "/"
            and _to_int_safe(f.get("parentid")) == real_parent
        ]
        log.debug("_list_folders parent=%s (real=%s): %d total, %d direct",
                  parent_id, real_parent, len(all_folders), len(direct))
        return direct
    except Exception as e:
        log.debug("_list_folders: %s", e)
        return []


def _create_folder(sess, vk: str, jsid: str, name: str, parent_id: int = 0, account_id: Optional[int] = None) -> Optional[int]:
    """Create a folder on JazzDrive. Returns new folder ID."""
    try:
        if parent_id == 0:
            real_parent = _get_root_folder_id(sess, vk, jsid, account_id=account_id)
        else:
            real_parent = int(parent_id)

        data = jazzdrive.sapi_request(
            endpoint="/folder",
            action="save",
            method="POST",
            json_data={"data": {"magic": False, "offline": False,
                                 "name": name, "parentid": real_parent}},
            account_id=account_id,
            tokens={"validationkey": vk, "jsessionid": jsid},
            timeout=30
        )
        if data.get("error"):
            log.warning("_create_folder API error for %r: %s", name, data["error"])
            return None
        
        body = data
        # Extract ID: {"id": <int>} or {"data": {"folder": {"id": <int>}}}
        fid = None
        if isinstance(body, dict):
            fid = body.get("id")
            if fid is None:
                data_obj = body.get("data", {})
                if isinstance(data_obj, dict):
                    folder_obj = data_obj.get("folder", data_obj)
                    if isinstance(folder_obj, dict):
                        fid = folder_obj.get("id") or folder_obj.get("folderid")
        if fid is not None:
            log.debug("_create_folder %r → id=%s (real_parent=%s)", name, fid, real_parent)
            return int(fid)
        log.warning("_create_folder %r: no id in response: %s", name, str(body)[:200])
    except Exception as e:
        log.warning("_create_folder error for %r: %s", name, e)
    return None


def _get_or_create_folder(sess, vk: str, jsid: str,
                           name: str, parent_id: int = 0, account_id: Optional[int] = None) -> int:
    """Return the ID of the named folder under parent_id, creating it if needed.

    Thread-safe: uses a per-(parent_id, name) lock to prevent concurrent calls
    from both finding the folder absent and both calling _create_folder(), which
    would produce duplicate JazzDrive folders for the same show/season.
    If _create_folder() fails (API error), retries _list_folders() once in case
    a concurrent thread already created the folder successfully.
    """
    def _find_in_list(items):
        for item in items:
            if isinstance(item, dict):
                n = item.get("name") or item.get("title") or ""
                if n == name:
                    fid = item.get("id") or item.get("folderid")
                    if fid is not None:
                        return int(fid)
        return None

    # Fast path: check without holding any lock
    items = _list_folders(sess, vk, jsid, parent_id, account_id=account_id)
    found = _find_in_list(items)
    if found is not None:
        return found

    # Folder not found — acquire per-folder lock, then double-check + create
    _lock = _get_folder_create_lock(int(parent_id) if parent_id else 0, name)
    with _lock:
        # Double-check: another thread may have created it while we waited
        items2 = _list_folders(sess, vk, jsid, parent_id, account_id=account_id)
        found2 = _find_in_list(items2)
        if found2 is not None:
            return found2

        new_id = _create_folder(sess, vk, jsid, name, parent_id, account_id=account_id)
        if new_id is not None:
            return new_id

        # Creation failed — retry list one final time (concurrent success / API inconsistency)
        items3 = _list_folders(sess, vk, jsid, parent_id, account_id=account_id)
        found3 = _find_in_list(items3)
        if found3 is not None:
            log.debug("_get_or_create_folder: creation failed but folder now exists (concurrent): %r → %d", name, found3)
            return found3

        log.warning("_get_or_create_folder: could not find or create folder %r under parent=%s", name, parent_id)
        return 0


# ─────────────────────────────────────────────────────────────────────────────
# Upload
# ─────────────────────────────────────────────────────────────────────────────

def _pre_upload_save_metadata(vk: str, jsid: str, name: str, mime: str, size: int,
                               parent_id: int, media_type: str = "video",
                               account_id=None):
    """Pre-upload save-metadata: registers file on JazzDrive, returns server-assigned GUID.

    Matches Android app upload flow:
      InterfaceC33222a.mo107994a(item) -> POST /sapi/upload/{mediaType}?action=save-metadata
      Response: UploadSaveMetadataResponse -> id (String) = the file GUID

    Body: form-encoded  data=<url-encoded JSON UploadSaveMetadataRequest>
    Response JSON: {"data": {"id": "<guid>", "status": "...", "success": "..."}}

    Returns the file GUID as int, or None on any failure (binary upload will proceed anyway).
    """
    import json as _j
    import urllib.parse as _up
    now_ms = str(int(time.time() * 1000))
    payload = {"data": {
        "name": name,
        "creationdate": now_ms,
        "modificationdate": now_ms,
        "contenttype": mime,
        "size": size,
        "folderid": parent_id,
        "favorite": False,
        "id": None,
        "clientproperties": [],
    }}
    encoded_body = "data=" + _up.quote(_j.dumps(payload))
    try:
        resp = jazzdrive.sapi_request(
            endpoint=f"/upload/{media_type}",
            action="save-metadata",
            method="POST",
            data=encoded_body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            # When account_id is provided let sapi_request load the full
            # token set (incl. raw_accesstoken for Authorization header).
            tokens=None if account_id else {"validationkey": vk, "jsessionid": jsid},
            account_id=account_id,
            timeout=30,
        )
        if resp.get("error"):
            log.debug("_pre_upload_save_metadata: server error %s", resp["error"])
            return None
        d = resp.get("data") or resp
        if isinstance(d, dict):
            guid_str = d.get("id") or d.get("guid") or d.get("fileId")
            if guid_str:
                try:
                    return int(guid_str)
                except (ValueError, TypeError):
                    return None
        return None
    except Exception as e:
        log.debug("_pre_upload_save_metadata failed (non-fatal): %s", e)
        return None


def _upload_file(sess, vk: str, jsid: str,
                 file_path: Path, parent_id: int = 0,
                 max_bps: float = 0,
                 progress_cb: Optional[Callable] = None,
                 cancel_event: Optional[threading.Event] = None,
                 account_id: Optional[int] = None,
                 override_name: Optional[str] = None,
                 forced_proxy: Optional[dict] = None) -> dict:
    """Upload a file using streaming multipart — never buffers the whole file.

    Uses _streaming_multipart() (ported from v1.0) so large files (multi-GB)
    don't exhaust RAM.  Also applies RFC 5987 filename encoding for non-ASCII
    filenames (emoji, Urdu, Arabic) to prevent JazzDrive HTTP 400 errors.

    forced_proxy: if provided, uses this proxy dict instead of resolve_proxies().
    Used by the retry loop to inject a fresh proxy from get_proxy_chain() on each attempt.
    """
    size = file_path.stat().st_size
    ext  = file_path.suffix.lower()
    mime = {"mkv": "video/x-matroska", "avi": "video/x-msvideo",
            "mov": "video/quicktime"}.get(ext.lstrip("."), "video/mp4")

    target_name = override_name or file_path.name
    log.info("JD upload: %s (%.1f MB) → folder %d", target_name,
             size / 1_048_576, parent_id)

    # Pre-upload: register file metadata with JazzDrive to get the GUID.
    # Matches Android flow: mo107994a(item) -> UploadSaveMetadataResponse.id.
    # If successful, we have the real file ID before the binary upload starts.
    _pre_guid = _pre_upload_save_metadata(
        vk, jsid, target_name, mime, size, parent_id,
        account_id=account_id,
    )
    if _pre_guid:
        log.info("JD upload: pre-upload save-metadata assigned GUID=%d", _pre_guid)

    body_gen, ct_header, content_length = _streaming_multipart(
        file_path, mime, parent_id,
        max_bps=max_bps,
        progress_cb=progress_cb,
        cancel_event=cancel_event,
        override_name=target_name
    )

    # Build the upload URL directly — /sapi/upload?action=save is the confirmed endpoint.
    # We bypass sapi_request here because requests adds Transfer-Encoding: chunked when
    # the body is a generator, even when Content-Length is explicitly set. JazzDrive's
    # Jetty server returns HTTP 400 when both headers are present. The fix (ported from
    # the working v1.0 radd_flix.py) is to use prepare_request() then strip the header
    # manually before sending.
    import urllib.parse as _ulp
    vk_q = _ulp.quote(vk, safe="")
    upload_url = (
        f"{CLOUD_BASE}/sapi/upload"
        f"?action=save"
        f"&validationkey={vk_q}"
        f"&acceptasynchronous=true"
        f"&responsetime=true"
    )
    msisdn = None
    raw_accesstoken = None
    if account_id:
        try:
            with db.conn() as _c:
                _row = _c.execute(
                    "SELECT msisdn, raw_accesstoken FROM accounts WHERE id=?",
                    (account_id,)
                ).fetchone()
                if _row:
                    msisdn          = _row["msisdn"]
                    raw_accesstoken = _row["raw_accesstoken"]
        except Exception:
            pass

    hdrs = jazzdrive.get_auth_headers(vk, jsid, msisdn=msisdn, raw_accesstoken=raw_accesstoken)
    hdrs.update({
        "Content-Type":   ct_header,
        "Content-Length": str(content_length),
    })

    import requests as _req2
    prepped = _req2.Request("POST", upload_url, headers=hdrs, data=body_gen).prepare()
    prepped.headers.pop("Transfer-Encoding", None)
    prepped.headers["Content-Length"] = str(content_length)

    with _req2.Session() as _up_sess:
        # Use forced_proxy from retry chain if provided, else pick best from pool
        _sapi_px = forced_proxy if forced_proxy is not None else jazzdrive.resolve_proxies(purpose='sapi')
        _proxy_url_used = ""
        if _sapi_px:
            _proxy_url_used = _sapi_px.get("_url") or _sapi_px.get("https") or _sapi_px.get("http") or ""
        try:
            raw_resp = _up_sess.send(prepped, timeout=_UPLOAD_TIMEOUT,
                                     proxies=_sapi_px if _sapi_px else None)
        except Exception as _conn_err:
            # Network-level failure — immediately demote this proxy so retries skip it
            if _proxy_url_used:
                try:
                    from . import proxy_pool as _pp
                    _pp.pool.mark_fail(_proxy_url_used)
                    log.warning("JD upload: proxy %s connection failed (marked bad): %s",
                                _proxy_url_used, _conn_err)
                except Exception:
                    pass
            raise

    if raw_resp.status_code == 407:
        # Proxy authentication / unreachable — demote it
        if _proxy_url_used:
            try:
                from . import proxy_pool as _pp
                _pp.pool.mark_fail(_proxy_url_used)
            except Exception:
                pass
        raise RuntimeError(f"JD upload HTTP 407: proxy error ({_proxy_url_used})")
    if raw_resp.status_code == 401:
        log.warning("JD upload: 401 — session expired during upload")
        raise RuntimeError("JD upload HTTP 401: session expired")
    if raw_resp.status_code >= 400:
        raise RuntimeError(f"JD upload HTTP {raw_resp.status_code}: {raw_resp.text[:200]}")

    try:
        data = raw_resp.json()
    except Exception:
        if raw_resp.status_code == 200:
            data = {"ok": True}
        else:
            raise RuntimeError(f"JD upload non-JSON response HTTP {raw_resp.status_code}: {raw_resp.text[:200]}")

    if data.get("error"):
        err = data["error"]
        raise RuntimeError(f"JD upload {err.get('code')}: {err.get('message')}")

    if isinstance(data, dict):
        rec = data.get("data") or data
        if isinstance(rec, list):
            rec = rec[0] if rec else {}
        if isinstance(rec, dict):
            fid = rec.get("id") or rec.get("file_id") or rec.get("fileId")
            if not fid:
                meta = rec.get("metadata") or {}
                for media_key in ("videos", "audios", "pictures", "files"):
                    items = meta.get(media_key) or []
                    if items and isinstance(items, list):
                        fid = items[0].get("id")
                        break
            if fid:
                pid = rec.get("parentid") or rec.get("parentId") or parent_id
                return {"id": int(fid), "name": file_path.name,
                        "parent_id": int(pid) if pid else parent_id, "raw": rec}

            # UploadResponse never contains an id field (Android gets it from
            # pre-upload save-metadata; binary upload response only has status/etag/lastupdate).
            # If we got the GUID via pre-upload registration, use it now.
            if _pre_guid:
                log.info("JD upload: using pre-upload GUID=%d (no id in upload response)", _pre_guid)
                return {"id": _pre_guid, "name": file_path.name,
                        "parent_id": parent_id, "raw": rec or {}}

        # Fallback: list parent folder to find file by name.
        # Triggers on any HTTP 200 (UploadResponse has no id field).
        _rec_status = (rec.get("status") or "") if isinstance(rec, dict) else ""
        _upload_ok = (
            data.get("ok")                                 # empty-body 200
            or _rec_status in ("U", "C", "A", "V", "I")  # upload success statuses
            or raw_resp.status_code == 200                 # any HTTP 200
        )
        if _upload_ok:
            log.info("JD upload: no id in response (status=%r) — listing parent folder for id", _rec_status)
            try:
                media_resp = jazzdrive.sapi_request(
                    endpoint="/media/video", action="get",
                    params={"parentId": parent_id},
                    tokens={"validationkey": vk, "jsessionid": jsid},
                    account_id=account_id,
                )
                items = (media_resp.get("data") or []) if isinstance(media_resp, dict) else []
                if isinstance(items, dict):
                    items = items.get("videos") or items.get("files") or []
                target_name = file_path.stem.lower()
                for item in (items if isinstance(items, list) else []):
                    iname = (item.get("name") or item.get("title") or "").lower()
                    if target_name[:20] in iname or iname[:20] in target_name:
                        fid = item.get("id") or item.get("file_id")
                        if fid:
                            return {"id": int(fid), "name": file_path.name,
                                    "parent_id": parent_id, "raw": item}
                # Could not confirm id but upload succeeded (empty 200)
                log.warning("JD upload: file uploaded but id not confirmable via listing — treating as success with id=0")
                return {"id": 0, "name": file_path.name, "parent_id": parent_id, "raw": {}}
            except Exception as _le:
                log.warning("JD upload: listing fallback failed: %s — treating as success", _le)
                return {"id": 0, "name": file_path.name, "parent_id": parent_id, "raw": {}}

    raise RuntimeError(f"JD upload returned no file id: {data!r}")


def _set_file_folder(vk: str, jsid: str, file_id: int, parent_id: int,
                     media_type: str = "video",
                     account_id: Optional[int] = None) -> bool:
    """Explicitly link an uploaded file to its folder via save-metadata.

    Jazz Drive's upload endpoint accepts parentId in the URL but doesn't always
    store that association reliably.  The authoritative method (same as the
    website's 'Move to folder' action) is:
        POST /sapi/upload/<mediatype>?action=save-metadata
        Body: data=<url-encoded JSON>  {"data": {"id": <file_id>, "folderid": <folder_id>}}
    NOTE: the field is "folderid" (lowercase), NOT "parentid".
    Body MUST be form-encoded (data=<url-encoded JSON>), NOT a JSON body.
    Ported directly from the working v1.0 radd_flix.py _set_file_folder().
    """
    if not file_id or file_id == 0:
        return False
    if not parent_id or parent_id <= 0:
        return False
    import json as _json_sf
    import urllib.parse as _up_sf
    payload = {"data": {"id": str(file_id), "folderid": int(parent_id)}}
    encoded_body = "data=" + _up_sf.quote(_json_sf.dumps(payload))
    try:
        data = jazzdrive.sapi_request(
            endpoint=f"/upload/{media_type}",
            action="save-metadata",
            method="POST",
            data=encoded_body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            account_id=account_id,
            tokens={"validationkey": vk, "jsessionid": jsid},
            timeout=30,
        )
        if data.get("error"):
            log.warning("_set_file_folder file=%d folder=%d: %s", file_id, parent_id, data["error"])
            return False
        log.info("_set_file_folder: file %d → folder %d OK (mt=%s)", file_id, parent_id, media_type)
        return True
    except Exception as e:
        log.warning("_set_file_folder error file=%d folder=%d: %s", file_id, parent_id, e)
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Share link
# ─────────────────────────────────────────────────────────────────────────────

def _create_share_link(sess, vk: str, jsid: str, file_id: int,
                        folder_id: Optional[int] = None) -> Optional[str]:
    """Create a public share link for a file.

    Jazz Drive ONLY supports folder-level share links (no /sapi/link/file endpoint exists).
    Strategy: share the folder the file lives in.  If folder_id is not supplied,
    fall back to listing the file's parent from the video list API.
    """
    target_folder: Optional[int] = folder_id

    if target_folder is None:
        try:
            data = jazzdrive.sapi_request(
                endpoint="/media/video",
                action="get",
                tokens={"validationkey": vk, "jsessionid": jsid}
            )
            if not data.get("error"):
                items: list = []
                if isinstance(data, dict):
                    for key in ("data", "videos", "items", "result"):
                        v = data.get(key)
                        if isinstance(v, list):
                            items = v
                            break
                        if isinstance(v, dict):
                            for k2 in ("videos", "items"):
                                if isinstance(v.get(k2), list):
                                    items = v[k2]
                                    break
                elif isinstance(data, list):
                    items = data
                for item in items:
                    if isinstance(item, dict):
                        iid = item.get("id") or item.get("file_id") or item.get("fileId")
                        if iid and int(iid) == file_id:
                            pid = item.get("parentId") or item.get("parentid")
                            if pid:
                                target_folder = int(pid)
                            break
        except Exception as e:
            log.debug("share: video list probe failed: %s", e)

    if target_folder:
        try:
            from ._legacy.jazz_share import get_or_create_folder_share as _gofs
            rec = _gofs(sess, {"validation_key": vk, "jsessionid": jsid}, target_folder)
            url_v = rec.get("share_url") or ""
            if url_v:
                return url_v
        except Exception as e:
            log.debug("share: folder share failed for folder_id=%s: %s", target_folder, e)

    try:
        data = jazzdrive.sapi_request(
            endpoint="/link/folder",
            action="save",
            method="POST",
            json_data={"data": {"folderId": target_folder or 0}},
            tokens={"validationkey": vk, "jsessionid": jsid}
        )
        if not data.get("error"):
            d = data.get("data") if isinstance(data, dict) else data
            if isinstance(d, dict):
                sk = d.get("shareKey") or d.get("sharedKey") or d.get("share_key") or ""
                url_v = d.get("url") or d.get("share_url") or ""
                if sk:
                    return f"{CLOUD_BASE}/f/{sk}"
                if url_v and url_v.startswith("http"):
                    log.debug("share: got URL from data.url for folder %s", target_folder)
                    return url_v
            log.debug("share: folder link response: %s", str(data)[:120])
    except Exception as e:
        log.debug("share: folder link fallback failed: %s", e)

    return None


# ─────────────────────────────────────────────────────────────────────────────
# Storage info
# ─────────────────────────────────────────────────────────────────────────────

def get_storage_info(vk: str, jsid: str) -> dict:
    """Fetch JazzDrive storage quota from /sapi/system/information.

    Returns {used_bytes, total_bytes} on success, or {error: str} on failure.
    """
    if not _REQUESTS_OK or not vk or not jsid:
        return {"error": "no session"}
    try:
        data = jazzdrive.sapi_request(
            endpoint="/system/information",
            action="get",
            tokens={"validationkey": vk, "jsessionid": jsid}
        )
        if data.get("error"):
            return {"error": data["error"].get("message")}
            
        info = data.get("data") if isinstance(data, dict) else data
        if isinstance(info, list) and info:
            info = info[0]
        if isinstance(info, dict):
            for key in ("storageInfo", "storage", "quota"):
                s = info.get(key)
                if isinstance(s, dict):
                    used  = (s.get("usedBytes")  or s.get("used_bytes")  or s.get("used")  or 0)
                    total = (s.get("totalBytes") or s.get("total_bytes") or s.get("total") or 0)
                    return {"used_bytes": int(used), "total_bytes": int(total)}
        return {"used_bytes": 0, "total_bytes": 0}
    except Exception as e:
        return {"error": str(e)[:120]}


# ─────────────────────────────────────────────────────────────────────────────
# Remote media listing
# ─────────────────────────────────────────────────────────────────────────────

def list_remote_media(vk: str, jsid: str, media_type: str = "", parent_id: int = 0) -> list:
    """List remote JazzDrive media items of the given type."""
    if not _REQUESTS_OK or not vk or not jsid:
        return []
    try:
        action = "getvideos" if not media_type or media_type == "video" else "get"
        data = jazzdrive.sapi_request(
            endpoint=f"/media/{media_type or 'video'}",
            action=action,
            params={"parentId": parent_id},
            tokens={"validationkey": vk, "jsessionid": jsid}
        )
        if data.get("error"):
            return []
        items: list = []
        if isinstance(data, dict):
            for key in ("data", "items", "files", "videos", "result"):
                v = data.get(key)
                if isinstance(v, list):
                    items = v
                    break
        elif isinstance(data, list):
            items = data
        return items
    except Exception as e:
        log.debug("list_remote_media: %s", e)
        return []


# ─────────────────────────────────────────────────────────────────────────────
# Manual upload jobs
# ─────────────────────────────────────────────────────────────────────────────

_jobs_lock = threading.Lock()
_manual_jobs: dict = {}  # job_id → job dict

# ── Live stats for DB-queue uploads (keyed by file_id) ──
_LIVE_STATS: dict = {}
_LIVE_STATS_LOCK = threading.Lock()

def _update_live_stat(file_id: int, bytes_done: int, total: int, proxy_url: str = ""):
    import time as _t
    now = _t.time()
    with _LIVE_STATS_LOCK:
        prev = _LIVE_STATS.get(file_id, {})
        prev_bytes = prev.get("bytes_done", 0)
        prev_time  = prev.get("updated_at", now)
        dt = now - prev_time
        db_bytes = bytes_done - prev_bytes
        if dt > 0.5 and db_bytes > 0:
            instant_bps = db_bytes / dt
            old_bps = prev.get("speed_bps", 0)
            speed = old_bps * 0.7 + instant_bps * 0.3 if old_bps else instant_bps
        else:
            speed = prev.get("speed_bps", 0)
        remaining = max(0, total - bytes_done)
        eta_s = int(remaining / speed) if speed > 100 else None
        _LIVE_STATS[file_id] = {
            "speed_bps": round(speed),
            "eta_s":     eta_s,
            "bytes_done": bytes_done,
            "total":      total,
            "proxy_url":  proxy_url or prev.get("proxy_url", ""),
            "updated_at": now,
        }

def get_live_stat(file_id: int) -> dict:
    with _LIVE_STATS_LOCK:
        return dict(_LIVE_STATS.get(file_id, {}))

def clear_live_stat(file_id: int):
    with _LIVE_STATS_LOCK:
        _LIVE_STATS.pop(file_id, None)


def update_manual_job(job_id: str, **fields) -> None:
    with _jobs_lock:
        job = _manual_jobs.get(job_id)
        if not job:
            return
        job.update(fields)


def queue_manual_upload(file_path: str, parent_id: int = 0,
                        account_id: Optional[int] = None) -> dict:
    """Queue a manual upload and run it in a background thread."""
    import uuid as _uuid2
    job_id = _uuid2.uuid4().hex[:10]
    now = int(time.time())
    fp_str = str(file_path)
    with _jobs_lock:
        _manual_jobs[job_id] = {
            "id":         job_id,
            "path":       fp_str,
            "state":      "queued",
            "uploaded":   0,
            "total":      0,
            "percent":    0,
            "error":      None,
            "started_at": now,
            "share_url":  None,
        }

    def _progress(sent: int, total: int):
        with _jobs_lock:
            if job_id in _manual_jobs:
                _manual_jobs[job_id]["uploaded"] = sent
                _manual_jobs[job_id]["total"]    = total
                _manual_jobs[job_id]["percent"]  = round(sent / total * 100, 1) if total else 0

    def _run():
        with _jobs_lock:
            if job_id in _manual_jobs:
                _manual_jobs[job_id]["state"] = "uploading"
        try:
            result = upload_to_jazzdrive(
                Path(fp_str),
                account_id=account_id,
                job_id=job_id,
                auto_delete=False,
                log_fn=lambda msg: update_manual_job(job_id, detail=msg),
            )
            with _jobs_lock:
                if job_id in _manual_jobs:
                    if result.get("ok"):
                        _manual_jobs[job_id]["state"]     = "done"
                        _manual_jobs[job_id]["percent"]   = 100
                        _manual_jobs[job_id]["share_url"] = result.get("share_url")
                        _manual_jobs[job_id]["uploaded"]  = _manual_jobs[job_id].get("total") or _manual_jobs[job_id].get("uploaded") or 0
                    else:
                        _manual_jobs[job_id]["state"] = "failed"
                        _manual_jobs[job_id]["error"] = result.get("error", "unknown")
        except Exception as e:
            with _jobs_lock:
                if job_id in _manual_jobs:
                    _manual_jobs[job_id]["state"] = "failed"
                    _manual_jobs[job_id]["error"] = str(e)[:200]

    t = threading.Thread(target=_run, daemon=True, name=f"manual-upload-{job_id}")
    t.start()
    return {"ok": True, "job_id": job_id}


def get_manual_jobs(limit: int = 50) -> list:
    """Return recent manual upload jobs sorted newest first."""
    with _jobs_lock:
        jobs = sorted(_manual_jobs.values(), key=lambda j: j["started_at"], reverse=True)
        return list(jobs[:limit])


# ─────────────────────────────────────────────────────────────────────────────
# High-level entry point
# ─────────────────────────────────────────────────────────────────────────────

def upload_to_jazzdrive(
    file_path: Path,
    *,
    account_id: Optional[int] = None,
    movie_title: Optional[str] = None,
    job_id: Optional[str] = None,
    log_fn=None,
    auto_delete: bool = True,
) -> dict:
    """
    Full pipeline: validate session → upload → share → DB record → local delete.
    Returns dict with keys: ok, remote_id, share_url, deleted, error.
    """
    def _log(msg: str):
        log.info("[uploader] %s", msg)
        if log_fn:
            log_fn(msg)

    if not _REQUESTS_OK:
        return {"ok": False, "error": "requests library not available"}

    file_path = Path(file_path)
    if not file_path.exists():
        return {"ok": False, "error": f"File not found: {file_path}"}
    if job_id:
        try:
            update_manual_job(job_id, state="uploading", total=file_path.stat().st_size)
        except Exception:
            pass

    # Pick account — respect role='flix' priority via get_active_account()
    try:
        if account_id:
            with db.conn() as c:
                row = c.execute("SELECT * FROM accounts WHERE id=? AND is_active=1",
                                (account_id,)).fetchone()
            if not row:
                return {"ok": False, "error": "No active JazzDrive account configured"}
            acct = dict(row)
        else:
            acct = get_active_account()
            if not acct:
                return {"ok": False, "error": "No active JazzDrive account configured"}
    except Exception as e:
        return {"ok": False, "error": f"DB error reading account: {e}"}

    vk   = acct.get("validation_key") or ""
    jsid = acct.get("jsessionid") or ""
    aid  = acct["id"]

    if not vk or not jsid:
        return {"ok": False,
                "error": "JazzDrive account has no session tokens — "
                         "re-login via Settings → JazzDrive Scan → Send OTP."}

    sess = _requests.Session()
    _sapi_px2 = jazzdrive.resolve_proxies(purpose='sapi')
    if _sapi_px2:
        sess.proxies.update(_sapi_px2)

    # Validate session
    _log(f"Checking JazzDrive session for account '{acct.get('label','?')}'…")
    if not verify_jd_session(vk, jsid, account_id=aid):
        return {"ok": False,
                "error": "JazzDrive session expired — "
                         "re-login via Settings → JazzDrive Scan → Send OTP."}
    
    # Re-fetch tokens from DB in case they were transparently rotated by sapi_request
    try:
        with db.conn() as _c3:
            _row3 = _c3.execute("SELECT validation_key, jsessionid FROM accounts WHERE id=?", (aid,)).fetchone()
            if _row3:
                vk = _row3["validation_key"]
                jsid = _row3["jsessionid"]
    except Exception:
        pass

    # Anti-double-upload: check if this file is already queued/in-progress in the
    # watcher queue (is_ready=0 or is_ready=-2).  If so, atomically claim it as
    # in-progress so _upload_pending won't race us.  If not already queued, insert
    # a new in-progress record so _scan_once won't queue it while we're uploading.
    # ── Strict Validations (User Request) ───────────────────────────────
    # 1. Size Limit: No file > 1.98 GB (to avoid split/failure issues)
    file_size_pre = file_path.stat().st_size
    MAX_SIZE = 1.98 * 1024**3
    if file_size_pre > MAX_SIZE:
        _log(f"Validation Error: File {file_path.name} is too large ({file_size_pre / 1024**3:.2f}GB). Max limit is 1.98GB.")
        return {"ok": False, "error": "File too large (> 1.98GB). Please split manually or use extraction."}
    
    # 2. Format Limit: Media files only — no ZIPs, PDFs, TXTs, images, etc.
    _upload_ext = file_path.suffix.lower()
    if _upload_ext in _NON_MEDIA_EXTENSIONS or _upload_ext in _ALWAYS_SKIP_EXT_MN:
        _log(f"Validation Error: Rejected non-media upload: {file_path.name} ({_upload_ext})")
        return {"ok": False, "error": f"Non-media file rejected ({_upload_ext}). Only video/audio/subtitle files are allowed."}
    
    # 3. Fingerprint claim...
    fp_claim = _fingerprint_file(file_path)
    fingerprint_key_claim = "upl:" + fp_claim
    _claimed_file_id: Optional[int] = None
    
    # --- Media Plan & Naming (Unified) ---
    from . import media_naming as _mn
    _plan = _mn.derive_media_plan(file_path.name)
    target_filename = _plan.filename
    
    # Use the movie_title hint to refine the title if provided (e.g. for batch uploads)
    if movie_title and len(movie_title) > 5 and not _plan.title:
         _plan.title = movie_title
         # Re-derive plan with better title hint if kind was unknown
         _plan = _mn.derive_media_plan(file_path.name)
         target_filename = _plan.filename

    try:
        with db.conn() as _cc:
            existing_row = _cc.execute(
                "SELECT id, is_ready FROM files WHERE local_path=? OR fingerprint=? LIMIT 1",
                (str(file_path), fingerprint_key_claim)
            ).fetchone()
            if existing_row and existing_row["is_ready"] == 1:
                # Already fully uploaded — skip
                _log(f"File already recorded as uploaded — skipping duplicate upload")
                return {"ok": False, "error": "Already uploaded (duplicate)"}
            if existing_row and existing_row["is_ready"] in (-2,):
                # Another thread is already uploading this — skip
                _log(f"File is already being uploaded — skipping duplicate")
                return {"ok": False, "error": "Already uploading (duplicate)"}
            if existing_row and existing_row["is_ready"] == 0:
                # Watcher queued it — claim it so _upload_pending won't race us
                claimed = _cc.execute(
                    "UPDATE files SET is_ready=-2 WHERE id=? AND is_ready=0",
                    (existing_row["id"],)
                ).rowcount
                if claimed:
                    _claimed_file_id = existing_row["id"]
            else:
                # Not in queue — insert an in-progress placeholder
                _claimed_file_id = db.upsert_file({
                    "fingerprint":  fingerprint_key_claim,
                    "source":       "upload",
                    "account_id":   aid,
                    "filename":     target_filename,
                    "local_path":   str(file_path),
                    "size_bytes":   file_size_pre,
                    "uploaded_at":  int(time.time()),
                    "is_ready":     -2,
                })
    except Exception as _ce:
        log.debug("upload_to_jazzdrive: DB claim failed (non-fatal): %s", _ce)

    def _unclaim():
        """Reset in-progress claim back to pending on any failure path."""
        if _claimed_file_id:
            try:
                with db.conn() as _uc:
                    _uc.execute(
                        "UPDATE files SET is_ready=0 WHERE id=? AND is_ready=-2",
                        (_claimed_file_id,)
                    )
            except Exception:
                pass

    # --- Folder Creation (Respecting MediaPlan hierarchy) ---
    current_parent = 0
    for folder_name in _plan.folder_path:
        _log(f"Ensuring /{folder_name}/ folder on JazzDrive…")
        current_parent = _get_or_create_folder(
            sess, vk, jsid, folder_name, parent_id=current_parent, account_id=aid
        ) or current_parent
    
    folder_id = current_parent

    # -- JazzDrive-side duplicate check ----------------------------------------
    # Before uploading, query JazzDrive live to see if target_filename already
    # exists in the resolved folder. JazzDrive silently renames duplicates to
    # "filename (1).mp4" -- this guard prevents that from ever happening.
    # Covers the case where: DB was reset between uploads, file was auto-deleted
    # after first upload, or the scan fingerprint does not match the upl: hash.
    if folder_id:
        try:
            _jd_check = jazzdrive.sapi_request(
                endpoint="/media/video",
                action="get",
                params={"parentId": folder_id, "folderId": folder_id},
                account_id=aid,
                tokens=None,
            )
            _jd_items = (_jd_check.get("data") or {}).get("videos") or []
            _target_lower = target_filename.lower()
            for _jd_item in _jd_items:
                _jd_folder = _jd_item.get("folder")
                if _jd_folder is not None and int(_jd_folder) != int(folder_id):
                    continue
                _jd_name = (_jd_item.get("name") or "").lower()
                _jd_softdel = _jd_item.get("softdeleted", False)
                if _jd_name == _target_lower and not _jd_softdel:
                    _exist_id = int(_jd_item["id"])
                    _log(
                        "JazzDrive duplicate guard: %r already exists in folder %s "
                        "as remote_id=%s -- skipping upload." % (target_filename, folder_id, _exist_id)
                    )
                    _exist_share = None
                    try:
                        _exist_share = _create_share_link(
                            sess, vk, jsid, _exist_id, folder_id=folder_id
                        )
                    except Exception as _sl_err:
                        log.debug("duplicate-guard share link failed: %s", _sl_err)
                    try:
                        _dup_rows = 0
                        if _claimed_file_id:
                            with db.conn() as _dc:
                                _dup_rows = _dc.execute(
                                    "UPDATE files SET is_ready=1, remote_id=?, share_url=?,"
                                    " remote_folder_id=?, fingerprint=?, uploaded_at=? WHERE id=?",
                                    (str(_exist_id), _exist_share or "", folder_id,
                                     "scan:" + str(_exist_id), int(time.time()), _claimed_file_id),
                                ).rowcount
                        if not _claimed_file_id or _dup_rows == 0:
                            if _dup_rows == 0 and _claimed_file_id:
                                log.warning(
                                    "duplicate-guard: UPDATE hit 0 rows for file_id=%s"
                                    " (row deleted by restart?) — falling back to upsert",
                                    _claimed_file_id,
                                )
                            db.upsert_file({
                                "fingerprint":      "scan:" + str(_exist_id),
                                "source":           "upload",
                                "account_id":       aid,
                                "filename":         target_filename,
                                "local_path":       str(file_path),
                                "size_bytes":       file_path.stat().st_size,
                                "remote_id":        str(_exist_id),
                                "remote_folder_id": folder_id,
                                "share_url":        _exist_share or "",
                                "uploaded_at":      int(time.time()),
                                "is_ready":         1,
                            })
                    except Exception as _db_err:
                        log.warning("duplicate-guard DB update failed: %s", _db_err)
                    _unclaim()
                    return {
                        "ok": True,
                        "skipped": True,
                        "reason": "already_on_jazzdrive",
                        "remote_id": _exist_id,
                        "share_url": _exist_share or "",
                    }
        except Exception as _jd_err:
            log.debug(
                "JazzDrive duplicate pre-check failed (non-fatal, upload continues): %s", _jd_err
            )

    # Load upload config (bandwidth limit, retries, etc.)
    upload_cfg = _load_upload_cfg()
    max_bps = (upload_cfg["bandwidth_limit_mbps"] * 1_000_000 / 8
               if upload_cfg["bandwidth_limit_mbps"] > 0 else 0)

    # Check file extension skip list
    ext = file_path.suffix.lower()
    if ext in ALWAYS_SKIP_EXTENSIONS:
        _unclaim()
        return {"ok": False, "error": f"Skipped — extension {ext!r} always skipped"}
    skip_exts = {e.lower() if e.startswith(".") else "." + e.lower()
                 for e in upload_cfg.get("skip_extensions", [])}
    if ext in skip_exts:
        _unclaim()
        return {"ok": False, "error": f"Skipped — extension {ext!r} in skip list"}

    # Check file size limit
    file_size = file_path.stat().st_size
    max_size_bytes = int(upload_cfg["max_file_size_gb"] * 1024 ** 3)
    if max_size_bytes > 0 and file_size > max_size_bytes:
        _unclaim()
        return {"ok": False,
                "error": f"File too large: {file_size / 1024**3:.2f} GB "
                         f"(limit: {upload_cfg['max_file_size_gb']} GB)"}

    _log(f"Uploading {target_filename} "
         f"({file_size / 1_048_576:.1f} MB) to JazzDrive…")

    # Upload with proxy-chain retry
    # On each attempt a DIFFERENT proxy from the pool is used — if a proxy dies
    # mid-upload it is immediately marked bad and the next best proxy takes over.
    max_retries = max(1, int(upload_cfg.get("max_retries", 3)))
    retry_delay = float(upload_cfg.get("retry_base_delay", 2))
    last_err: Optional[Exception] = None
    up = None

    # Pre-fetch ordered proxy chain so each retry uses a fresh, ranked proxy
    _proxy_chain: list = []
    try:
        from . import proxy_pool as _pp
        _proxy_chain = _pp.pool.get_proxy_chain(n=max(max_retries + 2, 5))
    except Exception:
        pass  # No pool available — _upload_file will call resolve_proxies() itself

    for attempt in range(1, max_retries + 1):
        # Inject a different proxy per attempt (None = let _upload_file pick from pool)
        _forced_px = _proxy_chain[attempt - 1] if (attempt - 1) < len(_proxy_chain) else None
        _px_label  = _forced_px.get("_url", "?") if _forced_px else "pool-default"
        try:
            up = _upload_file(sess, vk, jsid, file_path, parent_id=folder_id,
                              max_bps=max_bps, account_id=aid,
                              override_name=target_filename,
                              forced_proxy=_forced_px)
            if attempt > 1:
                _log(f"Upload succeeded on attempt {attempt}/{max_retries} "
                     f"via proxy {_px_label}")
            break
        except Exception as e:
            last_err = e
            if attempt < max_retries:
                _log(f"Upload attempt {attempt}/{max_retries} failed "
                     f"(proxy: {_px_label}): {e} — switching proxy, "
                     f"retrying in {retry_delay}s…")
                time.sleep(retry_delay)
            else:
                _log(f"Upload attempt {attempt}/{max_retries} failed "
                     f"(proxy: {_px_label}): {e} — no more retries.")

    if up is None:
        _unclaim()
        return {"ok": False, "error": f"Upload failed after {max_retries} attempt(s): {last_err}"}

    remote_id = up["id"]
    _log(f"Upload OK — remote_id={remote_id}")

    # Force folder association (save-metadata) — the upload URL includes parentId but
    # JazzDrive doesn't always honour it.  This explicit call guarantees the file lands
    # in the right folder.
    if remote_id and remote_id != 0:
        _set_file_folder(vk, jsid, remote_id, folder_id, account_id=aid)

    # Defense in depth: explicitly rename to clean name on JazzDrive.
    # JazzDrive async uploads can ignore the multipart filename; this guarantees
    # the file is stored with the clean name regardless of upload path used.
    if remote_id and remote_id != 0 and target_filename:
        try:
            jazzdrive.rename_video(aid, remote_id, target_filename, folder_id=folder_id)
            _log(f"JD rename OK: {target_filename}")
        except Exception as _rn_err:
            log.warning("JD post-upload rename failed (non-fatal): %s", _rn_err)

    # Share link — pass the folder we uploaded into so Jazz Drive can share it
    _log("Creating public share link…")
    upload_folder_id = up.get("parent_id") or folder_id or None
    share_url = _create_share_link(sess, vk, jsid, remote_id, folder_id=upload_folder_id)
    if share_url:
        _log(f"Share URL: {share_url}")
    else:
        _log("Warning: file uploaded but share link could not be created")

    # DB — update the claimed in-progress record to completed, or upsert fresh.
    file_db_id: Optional[int] = _claimed_file_id
    try:
        # Trigger metadata enrichment
        from . import metadata, assets, keys
        title_id = None
        
        tmdb_key = keys.get_active_value("tmdb")
        omdb_key = keys.get_active_value("omdb")
        
        # Derive initial meta from filename
        plan = _mn.derive_media_plan(file_path.name)
        initial_meta = {
            "title": plan.title or file_path.stem,
            "year": plan.year,
            "media_type": plan.kind or "movie",
        }
        
        # Always enrich — IMDbAPI.dev (free/no-key) covers Pakistani/South Asian content;
        # AI fallback covers anything else; TMDB/OMDB used when keys are available.
        initial_meta.setdefault("is_published", 1)
        enriched = metadata.enrich_title(initial_meta, tmdb_key=tmdb_key, omdb_key=omdb_key)
        title_id = db.upsert_title(enriched)
        if title_id:
            if enriched.get("poster"):
                assets.process_title_poster(title_id, enriched["poster"], aid, folder_id=folder_id)

        if _claimed_file_id:
            with db.conn() as _dc:
                _dc.execute(
                    "UPDATE files SET is_ready=1, title_id=?, remote_id=?, share_url=?, "
                    "account_id=?, remote_folder_id=?, uploaded_at=?, "
                    "fingerprint=?, size_bytes=?, season=?, episode=? WHERE id=?",
                    (title_id, str(remote_id), share_url or "", aid, folder_id,
                     int(time.time()), fingerprint_key_claim,
                     file_path.stat().st_size, _plan.season, _plan.episode, _claimed_file_id),
                )
            _log(f"DB files record updated — id={file_db_id}")
        else:
            file_db_id = db.upsert_file({
                "fingerprint":      fingerprint_key_claim,
                "title_id":         title_id,
                "source":           "upload",
                "account_id":       aid,
                "filename":         plan.filename,
                "local_path":       str(file_path),
                "size_bytes":       file_path.stat().st_size,
                "remote_id":        remote_id,
                "remote_folder_id": folder_id,
                "share_url":        share_url or "",
                "uploaded_at":      int(time.time()),
                "is_ready":         1,
            })
            _log(f"DB files record created — id={file_db_id}")

        # Trigger GitHub + Sheets mirror sync
        if file_db_id:
            mirror.push_file_async(file_db_id)
    except Exception as e:
        log.warning("DB upsert_file failed: %s", e)

    # Link file to title if we know the movie title
    if movie_title and file_db_id:
        try:
            with db.conn() as c:
                title_row = c.execute(
                    "SELECT id FROM titles WHERE title LIKE ? LIMIT 1",
                    (f"%{movie_title.split('(')[0].strip()}%",)
                ).fetchone()
                if title_row:
                    c.execute("UPDATE files SET title_id=? WHERE id=?",
                              (title_row["id"], file_db_id))
        except Exception:
            pass

    # Update queue URL with share link
    if job_id and share_url:
        try:
            with db.conn() as c:
                c.execute("UPDATE queue SET url=? WHERE job_id=?", (share_url, job_id))
        except Exception:
            pass

    deleted = False
    delete_error = None
    if auto_delete:
        if share_url:
            try:
                file_path.unlink()
                deleted = True
                _log(f"Local file deleted after successful upload: {file_path.name}")
                if file_db_id:
                    with db.conn() as c:
                        c.execute("UPDATE files SET local_path=NULL WHERE id=?", (file_db_id,))
            except Exception as e:
                delete_error = str(e)
                _log(f"Warning: could not delete local file: {e}")
        else:
            delete_error = "share link was not created"
            _log("Warning: auto-delete skipped because share link was not created")

    return {
        "ok":         True,
        "remote_id":  remote_id,
        "share_url":  share_url,
        "deleted":    deleted,
        "delete_error": delete_error,
        "file_db_id": file_db_id,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Legacy watch-folder scanner (kept for compatibility / trigger_scan_now())
# ─────────────────────────────────────────────────────────────────────────────

def _fingerprint_file(p: Path, max_attempts: int = 3, retry_delay: float = 2.0) -> str:
    """SHA-1 fingerprint of path + size.  Retries on PermissionError (Windows
    file locks) — ported from v1.0 radd_flix.py file_fingerprint()."""
    last_exc: Optional[Exception] = None
    for attempt in range(1, max_attempts + 1):
        try:
            h = hashlib.sha1()
            h.update(str(p.resolve()).encode("utf-8"))
            h.update(str(p.stat().st_size).encode())
            return h.hexdigest()[:24]
        except PermissionError as exc:
            last_exc = exc
            if attempt < max_attempts:
                log.debug(
                    "_fingerprint_file: PermissionError for %s (attempt %d/%d), "
                    "retrying in %.1fs …", p.name, attempt, max_attempts, retry_delay)
                time.sleep(retry_delay)
        except Exception:
            raise
    raise last_exc  # type: ignore[misc]


_seen: set[str] = set()
_seen_lock = threading.Lock()


def _scan_once(account_id: Optional[int] = None) -> int:
    """One pass over MEDIA_DIR; record any new files in the DB as upload-pending.

    Guards against duplicate records across restarts by checking the DB for the
    fingerprint AND the local_path before inserting a new row.  The in-memory
    ``_seen`` set is only a fast-path optimisation for within-process dedup.
    """
    config.ensure_dirs()
    n = 0
    for p in config.MEDIA_DIR.rglob("*"):
        if not p.is_file():
            continue
        if p.name.startswith(".") or p.name.endswith((".part", ".aria2", ".tmp")):
            continue
        fp = _fingerprint_file(p)
        fingerprint_key = "upl:" + fp
        with _seen_lock:
            if fp in _seen:
                continue
            _seen.add(fp)
        # DB-level dedup: skip if a record for this path already exists
        try:
            with db.conn() as _c:
                existing = _c.execute(
                    "SELECT id, is_ready FROM files WHERE local_path=? OR fingerprint=? LIMIT 1",
                    (str(p), fingerprint_key)
                ).fetchone()
            if existing:
                # If it's stuck as a ghost (is_ready=1 but no remote_id/share_url),
                # the batch reset above handles that; don't create another duplicate.
                log.debug("scan: skipping already-known file %s (db id=%s is_ready=%s)",
                          p.name, existing["id"], existing["is_ready"])
                continue
        except Exception as _dbe:
            log.debug("scan: DB check failed for %s: %s", p.name, _dbe)
        try:
            file_id = db.upsert_file({
                "fingerprint":  fingerprint_key,
                "source":       "upload",
                "account_id":   account_id,
                "filename":     p.name,
                "local_path":   str(p),
                "size_bytes":   p.stat().st_size,
                "uploaded_at":  int(time.time()),
                "is_ready":     0,
            })
            n += 1
            log.info("scan: queued for upload: %s (file_id=%s)", p.name, file_id)
        except Exception as e:
            log.warning("scan: queue upload failed for %s: %s", p, e)
    return n


def _release_pending(file_id: int) -> None:
    """Reset a file that was atomically claimed (is_ready=-2) back to pending (is_ready=0).

    Called from every early-exit path in _upload_pending so the file can be
    retried on the next watcher tick instead of being stuck forever.
    """
    try:
        with db.conn() as c:
            c.execute("UPDATE files SET is_ready=0 WHERE id=? AND is_ready=-2", (file_id,))
    except Exception as _e:
        log.warning("_release_pending: %s", _e)


def _upload_pending() -> None:
    """Upload one pending file (is_ready=0) from the DB queue to JazzDrive.

    Called from watcher_loop on every tick. Picks the oldest pending file,
    atomically claims it as is_ready=-2 (in-progress), uploads it, creates a
    share link, updates the DB, and optionally deletes the local copy.
    Early-exit paths always call _release_pending() so no file gets stuck.
    """
    import requests as _req

    # Atomically claim the oldest pending file — prevents race between watcher ticks.
    file_rec: Optional[dict] = None
    try:
        with db.conn() as c:
            row = c.execute(
                "SELECT * FROM files WHERE is_ready=0 ORDER BY id LIMIT 1"
            ).fetchone()
            if not row:
                return
            claimed = c.execute(
                "UPDATE files SET is_ready=-2 WHERE id=? AND is_ready=0",
                (row["id"],)
            ).rowcount
            if claimed == 0:
                return
            file_rec = dict(row)
    except Exception as e:
        log.warning("_upload_pending DB claim: %s", e)
        return

    file_id = file_rec["id"]

    file_path = Path(file_rec.get("local_path") or "")
    if not file_path.exists():
        log.warning("upload_pending: file not found: %s — marking skipped", file_path)
        try:
            with db.conn() as c:
                c.execute("UPDATE files SET is_ready=-1 WHERE id=?", (file_id,))
        except Exception:
            pass
        return

    acct = get_active_account()
    if not acct:
        log.debug("upload_pending: no active JD account with tokens — releasing")
        _release_pending(file_id)
        return

    vk   = acct.get("validation_key", "")
    jsid = acct.get("jsessionid", "")

    if not verify_jd_session(vk, jsid, account_id=acct["id"]):
        aid_for_backoff = acct["id"]
        # Check both the uploader-level backoff AND jazzdrive's sapi_request backoff.
        # sapi_request marks _SAPI_BACKOFF when verify_jd_session's internal call gets
        # 401 — so we can short-circuit here without another 8-call refresh attempt.
        _jd_backed_off = False
        try:
            _jd_backed_off = jazzdrive._is_sapi_backed_off(aid_for_backoff)
        except Exception:
            pass
        if _is_refresh_backed_off(aid_for_backoff) or _jd_backed_off:
            log.debug("upload_pending: account %s in OTP backoff — skipping refresh", aid_for_backoff)
            _release_pending(file_id)
            return
        log.info("upload_pending: JD session expired — attempting silent refresh...")
        try:
            result = jazzdrive.refresh_session(account_id=acct["id"])
            if result.get("ok"):
                log.info("upload_pending: session refreshed — re-fetching tokens")
                acct = get_active_account()
                if not acct:
                    log.warning("upload_pending: no active account after refresh — releasing")
                    _release_pending(file_id)
                    return
                vk   = acct.get("validation_key", "")
                jsid = acct.get("jsessionid", "")
                if not verify_jd_session(vk, jsid, account_id=acct["id"]):
                    log.warning("upload_pending: session still invalid after refresh — releasing")
                    _release_pending(file_id)
                    return
            else:
                err_msg = result.get("error", "")
                log.warning("upload_pending: refresh failed (%s) — releasing", err_msg)
                if "otp" in err_msg.lower() or "401" in err_msg or "unauthorized" in err_msg.lower():
                    _mark_refresh_backed_off(aid_for_backoff)
                _release_pending(file_id)
                return
        except Exception as _re:
            log.warning("upload_pending: refresh exception: %s — releasing", _re)
            _release_pending(file_id)
            return
    else:
        # Re-fetch anyway in case tokens were rotated during verify_jd_session's internal call
        try:
            with db.conn() as _c5:
                _row5 = _c5.execute("SELECT validation_key, jsessionid FROM accounts WHERE id=?", (acct["id"],)).fetchone()
                if _row5:
                    vk = _row5["validation_key"]
                    jsid = _row5["jsessionid"]
        except Exception:
            pass

    sess = _req.Session()
    _sapi_px3 = jazzdrive.resolve_proxies(purpose='sapi')
    if _sapi_px3:
        sess.proxies.update(_sapi_px3)
    upload_cfg = _load_upload_cfg()
    try:
        from . import media_naming

        plan = media_naming.derive_media_plan(file_path.name)
        
        # --- Unified Folder Creation (Respecting MediaPlan hierarchy) ---
        current_parent = 0
        for folder_name in plan.folder_path:
            log.info("upload_pending: Ensuring /%s/ folder...", folder_name)
            current_parent = _get_or_create_folder(
                sess, vk, jsid, folder_name, parent_id=current_parent, account_id=acct["id"]
            ) or current_parent
        
        folder_id = current_parent

        # -- JazzDrive-side duplicate guard (mirrors upload_to_jazzdrive guard) -----
        # _upload_file() is called directly here and bypasses the guard in
        # upload_to_jazzdrive(). This check prevents uploading a movie or episode
        # that already exists in the resolved JazzDrive folder under the same filename.
        # Covers: DB resets, scan fingerprint mismatch, re-queued files after failure.
        if folder_id:
            try:
                _jd_dup_check = jazzdrive.sapi_request(
                    endpoint="/media/video",
                    action="get",
                    params={"parentId": folder_id, "folderId": folder_id},
                    account_id=acct["id"],
                    tokens=None,
                )
                _jd_dup_items = (_jd_dup_check.get("data") or {}).get("videos") or []
                _dup_target_lower = plan.filename.lower()
                for _jd_dup_item in _jd_dup_items:
                    _dup_folder = _jd_dup_item.get("folder")
                    if _dup_folder is not None and int(_dup_folder) != int(folder_id):
                        continue
                    _dup_name = (_jd_dup_item.get("name") or "").lower()
                    if _dup_name == _dup_target_lower and not _jd_dup_item.get("softdeleted", False):
                        _dup_exist_id = int(_jd_dup_item["id"])
                        log.info(
                            "upload_pending: JD duplicate guard: %r already in folder %d "
                            "as remote_id=%d — skipping upload, recording existing file.",
                            plan.filename, folder_id, _dup_exist_id,
                        )
                        _dup_share = None
                        try:
                            _dup_share = _create_share_link(
                                sess, vk, jsid, _dup_exist_id, folder_id=folder_id
                            )
                        except Exception as _dup_sl_err:
                            log.debug("upload_pending dup-guard share link failed: %s", _dup_sl_err)
                        try:
                            _dup_rows = 0
                            if file_id:
                                with db.conn() as _dup_dc:
                                    _dup_rows = _dup_dc.execute(
                                        "UPDATE files SET is_ready=1, remote_id=?, share_url=?,"
                                        " remote_folder_id=?, fingerprint=?, uploaded_at=? WHERE id=?",
                                        (str(_dup_exist_id), _dup_share or "", folder_id,
                                         "scan:" + str(_dup_exist_id), int(time.time()), file_id),
                                    ).rowcount
                            if not file_id or _dup_rows == 0:
                                if _dup_rows == 0 and file_id:
                                    log.warning(
                                        "upload_pending dup-guard: UPDATE hit 0 rows for"
                                        " file_id=%s (row missing after restart?) — falling back to upsert",
                                        file_id,
                                    )
                                db.upsert_file({
                                    "fingerprint":      "scan:" + str(_dup_exist_id),
                                    "source":           "upload",
                                    "account_id":       acct["id"],
                                    "filename":         plan.filename,
                                    "season":           plan.season,
                                    "episode":          plan.episode,
                                    "remote_id":        str(_dup_exist_id),
                                    "remote_folder_id": folder_id,
                                    "share_url":        _dup_share or "",
                                    "uploaded_at":      int(time.time()),
                                    "is_ready":         1,
                                })
                        except Exception as _dup_db_err:
                            log.warning("upload_pending dup-guard DB update failed: %s", _dup_db_err)
                        clear_live_stat(file_id)
                        return  # already on JazzDrive — no local delete, no upload
            except Exception as _jd_dup_err:
                log.debug(
                    "upload_pending: JD duplicate pre-check failed (non-fatal, upload continues): %s",
                    _jd_dup_err,
                )

        # Get proxy URL for live stats tracking
        _active_proxy = (sess.proxies or {}).get("https", "")
        def _prog_cb(sent, total):
            _update_live_stat(file_id, sent, total, _active_proxy)
        resp = _upload_file(sess, vk, jsid, file_path, parent_id=folder_id, account_id=acct["id"],
                              override_name=plan.filename, progress_cb=_prog_cb)
        remote_id = resp.get("id")

        if remote_id is None:
            raise RuntimeError(f"JD upload returned no file id: {resp!r}")

        confirmed_remote_id = remote_id
        if remote_id == 0:
            log.info("upload_pending: empty-body 200 — file received (async indexing). Proceeding.")

        # Force folder association
        if confirmed_remote_id and confirmed_remote_id != 0:
            _set_file_folder(vk, jsid, confirmed_remote_id, folder_id, account_id=acct["id"])

        # Defense in depth: explicitly rename to canonical name on JazzDrive.
        # JazzDrive async uploads can ignore the multipart filename; this guarantees
        # the file is stored with the plan filename regardless of upload path used.
        # (Mirrors the rename block in upload_to_jazzdrive().)
        if confirmed_remote_id and confirmed_remote_id != 0 and plan.filename:
            try:
                jazzdrive.rename_video(acct["id"], confirmed_remote_id, plan.filename, folder_id=folder_id)
                log.debug("upload_pending: JD rename OK → %s", plan.filename)
            except Exception as _rn_err:
                log.debug("upload_pending: post-upload rename failed (non-fatal): %s", _rn_err)

        share_url = _create_share_link(sess, vk, jsid, confirmed_remote_id or 0, folder_id=folder_id)

        # Trigger metadata enrichment
        from . import metadata, assets, keys
        title_id = None
        
        tmdb_key = keys.get_active_value("tmdb")
        omdb_key = keys.get_active_value("omdb")
        
        # Derive initial meta from filename
        initial_meta = {
            "title": plan.title or file_path.stem,
            "year": plan.year,
            "media_type": plan.kind or "movie",
        }
        
        # Always enrich — IMDbAPI.dev (free/no-key) covers Pakistani/South Asian content;
        # AI fallback covers anything else; TMDB/OMDB used when keys are available.
        initial_meta.setdefault("is_published", 1)
        enriched = metadata.enrich_title(initial_meta, tmdb_key=tmdb_key, omdb_key=omdb_key)
        title_id = db.upsert_title(enriched)
        if title_id:
            if enriched.get("poster"):
                assets.process_title_poster(title_id, enriched["poster"], acct["id"], folder_id=folder_id)

        clear_live_stat(file_id)
        with db.conn() as c:
            # Inherit share_url from sibling file in same folder if creation failed
            if not share_url and folder_id:
                try:
                    with db.conn() as _inh:
                        _irow = _inh.execute(
                            "SELECT share_url FROM files WHERE remote_folder_id=? AND share_url IS NOT NULL AND share_url != '' LIMIT 1",
                            (folder_id,)).fetchone()
                        if _irow:
                            share_url = _irow["share_url"]
                            log.info("upload_pending: inherited share_url from sibling in folder %s", folder_id)
                except Exception as _ie2:
                    log.debug("upload_pending: share inherit failed: %s", _ie2)
            c.execute(
                "UPDATE files SET is_ready=1, title_id=?, remote_id=?, share_url=?, "
                "account_id=?, remote_folder_id=?, uploaded_at=?, season=?, episode=? WHERE id=?",
                (title_id, str(confirmed_remote_id), share_url or "", acct["id"], folder_id,
                 int(time.time()), plan.season, plan.episode, file_id),
            )
            # Propagate share_url to any sibling files in same folder missing one
            if share_url and folder_id:
                try:
                    with db.conn() as _prop:
                        _prop.execute(
                            "UPDATE files SET share_url=? WHERE remote_folder_id=? AND (share_url IS NULL OR share_url='')",
                            (share_url, folder_id))
                except Exception as _pe2:
                    log.debug("upload_pending: share propagate failed: %s", _pe2)

        # Ensure the file is added to the Canonical Media Index
        try:
            db.index_media_file(file_id)
        except Exception as _ie:
            log.debug("index_media_file failed for %s: %s", file_id, _ie)

        mirror.push_file_async(file_id)

        title_label = f"{plan.title} ({plan.year})" if plan.year else (plan.title or file_path.name)
        log.info("upload_pending: ✓ %s → /%s/ remote_id=%s share=%s",
                 file_path.name, title_label, confirmed_remote_id, share_url or "(none)")

        auto_del = upload_cfg.get("auto_delete", True)
        if auto_del and (share_url or confirmed_remote_id):
            try:
                file_path.unlink()
                with db.conn() as c:
                    c.execute("UPDATE files SET local_path=NULL WHERE id=?", (file_id,))
                log.info("upload_pending: deleted local file %s", file_path.name)
            except Exception as _de:
                log.warning("upload_pending: could not delete local file: %s", _de)

    except Exception as e:
        log.warning("upload_pending: ✗ %s — %s", file_path.name, e)
        _release_pending(file_id)


_STUCK_UPLOAD_TIMEOUT_S = 10 * 60  # 10 minutes: release files stuck at is_ready=-2


def _release_stuck_uploads() -> int:
    """Reset files that have been stuck at is_ready=-2 (in-progress) for over
    _STUCK_UPLOAD_TIMEOUT_S seconds back to is_ready=0 so the next watcher
    tick picks them up for retry.  This handles the race where a large file's
    SHA-1 fingerprint takes long enough that the upload thread exits without
    ever completing or releasing the claim."""
    cutoff = int(time.time()) - _STUCK_UPLOAD_TIMEOUT_S
    with db.conn() as c:
        n = c.execute(
            "UPDATE files SET is_ready=0 WHERE is_ready=-2 AND uploaded_at < ?",
            (cutoff,)
        ).rowcount
    if n:
        log.info("watcher_loop: auto-released %d upload(s) stuck >10 min → retrying", n)
    return n


def watcher_loop(stop_event: threading.Event, interval_s: int = 30) -> None:
    """Background loop: scan MEDIA_DIR for new files and upload pending ones."""
    # On startup, reset any files stuck as is_ready=-2 (in-progress) from a previous
    # crash or unclean shutdown.  Without this they would be permanently stuck.
    try:
        with db.conn() as c:
            stuck = c.execute(
                "UPDATE files SET is_ready=0 WHERE is_ready=-2"
            ).rowcount
        if stuck:
            log.info("watcher_loop: reset %d stuck in-progress file(s) to pending on startup", stuck)
    except Exception as _se:
        log.warning("watcher_loop: startup recovery failed: %s", _se)

    while not stop_event.wait(interval_s):
        # Respect the UPLOAD_ENABLED toggle — pause all file processing when
        # the upload service is disabled so we don't hammer JazzDrive while
        # the admin has intentionally paused uploads (e.g. between daily runs).
        if db.setting("UPLOAD_ENABLED", "1") != "1":
            log.debug("watcher_loop: UPLOAD_ENABLED=0, skipping tick")
            continue
        try:
            _release_stuck_uploads()
        except Exception as e:
            log.warning("watcher stuck-release: %s", e)
        try:
            _scan_once()
        except Exception as e:
            log.warning("watcher scan: %s", e)
        try:
            _upload_pending()
        except Exception as e:
            log.warning("upload_pending: %s", e)


def trigger_scan_now() -> int:
    return _scan_once()
