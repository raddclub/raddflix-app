---
name: JazzDrive duplicate upload guard
description: Both upload paths in uploader.py have JD-side pre-check to prevent duplicate uploads
---

## State (as of 2026-06-08)
Both upload paths are protected:
- `upload_to_jazzdrive()` at ~L1287 — TASK-048 guard
- `_upload_pending()` at ~L1791 — TASK-050 guard

## Guard logic
After folder resolution, query `/media/video?parentId=FOLDER_ID&folderId=FOLDER_ID`.
Compare `plan.filename.lower()` against all non-softdeleted names in the folder.
If match: UPDATE files SET is_ready=1, record remote_id + share_url, call clear_live_stat(), return.
Guard is non-fatal: exceptions log debug and fall through to upload.

**Why:** `_upload_pending()` calls `_upload_file()` directly and bypassed the upload_to_jazzdrive() guard entirely. Without this, re-queued or reset-DB files would upload duplicates.

**How to apply:** If adding a new upload code path, it must also include this JD-side pre-check after folder resolution, before the actual upload call.

## TASK-051 additional bugs fixed (2026-06-08)

**BUG-A: Poster duplicate accumulation** (`routes/library.py` push-poster-to-jd route)
- Route always re-uploaded `poster.jpg` without checking if one exists → JD accumulated `poster (1).jpg`, `poster (2).jpg` etc.
- Fix: query `/media/video` for existing `poster*.jpg` in folder, call `delete_files_permanent()` on all found, then upload fresh.
- `assets.py:process_title_poster()` was ALREADY safe (early-return if `poster_share_url` exists in DB).

**BUG-B: `_get_or_create_folder()` race condition** (`uploader.py`)
- No lock → two concurrent threads (scheduler + manual upload for same show) both see folder missing → both call `_create_folder()` → duplicate JD folders.
- Fix: per-(parent_id, name) lock `_get_folder_create_lock()`, double-check after acquiring, retry `_list_folders()` if `_create_folder()` fails.

**BUG-C: `_upload_pending()` missing `rename_video()`** (`uploader.py`)
- `upload_to_jazzdrive()` calls `rename_video()` post-upload (defense-in-depth). `_upload_pending()` skipped this.
- Fix: added `rename_video()` call after `_set_file_folder()` in `_upload_pending()`.

## Full _upload_file() call site audit (safe reference)
- `uploader.py` retry loop inside `upload_to_jazzdrive()` ✅ guarded
- `uploader.py _upload_pending()` ✅ TASK-050 + TASK-051 BUG-C
- `routes/library.py` poster ✅ TASK-051 BUG-A
- `assets.py process_title_poster()` ✅ early-return guard
- `keepalive.py` heartbeat ✅ intentional unique-name accumulation
