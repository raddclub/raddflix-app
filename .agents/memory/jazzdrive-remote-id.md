---
name: JazzDrive remote_id — permanent file identifier
description: JD's permanent file ID (remote_id) system, full chain from Oracle to Flutter Pass 0, and how folder shares work
---

## The Permanent File ID

Every file uploaded to JazzDrive is assigned a permanent integer **`id`** (called `remote_id`
in our Oracle DB and Flutter SQLite). Examples: `242518443`, `242518530`.

This ID:
- Is assigned at upload time and **never changes** — survives renames and folder moves
- Is the `id` field in all JazzDrive SAPI responses (`/sapi/media/video`, etc.)
- Is what `rename_video()`, `delete_files_permanent()`, and `trash_files()` accept as input

**Why:** Share URLs point to folders (not individual files). When two episodes share the same
folder share URL, the SAPI media response returns both files. `remote_id` is the only
filename-independent way to pick the correct one.

## Oracle DB Storage

```
files.remote_id TEXT          — e.g. "242518443" (stored as string, no UNIQUE constraint)
files.fingerprint TEXT UNIQUE — "scan:242518443" (derived from remote_id, unique per file)
files.share_url               — folder share URL (may be shared across episodes)
files.share_key               — extracted share key from share_url
```

## The Full Chain (Oracle → Flutter → JazzDrive)

```
1. Oracle /api/catalog/sync
   SELECT f.remote_id FROM files f WHERE ... AND season > 0
   Response: {"episodes": [..., {"remote_id": 242518443, "share_url": "...", ...}]}

2. Flutter sync_service.dart _persistItems()
   LocalDb.upsertEpisode({'remote_id': ep['remote_id'] as int? ?? 0, ...})
   → stored in SQLite episodes.remote_id column

3. Flutter local_db.dart getShareInfo(fileId, titleId)
   final remoteId = epRows.first['remote_id'] as int? ?? 0;
   return {'share_url': url, 'filename': filename, 'remote_id': remoteId};

4. Flutter player_screen.dart _openMedia()
   remoteId = shareInfo['remote_id'] as int? ?? 0;
   JazzDriveService.getStreamLink(cacheKey, shareUrl, remoteId: remoteId)

5. Flutter jazzdrive_service.dart _getMedia() — Pass 0
   for each record in JD SAPI response:
     if m['id'] == remoteId → MATCH (exact permanent ID, O(n))
   Falls through to Pass 1-3 filename matching only if remoteId == 0
```

## Folder Share Pattern (Spider-Noir, Vincenzo)

Episodes of the same show share **one folder share URL** containing all episodes:

```
Spider-Noir S01E01  file_id=37  remote_id=242518443  share_url=.../hoIyg7SgSFi...
Spider-Noir S01E02  file_id=36  remote_id=242518530  share_url=.../hoIyg7SgSFi...  ← SAME URL!
```

When Flutter calls `getStreamLink("37", share_url, remoteId: 242518443)`:
- JD returns 2 records: `{id:242518443, name:"Spider Noir S01E01.mp4"}` and `{id:242518530, name:"Spider Noir S01E02.mp4"}`
- Pass 0 matches `id == 242518443` → S01E01 selected ✅
- Cache key is `fileId` ("37" vs "36") → each episode has its own separate CDN URL cached ✅

## VERDICT: System is Correct (Audited 2026-06-09)

All components verified. No code changes were needed.

| Layer | Component | Status |
|-------|-----------|--------|
| Oracle DB | `files.remote_id` column | ✅ correct |
| Oracle API | `/sync` returns `remote_id` per episode | ✅ correct |
| Oracle admin | `rename_video`, `delete_files_permanent` use `remote_id` | ✅ correct |
| Flutter sync | `_persistItems` writes `remote_id` to SQLite | ✅ correct |
| Flutter DB | `episodes.remote_id` column (via ALTER TABLE migration) | ✅ correct |
| Flutter DB | `getShareInfo` returns `remote_id` in result map | ✅ correct |
| Flutter player | passes `remoteId` to `getStreamLink` | ✅ correct |
| Flutter JD service | Pass 0 matches by `m['id'] == remoteId` | ✅ correct |

**Why:** The system was designed this way from the start. `remote_id` is the correct
permanent identifier. Filename-based fallback (Passes 1-3) is a safety net only.
