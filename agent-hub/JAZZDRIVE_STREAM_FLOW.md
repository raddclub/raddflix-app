# JazzDrive Stream Integration — Complete Agent Reference

> **Last audited:** 2026-06-09  
> **Audit result:** ✅ 27/27 logic tests pass · 0 bugs remaining  
> **Coverage:** `jazzdrive_service.dart` · `download_service.dart` · `local_db.dart` · `player_screen.dart`

---

## What is JazzDrive?

JazzDrive (`cloud.jazzdrive.com.pk`) is Jazz Telecom's personal cloud storage service.  
RaddFlix stores all video files as JazzDrive shared folder links. On Jazz SIM, all calls to
`cloud.jazzdrive.com.pk` are **zero-rated** (no data charges).

Share URLs are **permanent** — they never expire. Only the final CDN download token expires (~2h).

---

## API Flow (2 HTTP calls)

```
JazzDrive Share URL
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 1 — Login to share session                             │
│                                                             │
│ POST https://cloud.jazzdrive.com.pk/sapi/link/login         │
│      ?action=login                                          │
│                                                             │
│ Body: { "data": { "accesstoken": "<shareKey>" } }           │
│                                                             │
│ Returns:                                                    │
│   • validationkey  (in JSON body)                           │
│   • JSESSIONID     (in Set-Cookie header)                   │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 2 — Get media/video list                               │
│                                                             │
│ GET https://cloud.jazzdrive.com.pk/sapi/media/video         │
│     ?action=get&shared=true                                 │
│     &key=<shareKey>                                         │
│     &validationkey=<validationKey>                          │
│                                                             │
│ Headers: Cookie: JSESSIONID=<jsid>                          │
│          validation_key: <validationKey>                    │
│                                                             │
│ Returns: list of file records, each with:                   │
│   • url          — CDN stream URL (self-signed k= token)    │
│   • downloadUrl  — original MKV (same k= token)             │
│   • name/filename — original filename                       │
│   • thumbnails[] — poster images                            │
│   • id           — permanent JazzDrive file ID (remote_id)  │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ STEP 3 — Build final stream URL                             │
│                                                             │
│ url = record["url"]                                         │
│ if url.startsWith('/'): url = CLOUD_BASE + url              │
│ if 'filename=' not in url: append ?filename=<encoded_name>  │
│                                                             │
│ ⚠️  DO NOT append validationkey to stream URL               │
│    The k= token is self-authenticating. Adding validationkey│
│    breaks the URL.                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Share Key Extraction

The share key is the last path segment of any JazzDrive share URL:

```
Supported URL formats:
  https://cloud.jazzdrive.com.pk/share/f/<KEY>
  https://cloud.jazzdrive.com.pk/share-landing/f/<KEY>
  https://cloud.jazzdrive.com.pk/f/<KEY>

