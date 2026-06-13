import os
import re
import time
import uuid
import base64 as _b64_mod
import json as _json_mod
import logging
import urllib.parse
from typing import Optional
import requests
import urllib3
import schema
import enricher
from .. import jazzdrive

# jazzdrive.com.pk (bare domain) has an SSL hostname mismatch — suppress only
# those warnings; all cloud.jazzdrive.com.pk calls remain fully verified.
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
log = logging.getLogger("scanner")
CLOUD_BASE = "https://cloud.jazzdrive.com.pk"
OAUTH_BASE = "https://jazzdrive.com.pk"

# Android OAuth2 credentials — decrypted from APK (classes2.dex C4622a / C3912s)
# AES/CBC/PKCS7 decrypt of o7("Rue+xcBP..","3Bdy7n..","7/iZTG..") and o7("qMgs+G..","cvosad..","UDczop..")
ANDROID_CLIENT_ID     = "fnbroot"
ANDROID_CLIENT_SECRET = "f&rW23"
ANDROID_REDIRECT_URI  = f"{CLOUD_BASE}/ui/html/clientoauth.html"
# Import from shared source of truth so scanner and uploader stay in sync
try:
    from ..media_naming import MEDIA_EXTENSIONS as _ME
    VIDEO_EXTENSIONS = {e for e in _ME if e in {
        '.mp4', '.mkv', '.avi', '.mov', '.m4v', '.webm', '.wmv', '.flv',
        '.ts', '.m2ts', '.mpg', '.mpeg', '.3gp', '.rmvb', '.rm', '.divx',
        '.xvid', '.vob', '.ogv', '.f4v', '.hevc', '.mts', '.3g2',
    }}
except ImportError:
    VIDEO_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.m4v', '.webm', '.wmv', '.flv', '.ts', '.m2ts'}
SKIP_FOLDERS = {
    '__pycache__', 'system', '.trash', 'thumbnails', 'heartbeat', 'logs',
    'cache', 'temp', 'tmp', 'auth', 'node_modules', '.git', '.idea',
    # Radd-specific junk / test folders — never index these
    'radd-heartbeat', 'radd-delta', 'raddhub', 'raddhub',
    'uploads_test_archive', 'radd-test-folder', 'radd_test_folder',
    'heartbeat (1)', 'radd-heartbeat (1)',
}
DEVICE_ID = uuid.uuid4().hex[:16]
def _auth_params(tokens: dict) -> str:
    vk = tokens.get('validation_key') or tokens.get('validationkey') or ''
    return f"validationkey={urllib.parse.quote(vk, safe='')}" if vk else ''
def _auth_headers(tokens: dict) -> dict:
    from .. import jazzdrive
    return jazzdrive._auth_headers(tokens)
def _build_url(path: str, tokens: dict) -> str:
    sep = '&' if '?' in path else '?'
    return f"{CLOUD_BASE}{path}{sep}{_auth_params(tokens)}"
def verify_session(tokens: dict) -> bool:
    try:
        data = jazzdrive.sapi_request(
            endpoint="/system/information",
            action="get",
            tokens={"validationkey": tokens.get('validation_key') or tokens.get('validationkey'),
                    "jsessionid": tokens.get('jsessionid')}
        )
        return not data.get('error')
    except Exception:
        return False
def list_folders(sess: requests.Session, tokens: dict, parent_id: int = 0, account_id: Optional[int] = None) -> list:
    """List JazzDrive folders.

    parent_id=0 uses the /media/folder/root endpoint (parentId=0 is rejected by
    the API).  Any other parent_id uses /media/folder?action=get&parentId=<id>.
    """
    try:
        _vk  = (tokens.get('validation_key') or tokens.get('validationkey')) if tokens else None
        _jid = tokens.get('jsessionid') if tokens else None
        _tok = {"validationkey": _vk, "jsessionid": _jid} if _vk else None

        if parent_id == 0:
            # Root-level: use the dedicated root endpoint
            data = jazzdrive.sapi_request(
                endpoint="/media/folder/root",
                action="get",
                account_id=account_id,
                tokens=_tok or None,
            )
        else:
            data = jazzdrive.sapi_request(
                endpoint="/media/folder",
                action="get",
                params={"parentId": parent_id},
                account_id=account_id,
                tokens=_tok or None,
            )

        if not isinstance(data, dict) or data.get('error'):
            return []

        raw = data.get('data') or {}
        if isinstance(raw, list):
            items = raw
        elif isinstance(raw, dict):
            items = raw.get('folders') or raw.get('items') or []
        else:
            items = []

        # Find the real root-folder id (magic=True item, name="/")
        root_fid: Optional[int] = None
        for it in items:
            if it.get('magic') or it.get('name') == '/':
                root_fid = it.get('id')
                break

        result = []
        for item in items:
            # Skip the virtual "/" root item itself
            if item.get('magic') or item.get('name') == '/':
                continue

            fid = item.get('id') or item.get('folderid') or item.get('folderId')
            if fid is None:
                continue

            pid = item.get('parentid') or item.get('parent_id') or item.get('parentId')

            # For root listing: accept items whose parent is the magic root,
            # or items that have no parentid (top-level in root response).
            if parent_id == 0:
                if pid is not None and root_fid is not None and int(pid) != root_fid:
                    continue
            else:
                # Subfolder listing: only return direct children
                if pid is not None and int(pid) != parent_id:
                    continue

            result.append({
                'id': int(fid),
                'name': item.get('name') or item.get('title') or f'folder_{fid}',
                'parent_id': int(pid) if pid is not None else (root_fid or parent_id),
            })
        return result
    except Exception as e:
        log.warning("list_folders(%s): %s", parent_id, e)
        return []
