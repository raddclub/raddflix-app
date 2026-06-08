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
  share_url was stored during the last Oracle catalog sync or JazzDrive delta sync.
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
- Delta JSON (zero-rated catalog sync) **includes share_urls** — security relies on APK
  integrity (AppGuard signature check + Frida detection), not on link hiding. A cracked APK
  gets fake empty data, never real share_urls.
- Oracle full catalog sync also includes share_urls and **requires JWT auth**
  (added 2026-06-02). Oracle = complete database; JazzDrive delta = full published snapshot.

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

> **Oracle catalog endpoints require JWT auth** (added 2026-06-02, commit `53e02a3b`).
> Flutter already sends `Authorization: Bearer <token>` via `_AuthInterceptor`. No client change needed.
> Endpoints `/api/catalog/sync`, `db_update`, `delta`, `share_url`, `batch`, `play` → 401 without token.
> Public exceptions: `/api/catalog/version`, `poster/<id>` — no streaming secrets.

---

## Catalog Sync — Two Paths

### Path 1: Oracle Sync (requires internet bundle or WiFi)
- Fetches full catalog including `share_url` and `file_id` for every title/episode
- Endpoints: `GET /api/catalog/sync` (full) and `GET /api/catalog/delta?since=<ts>` (incremental)
- Code: `SyncService._syncFromOracle()` in `sync_service.dart`
- Upserts complete rows into local SQLite including share_url

**Timeout behaviour (TASK-042, 2026-06-08):**

```
_syncFromOracle():
  getVersion().timeout(5s)    ← lightweight probe — returns 3 integers
    If Oracle responds → proceed to syncFull() / syncDelta() with 30s timeout
    If times out (5s) → TimeoutException → caught by sync() → falls to Path 2

api_client.dart Dio options:
  connectTimeout: 6s   ← was 15s before TASK-042
  receiveTimeout: 30s  ← unchanged (catalog downloads need this on slow connections)
```

No-bundle users fall to JazzDrive delta in ≤ 5 seconds total.
Users with internet have Oracle respond in < 1s — no impact.
Users with slow-but-real internet: probe takes 2-4s, Oracle sync continues normally.

### Path 2: JazzDrive Delta (zero-rated — always available without bundle)
- Fetches `delta.json` from `AppConstants.jazzDriveDeltaUrl` (set by RemoteConfig on startup)
- Contains **full playback data** — includes `share_url`, `file_id`, `folder_share_url`, and
  complete episode lists per show
- Is a **full snapshot** of all published titles from Oracle
- Uses `LocalDb.mergeDeltaTitle()` which preserves any share_url from prior Oracle syncs
- Code: `SyncService._syncFromJazzDriveDelta()` in `sync_service.dart`

**Sync priority (always Oracle first, delta as fallback):**
```
sync() flow:
  try:
    _syncFromOracle()    → full Oracle sync (getVersion probe + catalog fetch)
  catch ANY exception:   → TimeoutException, DioException, SocketException, etc.
    _syncFromJazzDriveDelta()
```

**Security model:** share_urls in delta.json are permanent (never expire). Security is enforced
by APK integrity — AppGuard signature check + Frida detection. A cracked APK sees fake empty
data, never real share_urls. See ZERO_RATING_DELTA.md and SECURITY_ARCHITECTURE.md.

---

## RemoteConfig — Delta URL Startup Behaviour (TASK-040, 2026-06-08)

```
main() before runApp():
  await RemoteConfig.loadCached()
    → reads jd_delta_url from SharedPreferences (INSTANT — no network)
    → AppConstants.jazzDriveDeltaUrl is set before app renders any frame
    → works even with no internet (uses cached value from last online session)

main() after runApp() — fire-and-forget, NOT awaited:
  RemoteConfig.fetchBackground()
    → hits Oracle /api/config with 4-second timeout
    → updates AppConstants.jazzDriveDeltaUrl in memory (hot update)
    → refreshes SharedPreferences for next cold start
    → silently ignored if Oracle is unreachable
```

This guarantees `jazzDriveDeltaUrl` is always populated when `_syncFromJazzDriveDelta()` runs,
even on the very first cold start of an offline Jazz SIM user.

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
After delta sync runs (≤5s on cold start), Jazz SIM users have an up-to-date catalog.
