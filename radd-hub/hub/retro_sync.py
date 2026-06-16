"""Retroactive Sync & Enrichment for JazzDrive data.

Iterates through already uploaded files, renames them according to standards,
enriches missing metadata, and ensures posters are uploaded to JazzDrive.
"""
from __future__ import annotations
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from . import db, scanner, jazzdrive, media_naming, metadata, assets

log = logging.getLogger("hub.retro_sync")

def run_retro_sync(account_id: int, progress_cb=None):
    """Run a full batch sync, enrichment, and renaming for an account."""
    def _log(msg):
        log.info(msg)
        if progress_cb:
            progress_cb({"type": "info", "message": msg})

    acct = db.get_account(account_id)
    if not acct:
        _log(f"Account {account_id} not found")
        return

    _log(f"Starting Retro Sync for {acct.get('label', acct['msisdn'])}...")

    # Phase 1: Deep Sync (Fetch remote state)
    # The existing scanner.scan_account handles the crawl and initial import.
    try:
        # We need a legacy ID for the scanner
        legacy_id = scanner._ensure_legacy_account(account_id)
        _log("Scanning JazzDrive account...")
        # Initialize active scan state for _scan_worker
        with scanner._scan_lock:
            scanner._active_scans[account_id] = {
                "running": True, "paused": False, "stop_requested": False,
                "started_at": int(time.time()), "events": []
            }
        scanner._scan_worker(account_id, legacy_id)
    except Exception as e:
        _log(f"Initial scan failed: {e}")
        return

    # Phase 2: Identification & Renaming Loop
    _log("Processing files for renaming and enrichment...")
    
    with db.conn() as c:
        files = [dict(r) for r in c.execute(
            "SELECT * FROM files WHERE account_id=? AND remote_id IS NOT NULL", 
            (account_id,)
        ).fetchall()]

    if not files:
        _log("No files found to process.")
        return

    _log(f"Found {len(files)} files. Starting enrichment...")

    import pathlib

    def process_file(file_info):
        try:
            file_id = file_info["id"]
            remote_id = file_info["remote_id"]
            current_filename = file_info["filename"]
            title_id = file_info.get("title_id")

            # 1. Enrichment (if missing title_id)
            if not title_id:
                plan = media_naming.derive_media_plan(current_filename)
                initial_meta = {
                    "title": plan.title or current_filename,
                    "year": plan.year,
                    "media_type": plan.kind or "movie",
                }
                # TMDB/OMDB Lookup
                enriched = metadata.enrich_title(initial_meta)
                title_id = db.upsert_title(enriched)
                if title_id:
                    db.update_file(file_id, {
                        "title_id": title_id,
                        "media_kind": plan.kind,
                        "season": plan.season,
                        "episode": plan.episode
                    })
            
            if not title_id:
                return False

            # 2. Renaming
            title = db.get_title(title_id)
            plan = media_naming.derive_media_plan(current_filename)
            # Re-derive target name from official title and year
            standard_name = current_filename
            if title:
                ext = pathlib.Path(current_filename).suffix
                
                if plan.kind == "tv" and plan.season is not None and plan.episode is not None:
                    standard_name = f"{title['title']} S{plan.season:02d}E{plan.episode:02d}"
                else:
                    standard_name = f"{title['title']} ({title['year']})" if title.get('year') else f"{title['title']}"
                
                # Sanitize stem
                standard_name = media_naming._sanitize_folder(standard_name) + ext
            
            if standard_name != current_filename:
                _log(f"Renaming remote: {current_filename} -> {standard_name}")
                res = jazzdrive.rename_video(account_id, remote_id, standard_name)
                if not res.get("error"):
                    db.update_file(file_id, {"filename": standard_name})
                    return True
                else:
                    _log(f"Rename failed for {current_filename}: {res.get('error')}")
            
            return False
        except Exception as e:
            log.error("Error processing file %s: %s", file_info.get("filename"), e)
            return False

    with ThreadPoolExecutor(max_workers=10) as executor:
        results = list(executor.map(process_file, files))
    
    renamed_count = sum(1 for r in results if r)
    _log(f"Finished renaming. Total renamed: {renamed_count}")

    # Phase 3: Poster Sync
    _log("Ensuring all titles have posters on JazzDrive...")
    with db.conn() as c:
        # Titles that are linked to files in this account
        titles_to_check = [dict(r) for r in c.execute(
            "SELECT DISTINCT t.* FROM titles t JOIN files f ON t.id = f.title_id WHERE f.account_id=?",
            (account_id,)
        ).fetchall()]

    processed_posters = 0
    for title in titles_to_check:
        if not title.get("poster_share_url") and title.get("poster"):
            _log(f"Uploading poster for: {title['title']}")
            res = assets.process_title_poster(title["id"], title["poster"], account_id)
            if res:
                processed_posters += 1

    _log(f"Poster sync complete. Uploaded {processed_posters} posters.")
    _log("Retro Sync finished successfully.")

if __name__ == "__main__":
    import sys
    # Example usage: python3 -m hub.retro_sync <account_id>
    if len(sys.argv) > 1:
        run_retro_sync(int(sys.argv[1]))
    else:
        print("Usage: python3 -m hub.retro_sync <account_id>")
