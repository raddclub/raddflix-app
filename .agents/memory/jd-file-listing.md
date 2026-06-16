---
name: JazzDrive file listing
description: /media/video is blind to non-video (file-type) items; use /media/file endpoint for those
---

## Rule
- `/media/video` — lists uploaded video files. Returns 0 results for items with `mediatype="file"` (e.g. delta.txt, delta.json uploaded via the file upload API).
- `/media/file?action=get&parentId=FOLDER_ID` — lists non-video files. Returns `data.files[]` with a `folder` field. Filter client-side by folder ID.
- `list_all_files_in_folder(account_id, folder_id)` in `jazzdrive.py` encapsulates this correctly.

**Why:** Radd-Delta folder stores delta.txt as a file-type item. Early code used /media/video to check the folder, returned 0 results, and accumulated orphaned delta files.

**How to apply:** Use /media/video for movie/episode video files. Use /media/file (or list_all_files_in_folder) for anything uploaded as a non-video file (delta, metadata, etc).
