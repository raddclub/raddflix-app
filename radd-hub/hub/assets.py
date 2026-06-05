"""Utility for downloading and uploading posters to JazzDrive."""
import logging
import requests
import tempfile
from pathlib import Path
from . import db, uploader, config, jazzdrive

log = logging.getLogger("hub.assets")

def process_title_poster(title_id: int, poster_url: str, account_id: int, folder_id: int = 0):
    """Download a poster from a URL and upload it to the title's JazzDrive folder."""
    if not poster_url or not title_id:
        return None

    # Check if we already have a poster share url
    title = db.get_title(title_id)
    if not title:
        return None
    
    if title.get("poster_share_url"):
        return title["poster_share_url"]

    log.info("Processing poster for title %s: %s", title_id, poster_url)

    try:
        # 1. Download to temp
        resp = requests.get(poster_url, timeout=20)
        if resp.status_code != 200:
            log.warning("Failed to download poster: %s", resp.status_code)
            return None
        
        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            tmp.write(resp.content)
            tmp_path = Path(tmp.name)

        # 2. Upload to JazzDrive
        if not folder_id:
            # Fallback: try to find the folder from existing files for this title
            with db.conn() as c:
                row = c.execute("SELECT remote_folder_id FROM files WHERE title_id=? AND remote_folder_id IS NOT NULL LIMIT 1", (title_id,)).fetchone()
                folder_id = int(row["remote_folder_id"]) if row else 0

        if not folder_id:
            # Last resort: create a new folder
            from . import media_naming
            plan = media_naming.derive_media_plan(title["title"])
            title_label = f"{title['title']} ({title['year']})" if title.get("year") else title["title"]
            
            acct = db.get_account(account_id)
            if not acct: return None
            
            vk = acct.get("validation_key")
            jsid = acct.get("jsessionid")
            sess = requests.Session()
            _px = jazzdrive.resolve_proxies(purpose='sapi')
            if _px: sess.proxies.update(_px)
            folder_id = uploader._get_or_create_folder(sess, vk, jsid, title_label, parent_id=0, account_id=account_id)

        if not folder_id:
            log.warning("Could not find/create folder for poster upload")
            tmp_path.unlink()
            return None

        # Upload poster.jpg
        acct = db.get_account(account_id)
        vk = acct.get("validation_key")
        jsid = acct.get("jsessionid")
        sess = requests.Session()
        _px2 = jazzdrive.resolve_proxies(purpose='sapi')
        if _px2: sess.proxies.update(_px2)
        
        # Always upload as "poster.jpg" so the library route can find it
        # by name inside the shared folder via generate_direct_link.
        poster_path = tmp_path.parent / "poster.jpg"
        tmp_path.rename(poster_path)
        
        try:
            res = uploader._upload_file(sess, vk, jsid, poster_path, parent_id=folder_id, account_id=account_id)
            remote_id = res.get("id")
            
            # Get share link
            share_url = uploader._create_share_link(sess, vk, jsid, remote_id, folder_id=folder_id)
            
            if share_url:
                db.update_title(title_id, {"poster_share_url": share_url})
                log.info("Poster uploaded and linked for title %s: %s", title_id, share_url)
                return share_url
        finally:
            if poster_path.exists():
                poster_path.unlink()

    except Exception as e:
        log.warning("Error processing poster for title %s: %s", title_id, e)
    
    return None

def process_title_backdrop(title_id: int, backdrop_url: str, account_id: int, folder_id: int = 0):
    """(DISABLED) Backdrops are no longer needed, using posters only."""
    return None
