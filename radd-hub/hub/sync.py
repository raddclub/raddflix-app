"""3-way GitHub / Google Sheets sync for the Radd Hub database.

Ported from v1.0 hub/_legacy/db_github.py and db_gsheets.py.

Public surface
--------------
sync_all(mode)          — push all files to GitHub and/or Sheets
sync_entry(fingerprint) — push a single file row to both mirrors
status()                — return mirror health dict (counts + last timestamps)
"""
from __future__ import annotations
import logging
import os
import time
from typing import Optional

from . import db

log = logging.getLogger("hub.sync")


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def _github_cfg() -> tuple[str, str, str, str]:
    """Return (token, repo, db_path, branch) from DB settings, falling back to env."""
    # Try plain settings first, then the key vault, then env
    token = db.setting("github_token_plain") or ""
    if not token:
        try:
            from . import keys as _keys
            token = _keys.get_active_value("github") or ""
        except Exception:
            pass
    if not token:
        token = os.environ.get("GITHUB_TOKEN", "")
    repo   = db.setting("github_repo")        or os.environ.get("GITHUB_REPO", "")
    path   = db.setting("github_db_path")     or os.environ.get("GITHUB_DB_PATH", "uploaded_files.json")
    branch = db.setting("github_branch")      or os.environ.get("GITHUB_BRANCH", "main")
    return token.strip(), repo.strip(), (path or "uploaded_files.json").strip(), (branch or "main").strip()


def _gsheets_cfg() -> tuple[str, str, str]:
    """Return (sa_json, sheet_id, sheet_name) from DB settings, falling back to env."""
    sa_json    = db.setting("gsheets_sa_json_plain") or os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON", "")
    sheet_id   = db.setting("gsheet_id")             or os.environ.get("GOOGLE_SHEET_ID", "")
    sheet_name = db.setting("gsheet_name")           or os.environ.get("GOOGLE_SHEET_NAME", "")
    return (sa_json or "").strip(), (sheet_id or "").strip(), (sheet_name or "JazzDrive Uploads").strip()


# ---------------------------------------------------------------------------
# Internal: build a flat dict keyed by fingerprint for GitHub push
# ---------------------------------------------------------------------------

def _build_db_snapshot() -> dict:
    """Fetch all files from the DB and return a fingerprint → record dict."""
    files = db.list_files(limit=10_000)
    out: dict = {}
    for f in files:
        fp = f.get("fingerprint") or str(f.get("id", ""))
        out[fp] = f
    return out


# ---------------------------------------------------------------------------
# GitHub mirror
# ---------------------------------------------------------------------------

def _push_github(snapshot: dict) -> dict:
    """Push the full DB snapshot to GitHub.  Returns {ok, records, error}."""
    import json, base64
    import requests as _req
    token, repo, path, branch = _github_cfg()
    if not token or not repo:
        return {"ok": False, "records": 0,
                "error": "GitHub not configured (missing token or repo)"}
    try:
        hdrs = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        content = json.dumps(snapshot, indent=2, default=str)
        encoded = base64.b64encode(content.encode()).decode()
        sha_r = _req.get(
            f"https://api.github.com/repos/{repo}/contents/{path}",
            headers=hdrs, params={"ref": branch}, timeout=15)
        sha = sha_r.json().get("sha") if sha_r.status_code == 200 else None
        payload: dict = {
            "message": f"Auto-update: {len(snapshot)} record(s)",
            "content": encoded,
            "branch":  branch,
        }
        if sha:
            payload["sha"] = sha
        r = _req.put(
            f"https://api.github.com/repos/{repo}/contents/{path}",
            headers=hdrs, json=payload, timeout=30)
        if r.status_code in (200, 201):
            log.info("GitHub sync OK: %d records → %s/%s", len(snapshot), repo, path)
            return {"ok": True, "records": len(snapshot), "error": None}
        return {"ok": False, "records": 0,
                "error": f"HTTP {r.status_code}: {r.text[:200]}"}
    except Exception as exc:
        log.error("GitHub sync error: %s", exc)
        return {"ok": False, "records": 0, "error": str(exc)}


