# JazzDrive Flutter Logic — Verified Architecture & Audit Results

**Last updated:** 2026-06-09  
**Audited by:** Replit Agent  
**Status:** ✅ Core logic correct | ⚠️ 3 bugs fixed in test file | 🔧 1 cosmetic fix in service

---

## What This Covers

This document answers the question every new agent asks:
> *"Is the JazzDrive share URL flow geo-blocked? Does it need a login or OTP?  
> Does the Flutter Dart code correctly replicate what Node.js proved works?"*

**Short answer:** No geo-block. No OTP. The Flutter logic is correct.  
If share URLs return MED-1011, it's the Oracle SAPI session, not geo-blocking.

---

## Confirmed Architecture (Do Not Re-Litigate)

### Share URL Access — Globally Public, No OTP

JazzDrive share URLs (`https://cloud.jazzdrive.com.pk/share/f/<shareKey>`) are:
- ✅ **Accessible from anywhere in the world** — no geo-restriction
- ✅ **No Jazz SIM required** to resolve share keys  
- ✅ **No OTP, no account login** for the share login step
- ✅ **Permanent** — share URLs never expire once created (by design)
- ⚠️ **MED-1011 "Key is invalid"** does NOT mean geo-blocked — it means the share was deleted, or the Oracle JazzDrive SAPI session has expired (see below)

**Node.js test confirmed (2026-06-07):** All share URLs resolved to CDN stream links from a non-Jazz, non-Pakistan server. Zero-rating is irrelevant for URL resolution — it only matters for data billing on Jazz SIM.

### The 2-Call Flow (Dart mirrors this exactly)

```
App → POST /sapi/link/login?action=login   {data: {accesstoken: <shareKey>}}
    ← {validationKey: "...", jsessionid: "..."}  (+ Set-Cookie JSESSIONID)

App → GET  /sapi/media/video?action=get&shared=true&key=<shareKey>&validationkey=<vk>
         Cookie: JSESSIONID=<jsid>  |  validation_key: <vk>  (both headers)
    ← {data: {list: [{id, name, url, thumbnails}]}}

App → Build CDN URL:  rawUrl (absolute or prepend cloudBase) + ?filename=<name>
      DO NOT append validationkey — the k= token in rawUrl is self-signing
```

---

## Flutter Dart Code Audit — File-by-File

### `core/security/request_encoder.dart` ✅ CORRECT

| Check | Result |
|-------|--------|
| XOR decode with padding fix (`'=' * ((4 - len % 4) % 4)`) | ✅ Present |
| RF1: prefix identifies scrambled URLs | ✅ Correct |
| `scrambleUrl` / `unscrambleUrl` use deviceId as key | ✅ Correct |
| `enabled = true` | ✅ |
| Session key formula: `sha256("raddflix_xor_v1:{deviceId}:{day}:{hour}")[:32]` | ✅ Matches Oracle |

### `core/services/jazzdrive_service.dart` ✅ CORRECT (1 cosmetic fix)

| Check | Result |
|-------|--------|
| `_loginShare`: checks JSON body for jsessionid first | ✅ Correct |
| `_loginShare`: strips node suffix from JSESSIONID (`.2i182` → stripped) | ✅ Correct |
| `_loginShare`: detects MED-1011 / FOL-1004 error codes | ✅ Correct |
| `_getMedia`: Pass 0 remote_id exact match | ✅ Correct |
| `_getMedia`: Pass 1 case-insensitive substring | ✅ Correct |
| `_getMedia`: Pass 2 normalised (dots/underscores → spaces) | ✅ Correct |
| `_getMedia`: Pass 3 episode code (s01e02) | ✅ Correct |
| `_buildStreamUrl`: does NOT append validationkey to CDN URL | ✅ Critical, correct |
| Cache TTL = 110 min (safely under 2h CDN token expiry) | ✅ Correct |
| `warmTopFreeItems`: 60-min guard prevents duplicate calls | ✅ Correct |

