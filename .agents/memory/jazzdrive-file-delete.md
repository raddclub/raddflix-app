---
name: JazzDrive delete/trash quirks
description: trash_files() returns success but doesn't actually soft-delete; always use delete_files_permanent()
---

## Rule
Always use `delete_files_permanent(account_id, [file_ids])` for cleanup.
Never use `trash_files()` for either `media_type="file"` or `media_type="video"` — both return false-positive success without actually removing the file.

**Why:** Confirmed in TASK-049 (file-type) and TASK-050 (video-type: Vncenz0 duplicates appeared un-trashed after TASK-047 called trash_files on them).

**How to apply:** Any time you need to remove a file from JazzDrive (delta cleanup, orphan cleanup, duplicate removal), call `delete_files_permanent()`. Document this in code comments.