def list_videos(sess: requests.Session, tokens: dict, folder_id: int, account_id: Optional[int] = None) -> list:
    try:
        # Include both parentId and folderId for maximum compatibility
        # Only build a tokens dict if we actually have real values.
        # Passing {"validationkey": None} to sapi_request is truthy but
        # useless — it blocks the automatic DB lookup by account_id.
        _vk  = tokens.get('validation_key') or tokens.get('validationkey') if tokens else None
        _jid = tokens.get('jsessionid') if tokens else None
        _tok = {"validationkey": _vk, "jsessionid": _jid} if _vk else None

        # Paginate until more=false (GetMediaWrapper.more from Android RE)
        items = []
        _offset = 0
        _MAX_PAGES = 50
        for _page in range(_MAX_PAGES):
            _params = {"parentId": folder_id, "folderId": folder_id}
            if _offset > 0:
                _params["offset"] = _offset
            data = jazzdrive.sapi_request(
                endpoint="/media/video",
                action="get",
                params=_params,
                account_id=account_id,
                tokens=_tok,
            )
            if data.get('error'):
                break
            _page_items = []
            if isinstance(data, dict):
                for key in ('data', 'videos', 'items', 'result'):
                    v = data.get(key)
                    if isinstance(v, list):
                        _page_items = v
                        break
                    if isinstance(v, dict):
                        for sub in ('videos', 'items', 'files'):
                            if isinstance(v.get(sub), list):
                                _page_items = v[sub]
                                break
                        if _page_items:
                            break
            elif isinstance(data, list):
                _page_items = data
            if not _page_items:
                break
            items.extend(_page_items)
            _offset += len(_page_items)
            # Check more flag (GetMediaWrapper.more / hasMore)
            _more = False
            if isinstance(data, dict):
                for _dk in ('data', 'result'):
                    _dv = data.get(_dk)
                    if isinstance(_dv, dict):
                        _more = bool(_dv.get('more') or _dv.get('hasMore'))
                        break
                if not _more:
                    _more = bool(data.get('more') or data.get('hasMore'))
            if not _more:
                break
            log.debug("list_videos folder=%s page=%d: %d items, more=True offset=%d",
                      folder_id, _page+1, len(_page_items), _offset)
            
        # Non-video extensions we always skip (docs, archives, misc images).
        # .jpg / .jpeg are handled explicitly below so we can distinguish
        # poster files (keep, tagged) from backdrop files (discard always).
        _SKIP_EXTS = {
            '.png', '.gif', '.bmp', '.webp', '.tiff', '.svg',
            '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
            '.txt', '.csv', '.json', '.xml', '.html', '.htm', '.md',
            '.zip', '.rar', '.7z', '.tar', '.gz',
            '.exe', '.apk', '.ipa', '.dmg', '.iso',
            '.tmp', '.part', '.crdownload',
        }

        result = []
        for item in items:
            # JazzDrive always returns the full video list regardless of folderId.
            # The authoritative folder assignment is the 'folder' field on each item.
            # Filter by it so each video is only processed under its real folder.
            item_folder = item.get('folder') or item.get('parentid') or item.get('parentId')
            if item_folder is not None and int(item_folder) != int(folder_id):
                continue

            fid = item.get('id') or item.get('videoId') or item.get('video_id')
            name = item.get('name') or item.get('title') or item.get('filename') or ''
            size = item.get('size') or item.get('filesize') or item.get('size_bytes') or 0
            if not fid or not name:
                continue

            _ext = os.path.splitext(name.lower())[1]
            _name_lower = name.lower()

            # ── JPEG/JPG: handle poster vs backdrop vs other ──────────────────
            if _ext in ('.jpg', '.jpeg'):
                if _name_lower.startswith('backdrop'):
                    # Backdrop images are never needed — discard always.
                    continue
                if _name_lower.startswith('poster'):
                    # Poster image: tag it so scan_folder can capture the
                    # folder→poster mapping.  It is NOT a streamable media
                    # file, so scan_folder will filter it from folder_files.
                    result.append({
                        'remote_id':  str(fid),
                        'filename':   name,
                        'size_bytes': int(size) if str(size).isdigit() else 0,
                        'folder_id':  folder_id,
                        '_is_poster': True,
                    })
                # Any other .jpg (thumbnails, etc.) → discard
                continue

            # ── All other non-video extensions → skip ────────────────────────
            if _ext in _SKIP_EXTS:
                continue

            result.append({
                'remote_id': str(fid),
                'filename': name,
                'size_bytes': int(size) if str(size).isdigit() else 0,
                'folder_id': folder_id,
            })
        return result
    except Exception as e:
        log.warning("list_videos(%s): %s", folder_id, e)
        return []
def get_or_create_share_link(sess: requests.Session, tokens: dict, folder_id: int, account_id: Optional[int] = None) -> dict:
    vk = tokens.get('validation_key') or tokens.get('validationkey')
    jid = tokens.get('jsessionid')
    
    # 1. Try to find existing link first
    try:
        # Some accounts require POST, some GET. sapi_request defaults to GET for action=get.
        data = jazzdrive.sapi_request(
            endpoint="/link",
            action="get",
            account_id=account_id,
            tokens={"validationkey": vk, "jsessionid": jid}
        )
        if not data.get('error'):
            items = []
            if isinstance(data, dict):
                for key in ('data', 'links', 'items', 'result'):
                    v = data.get(key)
                    if isinstance(v, list):
                        items = v
                        break
            elif isinstance(data, list):
                items = data
            
            for link in items:
                d = link.get('data') if isinstance(link.get('data'), dict) else link
                link_fid = d.get('folderid') or d.get('folderId') or 0
                if int(link_fid or 0) == int(folder_id):
                    sk = d.get('shareKey') or d.get('sharedKey') or ''
                    if sk:
                        return {
                            'share_key': sk,
                            'share_url': f"{CLOUD_BASE}/f/{sk}",
                            'share_link_id': str(d.get('id') or ''),
                            'share_folder_id': str(folder_id),
                        }
    except Exception as e:
        log.debug("list_links failed: %s", e)

    # 2. Create new link if not found
    try:
        # Use both folderid and folderId for compatibility across different account types
        data = jazzdrive.sapi_request(
            endpoint="/link/folder",
            action="save",
            method="POST",
            json_data={'data': {'folderid': int(folder_id), 'folderId': int(folder_id)}},
            account_id=account_id,
            tokens={"validationkey": vk, "jsessionid": jid}
        )
        if not data.get('error'):
            d = data.get('data') if isinstance(data.get('data'), dict) else data
            sk = d.get('shareKey') or d.get('sharedKey') or ''
            url = d.get('url') or ''
            
            if not sk and url:
                # Extract sk from url: https://.../share/f/SK or https://.../f/SK
                if '/share/f/' in url:
                    sk = url.split('/share/f/')[1].split('?')[0]
                elif '/f/' in url:
                    sk = url.split('/f/')[1].split('?')[0]

            if sk:
                return {
                    'share_key': sk,
                    'share_url': url or f"{CLOUD_BASE}/f/{sk}",
                    'share_link_id': str(d.get('id') or ''),
                    'share_folder_id': str(folder_id),
                }
            else:
                log.warning("create_share_link: success response but no shareKey for folder %s. Body: %s", folder_id, data)
        else:
            log.warning("create_share_link: API error for folder %s: %s", folder_id, data.get('error'))
    except Exception as e:
        log.warning("create_share_link(%s) exception: %s", folder_id, e)
    
    return {}