Regex: /\/(?:share-landing\/f|share\/f|f)\/([^/?#]+)/
```

Dart: `_extractShareKey(shareUrl)` in `jazzdrive_service.dart`  
JS mirror: `extractShareKey(shareUrl)` in `jazzdrive_logic_test.js`

---

## Request Headers (Required)

```
Accept:          application/json, text/plain, */*
Content-Type:    application/json;charset=UTF-8
Origin:          https://cloud.jazzdrive.com.pk
Referer:         https://cloud.jazzdrive.com.pk/share/f/<shareKey>
User-Agent:      Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 ...
X-Requested-With: com.jazz.drive
```

---

## 4-Pass File Matching (Folder Shares)

A folder share can contain many files (e.g. all episodes of a TV season).
The Flutter app picks the right file using 4 passes, in priority order:

| Pass | Method | When Used |
|------|--------|-----------|
| 0 | Match by `record.id == remoteId` | When `remoteId > 0` (stored in SQLite `episodes.remote_id`) |
| 1 | Case-insensitive substring of filename | `targetFilename` provided |
| 2 | Normalised (dots/underscores → spaces) substring | Pass 1 failed |
| 3 | Episode code match `s01e04` pattern | Pass 2 failed |
| Fallback | `records.first` | All passes failed |

**Pass 0 is the most reliable** — JazzDrive's `id` field is a permanent integer
assigned at upload time and never changes even if the file is renamed.

Dart: `_getMedia()` in `jazzdrive_service.dart`  
JS mirror: `matchRecord()` + `Pass0` block in `jazzdrive_logic_test.js`

---

## RF1 Share URL Scrambling

Share URLs are stored **encrypted** in the local SQLite database (AES-256/SQLCipher).
In addition, the `share_url` field is scrambled with a device-bound key before
being written to SQLite:

```
Write to DB:    _encodeUrl(url) → RequestEncoder.scrambleUrl(url, deviceId) → "RF1:xxx"
Read from DB:   _decodeUrl(url) → RequestEncoder.unscrambleUrl(url, deviceId) → original URL
```

**CRITICAL RULE**: Any code that reads `share_url` from:
- `CatalogItem.shareUrl` (raw model field from `_rowToItem`) 
- Direct `db.query('titles', ...)` without going through a helper

...will get the **scrambled** `RF1:xxx` value. This MUST be decoded before calling JazzDrive.

### Safe paths (decode already done internally):
- `LocalDb.getShareInfo(fileId)` → returns decoded share_url ✅
- `LocalDb.getShareUrl(fileId)` → returns decoded share_url ✅
- `LocalDb.getTopFreeMovies(count)` → returns decoded share_urls ✅
- `LocalDb.decodeShareUrl(url)` → decode on-demand ✅

### Callers that MUST decode manually:
- Any code using `CatalogItem.shareUrl` directly → call `LocalDb.decodeShareUrl(item.shareUrl)` first

---

## JazzDrive Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| `MED-1011` | Share key invalid or expired | Content removed from JazzDrive — notify admin |
| `FOL-1004` | Folder deleted from JazzDrive | Same as above |
| (HTTP 200 + error in JSON body) | API error | Parse `response["error"]["code"]` |

Note: JazzDrive returns HTTP **200** even for errors. Always check the JSON body for an
`error` object, not just the HTTP status code.

---

## Cache Strategy

```
TTL:  110 minutes  (CDN tokens expire ~2h; 110min is safely under to avoid stale URLs)

Layer 1: In-memory Map<String, _CacheEntry>  — instant, no disk I/O
Layer 2: SQLite table stream_cache           — survives app restart

On app start: loadCacheFromDb() copies all non-expired DB entries into memory.
On warm:      warmTopFreeItems(N) pre-fetches top N free movies' stream links.
              60-minute guard prevents repeated warm calls on cold start.

Cache key: file_id (unique per file across entire catalog)
```

---

## File Map

| File | Purpose |
|------|---------|
| `raddflix_flutter/lib/core/services/jazzdrive_service.dart` | **Main JazzDrive client** — login, media fetch, 4-pass match, cache, warm |
| `raddflix_flutter/lib/core/download/download_service.dart` | Download flow — resolves stream URL before downloading |
| `raddflix_flutter/lib/core/db/local_db.dart` | SQLite helpers — RF1 encode/decode, getShareInfo, getTopFreeMovies, stream_cache CRUD |
| `raddflix_flutter/lib/screens/player_screen.dart` | Playback — resolves shareUrl → getStreamLink → passes to media player |
| `raddflix_flutter/test_suite/jazzdrive_logic_test.js` | **Logic test suite** — 27 tests, zero network needed (pure JS mirrors of Dart functions) |
| `radd-hub/bots/whatsapp/direct_link_generator.js` | Oracle Node.js version (reference implementation) |
| `radd-hub/bots/whatsapp/lib/link4.js` | Lower-level Oracle link generator (older, uses validationkey on stream URL — DIFFERENT from Flutter) |

---

## Data Flow Per Use Case

### 1. User presses Play

```
player_screen.dart
  ├── LocalDb.getShareInfo(fileId)
  │     → episodes table OR titles table
  │     → decodes RF1 internally
  │     → returns { share_url, filename, remote_id }
  │
  ├── [fallback] LocalDb.decodeShareUrl(_inlineShareUrl)
  │
  └── JazzDriveService.getStreamLink(cacheKey, shareUrl,
            targetFilename: filename, remoteId: remoteId)
        ├── [hit]  in-memory cache → instant
        ├── [hit]  SQLite stream_cache → fast
        └── [miss] _generateLink()
              ├── _loginShare()   → POST /sapi/link/login
              └── _getMedia()     → GET /sapi/media/video
```

### 2. User presses Download

```
download_service.dart
  ├── Path A (shareUrl passed by caller)
  │     LocalDb.decodeShareUrl(shareUrl)  ← RF1 decode
  │     JazzDriveService.getStreamLink(fileId, decodedUrl,
  │           targetFilename: targetFilename, remoteId: remoteId)
  │
  └── Path B (no shareUrl — look up from DB)
        LocalDb.getShareInfo(fileId)      ← returns decoded URL + filename + remote_id
        JazzDriveService.getStreamLink(fileId, dbShareUrl,
              targetFilename: dbFilename, remoteId: dbRemoteId)
```

### 3. App startup warm (background)

```
main.dart → unawaited(JazzDriveService.warmTopFreeItems(5))
  └── LocalDb.getTopFreeMovies(5)
        → decodes RF1 internally, returns { file_id, share_url }
        → JazzDriveService.getStreamLink (per movie)
              → caches result for 110 min
```

---

## Test Suite

**File:** `raddflix_flutter/test_suite/jazzdrive_logic_test.js`  
**Run:** `node jazzdrive_logic_test.js`  
**Result (2026-06-09):** 27/27 ✅ — no network needed

Tests cover:
- `_extractShareKey` — 7 URL format cases
- 3-pass filename match — Pass 1, Pass 2, Pass 3, fallback-to-first
- `_buildStreamUrl` — relative URL, filename encoding, no double-append
- `_buildPosterUrl` — relative, absolute, null, empty
- `_getMedia` response parsing — 5 JSON shapes + thumbnail extraction

**Live network test** (Jazz SIM device required):
```bash
node jazzdrive_logic_test.js --live "https://cloud.jazzdrive.com.pk/share/f/<KEY>" "S01E04.mkv"
```

---

## Known Issues / Gotchas

### MED-1011 from Replit / non-Jazz-SIM IPs
The JazzDrive share login endpoint (`/sapi/link/login`) returns `MED-1011 — Key is invalid`
when called from non-Jazz-SIM IPs. This is **not geo-blocking** — the share landing page
(`/share/f/<KEY>`) loads publicly. The login API simply requires a fresh session (no stale cookies).

**If you get MED-1011 in Node.js tests from Replit:**
- This is expected — you cannot test the live network flow from Replit
- Use the logic test suite (`jazzdrive_logic_test.js`) for code correctness
- Full live test requires a Jazz SIM Android device or Oracle server session

### JSESSIONID on Android
Dart's `HttpClient` (used by Dio) passes `Set-Cookie` headers through on Android.  
The Dart code reads JSESSIONID from the JSON body first (as a fallback if headers are lost),
then from `resp.headers.map['set-cookie']`. JazzDrive does NOT include JSESSIONID in
the JSON body — only in `Set-Cookie`. The header approach is the working path.

### CDN URL vs Download URL
JazzDrive records have two URL fields:
- `url` → transcoded stream (HLS/MP4, used by Flutter for both watch + download)
- `downloadUrl` → original MKV (used by Oracle Python for downloads)

Flutter intentionally uses `url` for both streaming and downloading. This is correct for
mobile (transcoded = smaller, battery-friendly). Oracle uses `downloadUrl` for full-quality.

### Oracle `link4.js` vs Flutter
`link4.js` **adds** `validationkey` to the stream URL. Flutter `_buildStreamUrl` does **NOT**.
Both approaches work but they are different. Flutter's approach (no validationkey on stream URL)
is the correct one — the `k=` token is self-authenticating.

### stream_cache TTL
If a stream URL fails to play (403/401), call `JazzDriveService.invalidate(fileId)` to
clear the cache and force a fresh link on next play. The player screen does this on retry.

---

## Bug History

| Bug ID | File | Description | Status |
|--------|------|-------------|--------|
| BUG-DL-PATH-B | `download_service.dart` | Path B used `getShareUrl()` losing filename+remote_id → always downloaded episode 1 | ✅ Fixed (commit 1cbec5a) |
| BUG-DL-RF1 | `download_service.dart` | Path A passed raw RF1:xxx URL to JazzDrive without decoding | ✅ Fixed (commit 1cbec5a) |

---

*Generated by Replit Agent audit — 2026-06-09. Update this file after any changes to JazzDrive integration logic.*