# ---------------------------------------------------------------------------
# Google Sheets mirror
# ---------------------------------------------------------------------------

_SHEET_HEADERS = [
    "fingerprint", "filename", "local_path", "media_kind", "size_mb",
    "uploaded_at", "share_url", "folder_path", "source",
    "remote_id", "remote_folder_id", "share_key", "is_ready",
    "github_status", "gsheets_status",
]


def _file_to_row(f: dict) -> list:
    size_mb = round((f.get("size_bytes") or 0) / 1_048_576, 2)
    return [
        f.get("fingerprint", ""),
        f.get("filename", ""),
        f.get("local_path", ""),
        f.get("media_kind", ""),
        size_mb,
        f.get("uploaded_at", ""),
        f.get("share_url", ""),
        f.get("folder_path", ""),
        f.get("source", ""),
        f.get("remote_id", ""),
        f.get("remote_folder_id", ""),
        f.get("share_key", ""),
        f.get("is_ready", 0),
        f.get("github_status", ""),
        f.get("gsheets_status", ""),
    ]


def _push_gsheets(snapshot: dict) -> dict:
    """Push the full DB snapshot to Google Sheets.  Returns {ok, records, error}."""
    try:
        from ._legacy.db_gsheets import sync_full_db as _sync_full_db
        ok = _sync_full_db(snapshot)
        return {"ok": ok, "records": len(snapshot), "error": None if ok else "sync_full_db returned False"}
    except ImportError:
        pass
    except Exception as exc:
        return {"ok": False, "records": 0, "error": str(exc)}

    # Fallback: inline gspread implementation
    sa_json_str, sheet_id, sheet_name = _gsheets_cfg()
    if not sa_json_str or not sheet_id:
        return {"ok": False, "records": 0,
                "error": "Google Sheets not configured (missing service account JSON or sheet ID)"}
    try:
        import json
        import gspread
        from google.oauth2.service_account import Credentials
        sa_info = json.loads(sa_json_str)
        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ]
        creds = Credentials.from_service_account_info(sa_info, scopes=scopes)
        client = gspread.authorize(creds)
        spreadsheet = client.open_by_key(sheet_id)
        try:
            ws = spreadsheet.worksheet(sheet_name)
        except Exception:
            ws = spreadsheet.add_worksheet(title=sheet_name, rows=1000, cols=len(_SHEET_HEADERS))
        rows = [_SHEET_HEADERS]
        for f in snapshot.values():
            rows.append(_file_to_row(f))
        ws.clear()
        ws.update("A1", rows, value_input_option="USER_ENTERED")
        log.info("Sheets sync OK: %d records → %s", len(snapshot), sheet_id)
        return {"ok": True, "records": len(snapshot), "error": None}
    except ImportError as exc:
        return {"ok": False, "records": 0,
                "error": f"gspread not installed: {exc}. Run: pip install gspread google-auth"}
    except Exception as exc:
        log.error("Sheets sync error: %s", exc)
        return {"ok": False, "records": 0, "error": str(exc)}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def sync_all(mode: str = "both") -> dict:
    """Push all DB records to GitHub and/or Google Sheets.

    mode: 'github' | 'gsheets' | 'both'
    Returns {github: {...}, gsheets: {...}, ts: ...}
    """
    snapshot = _build_db_snapshot()
    result: dict = {"ts": int(time.time()), "total_records": len(snapshot)}

    if mode in ("github", "both"):
        t0 = time.time()
        res = _push_github(snapshot)
        res["elapsed"] = round(time.time() - t0, 2)
        result["github"] = res
        if res["ok"]:
            db.set_setting("sync_github_last_at", str(int(time.time())))
            db.set_setting("sync_github_last_count", str(len(snapshot)))
            # Mark all synced files so github_synced count reflects reality
            with db.conn() as _c:
                _c.execute("UPDATE files SET github_status='ok', github_synced_at=? WHERE github_status IS NULL OR github_status!='ok'",
                           (int(time.time()),))

    if mode in ("gsheets", "both"):
        t0 = time.time()
        res = _push_gsheets(snapshot)
        res["elapsed"] = round(time.time() - t0, 2)
        result["gsheets"] = res
        if res["ok"]:
            db.set_setting("sync_gsheets_last_at", str(int(time.time())))
            db.set_setting("sync_gsheets_last_count", str(len(snapshot)))

    return result


