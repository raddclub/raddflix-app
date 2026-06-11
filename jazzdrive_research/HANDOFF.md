# JazzDrive RE Handoff

## Session Summary (June 2026)

### APK RE Complete
XAPK decompiled (29,381 Java files at `/tmp/jd_decompiled/`).
Key files: `ItemUploadTask.java`, `MediaSapi.java`, `SapiHandler.java`,
`GetMediaWrapper.java`, `UploadResult.java`, `Item.java`, `C33227f.java`,
`UploadSaveMetadataResponse.java`, `UploadSaveMetadataRequest.java`.

### Critical Finding: How Android Gets File IDs
The Android app calls `POST /sapi/upload/{mediaType}?action=save-metadata` BEFORE
the binary upload. The response (`UploadSaveMetadataResponse`) contains the `id`
field (String) which is the server-assigned file GUID. Oracle was missing this step.

### All 6 Backend Bugs Fixed
See `FIX_GUIDE.md` for details. All fixes applied to Oracle at `/opt/jazzmax/radd-hub/hub/`:
- `jazzdrive.py`: `responsetime=true` added to all SAPI calls
- `uploader.py`: `_pre_upload_save_metadata()` + fixed fallback condition
- `_legacy/scanner.py`: pagination loop for `more=true` pages

### Oracle Server
- IP: `92.4.95.252`
- SSH: `/tmp/oracle_key`
- Flask service: `sudo supervisorctl restart raddflix_radd`
- Port: 5000
- Repo: `/opt/jazzmax/` (git remote: raddclub/raddflix-app)

### Remaining Work
1. Test uploads end-to-end to confirm `_pre_upload_save_metadata` returns real GUIDs
2. Verify `/sapi/media/folder?action=get&parentid=0` works (Bug 5)
3. Test scanner pagination with a large account (>100 files)