**Cosmetic bug (LOW — logging only):**  
`JazzDriveLink.filename` is always `''` when returned from memory/DB cache hit.  
Does not affect playback or downloads. Only makes debug logs less informative.

### `core/download/download_service.dart` ✅ CORRECT

Both prior bugs are fixed (from 2026-06-09 session 3):

| Bug | Fix | Status |
|-----|-----|--------|
| BUG-DL-PATH-B: Path B used `getShareUrl()` — lost filename + remote_id | Changed to `getShareInfo()` | ✅ Fixed |
| BUG-DL-RF1: Path A never decoded RF1:xxx before JazzDrive call | Added `LocalDb.decodeShareUrl()` before call | ✅ Fixed |

### `core/db/local_db.dart` ✅ CORRECT

| Check | Result |
|-------|--------|
| `_encodeUrl()` called in `upsertTitle`, `mergeDeltaTitle`, `upsertEpisode` | ✅ All paths encode |
| `getTopFreeMovies()` decodes RF1:xxx before returning | ✅ Correct (uses `_decodeUrl` in loop) |
| `getShareInfo()` decodes RF1:xxx before returning | ✅ Correct |
| `getShareUrl()` decodes RF1:xxx before returning | ✅ Correct |
| `_rowToItem` includes `fileId` | ✅ Fixed (AUDIT-03) |
| `mergeDeltaTitle` preserves existing share_url if delta omits it | ✅ Correct |
| `folder_share_url` persisted in both INSERT and UPDATE | ✅ Fixed (FIX-FOLDER-01) |

### `screens/player_screen.dart` `_openMedia` ✅ CORRECT

```dart
// Step 1: Get share_url + filename from local DB (fast, works offline)
final shareInfo = await LocalDb.getShareInfo(fileId);      // ✅ uses getShareInfo not getShareUrl
shareUrl       = shareInfo['share_url'] as String?;         // already decoded by getShareInfo
targetFilename = shareInfo['filename']  as String?;
remoteId       = shareInfo['remote_id'] as int? ?? 0;

// Step 2: Fallback to inline shareUrl from route args
if (shareUrl == null || shareUrl.isEmpty) {
  shareUrl = await LocalDb.decodeShareUrl(_inlineShareUrl); // ✅ decodes RF1:xxx first
}

// Step 3: Get CDN stream URL (zero-rated on Jazz SIM)
final link = await JazzDriveService.getStreamLink(
  cacheKey, shareUrl,
  targetFilename: targetFilename,
  remoteId: remoteId,                                        // ✅ Pass 0 enabled
);
```

---

## Bugs Fixed in This Session

### `test_suite/jazzdrive_dart_test.dart` — 3 Bugs Fixed

**FIX-TEST-01 (MEDIUM): Missing MED-1011 error detection**  
- **Before:** Login returning `{"error":{"code":"MED-1011",...}}` caused test to throw  
  `"no validationKey in response"` — unhelpful, hides root cause  
- **After:** Detects error code and throws:  
  `"Content unavailable (MED-1011: Key is invalid). If on ALL shares → Oracle session expired."`

**FIX-TEST-02 (HIGH): JSESSIONID only read from Set-Cookie, not JSON body**  
- **Before:** Test only checked `Set-Cookie` response header for JSESSIONID  
- **After:** Mirrors service: checks `inner['jsessionid']` in JSON body first, Set-Cookie as fallback  
- **Why it matters:** On Android, Dart's HttpClient may absorb Set-Cookie before Dio sees them.  
  The service has always used JSON body first. The test was wrong, not the service.

**FIX-TEST-03 (MEDIUM): Node suffix not stripped from JSESSIONID**  
- **Before:** JSESSIONID sent as `06B2BCBBE57.2i182` (full with node hint)  
- **After:** Stripped to `06B2BCBBE57` — matches service behaviour  
- **Why:** JazzDrive load balancer node suffix causes session mismatches on some requests

---

## When MED-1011 Hits All Share URLs — Root Cause & Fix