def sync_entry(fingerprint: str) -> dict:
    """Push a single file entry (by fingerprint) to both mirrors."""
    files = db.list_files(limit=10_000)
    entry = next((f for f in files if f.get("fingerprint") == fingerprint), None)
    if not entry:
        return {"ok": False, "error": f"fingerprint {fingerprint!r} not found"}

    snapshot = {fingerprint: entry}
    gh_res = _push_github(snapshot)
    gs_res = _push_gsheets(snapshot)

    if gh_res.get("ok"):
        db.update_mirror_status(entry["id"], github="ok")
    if gs_res.get("ok"):
        db.update_mirror_status(entry["id"], gsheets="ok")

    return {"ok": gh_res.get("ok") or gs_res.get("ok"),
            "github": gh_res, "gsheets": gs_res}


def status() -> dict:
    """Return a quick status dict: last sync times + record counts."""
    counts = db.count_library()
    return {
        "total_files":         counts.get("files", 0),
        "github_synced":       counts.get("github_synced", 0),
        "gsheets_synced":      counts.get("gsheets_synced", 0),
        "github_last_at":      db.setting("sync_github_last_at"),
        "github_last_count":   db.setting("sync_github_last_count"),
        "gsheets_last_at":     db.setting("sync_gsheets_last_at"),
        "gsheets_last_count":  db.setting("sync_gsheets_last_count"),
        "github_configured":   bool((_github_cfg()[0]) and (_github_cfg()[1])),
        "gsheets_configured":  bool((_gsheets_cfg()[0]) and (_gsheets_cfg()[1])),
    }


# ---------------------------------------------------------------------------
# Bidirectional pull: GitHub → local DB
# ---------------------------------------------------------------------------

def pull_from_github() -> dict:
    """Fetch the full library JSON from GitHub and upsert missing files into local DB.

    Returns {ok, pulled, skipped, error}.
    """
    import json as _json
    import base64 as _b64
    try:
        import requests as _req
    except ImportError:
        return {"ok": False, "pulled": 0, "skipped": 0, "error": "requests not available"}

    token, repo, path, branch = _github_cfg()
    if not token or not repo:
        return {"ok": False, "pulled": 0, "skipped": 0,
                "error": "GitHub not configured (missing token or repo)"}

    try:
        hdrs = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        r = _req.get(
            f"https://api.github.com/repos/{repo}/contents/{path}",
            headers=hdrs, params={"ref": branch}, timeout=20)
        if r.status_code == 404:
            return {"ok": True, "pulled": 0, "skipped": 0, "error": None}
        if not r.ok:
            return {"ok": False, "pulled": 0, "skipped": 0,
                    "error": f"HTTP {r.status_code}: {r.text[:200]}"}

        content = _b64.b64decode(r.json()["content"].replace("\n", "")).decode("utf-8")
        remote_db: dict = _json.loads(content)
    except Exception as exc:
        log.warning("pull_from_github fetch failed: %s", exc)
        return {"ok": False, "pulled": 0, "skipped": 0, "error": str(exc)}

    pulled = skipped = 0
    for _key, entry in remote_db.items():
        if not isinstance(entry, dict):
            skipped += 1
            continue
        fp = entry.get("fingerprint")
        if not fp:
            skipped += 1
            continue
        # Only import if not already local
        with db.conn() as c:
            existing = c.execute("SELECT id FROM files WHERE fingerprint=?", (fp,)).fetchone()
        if existing:
            skipped += 1
            continue
        try:
            db.upsert_file({
                "fingerprint":      fp,
                "source":           entry.get("source") or "scan",
                "account_id":       entry.get("account_id"),
                "filename":         entry.get("filename") or entry.get("name") or "",
                "media_kind":       entry.get("media_kind") or entry.get("mediatype"),
                "season":           entry.get("season"),
                "episode":          entry.get("episode"),
                "size_bytes":       entry.get("size_bytes") or 0,
                "quality":          entry.get("quality"),
                "remote_id":        entry.get("remote_id"),
                "remote_folder_id": entry.get("remote_folder_id"),
                "folder_path":      entry.get("folder_path"),
                "share_url":        entry.get("share_url"),
                "share_key":        entry.get("share_key"),
                "share_link_id":    entry.get("share_link_id"),
                "share_folder_id":  entry.get("share_folder_id"),
                "download_url":     entry.get("download_url"),
                "uploaded_at":      entry.get("uploaded_at"),
                "scanned_at":       entry.get("scanned_at"),
                "is_ready":         entry.get("is_ready", 1),
                "github_status":    "ok",
            })
            pulled += 1
        except Exception as exc2:
            log.warning("pull_from_github upsert failed for %s: %s", fp, exc2)
            skipped += 1

    log.info("pull_from_github: pulled=%d skipped=%d total_remote=%d", pulled, skipped, len(remote_db))
    db.set_setting("sync_pull_github_last_at", str(int(time.time())))
    db.set_setting("sync_pull_github_last_count", str(pulled))
    return {"ok": True, "pulled": pulled, "skipped": skipped, "error": None}


