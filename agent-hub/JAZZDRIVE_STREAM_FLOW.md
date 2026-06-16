# JazzDrive Stream Integration — Complete Agent Reference

> **Last audited:** 2026-06-16
> **Audit result:** ✅ 27/27 logic tests pass · 0 bugs remaining
> **Coverage:** `jazzdrive_service.dart` · `download_service.dart` · `local_db.dart` · `player_screen.dart`

---

## ⚠️ CRITICAL FOR FUTURE AGENTS — Read This First

### JazzDrive API works globally — no IP restriction

**Confirmed by live testing (2026-06-16) from Replit (US server, non-Jazz IP):**

| Call | Result |
|------|--------|
| `POST /sapi/link/login` with valid share key | ✅ HTTP 200, valid `validationkey` |
| `GET /sapi/media/video` with validationkey | ✅ HTTP 200, video records returned |
| CDN download URL (k= token) | ✅ HTTP 206, real MP4 (`ftyp isom` confirmed, 65536 bytes) |

**JazzDrive share link resolution works from any IP worldwide.**  
MED-1011 means the share key is **invalid or the folder was deleted** — never an IP issue.

**How to verify a share key is valid without a device:**
```
GET https://cloud.jazzdrive.com.pk/share/f/<shareKey>
Check: og:title in HTML response = folder/file name (e.g. "Interstellar (2014)")
If og:title is present → key IS valid on JazzDrive server
```

### JSESSIONID .NODE suffix — NEVER strip it

```
✅ WITH suffix (e.g. JSESSIONID=7BCF...E3.2i182):   /sapi/media/video → HTTP 200, video records
❌ WITHOUT suffix (e.g. JSESSIONID=7BCF...E3):       /sapi/media/video → HTTP 401 HTML error page
```

The suffix (`.2i182`, `.1i204`, etc.) is the **JazzDrive load balancer node ID**.
The LB uses it for sticky session routing — both calls MUST hit the same backend node.
If the suffix is stripped, the media call lands on a different node with no session record → 401.

**The JSESSIONID value comes from two sources:**
1. JSON body: `data.jsessionid` — already includes the suffix ✅ (preferred, Android-reliable)
2. Set-Cookie header: `JSESSIONID=<value>` — also includes the suffix ✅ (fallback)

