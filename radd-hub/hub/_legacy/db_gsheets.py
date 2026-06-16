import json
import logging
import os
import threading
log = logging.getLogger("RaddFlix.GSheets")
_sheets_lock = threading.Lock()
HEADERS = [
    "file_id", "name", "path", "mediatype", "size_mb", "uploaded_at",
    "share_url", "share_folder_path", "media_kind",
    "tmdb_title", "tmdb_year", "tmdb_rating", "tmdb_poster",
    "remote_folder_id", "share_folder_id", "share_key", "fingerprint",
]
_GSHEETS_TIMEOUT = 30
def _get_config():
    sa_json    = os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON", "")
    sheet_id   = os.environ.get("GOOGLE_SHEET_ID", "")
    sheet_name = os.environ.get("GOOGLE_SHEET_NAME", "")
    if not sa_json or not sheet_id:
        try:
            cfg_path = os.path.join(os.path.dirname(__file__), "config.json")
            with open(cfg_path) as f:
                cfg = json.load(f)
            sa_json    = sa_json    or cfg.get("google_service_account_json", "")
            sheet_id   = sheet_id   or cfg.get("google_sheet_id", "")
            sheet_name = sheet_name or cfg.get("google_sheet_name", "")
        except Exception:
            pass
    return sa_json, sheet_id, sheet_name or "JazzDrive Uploads"
def _get_client():
    try:
        import gspread
        from google.oauth2.service_account import Credentials
    except ImportError:
        log.error("gspread not installed. Run: pip install gspread google-auth")
        return None
    sa_json_str, sheet_id, _ = _get_config()
    if not sa_json_str or not sheet_id:
        return None
    try:
        sa_info = json.loads(sa_json_str)
        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive",
        ]
        creds = Credentials.from_service_account_info(sa_info, scopes=scopes)
        client = gspread.authorize(creds)
        try:
            import requests as _requests
            orig_request = client.session.request
            def _timed_request(method, url, **kwargs):
                kwargs.setdefault("timeout", _GSHEETS_TIMEOUT)
                return orig_request(method, url, **kwargs)
            client.session.request = _timed_request
        except Exception:
            pass                                                        
        return client
    except Exception as exc:
        log.error("Google Sheets auth failed: %s", exc)
        return None
def _get_or_create_sheet(client, sheet_id, sheet_name):
    try:
        spreadsheet = client.open_by_key(sheet_id)
        try:
            worksheet = spreadsheet.worksheet(sheet_name)
        except Exception:
            worksheet = spreadsheet.add_worksheet(title=sheet_name, rows=1000, cols=len(HEADERS))
            worksheet.append_row(HEADERS, value_input_option="RAW")
            log.info("Created Google Sheet tab: %s", sheet_name)
        return worksheet
    except Exception as exc:
        log.error("Could not open Google Sheet: %s", exc)
        return None
def _extract_row(fingerprint: str, entry: dict) -> list:
    resp = entry.get("response", {})
    meta = resp.get("metadata", {}) if isinstance(resp, dict) else {}
    tmdb = entry.get("tmdb") or {}
    file_id = resp.get("id", "") if isinstance(resp, dict) else ""
    size_bytes = 0
    files_list = meta.get("files", meta.get("videos", meta.get("pictures", [])))
    if files_list and isinstance(files_list, list):
        size_bytes = files_list[0].get("size", 0)
    size_mb = round(size_bytes / (1024 * 1024), 2) if size_bytes else 0
    return [
        file_id,
        entry.get("name", ""),
        entry.get("path", ""),
        entry.get("mediatype", resp.get("type", "") if isinstance(resp, dict) else ""),
        size_mb,
        entry.get("uploaded_at", ""),
        entry.get("share_url", ""),
        entry.get("share_folder_path", ""),
        entry.get("media_kind", ""),
        tmdb.get("title", "") if isinstance(tmdb, dict) else entry.get("tmdb_title", ""),
        tmdb.get("year", "")  if isinstance(tmdb, dict) else entry.get("tmdb_year", ""),
        tmdb.get("rating", "") if isinstance(tmdb, dict) else entry.get("tmdb_rating", ""),
        tmdb.get("poster_path", "") if isinstance(tmdb, dict) else entry.get("tmdb_poster", ""),
        entry.get("remote_folder_id", 0),
        entry.get("share_folder_id", ""),
        entry.get("share_key", ""),
        fingerprint,
    ]
def _get_existing_ids(worksheet) -> dict:
    try:
        records = worksheet.get_all_values()
        if not records or len(records) < 2:
            return {}
        id_map = {}
        for i, row in enumerate(records[1:], start=2):
            if row and row[0]:
                id_map[row[0]] = i
        return id_map
    except Exception as exc:
        log.error("Could not read existing rows: %s", exc)
        return {}
def append_entry(fingerprint: str, entry: dict) -> bool:
    with _sheets_lock:
        sa_json, sheet_id, sheet_name = _get_config()
        if not sa_json or not sheet_id:
            log.debug("Google Sheets sync skipped — credentials not set.")
            return False
        client = _get_client()
        if not client:
            return False
        worksheet = _get_or_create_sheet(client, sheet_id, sheet_name)
        if not worksheet:
            return False
        try:
            row = _extract_row(fingerprint, entry)
            existing = _get_existing_ids(worksheet)
            file_id = row[0]
            if file_id and file_id in existing:
                row_num = existing[file_id]
                worksheet.update(f"A{row_num}:{chr(65 + len(HEADERS) - 1)}{row_num}", [row])
                log.info("Google Sheets: updated row for file_id=%s (%s)", file_id, entry.get("name", ""))
            else:
                try:
                    worksheet.append_row(row, value_input_option="USER_ENTERED")
                    log.info("Google Sheets: appended row for %s", entry.get("name", ""))
                except Exception as append_exc:
                    err_str = str(append_exc)
                    if "10000000" in err_str or "limit" in err_str.lower() or "cells" in err_str.lower():
                        # Sheet is at the 10M cell limit — clear all data and start fresh
                        log.warning("Google Sheets cell limit hit — clearing sheet and rewriting current row")
                        try:
                            worksheet.clear()
                            worksheet.append_row(HEADERS, value_input_option="RAW")
                            worksheet.append_row(row, value_input_option="USER_ENTERED")
                            log.info("Google Sheets: cleared and re-seeded for %s", entry.get("name", ""))
                        except Exception as clear_exc:
                            log.error("Google Sheets clear+rewrite failed: %s", clear_exc)
                            return False
                    else:
                        raise
            return True
        except Exception as exc:
            log.error("Google Sheets append error: %s", exc)
            return False
def sync_full_db(db: dict) -> bool:
    with _sheets_lock:
        sa_json, sheet_id, sheet_name = _get_config()
        if not sa_json or not sheet_id:
            log.debug("Google Sheets sync skipped — credentials not set.")
            return False
        client = _get_client()
        if not client:
            return False
        worksheet = _get_or_create_sheet(client, sheet_id, sheet_name)
        if not worksheet:
            return False
        try:
            rows = [HEADERS]
            for fp, entry in db.items():
                rows.append(_extract_row(fp, entry))
            worksheet.clear()
            worksheet.update("A1", rows, value_input_option="USER_ENTERED")
            log.info("Google Sheets: full sync complete — %d records", len(db))
            return True
        except Exception as exc:
            log.error("Google Sheets full sync error: %s", exc)
            return False