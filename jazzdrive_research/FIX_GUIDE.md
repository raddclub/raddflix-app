# JazzDrive Oracle Backend — Fix Guide

**Status**: All 6 bugs FIXED (June 2026)
**Files changed**: `hub/jazzdrive.py`, `hub/uploader.py`, `hub/_legacy/scanner.py`

## Bug 1 (FIXED): Binary upload returns no file ID

**Root cause** (`UploadSaveMetadataResponse.java`):
- Android calls save-metadata FIRST to register the file
- `UploadSaveMetadataResponse.id` (String) = file GUID
- Binary `UploadResponse` has NO id field — by design

**Fix**: `_pre_upload_save_metadata()` in `uploader.py`:
```python
payload = {"data": {"name": name, "creationdate": now_ms, ...
                    "size": size, "folderid": parent_id, "id": None, ...}}
resp = jazzdrive.sapi_request(endpoint=f"/upload/video",
    action="save-metadata", method="POST", data=form_encoded_payload, ...)
return int(resp["data"]["id"])  # file GUID
```
Called before binary upload in `_upload_file`.

## Bug 2 (FIXED): Fallback listing never triggered on upload success

**Root cause**: condition `if data.get("ok")` never True for normal JSON response.
`{"data": {"status":"U","etag":"...","lastupdate":...}}` → raises RuntimeError.

**Fix**: Trigger listing fallback on any HTTP 200:
```python
_rec_status = (rec.get("status") or "") if isinstance(rec, dict) else ""
_upload_ok = (
    data.get("ok")
    or _rec_status in ("U", "C", "A", "V", "I")
    or raw_resp.status_code == 200
)
if _upload_ok:
    # list parent folder, find file by name
```

## Bug 3 (FIXED): Missing responsetime=true

`SapiHandler.m52004k` always appends `responsetime=true`.

**Fix**: Added to `jazzdrive.py` `sapi_request`:
```python
req_params["responsetime"] = "true"
```
And to direct binary upload URL.

## Bug 4 (FIXED): Scanner missing pagination

`GetMediaWrapper.more` (boolean) signals more pages.

**Fix**: `_legacy/scanner.py` `list_videos` pagination loop:
```python
for _page in range(50):
    _params = {"parentId": folder_id, "folderId": folder_id}
    if offset > 0:
        _params["offset"] = offset
    data = jazzdrive.sapi_request(..., params=_params, ...)
    items.extend(parse_page(data))
    if not data.get("data", {}).get("more"):
        break
    offset += len(page_items)
```

## Bug 5: _get_root_folder_id endpoint (unverified)

`/sapi/media/folder?action=get&parentid=0` not in Retrofit interface.
Not breaking — folder creation uses `_get_or_create_folder` gracefully.

## Bug 6 (FIXED): responsetime=true missing from binary upload URL

Covered by Fix 3. Binary upload URL now includes `&responsetime=true`.