def get_storage_info(sess: requests.Session, tokens: dict, account_id: Optional[int] = None) -> dict:
    try:
        data = jazzdrive.sapi_request(
            endpoint="/system/information",
            action="get",
            account_id=account_id,
            tokens={"validationkey": tokens.get('validation_key') or tokens.get('validationkey'),
                    "jsessionid": tokens.get('jsessionid')}
        )
        if not data.get('error'):
            info = data.get('data') or data
            used = info.get('usedspace') or info.get('used') or info.get('usedSpace') or 0
            total = info.get('totalspace') or info.get('total') or info.get('totalSpace') or 0
            free = int(total) - int(used) if str(total).isdigit() else 0
            return {'used': int(used) if str(used).isdigit() else 0, 'free': max(0, free)}
    except Exception:
        pass
    return {'used': 0, 'free': 0}
def _parse_episode_info(filename: str):
    m = re.search(r'[Ss](\d{1,2})[Ee](\d{1,3})', filename)
    if m:
        return int(m.group(1)), int(m.group(2))
    m = re.search(r'[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,3})', filename, re.IGNORECASE)
    if m:
        return int(m.group(1)), int(m.group(2))
    m = re.search(r'(\d{1,2})x(\d{1,2})', filename)
    if m:
        return int(m.group(1)), int(m.group(2))
    return None, None
def _parse_quality(filename: str) -> str:
    patterns = [
        (r'\b2160p\b|\b4K\b', '4K'), (r'\b1080p\b', '1080p'),
        (r'\b720p\b', '720p'), (r'\b480p\b', '480p'),
        (r'\bHDR\b', 'HDR'), (r'\bBluRay\b|\bBDRip\b', 'BluRay'),
        (r'\bWebRip\b|\bWEB-DL\b|\bWEBDL\b', 'WEB-DL'),
        (r'\bDVDRip\b', 'DVDRip'), (r'\bHDRip\b', 'HDRip'),
    ]
    for pattern, label in patterns:
        if re.search(pattern, filename, re.IGNORECASE):
            return label
    return ''
def _generate_fingerprint(remote_id: str, account_id: int) -> str:
    return f"jazz_{account_id}_{remote_id}"
