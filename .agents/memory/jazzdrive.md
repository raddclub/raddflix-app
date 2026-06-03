---
name: JazzDrive CDN Integration
description: Zero-rating, share_urls, SAPI flow, delta.json format, upload status
---

# JazzDrive CDN Integration

## What JazzDrive Is
Jazz's cloud storage (cloud.jazzdrive.com.pk). Jazz zero-rates all traffic to/from this domain at network level — Jazz SIM users pay no data charges for streaming.

## Share URLs Are Public
`share_url` values stored in the DB are **public links** — no JazzDrive login needed to resolve them to a CDN URL. The security model is APK integrity (AppGuard), not link secrecy.

**Why this matters:** If you see JazzDrive SAPI 401 errors in server logs, that means the SERVER cannot upload new files to JazzDrive. It does NOT mean streaming is broken. Existing share_urls are public and work without authentication.

## Playback Flow (NEVER change this)
```
1. Flutter reads share_url from local SQLite (no network)
2. POST cloud.jazzdrive.com.pk/sapi/link/login
   Body: { shareUrl, device_id }
   Response: { validationKey, JSESSIONID }
3. GET cloud.jazzdrive.com.pk/sapi/media/video
   Headers: JSESSIONID cookie + validationKey
   Response: { cdnUrl }
4. Cache cdnUrl for 3 hours in stream_cache SQLite table
5. media_kit opens cdnUrl — zero-rated streaming begins
```

Code: `raddflix_flutter/lib/core/services/jazzdrive_service.dart → JazzDriveService.getStreamLink()`

**CRITICAL:** Never route JazzDrive API calls through Oracle. Phone→Oracle is NOT zero-rated.

## delta.json Format
Uploaded to JazzDrive by `delta_push.py`. Contains:
```json
{
  "version": 1780437662,
  "titles": [ { "id": 1, "title": "...", "poster_share_url": "...", ... } ],
  "episodes": [ { "title_id": 1, "season": 1, "episode": 1, "file_share_url": "..." } ]
}
```

**BUG-S01 (UNFIXED):** `delta.json` version field does NOT include `catalog_forced_version` from settings table. After force-bump, server returns bumped version from `/api/catalog/version` but delta.json still has old version → infinite re-sync loop.

## folder_share_url
All titles currently have `folder_share_url = NULL` (Known Issue R3). This field would enable folder-based episode resolution for TV shows. Currently unused because JazzDrive SAPI 401 prevents new uploads.

## Current JazzDrive Status
- 44/45 files have `share_url` populated → streaming works for 44 files
- Server SAPI: 401 → cannot upload new files or poster images
- delta.json: last generated with old `version` field (BUG-S01 needs fixing)