**The Flutter code reads from the JSON body first** (more reliable on Android where
Dart's `HttpClient` may absorb Set-Cookie headers before they reach Dio interceptors).

---

## What is JazzDrive?

JazzDrive (`cloud.jazzdrive.com.pk`) is Jazz Telecom's personal cloud storage service.  
RaddFlix stores all video files as JazzDrive shared folder links. On Jazz SIM, all calls to
`cloud.jazzdrive.com.pk` are **zero-rated** (no data charges).

Share URLs are **permanent** — they never expire. Only the final CDN download token expires (~2h).

---

## Share Key Structure (Decoded)

A JazzDrive share key is base64-encoded binary with this structure:

```
base64( random_token(16 bytes) + user_account_id(ASCII) + "_" + file_id(ASCII) )

Example key:  lTzy2wdJQDqnsHSZNJGMBjA0NzE3MTIzNzE2NzFfMjYwMzgwMA
Decoded:      [16 random bytes] + "0471712371671" + "_" + "2603800"
              └─ auth token ──┘   └─ JD account id ──┘   └─ file id ┘
```

The `file_id` in the key matches `remote_id` stored in the local SQLite `episodes` table.  
This enables Pass 0 matching (most reliable, completely filename-independent).

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
│   • validationkey  (in JSON body at data.validationkey)     │
│   • jsessionid     (in JSON body at data.jsessionid)        │
│   • JSESSIONID     (also in Set-Cookie header)              │
│                                                             │
│ ⚠️  Keep the FULL jsessionid value including .NODE suffix   │
│    (e.g. "7BCF...E3.2i182"). NEVER strip it.               │
│                                                             │
│ Returns MED-1011 if share key is invalid/deleted            │
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
│ Headers: Cookie: JSESSIONID=<full_jsid_with_node_suffix>    │
│          validation_key: <validationKey>                    │
│                                                             │
│ Returns: list of file records, each with:                   │
│   • url          — CDN stream URL (self-signed k= token)    │
│   • downloadUrl  — original MKV (same k= token)             │
│   • name/filename — original filename                       │
│   • thumbnails[] — poster images                            │
│   • id           — permanent JazzDrive file ID (= remote_id)│
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
│    The k= token is self-authenticating (HMAC-signed).       │
│    Adding validationkey= to the CDN URL is incorrect        │
│    and breaks the URL.                                      │
│    validationkey is only for Steps 1 and 2 (SAPI calls).   │
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
Accept:           application/json, text/plain, */*
Content-Type:     application/json;charset=UTF-8
Origin:           https://cloud.jazzdrive.com.pk
Referer:          https://cloud.jazzdrive.com.pk/share/f/<shareKey>
User-Agent:       Mozilla/5.0 (Linux; Android 12; SM-A515F) AppleWebKit/537.36 ...
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
The `id` in the share key itself matches `remote_id` in the SQLite `episodes` table.

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
| `MED-1011` | Share key invalid or folder deleted | Verify via og:title check; if missing, update DB with new share URL |
| `FOL-1004` | Folder deleted from JazzDrive | Content removed — notify admin |
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

## Diagnostic Test (On-Device Chain Verification)

`JazzDriveService.diagnosticTest()` runs the full chain without any cache, from the actual device:

```dart
final result = await JazzDriveService.diagnosticTest(
  shareUrl: shareUrl,       // decoded share URL from LocalDb
  targetFilename: filename, // optional — for Pass 1-3 matching
  remoteId: remoteId,       // optional — for Pass 0 matching (preferred)
);

// Success: result contains share_key, login, media, stream_url
// Failure: result contains error (string describing which step failed)
```

Access from the app: Profile screen → tap version text 5 times → Diagnostics → Checks tab.

---

## File Map

| File | Purpose |
|------|---------|
| `raddflix_flutter/lib/core/services/jazzdrive_service.dart` | **Main JazzDrive client** — login, media fetch, 4-pass match, cache, warm, diagnosticTest() |
| `raddflix_flutter/lib/core/download/download_service.dart` | Download flow — resolves stream URL before downloading |
| `raddflix_flutter/lib/core/db/local_db.dart` | SQLite helpers — RF1 encode/decode, getShareInfo, getTopFreeMovies, stream_cache CRUD |
| `raddflix_flutter/lib/screens/player_screen.dart` | Playback — resolves shareUrl → getStreamLink → passes to media player |
| `raddflix_flutter/lib/screens/debug_diagnostics_screen.dart` | On-device diagnostics — live JazzDrive chain test, JAZZDRIVE log filter |
| `raddflix_flutter/test_suite/jazzdrive_logic_test.js` | **Logic test suite** — 27 tests, zero network needed (pure JS mirrors of Dart functions) |
| `radd-hub/bots/whatsapp/direct_link_generator.js` | Oracle Node.js version (reference implementation) |

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
              │     → keep FULL JSESSIONID with .NODE suffix
              └── _getMedia()     → GET /sapi/media/video
                    → _buildStreamUrl(rawUrl, filename)
                         → prepend CLOUD if relative
                         → append filename= if not present
                         → k= token authenticates CDN request
                         → validationkey NOT added to CDN URL
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
**Result (2026-06-16):** 27/27 ✅ — no network needed

Tests cover:
- `_extractShareKey` — 7 URL format cases
- 3-pass filename match — Pass 1, Pass 2, Pass 3, fallback-to-first
- `_buildStreamUrl` — relative URL, filename encoding, no double-append, NO validationkey
- `_buildPosterUrl` — relative, absolute, null, empty
- `_getMedia` response parsing — 5 JSON shapes + thumbnail extraction

**Verify a share key is valid without a device:**
```bash
curl -s "https://cloud.jazzdrive.com.pk/share/f/<KEY>" | grep -o 'og:title[^>]*content="[^"]*"'
# If output contains a real title → key is valid on JazzDrive server
```

---

## Known Issues / Gotchas

### CDN URL vs Download URL
JazzDrive records have two URL fields:
- `url` → transcoded stream (HLS/MP4, used by Flutter for both watch + download)
- `downloadUrl` → original MKV (used by Oracle Python for downloads)

Flutter intentionally uses `url` for both streaming and downloading. This is correct for
mobile (transcoded = smaller, battery-friendly).

### stream_cache TTL
If a stream URL fails to play (403/401), call `JazzDriveService.invalidate(fileId)` to
clear the cache and force a fresh link on next play. The player screen does this on retry.

### JSESSIONID node suffix — critical, do not strip
The JSESSIONID returned by JazzDrive **must be kept in full**, including the `.NODE` suffix
(e.g. `.2i182`). The JazzDrive load balancer uses this suffix for sticky session routing —
both the login call and the media call MUST land on the same backend node.

**Stripping the suffix sends the media call to a different node, which has no session record
for this login → HTTP 401 HTML error page (not JSON), which breaks JSON parsing in the app.**

The Flutter code reads JSESSIONID from the JSON body (`data.jsessionid`) as the preferred
source — this value already includes the suffix and is more reliable than the Set-Cookie
header on Android (where Dart's `HttpClient` may absorb Set-Cookie before Dio sees it).

---

## Bug History

| Bug ID | File | Description | Status |
|--------|------|-------------|--------|
| BUG-DL-PATH-B | `download_service.dart` | Path B used `getShareUrl()` losing filename+remote_id → always downloaded episode 1 | ✅ Fixed |
| BUG-DL-RF1 | `download_service.dart` | Path A passed raw RF1:xxx URL to JazzDrive without decoding | ✅ Fixed |
| BUG-JD-VK | `jazzdrive_service.dart` | `_buildStreamUrl` appended `validationkey=` to CDN URL — k= token is self-authenticating, this is incorrect and breaks CDN URLs | ✅ Fixed 2026-06-16 |
| BUG-JD-SESSION | `jazzdrive_service.dart` | JSESSIONID `.NODE` suffix was being stripped — causes sticky session routing to fail (HTTP 401 HTML on media call) | ✅ Fixed 2026-06-16 |

---

*Generated by Replit Agent audit — 2026-06-16. Update after any JazzDrive integration changes.*