def scan_account(account_id: int, progress_cb=None, extra_skip_folders=None) -> dict:
    from concurrent.futures import ThreadPoolExecutor, as_completed

    # Merge static skip set with any runtime-provided user exclusions
    _skip = SKIP_FOLDERS | {s.lower().strip() for s in (extra_skip_folders or []) if s.strip()}

    def emit(event, msg):
        log.info("[%s] %s", event, msg)
        schema.log_scan(account_id, event, msg)
        if progress_cb:
            progress_cb(event, msg)
            
    acct = schema.get_account(account_id)
    if not acct:
        emit('error', f'Account #{account_id} not found in database')
        return {}
        
    tokens = {
        'validation_key': acct.get('validation_key') or '',
        'jsessionid': acct.get('jsessionid') or '',
        'msisdn': acct.get('msisdn'),
    }
    if not tokens['validation_key'] or not tokens['jsessionid']:
        emit('error', 'Account has no session — please login first (paste validation_key + JSESSIONID from browser DevTools)')
        return {}
        
    sess = requests.Session()
    emit('scan_start', f"Starting scan for account: {acct.get('label')} ({acct.get('msisdn')})")
    
    storage = get_storage_info(sess, tokens, account_id=account_id)
    if storage['used'] or storage['free']:
        schema.update_account_storage(account_id, storage['used'], storage['free'])
        used_gb = storage['used'] / (1024**3)
        free_gb = storage['free'] / (1024**3)
        emit('info', f"Storage: {used_gb:.1f} GB used, {free_gb:.1f} GB free")
        
    emit('info', 'Mapping folder tree...')
    folder_path_map = {0: ''}
    all_folders_flat = {}
    visited = set()
    skipped_parent_ids: set = set()   # IDs of pruned subtree roots
    queue = [0]

    # Also seed the magic content root (name="/", magic=True) so the BFS
    # visits real content folders — all content folders are children of this
    # virtual root, and calling parent_id=0 alone misses them.
    #
    # IMPORTANT: pass tokens explicitly here. sapi_request resolves account_id
    # against the v3 DB, but scan_account receives a *legacy* account_id which
    # doesn't exist there.  Explicit tokens bypass the DB lookup entirely.
    try:
        _root_data = jazzdrive.sapi_request(
            "/media/folder/root", action="get",
            account_id=account_id,
            tokens={"validationkey": tokens["validation_key"],
                    "jsessionid": tokens["jsessionid"]},
        )
        _root_items = (_root_data.get("data") or {}).get("folders", [])
        for _it in _root_items:
            if _it.get("magic") or _it.get("name") == "/":
                _magic_id = int(_it["id"])
                folder_path_map[_magic_id] = ''
                if _magic_id not in queue:
                    queue.append(_magic_id)
                break
    except Exception:
        pass

    while queue:
        parent_id = queue.pop(0)
        if parent_id in visited:
            continue
        visited.add(parent_id)

        folders = list_folders(sess, tokens, parent_id, account_id=account_id)
        for f in folders:
            fid = f['id']
            parent_path = folder_path_map.get(parent_id, '')
            full_path = f"{parent_path}/{f['name']}".lstrip('/')
            folder_path_map[fid] = full_path

            # ── BFS pruning: skip this folder AND its entire subtree ─────────
            # Check both the folder name and every path segment so that a folder
            # nested inside a skipped parent is pruned even if its own name is
            # innocent (e.g. "Salaar (2023)" nested inside "uploads_test_archive").
            name_lower = f['name'].lower()
            path_parts = {seg.lower() for seg in full_path.replace('\\', '/').split('/') if seg}
            if (any(skip in name_lower for skip in _skip)
                    or any(skip in seg for skip in _skip for seg in path_parts)
                    or parent_id in skipped_parent_ids):
                skipped_parent_ids.add(fid)   # propagate prune to children
                continue                       # don't add to all_folders_flat or queue

            all_folders_flat[fid] = {**f, 'path': full_path}
            if fid not in visited:
                queue.append(fid)
        time.sleep(0.05)

    emit('info', f"Found {len(all_folders_flat)} folders. Scanning for videos in parallel...")
    
    all_files = []
    folders_visited = 0

    # folder_id (int) → {'filename': 'poster_N.jpg', 'share_url': '...'}
    # Written by scan_folder (thread-safe: GIL protects dict writes in CPython).
    _folder_poster_map: dict = {}

    def scan_folder(fid, folder_info):
        t_sess = requests.Session() # Thread-local session
        folder_path = folder_info['path']
        folder_name = folder_info['name']

        # Check both the immediate folder name and every segment of the full path.
        # The BFS already prunes skipped subtrees, but this is a second line of
        # defence in case anything slipped through (e.g. custom exclusions added
        # mid-scan via the UI).
        _path_segs = {seg.lower() for seg in folder_path.replace('\\', '/').split('/') if seg}
        if (any(skip in folder_name.lower() for skip in _skip)
                or any(skip in seg for skip in _skip for seg in _path_segs)):
            return []

        all_items = list_videos(t_sess, tokens, fid, account_id=account_id)

        # ── Separate poster-tagged items from real media ──────────────────────
        poster_items = [v for v in all_items if v.get('_is_poster')]
        videos       = [v for v in all_items if not v.get('_is_poster')]

        if not videos and not poster_items:
            return []

        # Share link (folder-level) — used for both media files and poster lookup.
        share_info = get_or_create_share_link(t_sess, tokens, fid, account_id=account_id)
        folder_share_url = share_info.get('share_url', '')

        # ── Record the first poster found for this folder ─────────────────────
        # We store the folder's share URL alongside the actual filename so the
        # v3 importer can set poster_share_url on the matched title.
        if poster_items and folder_share_url:
            best_poster = poster_items[0]   # prefer the first one found
            _folder_poster_map[str(fid)] = {
                'filename':  best_poster['filename'],
                'share_url': folder_share_url,
            }

        if not videos:
            return []

        emit('folder', f"📁 {folder_path} ({len(videos)} files)")

        folder_files = []
        for video in videos:
            season, episode = _parse_episode_info(video['filename'])
            quality = _parse_quality(video['filename'])
            fp = _generate_fingerprint(video['remote_id'], account_id)
            folder_files.append({
                'fingerprint': fp,
                'account_id': account_id,
                'filename': video['filename'],
                'season': season,
                'episode': episode,
                'size_bytes': video['size_bytes'],
                'quality': quality,
                'remote_id': video['remote_id'],
                'remote_folder_id': str(fid),
                'folder_path': folder_path,
                'share_url': folder_share_url,
                'share_key': share_info.get('share_key', ''),
                'share_link_id': share_info.get('share_link_id', ''),
                'share_folder_id': share_info.get('share_folder_id', ''),
                'is_ready': 1 if folder_share_url else 0,
                'uploaded_at': int(time.time()),
            })
        return folder_files

    # Use 10 threads for crawling
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(scan_folder, fid, info): fid for fid, info in all_folders_flat.items()}
        for future in as_completed(futures):
            try:
                res = future.result()
                if res:
                    all_files.extend(res)
                    folders_visited += 1
                    emit('progress', f"Files found so far: {len(all_files)}")
            except Exception as e:
                log.warning("Parallel folder scan error: %s", e)

    # ── Root-level loose file scan ─────────────────────────────────────────────
    # Some JazzDrive accounts keep files directly at parentId=0 (not inside any
    # named folder).  The BFS above only adds *sub-folders* to all_folders_flat,
    # so those loose files would be silently missed.  We try both parentId=0 and
    # the real root-folder ID (name="/") to catch them.
    try:
        seen_ids = {str(f['remote_id']) for f in all_files}
        root_candidates = [0]
        # Also try the real "/" folder ID if we found one during BFS
        for fid, info in all_folders_flat.items():
            if info.get('name') == '/':
                root_candidates.append(fid)
                break
        root_found = []
        for root_id in root_candidates:
            videos = list_videos(sess, tokens, root_id, account_id=account_id)
            for video in videos:
                # Skip poster-tagged items at root level — they don't belong
                # to a specific title folder and can't be matched.
                if video.get('_is_poster'):
                    continue
                rid = str(video['remote_id'])
                if rid in seen_ids:
                    continue
                seen_ids.add(rid)
                season, episode = _parse_episode_info(video['filename'])
                quality = _parse_quality(video['filename'])
                fp = _generate_fingerprint(video['remote_id'], account_id)
                root_found.append({
                    'fingerprint':    fp,
                    'account_id':     account_id,
                    'filename':       video['filename'],
                    'season':         season,
                    'episode':        episode,
                    'size_bytes':     video['size_bytes'],
                    'quality':        quality,
                    'remote_id':      video['remote_id'],
                    'remote_folder_id': str(root_id),
                    'folder_path':    '',
                    'share_url':      '',
                    'share_key':      '',
                    'share_link_id':  '',
                    'share_folder_id': '',
                    'is_ready':       0,
                    'uploaded_at':    int(time.time()),
                })
        if root_found:
            all_files.extend(root_found)
            emit('info', f"Found {len(root_found)} loose file(s) in JazzDrive root folder")
    except Exception as _re:
        log.debug("root loose-file scan: %s", _re)

    schema.mark_account_scanned(account_id)
    emit('scan_done', f"✅ Scan complete: {folders_visited} folders, {len(all_files)} files")
    return {
        'files':             all_files,
        'folders_scanned':   folders_visited,
        'files_found':       len(all_files),
        'folder_poster_map': _folder_poster_map,
    }
def enrich_and_save(files: list, account_id: int, progress_cb=None) -> int:
    def emit(event, msg):
        schema.log_scan(account_id, event, msg)
        if progress_cb:
            progress_cb(event, msg)
    grouped = {}
    for f in files:
        folder = f.get('folder_path', '')
        grouped.setdefault(folder, []).append(f)

    # Per-scan TMDB dedup cache: filename → (metadata, title_id)
    # Prevents calling TMDB 35× for the same file spread across nested archive folders.
    _tmdb_cache: dict = {}

    titles_done = 0
    for folder_path, folder_files in grouped.items():
        if not folder_files:
            continue
        sample = folder_files[0]['filename']
        prefer = 'tv' if any(
            f.get('season') or re.search(r'[Ss]\d{1,2}[Ee]\d{1,3}', f['filename'])
            for f in folder_files
        ) else 'auto'

        # Use cache key = (lowercase filename, prefer_type) so identical files in
        # different nested folders never hit TMDB more than once per scan.
        cache_key = (sample.lower(), prefer)
        if cache_key in _tmdb_cache:
            metadata, title_id = _tmdb_cache[cache_key]
        else:
            emit('tmdb', f"🔍 TMDB lookup: {sample}")
            metadata = enricher.fetch_full_metadata(sample, prefer_type=prefer)
            title_id = None
            if metadata and metadata.get('title') and metadata.get('content_key'):
                title_id = schema.upsert_title(metadata)
                emit('tmdb_ok', f"✅ {metadata['title']} ({metadata.get('year','')})")
                titles_done += 1
            else:
                emit('tmdb_miss', f"⚠️ No TMDB match for: {sample}")
            _tmdb_cache[cache_key] = (metadata, title_id)
            time.sleep(0.05)

        for file_rec in folder_files:
            file_rec['title_id'] = title_id
            schema.upsert_file(file_rec)
    return titles_done


