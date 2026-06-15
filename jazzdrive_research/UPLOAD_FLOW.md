# JazzDrive Upload Flow

> Source: `hub/uploader.py` and `hub/jazzdrive.py`. Verified 2026-06-15.

---

## Upload Pipeline Overview

```
Local file in /data/media/
    │
    ▼
files table (state=pending)
    │
    ▼
_scan_once()  [background watcher, every 30s]
    │  Finds pending files
    ▼
_upload_pending()
    │
    ├─ get_active_account()         Read account from DB (prioritizes role='flix')
    ├─ verify_jd_session()          Probe /sapi/media/folder?parentId=0 — needs live VK+JID
    │   └─ If fails: refresh_session() → android_refresh_session → sapi_direct_login
    │
    ├─ _get_or_create_folder()      Walk/create folder tree: /MovieTitle (Year)/
    ├─ Duplicate guard              GET /sapi/media/video — checks if filename already uploaded
    │   └─ If duplicate: record existing remote_id, skip upload, go to share link
    │
    ├─ _pre_upload_save_metadata()  POST save-metadata (placeholder creation)
    ├─ _upload_file()               POST multipart with ProgressReader wrapper
    │   └─ Proxy chain retry: mark_fail on connection error, try next proxy
    │
    ├─ _set_file_folder()           Move file into correct folder (if not already there)
    ├─ _create_share_link()         Create public folder share link
    │
    └─ DB update: state=done, remote_id, remote_folder_id, share_url, folder_path
```

---

## Session Verification (`verify_jd_session`)

```python
# Probes /sapi/media/folder?parentId=0 — NOT /sapi/system/information
# Reason: system/information returns 200 even with expired JSESSIONID (VK-only check).
# Folder list requires a LIVE JSESSIONID — catches cookie-expiry accurately.
def verify_jd_session(vk: str, jsid: str, account_id: Optional[int]) -> bool:
    data = jazzdrive.sapi_request(endpoint="/media/folder", action="get",
                                  params={"parentId": 0}, ...)
    return not data.get("error")
```

If `verify_jd_session` returns False, the uploader calls `refresh_session()` before proceeding.
If refresh also fails, the file is released back to `state=pending` and the job is marked `session_dead`.

---

## Folder Structure

JazzDrive folders are created under the account root:
```
/  (root folder — real ID from /sapi/media/folder?parentId=0, NOT id=0)
└── MovieTitle (Year)/
    ├── MovieTitle (Year).mp4
    └── poster.jpg
```

For TV shows:
```
/
└── Show Title (Year)/
    └── Season 01/
        ├── Show Title S01E01.mp4
        └── poster.jpg
```

**Root folder ID**: The real root folder ID is NOT `0`. It is returned by the folder list API
(the folder whose name is `"/"`). Cached in `_root_folder_id_cache` by JSESSIONID prefix.

---

## Duplicate Guard

Before uploading, the uploader calls `list_all_files_in_folder(account_id, folder_id)`:
```
GET /sapi/media/video?action=get&parentId=<folder_id>&validationkey=<vk>
```

If a file with the same name already exists in JazzDrive:
1. Log `JD duplicate guard: '<filename>' already in folder <id> as remote_id=<id> — skipping upload`
2. Record the existing `remote_id` in the DB.
3. Skip the binary upload.
4. Proceed directly to share link creation.

This guard prevents re-uploading files that are already on JazzDrive after a Flask restart
interrupted a previous upload that was actually complete on the JazzDrive side.

---

## Upload Request Details

```
POST /sapi/upload/video?action=upload&validationkey=<vk>&responsetime=true
Content-Type: multipart/form-data; boundary=<boundary>

--<boundary>
Content-Disposition: form-data; name="filesize"
<size_in_bytes>
--<boundary>
Content-Disposition: form-data; name="name"
<filename.ext>
--<boundary>
Content-Disposition: form-data; name="parentId"
<folder_id>
--<boundary>
Content-Disposition: form-data; name="file"; filename="<filename.ext>"
Content-Type: video/mp4
<binary data>
--<boundary>--
```

**Progress tracking**: Uses a `ProgressReader` wrapper on the file object that calls
`_update_live_stat()` on every `read()` call, writing bytes_done + total to an in-memory dict
for the live upload progress UI.

---

## Share Link

After a successful upload (or duplicate guard), the uploader creates a public share link on the **folder** (not the file):

```
POST /sapi/media/folder/share?action=create&validationkey=<vk>
Content-Type: application/json

{"data": {"id":<folder_id>,"type":"public","folderid":<folder_id>}}
```

The resulting `share_url` is stored in `files.share_url` and used by the Flutter player
to generate direct streaming links.

---

## Auto-Delete

If `upload_auto_delete=true` in DB settings, local files are deleted after upload completes:
- Delete only if `share_url IS NOT NULL OR remote_id IS NOT NULL`.
- Files with neither are NOT deleted (upload may have partially failed).

---

## Upload States

| State | Meaning |
|-------|---------|
| `pending` | Waiting to be uploaded. Default state. |
| `in_progress` | Currently being uploaded by the watcher. |
| `done` | Upload complete. `remote_id`, `share_url` populated. |
| `session_dead` | Upload attempted but JD session is dead. Re-login required. |
| `error` | Upload failed with a non-session error. |

The watcher resets `in_progress` → `pending` on startup (in case Flask restarted mid-upload).

---

## Proxy Behavior for Upload

With `JAZZDRIVE_PROXY_BYPASS=1` (current Oracle setting):
- All upload traffic goes via `wg0` VPN directly to `cloud.jazzdrive.com.pk`.
- No proxy pool used. `resolve_proxies()` returns `None`.
- JazzDrive is not geo-restricted — direct upload from Oracle (Indian IP via wg0) works.

Without bypass (non-VPN environments):
- `get_proxy_chain(n=max_retries+2)` fetches a list of PK proxies before the retry loop.
- Each retry attempt uses a DIFFERENT proxy from the chain.
- Connection errors: `pool.mark_fail(proxy_url)` → proxy demoted immediately.
- HTTP 407: marks proxy bad and raises clear error.