# ---------------------------------------------------------------------------
# Clear remote databases
# ---------------------------------------------------------------------------

def clear_github_db() -> dict:
    """Replace the GitHub JSON file with an empty object {}."""
    import json as _json, base64 as _b64
    try:
        import requests as _req
    except ImportError:
        return {"ok": False, "error": "requests not available"}

    token, repo, path, branch = _github_cfg()
    if not token or not repo:
        return {"ok": False, "error": "GitHub not configured"}

    try:
        hdrs = {
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        sha_r = _req.get(
            f"https://api.github.com/repos/{repo}/contents/{path}",
            headers=hdrs, params={"ref": branch}, timeout=15)
        sha = sha_r.json().get("sha") if sha_r.status_code == 200 else None

        payload: dict = {
            "message": "Clear database",
            "content": _b64.b64encode(b"{}").decode(),
            "branch":  branch,
        }
        if sha:
            payload["sha"] = sha
        r = _req.put(
            f"https://api.github.com/repos/{repo}/contents/{path}",
            headers=hdrs, json=payload, timeout=30)
        ok = r.status_code in (200, 201)
        return {"ok": ok, "error": None if ok else f"HTTP {r.status_code}: {r.text[:200]}"}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


def clear_gsheets_db() -> dict:
    """Clear all data rows from the Google Sheet (keeps header row)."""
    sa_json_str, sheet_id, sheet_name = _gsheets_cfg()
    if not sa_json_str or not sheet_id:
        return {"ok": False, "error": "Google Sheets not configured"}
    try:
        import json
        import gspread
        from google.oauth2.service_account import Credentials
        sa_info = json.loads(sa_json_str)
        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ]
        creds = Credentials.from_service_account_info(sa_info, scopes=scopes)
        client = gspread.authorize(creds)
        spreadsheet = client.open_by_key(sheet_id)
        try:
            ws = spreadsheet.worksheet(sheet_name)
        except Exception:
            ws = spreadsheet.add_worksheet(title=sheet_name, rows=1000, cols=len(_SHEET_HEADERS))
        ws.clear()
        ws.append_row(_SHEET_HEADERS, value_input_option="RAW")
        return {"ok": True, "error": None}
    except ImportError as exc:
        return {"ok": False, "error": f"gspread not installed: {exc}"}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
