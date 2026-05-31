"""Bulk Link Engine — proactively refreshes stream links for the library.

This ensures instant playback in RaddFlix by pre-generating time-limited 
direct download links from JazzDrive shares.
"""
from __future__ import annotations
import logging
import threading
import time
from typing import Optional
from . import db, jazzdrive, config

log = logging.getLogger("hub.bulk_links")

class BulkLinkEngine:
    def __init__(self, stop_event: threading.Event):
        self._stop_event = stop_event

    def run_forever(self):
        log.info("Bulk Link Engine loop started.")
        
        # Initial wait (1 minute) to let system settle after boot
        if self._stop_event.wait(60):
            return
            
        while not self._stop_event.is_set():
            try:
                self.refresh_links()
            except Exception as e:
                log.error("BulkLinkEngine loop error: %s", e)
            
            # Run every 2 hours
            if self._stop_event.wait(2 * 3600):
                break
        
        log.info("Bulk Link Engine loop stopped.")

    def refresh_links(self):
        """Intelligently refresh stream links."""
        log.info("Starting bulk link refresh cycle...")
        
        now = int(time.time())
        # We refresh if it expires in less than 2 hours
        expiring_threshold = now + 7200 
        
        with db.conn() as c:
            # Query for files that need links.
            # Priority:
            # 1. Popular files (highest request_count)
            # 2. Most recently added files (highest ID)
            # Limit to 200 files per cycle to avoid flooding
            query = """
                SELECT f.id, f.filename, f.share_url, f.title_id, t.folder_share_url,
                       COALESCE(sl.request_count, 0) as popularity,
                       sl.expires_at, f.account_id
                FROM files f
                JOIN titles t ON f.title_id = t.id
                LEFT JOIN stream_links sl ON f.id = sl.file_id AND sl.is_valid = 1
                WHERE f.is_ready = 1
                AND (sl.id IS NULL OR sl.expires_at < ?)
                ORDER BY popularity DESC, f.id DESC
                LIMIT 200
            """
            targets = c.execute(query, (expiring_threshold,)).fetchall()
            
        if not targets:
            log.info("No links need refreshing at this time.")
            return
            
        log.info(f"Identified {len(targets)} files for link generation.")
        
        success_count = 0
        for row in targets:
            if self._stop_event.is_set():
                break
                
            file_id = row['id']
            filename = row['filename']
            # Prefer direct file share_url, fallback to folder_share_url
            share_url = row['share_url'] or row['folder_share_url']
            account_id = row['account_id']
            
            if not share_url:
                log.debug(f"Skipping {filename} (ID: {file_id}): No share URL available.")
                continue
                
            try:
                # generate_direct_link is share-based (guest login), so account_id 
                # isn't strictly needed but good for logging/tracking.
                res = jazzdrive.generate_direct_link(share_url, target_filename=filename)
                if res.get("ok"):
                    # Save with 8h expiry (28800s)
                    db.save_stream_link(file_id, res['direct_link'], 
                                        expires_in=28800, account_id=account_id)
                    success_count += 1
                    log.debug(f"✓ Generated link for {filename}")
                else:
                    log.warning(f"× Failed to generate link for {filename}: {res.get('error')}")
            except Exception as e:
                log.error(f"Error generating link for {filename}: {e}")
                
            # Anti-throttle delay (2s per file = ~7 min for 200 files)
            time.sleep(2)
            
        log.info(f"Bulk link refresh cycle complete. Generated {success_count} links.")

def loop(stop_event: threading.Event):
    """Entry point for threading.Thread and self_heal watchdog."""
    engine = BulkLinkEngine(stop_event)
    engine.run_forever()