def mobile_direct_verify_otp(msisdn: str, otp: str, proxies: Optional[dict] = None) -> dict:
    """Verify OTP via JazzDrive Android mobile API."""
    from .. import db as _db
    # Use the stored device ID/name so every login registers the SAME device on
    # JazzDrive. This eliminates the one-active-Android-device conflict with the
    # real phone — JazzDrive sees both as the same device.
    _m = str(msisdn).strip().replace("+92", "0").replace("+", "").replace(" ", "")
    device_id   = (_db.setting("JAZZDRIVE_DEVICE_ID") or "").strip() or f"fac-{_m[-10:]}"
    device_name = (_db.setting("JAZZDRIVE_DEVICE_NAME") or "Infinix Hot 9 Play").strip()
    encoded_otp    = urllib.parse.quote(str(otp).strip(),    safe='')
    encoded_msisdn = urllib.parse.quote(str(msisdn).strip(), safe='')

    sess = requests.Session()
    hdrs = {
        'User-Agent':       'Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)',
        'Accept':           'application/json, */*',
        'X-deviceid':       device_id,
        'X-devicename':     device_name,
        'X-Requested-With': 'com.jazz.drive',
    }

    candidates = [
        f'{CLOUD_BASE}/sapi/login/oauth?action=login&platform=Android&keytype=otp&key={encoded_otp}&msisdn={encoded_msisdn}',
        f'{CLOUD_BASE}/sapi/login?action=login&platform=Android&keytype=otp&key={encoded_otp}&msisdn={encoded_msisdn}',
        f'{CLOUD_BASE}/sapi/login/oauth?action=login&platform=Android&keytype=otp&key={encoded_otp}',
        f'{CLOUD_BASE}/sapi/login/oauth?keytype=otp&key={encoded_otp}&msisdn={encoded_msisdn}',
    ]

    for url in candidates:
        try:
            r = sess.get(url, headers=hdrs, timeout=25, proxies=proxies)
            log.debug("mobile_direct_verify: HTTP %d @ %s", r.status_code, url[:100])
            if r.status_code != 200:
                log.debug("mobile_direct_verify: HTTP %d body: %s", r.status_code, r.text[:150])
                continue
            try:
                body = r.json()
            except Exception:
                continue
            data = body.get('data', body) if isinstance(body, dict) else {}
            if not isinstance(data, dict):
                data = body if isinstance(body, dict) else {}
            vk  = (data.get('validationkey') or data.get('validation_key') or
                   data.get('accesstoken')   or data.get('access_token') or '')
            rt  = (data.get('refreshtoken')  or data.get('refresh_token') or
                   data.get('RefreshToken')  or '')
            jid = (data.get('jsessionid')    or data.get('JSESSIONID') or
                   data.get('sessionId')     or sess.cookies.get('JSESSIONID', '') or '')
            node = jid.split('.')[-1] if jid and '.' in jid else ''
            if vk:
                log.info("mobile_direct_verify: OK vk_len=%d rt=%s", len(vk), bool(rt))
                return {
                    'validation_key': vk,
                    'jsessionid':     jid,
                    'node':           node,
                    'refresh_token':  rt,
                }
            log.debug("mobile_direct_verify: 200 but no vk in body: %s", str(data)[:200])
        except Exception as _req_e:
            log.debug("mobile_direct_verify: error: %s", _req_e)

    raise RuntimeError(
        f"mobile_direct_verify_otp: all {len(candidates)} candidates failed"
    )


