# RaddFlix Streaming Architecture — Source of Truth

> **Read this before touching anything related to streams, downloads, or catalog.**

---

## The Two-Tier System — Critical Mental Model

RaddFlix is built around two completely separate infrastructure tiers. Always know which tier you are in:

| Tier | URL | Zero-rated on Jazz SIM? | Requires internet bundle? |
|------|-----|------------------------|--------------------------|
| **Oracle server** | 92.4.95.252 | ❌ NO | ✅ YES — regular data bundle needed |
| **JazzDrive CDN** | cloud.jazzdrive.com.pk | ✅ YES | ❌ NO — always works on Jazz SIM |

**What zero-rated means in Pakistan:** Jazz Telecom network-level whitelists `cloud.jazzdrive.com.pk`. Traffic to that domain does not require a data bundle — it works even when the user has Rs.0 balance and no active package. This is a Jazz network feature, the same mechanism used for JazzCash, JazzWorld app, etc. It is NOT the same as "free with a bundle" — it means the bundle is not required at all.

---

## How a Video Plays — Step by Step

When a user taps Play on a RaddFlix catalog title:

```
Step 1: share_url lookup (no network)
  App reads the file's share_url from local SQLite DB.
  share_url was stored during the last Oracle catalog sync.
  Example: https://cloud.jazzdrive.com.pk/share/f/XXXXXX

Step 2: JazzDrive API login (zero-rated — no bundle needed)
  POST https://cloud.jazzdrive.com.pk/sapi/link/login?action=login
  Body: { "data": { "accesstoken": "XXXXXX" } }
  Response: validationKey + JSESSIONID cookie

Step 3: JazzDrive API media fetch (zero-rated — no bundle needed)
  GET https://cloud.jazzdrive.com.pk/sapi/media/video?action=get&shared=true&key=...&validationkey=...
  Response: direct CDN stream URL (e.g. https://cloud.jazzdrive.com.pk/cdn/...)

Step 4: Cache CDN URL (3 hours — memory + SQLite stream_cache table)

Step 5: media_kit player opens the CDN URL → video plays (zero-rated)
```

**The Oracle server (92.4.95.252) is NOT involved at playback time.**
**Steps 2 and 3 are zero-rated — work without any data bundle on Jazz SIM.**

Code: `lib/core/services/jazzdrive_service.dart` → `JazzDriveService.getStreamLink()`

---

## NEVER Do This

**NEVER route JazzDrive API calls through the Oracle server.**

If the app ever calls Oracle to get a CDN URL, and Oracle calls JazzDrive on behalf of the app, then traffic goes: Phone → Oracle → JazzDrive. The Phone→Oracle leg is NOT zero-rated. Zero-rating breaks for all users.

The two JazzDrive API calls (`/sapi/link/login` and `/sapi/media/video`) **must always be made directly from the phone to `cloud.jazzdrive.com.pk`**.

---

## The share_url — Most Important Secret

Every title/episode in local SQLite has a `share_url` — a JazzDrive file share link:
```
https://cloud.jazzdrive.com.pk/share/f/XXXXXX
```
This is stored in the `files` table (episodes) and `titles` table (movies) in the app's encrypted SQLite DB.

**If someone extracts share_urls → they can stream content without the app and without a subscription.**

Protection:
- SQLCipher AES-256 on local DB (key from Android Keystore — hardware-backed)
- Delta JSON (zero-rated catalog sync) contains metadata ONLY — NO share_url, NO file_id
- Full catalog sync (with share_urls) only comes from Oracle → requires bundle/WiFi

---

## Download Flow

Downloads use the exact same JazzDrive link generation as streaming:
1. `JazzDriveService.getStreamLink()` → same 2 zero-rated JazzDrive API calls → CDN URL
2. App downloads from CDN URL to `<app-documents>/downloads/<fileId>.mp4`

Both streaming and downloading are zero-rated. Both share the same `stream_cache` SQLite table (3h TTL).