**Symptom:** Every share URL login returns `{"error":{"code":"MED-1011","message":"Key is invalid"}}`  
**This is NOT geo-blocking.** It is also NOT the share URLs expiring.

**Root cause:** The Oracle JazzDrive account (03286829827) lost its SAPI `validation_key`.  
Without a valid SAPI session on the JazzDrive account that owns the files,  
JazzDrive cannot validate share key login requests — returns MED-1011 for everything.

**Diagnosis:**
```sql
-- Check Oracle DB:
SELECT id, msisdn, is_active, 
       CASE WHEN validation_key IS NOT NULL AND validation_key != '' THEN 'HAS_VK' ELSE 'NO_VK' END,
       datetime(last_keepalive_at, 'unixepoch')
FROM accounts;
-- If NO_VK → session expired. Fix below.
```

**Fix (takes ~5 seconds, safe):**
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd && sleep 5 && curl -s http://localhost:5000/healthz"
# Expected: {"ok":true,"version":"3.0.0"}
```
Flask restart triggers Android OAuth2 refresh via wg0 → new VK written to accounts table → shares work again.  
No OTP needed. Session auto-recovers every time.

**Important:** If restart does not fix MED-1011, check that wg0 is up:
```bash
ssh oracle "ip addr show wg0"
# Must show: inet 172.16.0.2/32
```

---

## Key Rules for Future Agents

1. **Never add geo-restriction logic** — JazzDrive shares work globally, always
2. **MED-1011 on all shares = Oracle SAPI session expired**, not geo-block or expired links
3. **JSESSIONID comes from JSON body first** (`inner['jsessionid']`), Set-Cookie is fallback
4. **Always strip node suffix** from JSESSIONID (`.2i182` → stripped)
5. **Never append `validationkey=`** to the final CDN stream URL — breaks playback
6. **RF1:xxx URLs must be decoded** before passing to JazzDriveService — always use  
   `LocalDb.getShareInfo()` or `LocalDb.decodeShareUrl()`, never raw `CatalogItem.shareUrl`
7. **Use `getShareInfo()` not `getShareUrl()`** — the latter loses `filename` and `remote_id`  
   which breaks Pass 0 and Passes 1-3 for folder-share episodes
8. **Share URLs are permanent** — they do not expire by time. MED-1011 = account issue, not age.
9. **XML/DOCTYPE response** from JazzDrive media call = stale cookie, NOT geo-block.  
   Fix: `JazzDriveService.invalidate(fileId)` then retry — player_screen does this automatically.

---

## Test Suite — Running the Integration Test

```bash
# Requires: Dart SDK, valid Oracle session (share URLs live)
dart run raddflix_flutter/test_suite/jazzdrive_dart_test.dart
```

All 8 tests cover:
- Movies: Pass 0 (remote_id), Pass 1 (substring), multi-file folder selection
- TV: Pass 0 (Vincenzo — must pick correct episode from 4-file folder)  
- TV: Pass 3 (Spider-Noir — corrupted upload names, only episode code works)
- Critical: Episode isolation (E02 must not return E01 from same folder)

**Expected output when Oracle session is healthy:**
```
All 8 tests passed.
```

---

## File Reference

```
Flutter:
  core/security/request_encoder.dart     XOR encode/decode + RF1: scrambling
  core/api/api_client.dart               Dio + XOR interceptor + auth
  core/db/local_db.dart                  SQLCipher DB, schema v17
  core/services/jazzdrive_service.dart   JazzDrive share → CDN URL (THE core)
  core/download/download_service.dart    Download via JazzDrive
  screens/player_screen.dart             _openMedia: full resolution chain

Test:
  test_suite/jazzdrive_dart_test.dart    Integration test (mirrors service exactly)

Oracle:
  hub/jazzdrive.py                       JazzDrive session, OTP, upload, keepalive
  hub/routes/catalog_api.py              /api/catalog/sync (builds delta)
  data/radd_hub.db                       files table: share_url, remote_id, filename
```
