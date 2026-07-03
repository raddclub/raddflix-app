# JazzDrive Flutter Logic — Verified Architecture & Audit Results

**Last updated:** 2026-06-16 (6th session — validationkey CDN bug fix)
**Status:** ✅ All logic correct and verified

---

## What This Covers

This document answers the question every new agent asks:
> *"Is the JazzDrive share URL flow geo-blocked? Does it need a login or OTP?  
> Does the Flutter Dart code correctly replicate what Node.js proved works?"*

**Short answer:** No geo-block. No OTP. The Flutter logic is now correct.  
If share URLs return MED-1011, the share key is invalid or the folder was deleted.

---

## Confirmed Architecture (Do Not Re-Litigate)

### Share URL Access — Globally Public, No OTP

JazzDrive share URLs (`https://cloud.jazzdrive.com.pk/share/f/<shareKey>`) are:
- ✅ **Accessible from anywhere in the world** — no geo-restriction, no IP-block
- ✅ **No Jazz SIM required** to call the login API or resolve share keys
- ✅ **No OTP, no account login** for the share login step
- ✅ **Permanent** — share URLs never expire once created
- ⚠️ **MED-1011** means the share key is invalid OR the folder was deleted — NOT geo-blocking

### Live proof (2026-06-16)
Login API tested from Replit (US server, non-Jazz IP):
`POST /sapi/link/login` → HTTP 200, valid `validationkey` returned.
`GET /sapi/media/video` → HTTP 200, video records returned.
CDN download URL → HTTP 200, real MP4 (`ftyp isom` magic bytes confirmed).
**JazzDrive works globally from any IP.**

### The 3-Step Flow (Dart mirrors this exactly)

```
Step 1: POST /sapi/link/login?action=login
  Body:    { data: { accesstoken: <shareKey> } }
  Headers: Content-Type: application/json;charset=UTF-8
           User-Agent: Android Chrome
           X-Requested-With: com.jazz.drive
           Referer: https://cloud.jazzdrive.com.pk/share/f/<shareKey>
  Returns: { data: { validationkey: "...", jsessionid: "..." } }

Step 2: GET /sapi/media/video?action=get&shared=true&key=<shareKey>&validationkey=<vk>
  Headers: validation_key: <vk>
           Cookie: JSESSIONID=<jsid>
  Returns: { data: { list: [{ id, name, url, thumbnails }] } }

Step 3: Build final CDN stream URL
  url = record["url"]
  if url.startsWith('/'): url = CLOUD_BASE + url
  if 'filename=' not in url: append ?filename=<encoded_name>

  ⚠️  DO NOT append validationkey= to the CDN stream URL.
      The k= token inside the URL is self-authenticating (HMAC-signed).
      Adding validationkey= is incorrect and breaks the URL.
      validationkey is used ONLY in Steps 1 and 2 (SAPI calls).
```

---

## Flutter Dart Code Audit — File-by-File (Post-Fix 2026-06-16)

### `core/security/request_encoder.dart` ✅ CORRECT

XOR encode/decode, RF1 prefix scrambling, padding fix, hourly key rotation — all correct.

### `core/services/jazzdrive_service.dart` ✅ FIXED (2026-06-16)

| Method | Status | Notes |
|--------|--------|-------|
| `_extractShareKey` | ✅ | Regex matches all URL variants |
| `_loginShare` | ✅ | Checks JSON body for JSESSIONID first, strips node suffix |
| `_loginShare` error detection | ✅ | Detects MED-1011 / FOL-1004 with descriptive throw |
| `_getMedia` | ✅ | 4-pass matching: remote_id → substring → normalised → episode code |
| `_buildStreamUrl` | ✅ FIXED | Removed `validationkey=` from CDN URL. Signature is now `(rawUrl, filename)` — 2 args. Added `filename=` guard against double-append. |
| Cache strategy | ✅ | 110 min TTL (under ~2h CDN token expiry), 2-layer: memory + SQLite |

### `core/download/download_service.dart` ✅ CORRECT

Both prior bugs (BUG-DL-PATH-B, BUG-DL-RF1) confirmed fixed. No changes needed in this session.

### `core/db/local_db.dart` ✅ CORRECT

RF1 decode on all read paths; `getShareInfo` returns decoded URL + filename + remote_id.

### `screens/player_screen.dart` `_openMedia` ✅ CORRECT

Uses `getShareInfo` → passes `remoteId` + `targetFilename` → `getStreamLink`.

---

## When MED-1011 Hits All Share URLs — Root Cause & Fix

**This is NOT geo-blocking. JazzDrive works globally from any IP (confirmed 2026-06-16).**

MED-1011 means one of:
1. The share key has been deleted from JazzDrive
2. The share key has been revoked/changed on the JazzDrive account
3. The `accesstoken` field in the POST body is malformed

**Diagnosis:**
- Verify the share key is still valid: `GET https://cloud.jazzdrive.com.pk/share/f/<key>`
- If response HTML contains a real `og:title` → key IS valid on JazzDrive server
- If response is a 404 or generic page → key has been deleted (update DB with new share URL)

---

## The 10 Rules — Never Break These

1. **No geo-restriction logic** — JazzDrive shares work globally, no Jazz SIM needed for API calls
2. **MED-1011 = invalid/deleted share key** — not geo-block, not expired, not IP issue
3. **DO NOT add validationkey= to the CDN stream URL** — the k= token is self-authenticating; adding validationkey= breaks the URL
4. **JSESSIONID from JSON body first** (`inner['jsessionid']`), Set-Cookie as fallback
5. **Strip node suffix** from JSESSIONID (`.2i182` → stripped)
6. **RF1:xxx URLs must be decoded** before passing to JazzDriveService
7. **Use `getShareInfo()` not `getShareUrl()`** — keeps `filename` + `remote_id`
8. **Share URLs are permanent** — MED-1011 = key deleted/revoked, not age
9. **XML/DOCTYPE from media call** = stale cookie; `invalidate(fileId)` then retry
10. **`_buildStreamUrl` takes 2 args**: rawUrl, filename — the `validationKey` parameter was removed

---

## Test Suite

```bash
node raddflix_flutter/test_suite/jazzdrive_logic_test.js
```

Result (2026-06-16): 27/27 ✅ — no network needed.
The JS `buildStreamUrl` in the test suite correctly does NOT add validationkey. Dart is now aligned.

---

## Bug History

| Bug ID | File | Description | Status |
|--------|------|-------------|--------|
| BUG-DL-PATH-B | `download_service.dart` | Path B used `getShareUrl()` losing filename+remote_id → always downloaded episode 1 | ✅ Fixed |
| BUG-DL-RF1 | `download_service.dart` | Path A passed raw RF1:xxx URL to JazzDrive without decoding | ✅ Fixed |
| BUG-JD-VK | `jazzdrive_service.dart` | `_buildStreamUrl` appended `validationkey=` to CDN URL — k= token is self-authenticating, validationkey does not belong in CDN URL | ✅ Fixed 2026-06-16 |

---

*Generated by Replit Agent audit — updated 2026-06-16.*