def jazzdrive_login(msisdn: str, use_android: bool = True, proxies: Optional[dict] = None) -> dict:
    """Initiate the JazzDrive OAuth2 login flow and trigger an OTP SMS."""
    # Critical: Normalize to local 03xxxxxxxxx format. 
    # International 923... format often fails to trigger the redirect to verify.php.
    m = msisdn.strip().replace(" ", "").replace("-", "").replace("+", "")
    if m.startswith("92"):
        msisdn_local = "0" + m[2:]
    elif m.startswith("3") and len(m) == 10:
        msisdn_local = "0" + m
    else:
        msisdn_local = m

    _UA_ANDROID = "Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)"
    _UA_WEB     = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) "
                   "Chrome/124.0.0.0 Safari/537.36")
    
    _UA = _UA_ANDROID if use_android else _UA_WEB

    sess = requests.Session()
    if proxies:
        sess.proxies = proxies
    sess.verify = False  # jazzdrive.com.pk bare domain has SSL hostname mismatch
    
    headers = {
        "Accept":           "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Accept-Language":  "en-US,en;q=0.9",
        "Origin":           OAUTH_BASE,
        "Referer":          OAUTH_BASE + "/",
        "User-Agent":       _UA,
    }
    if use_android:
        headers["X-Requested-With"] = "com.jazz.drive"
        headers.pop("Origin", None)
        headers.pop("Referer", None)
        
    sess.headers.update(headers)

    state = uuid.uuid4().hex
    if use_android:
        client_id    = ANDROID_CLIENT_ID
        redirect_uri = ANDROID_REDIRECT_URI
    else:
        client_id    = "web"
        redirect_uri = f"{CLOUD_BASE}/ui/html/oauth.html"

    # Step 1: GET authorization.php with allow_redirects=True → lands on signup.php
    try:
        r1 = sess.get(
            f"{OAUTH_BASE}/oauth2/authorization.php",
            params={"response_type": "code", "client_id": client_id,
                    "redirect_uri": redirect_uri, "state": state},
            allow_redirects=True,
            timeout=30,
            proxies=proxies,
        )
    except Exception as e:
        raise RuntimeError(f"Failed to reach authorization.php: {e}")

    signup_url = r1.url
    log.info("jazzdrive_login: authorization.php landed on %s", signup_url[:100])

    if "signup.php" not in signup_url and "id=" not in signup_url:
        raise RuntimeError(
            f"Expected signup.php redirect, got: {signup_url[:120]}"
        )

    # Step 2: POST msisdn to signup.php. Try multiple formats if one fails.
    # Formats to try: 03... (local), 923... (intl), 3... (raw)
    formats_to_try = [msisdn_local]
    if msisdn_local.startswith("0"):
        formats_to_try.append("92" + msisdn_local[1:])
        formats_to_try.append(msisdn_local[1:])
    
    verify_url = None
    last_r = r1

    for attempt_msisdn in formats_to_try:
        try:
            log.info("jazzdrive_login: attempting signup POST with %s", attempt_msisdn)
            r2 = sess.post(
                signup_url,
                data={"msisdn": attempt_msisdn, "enrichment_status": ""},
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                    "Referer":      signup_url,
                    "Origin":       OAUTH_BASE,
                },
                allow_redirects=True,
                timeout=30,
                proxies=proxies,
            )
            last_r = r2
            _body_full  = r2.text or ''
            _body_lower = _body_full.lower()

            # Accepted patterns: URL contains 'verify.php' OR contains 'id=' (the session token)
            # AND the body contains specific OTP verification signals.
            def _is_verify(url: str, body_lower: str) -> bool:
                if "verify.php" in url:
                    return True
                # Look for OTP input field or specific "Enter OTP" text to avoid false positives
                # from jQuery script tags or description text.
                if "id=" in url:
                    if 'name="otp"' in body_lower or 'name="code"' in body_lower:
                        return True
                    if 'id="otp"' in body_lower or 'id="code"' in body_lower:
                        return True
                    if 'enter verification code' in body_lower or 'enter otp' in body_lower:
                        return True
                    if 'verification code sent' in body_lower or 'otp sent' in body_lower:
                        return True
                    # Generic "code" and "sent"/"enter" combination
                    if 'code' in body_lower and ('sent' in body_lower or 'enter' in body_lower):
                        return True
                return False

            if _is_verify(r2.url, _body_lower):
                verify_url = r2.url
                break

            for resp in r2.history:
                loc = resp.headers.get("Location", "")
                if loc:
                    full_loc = (loc if loc.startswith("http")
                                else f"{OAUTH_BASE}/oauth2/{loc.lstrip('/')}")
                    if "verify.php" in full_loc:
                        verify_url = full_loc
                        break
            if verify_url:
                break
            
            log.debug("jazzdrive_login: format %s failed to trigger verify", attempt_msisdn)
            time.sleep(1) # be gentle on retries
        except Exception as e:
            log.warning("jazzdrive_login: signup POST failed for %s: %s", attempt_msisdn, e)

    if not verify_url:
        _body_full = last_r.text or ''
        _body_lower = _body_full.lower()
        _signals = [kw for kw in ('otp', 'verify', 'code', 'error', 'invalid', 'enter', 'resend', 'sms', 'sent') if kw in _body_lower]
        _err_msg = ""
        if "error" in _body_lower or "invalid" in _body_lower:
            import re as _re_err
            m_err = _re_err.search(r'(?:error|invalid|failed)[^>]*>([^<]{3,100})<', _body_full, _re_err.I)
            if m_err:
                _err_msg = f" (Server says: \"{m_err.group(1).strip()}\")"
        
        raise RuntimeError(
            f"OTP trigger failed{_err_msg}. signup.php did not redirect to verify. "
            f"Keywords: {_signals}. Last URL: {last_r.url[:120]}"
        )

    return {"verify_url": verify_url, "session": sess,
            "use_android": use_android, "msisdn": msisdn}



def _extract_raw_at(access_token_str: str) -> str:
    """Safe decoder: handles raw-hex (from refresh) and base64-JSON (from login).

    Verified guide §3: /oauth2/refresh_token.php returns raw 40-char hex.
    /sapi/login/oauth returns base64-JSON {"data":{"accesstoken":"...","refreshtoken":"..."}}.
    """
    try:
        pad  = (4 - len(access_token_str) % 4) % 4
        data = _json_mod.loads(_b64_mod.b64decode(access_token_str + "=" * pad).decode())
        return data.get("data", {}).get("accesstoken", access_token_str)
    except Exception:
        return access_token_str


def _decode_access_token(access_token_str: str) -> dict:
    """Decode a base64-JSON access_token. Returns {} on failure."""
    try:
        pad  = (4 - len(access_token_str) % 4) % 4
        return _json_mod.loads(
            _b64_mod.b64decode(access_token_str + "=" * pad).decode()
        ).get("data", {})
    except Exception:
        return {}