---

## What Oracle Does vs What JazzDrive Does

| Operation | Goes to Oracle? | Goes to JazzDrive? | Requires bundle? |
|-----------|----------------|-------------------|-----------------|
| Login / registration | ✅ Yes | ❌ No | ✅ Yes |
| Catalog sync (gets share_urls) | ✅ Yes | ❌ No | ✅ Yes |
| Subscription / quota check | ✅ Yes | ❌ No | ✅ Yes |
| Watch history sync | ✅ Yes | ❌ No | ✅ Yes |
| Get stream/download CDN URL | ❌ No | ✅ Yes | ❌ No (zero-rated) |
| Actual video streaming | ❌ No | ✅ Yes (CDN) | ❌ No (zero-rated) |
| Downloading a video file | ❌ No | ✅ Yes (CDN) | ❌ No (zero-rated) |
| Playing a downloaded file | ❌ No | ❌ No | ❌ No (local file) |
| Browsing catalog (already synced) | ❌ No | ❌ No | ❌ No (local SQLite) |

---

## Catalog Sync — Two Paths

### Path 1: Oracle Sync (requires internet bundle or WiFi)
- Fetches full catalog including `share_url` and `file_id` for every title/episode
- Endpoints: `GET /api/catalog/sync` (full) and `GET /api/catalog/delta?since=<ts>` (incremental)
- Code: `SyncService._syncFromOracle()` in `sync_service.dart`
- Upserts complete rows into local SQLite including share_url

### Path 2: JazzDrive Delta (zero-rated — PARTIALLY IMPLEMENTED)
- Fetches `delta.json` from `AppConstants.jazzDriveDeltaUrl`
- Contains metadata ONLY: id, title, year, description, poster_url, genres, is_free, media_type, language, status, is_ongoing, rating, season_count, episode_count, db_version
- **NEVER includes file_id or share_url** — security requirement (see Rule 5 in REINCARNATION.md)
- Uses `LocalDb.mergeDeltaTitle()` which preserves existing share_url from prior Oracle syncs
- Code: `SyncService._syncFromJazzDriveDelta()` in `sync_service.dart`

**Current gap:** `AppConstants.jazzDriveDeltaUrl` returns `$apiBaseUrl/api/catalog/delta` (Oracle).
True zero-rated catalog updates require: upload a `delta.json` file to a JazzDrive share folder
and update this constant to point at that JazzDrive URL.
Until then, catalog sync always requires a bundle.

---

## Stream Link Cache

CDN URLs expire in ~1-2 hours. The app caches them for 3 hours:
- Layer 1: In-memory `Map<String, _CacheEntry>` — instant, lost on app restart
- Layer 2: `stream_cache` table in local SQLite — survives restarts, loaded on app start
- On expiry: auto-retry once — fetches fresh share_url from Oracle, invalidates cache, re-calls JazzDrive

Player `_jazzAutoRetry()` detects expired links and refreshes transparently during playback.

---

## Offline Behavior Summary

| User situation | Can stream? | Can download? | Can browse catalog? |
|---------------|------------|--------------|-------------------|
| Jazz SIM, no bundle, share_url in DB | ✅ Zero-rated | ✅ Zero-rated | ✅ Local cache |
| Jazz SIM, no bundle, share_url missing | ❌ (needs Oracle) | ❌ (needs Oracle) | ✅ Local cache |
| Jazz SIM, has bundle | ✅ | ✅ | ✅ |
| Non-Jazz SIM, has bundle | ✅ (uses data) | ✅ (uses data) | ✅ |
| Any SIM, airplane mode | ❌ | ❌ | ✅ Local cache |
| Downloaded content (any SIM) | ✅ Local file | — | ✅ |

**Key insight:** First-time setup (login + catalog sync) requires a bundle or WiFi once.
After that, Jazz SIM users stream freely without any bundle.