def jazzdrive_verify_otp(sess: requests.Session, verify_url: str, otp: str,
                         use_android: bool = True,
                         msisdn: str = "",
                         proxies: Optional[dict] = None) -> dict:
    """Submit OTP and exchange the auth code for long-lived Android tokens.

    Verified flow (jazzdrive_test.py — all 13 tests passing):
      Step 3:  POST OTP with allow_redirects=False, hop-by-hop until code= in Location.
               MUST NOT follow automatically — fetching clientoauth.html invalidates code.
      Step 4:  POST OAUTH_BASE/oauth2/token.php (standard OAuth2) → raw 40-char hex tokens.
               NOTE: /sapi/login/oauth?keytype=oauth2code ALWAYS returns HTTP 400.
      Step 4b: Wrap raw_at in base64-JSON, GET /sapi/login/oauth?keytype=accesstoken
               → fresh validationkey + JSESSIONID.
    """
    _UA_ANDROID = "Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)"
    _UA_WEB     = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) "
                   "Chrome/124.0.0.0 Safari/537.36")
    
    _UA = _UA_ANDROID if use_android else _UA_WEB

    # Set proxies on the session if provided to cover all sess.get/post calls (including redirects)
    if proxies:
        sess.proxies = proxies

    # Update headers for official app look
    sess.headers.update({
        "Accept":           "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "User-Agent":       _UA,
    })
    if use_android:
        sess.headers["X-Requested-With"] = "com.jazz.drive"
        sess.headers.pop("Origin", None)
        sess.headers.pop("Referer", None)
    else:
        sess.headers.update({
            "Origin":  OAUTH_BASE,
            "Referer": OAUTH_BASE + "/",
        })

    # ── Step 3: Submit OTP with manual hop-by-hop redirect interception ────────
    msisdn_clean = (msisdn or "").replace("+", "").replace(" ", "").replace("-", "")

    try:
        log.info("OTP POST to %s (msisdn=%s)", verify_url[:80], msisdn_clean)
        # CRITICAL: We MUST use allow_redirects=False and manually follow to capture the 'code'
        # from the Location header BEFORE it hits clientoauth.html (which invalidates it).
        r = sess.post(
            verify_url,
            data={'otp': str(otp)},
            headers={
                'Content-Type': 'application/x-www-form-urlencoded',
                'Referer':      verify_url,
                'User-Agent':   _UA,
            },
            allow_redirects=False,
            timeout=30,
            proxies=proxies,
        )
        log.info("Initial OTP POST status: %d, Location: %s", r.status_code, r.headers.get('Location'))
    except Exception as e:
        raise RuntimeError(f"OTP POST failed: {type(e).__name__}: {e}")

    def _extract_code(url: str):
        if not url: return None
        for part in (urllib.parse.urlparse(url).fragment,
                     urllib.parse.urlparse(url).query):
            if part:
                p = urllib.parse.parse_qs(part)
                if 'code' in p:
                    return urllib.parse.unquote(p['code'][0])
        m = re.search(r'[?&#]code=([a-zA-Z0-9.\-_=]+)', url, re.I)
        return urllib.parse.unquote(m.group(1)) if m else None

    code        = None
    current_url = verify_url
    
    # Manual hop-by-hop redirect follow to capture the code
    # JazzDrive redirects: verify.php -> clientoauth.html?code=... -> app redirect
    for hop in range(10):
        status   = r.status_code
        location = r.headers.get('Location', '')
        log.info("Hop %d: status=%d, url=%s, Location=%s", hop, status, r.url[:60], location[:60] if location else 'None')
        
        if location:
            if not location.startswith('http'):
                location = urllib.parse.urljoin(current_url, location)
            
            code = _extract_code(location)
            if code:
                log.info("Auth code intercepted at hop %d (Location: %s)", hop, location[:60])
                break
        
        if status == 200:
            # Check body if code wasn't in redirect (some flows do this)
            code = _extract_code(r.url) or _extract_code(r.text)
            if code:
                log.info("Auth code found in page at hop %d", hop)
                break
            # If no code and status 200, we might be on the error page or success page without code
            break
            
        if status not in (301, 302, 303, 307, 308) or not location:
            break
            
        # Follow the redirect one hop at a time
        current_url = location
        try:
            r = sess.get(current_url, allow_redirects=False, timeout=20)
        except Exception as _hop_e:
            log.warning("OTP hop %d GET failed: %s", hop, _hop_e)
            break

    if not code:
        # Check body for common success patterns or errors
        body = r.text or ''
        log.info("Auth code not found. Response body starts with: %s", body[:300])
        # Save response for debugging
        try:
            debug_path = Path("radd-hub/data/otp_last_response.html")
            debug_path.parent.mkdir(parents=True, exist_ok=True)
            debug_path.write_text(body)
            log.info("Saved OTP response body to %s (status=%d)", debug_path, r.status_code)
        except Exception as _e:
            log.debug("Failed to save debug body: %s", _e)

        # Aggressive code search in body (any length, any format)
        m = re.search(r'[?&#]code=([a-zA-Z0-9.\-_=]+)', body, re.I)
        if m:
            code = m.group(1)
            log.info("Auth code found in page body (len=%d).", len(code))
        else:
            log.warning("OTP verification failed. Status: %d, Final URL: %s", r.status_code, r.url)
            
            if "invalid" in body.lower() or "error" in body.lower():
                m_err = re.search(r'(?:error|invalid|failed)[^>]*>([^<]{3,100})<', body, re.I)
                if m_err:
                    raise RuntimeError(f"OTP verification failed: {m_err.group(1).strip()}")
                if "invalid otp" in body.lower():
                    raise RuntimeError("OTP verification failed: Invalid OTP entered.")
                if "expired" in body.lower():
                    raise RuntimeError("OTP verification failed: OTP or session expired.")

    if not code:
        raise RuntimeError(
            f"OTP verification failed — no auth code in redirect chain. "
            f"Last URL: {r.url[:150]}"
        )

    log.info("Auth code extracted (len=%d), POSTing to /oauth2/token.php ...", len(code))

    # ── Step 4: POST /oauth2/token.php — standard OAuth2 code exchange ─────────
    # VERIFIED: this is the ONLY endpoint that works.
    # /sapi/login/oauth?keytype=oauth2code always returns HTTP 400 (JazzDrive homepage).
    try:
        r4 = sess.post(
            f"{OAUTH_BASE}/oauth2/token.php",
            data={
                "grant_type":    "authorization_code",
                "code":          code,
                "client_id":     ANDROID_CLIENT_ID,
                "client_secret": ANDROID_CLIENT_SECRET,
                "redirect_uri":  ANDROID_REDIRECT_URI,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            timeout=30,
            verify=False,  # jazzdrive.com.pk bare domain SSL hostname mismatch
        )
    except Exception as e:
        raise RuntimeError(f"token.php POST network error: {e}")

    log.info("token.php → HTTP %d  (%d bytes)", r4.status_code, len(r4.content))
    if r4.status_code != 200:
        raise RuntimeError(f"token.php HTTP {r4.status_code}. Body: {r4.text[:400]}")

    log.info("token.php raw response: %s", r4.text[:500])
    try:
        tok_body = r4.json()
    except Exception:
        raise RuntimeError(f"Non-JSON from token.php: {r4.text[:300]}")

    raw_at = tok_body.get("access_token", "")
    raw_rt = tok_body.get("refresh_token", "")

    if not raw_at:
        raise RuntimeError(f"No access_token in token.php response: {tok_body}")

    log.info("token.php OK — raw_at=%s... has_rt=%s", raw_at[:12], bool(raw_rt))

    # ── Step 4b: Extract JSESSIONID from redirect-chain cookies (fastest path) ──
    # During the hop-by-hop redirect above, the session naturally visits
    # cloud.jazzdrive.com.pk/clientoauth.html which sets JSESSIONID (and sometimes
    # validation_key) as cookies.  If they're already here, use them directly —
    # no SAPI silent-login call needed.
    _cloud_cookies: dict = {}
    for c in sess.cookies:
        if "cloud.jazzdrive" in (c.domain or ""):
            _cloud_cookies[c.name] = c.value

    _jid_from_chain = (_cloud_cookies.get("JSESSIONID") or
                       _cloud_cookies.get("jsessionid") or "")
    _vk_from_chain  = (_cloud_cookies.get("validation_key") or
                       _cloud_cookies.get("validationkey") or "")

    if _jid_from_chain:
        log.info(
            "JSESSIONID obtained directly from OAuth redirect chain (no SAPI call needed) "
            "jid=%s... vk=%s", _jid_from_chain[:16], bool(_vk_from_chain)
        )
        _node = _jid_from_chain.split('.')[-1] if '.' in _jid_from_chain else ''
        return {
            'validation_key':  _vk_from_chain,
            'jsessionid':      _jid_from_chain,
            'node':            _node,
            'refresh_token':   raw_rt,
            'raw_accesstoken': raw_at,
            'access_token':    raw_at,
        }

    # Cookies not set yet — try fetching clientoauth.html explicitly.
    # This is what a real browser does after the OTP redirect; it sets JSESSIONID
    # on cloud.jazzdrive.com.pk naturally without any geo-restricted SAPI endpoint.
    if current_url and "cloud.jazzdrive" in current_url and "clientoauth" in current_url:
        try:
            log.info("Fetching clientoauth.html to obtain session cookies: %s", current_url[:100])
            _rc = sess.get(current_url, timeout=20, proxies=proxies)
            log.info("clientoauth.html → HTTP %d", _rc.status_code)
            for c in sess.cookies:
                if "cloud.jazzdrive" in (c.domain or ""):
                    _cloud_cookies[c.name] = c.value
            _jid_from_chain = (_cloud_cookies.get("JSESSIONID") or
                               _cloud_cookies.get("jsessionid") or "")
            _vk_from_chain  = (_cloud_cookies.get("validation_key") or
                               _cloud_cookies.get("validationkey") or "")
            if _jid_from_chain:
                log.info("JSESSIONID obtained via clientoauth.html fetch: jid=%s...", _jid_from_chain[:16])
                _node = _jid_from_chain.split('.')[-1] if '.' in _jid_from_chain else ''
                return {
                    'validation_key':  _vk_from_chain,
                    'jsessionid':      _jid_from_chain,
                    'node':            _node,
                    'refresh_token':   raw_rt,
                    'raw_accesstoken': raw_at,
                    'access_token':    raw_at,
                }
        except Exception as _coe:
            log.debug("clientoauth.html fetch failed: %s", _coe)

    # Last resort: SAPI silent-login using the raw_accesstoken.
    # This endpoint is geo-restricted by JazzDrive to PK IPs, so it may fail
    # from non-Pakistani servers.  Clear any stale cloud.jazzdrive cookies first.
    _stale = [
        (c.domain, c.path, c.name)
        for c in sess.cookies
        if "cloud.jazzdrive" in (c.domain or "")
    ]
    for _d, _p, _n in _stale:
        try:
            sess.cookies.clear(_d, _p, _n)
        except Exception:
            pass
    if _stale:
        log.info("Cleared %d stale cloud.jazzdrive cookie(s) before SAPI fallback: %s",
                 len(_stale), [n for _, _, n in _stale])

    msisdn_clean = (msisdn or "").replace("+", "").replace(" ", "").replace("-", "")
    device_id    = (f"android-raddhub-{msisdn_clean[-10:]}" if len(msisdn_clean) >= 10
                    else "android-raddhub-12345678")

    at_json  = _json_mod.dumps({"data": {"accesstoken": raw_at}})
    at_b64e  = urllib.parse.quote(_b64_mod.b64encode(at_json.encode()).decode(), safe="")
    
    # We try multiple candidates to avoid HTTP 500
    candidates = [
        (f"{CLOUD_BASE}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64e}", "Android-Nested"),
        (f"{CLOUD_BASE}/sapi/login/oauth?action=login&platform=web&keytype=accesstoken&key={at_b64e}", "Web-Nested"),
        (f"{CLOUD_BASE}/sapi/login/oauth?keytype=accesstoken&key={at_b64e}", "Legacy-Direct"),
        (f"{CLOUD_BASE}/sapi/login?action=login&platform=Android&keytype=accesstoken&key={at_b64e}", "Android-Raw"),
    ]

    # Temporarily restore SSL verification for cloud.jazzdrive.com.pk (valid cert)
    _prev_verify = sess.verify
    sess.verify = True
    sess.headers.update({
        "Accept":             "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With":   "com.jazz.drive",
        "X-deviceid":         device_id,
        "User-Agent":         "Dalvik/2.1.0 (Linux; U; Android 10; Infinix X680F Build/QP1A.190711.020)",
    })
    # Remove browser headers for pure app look
    sess.headers.pop("Origin", None)
    sess.headers.pop("Referer", None)
    
    last_err = "No candidates tried"
    r4b = None
    for sapi_url, label in candidates:
        try:
            log.info("sapi silent login: trying %s @ %s", label, sapi_url[:100])
            r4b = sess.get(sapi_url, timeout=30, proxies=proxies)
            if r4b.status_code == 200:
                log.info("✓ %s candidate succeeded", label)
                break
            last_err = f"[{label}] HTTP {r4b.status_code}: {r4b.text[:200]}"
            log.debug("sapi silent login: %s candidate failed: %s", label, last_err)
        except Exception as e:
            last_err = str(e)
            log.debug("sapi silent login: %s network error: %s", label, last_err)
    
    sess.verify = _prev_verify

    if not r4b or r4b.status_code != 200:
        # SAPI silent login is blocked on non-Pakistani IPs (JazzDrive geo-restricts
        # the keytype=accesstoken endpoint to PK network ranges).
        # Return a partial result so the caller can persist refresh_token + raw_at,
        # and prompt the user to paste browser cookies instead.
        log.warning(
            "SAPI silent login blocked (%s) — returning partial tokens "
            "(no JSESSIONID). User must paste browser cookies to activate session.",
            last_err,
        )
        return {
            "validation_key":  "",
            "jsessionid":      "",
            "node":            "",
            "refresh_token":   raw_rt,
            "raw_accesstoken": raw_at,
            "access_token":    raw_at,
            "_sapi_blocked":   True,
            "_sapi_error":     last_err,
        }

    try:
        body4b = r4b.json()
        d = body4b.get("data", body4b) if isinstance(body4b, dict) else {}
    except Exception:
        raise RuntimeError(f"Non-JSON from sapi silent login: {r4b.text[:300]}")

    vk  = d.get("validationkey") or d.get("validation_key") or d.get("ValidationKey") or ""
    jid = (d.get("jsessionid") or d.get("JSESSIONID")
           or r4b.cookies.get("JSESSIONID") or "")

    if not jid:
        raise RuntimeError(
            f"Silent login 200 but missing JSESSIONID. data={d}"
        )

    node = jid.split('.')[-1] if jid and '.' in jid else ''

    log.info("Android token exchange complete — vk=%s... jid=%s... rt=%s",
             vk[:12], jid[:12], bool(raw_rt))
    return {
        'validation_key':  vk,
        'jsessionid':      jid,
        'node':            node,
        'refresh_token':   raw_rt,
        'raw_accesstoken': raw_at,
        'access_token':    raw_at,
    }