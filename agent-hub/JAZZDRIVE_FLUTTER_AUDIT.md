# JazzDrive Flutter Logic — Verified Architecture & Audit Results

**Last updated:** 2026-06-09 (5th session — CRITICAL BUG FIX)
**Status:** ✅ All logic correct and verified against working Node.js reference script

---

## What This Covers

This document answers the question every new agent asks:
> *"Is the JazzDrive share URL flow geo-blocked? Does it need a login or OTP?  
> Does the Flutter Dart code correctly replicate what Node.js proved works?"*

**Short answer:** No geo-block. No OTP. The Flutter logic is now correct.  
If share URLs return MED-1011, it's the Oracle SAPI session, not geo-blocking.

---

## Confirmed Architecture (Do Not Re-Litigate)

### Share URL Access — Globally Public, No OTP

JazzDrive share URLs (`https://cloud.jazzdrive.com.pk/share/f/<shareKey>`) are:
- ✅ **Accessible from anywhere in the world** — no geo-restriction
- ✅ **No Jazz SIM required** to resolve share keys
- ✅ **No OTP, no account login** for the share login step
- ✅ **Permanent** — share URLs never expire once created
- ⚠️ **MED-1011** does NOT mean geo-blocked — it means share deleted, or Oracle SAPI session expired

### The 3-Step Flow (Dart mirrors this exactly — verified vs working Node.js script)

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

Step 3: Build final CDN URL:
  <rawUrl>?validationkey=<vk>&filename=<encoded_filename>
  ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  REQUIRED — CDN authenticates every request with validationkey.
  Without it the server returns 401/403 and playback fails.
```

---

## CRITICAL BUG — Now Fixed (BUG-JD-VK)

**This was the root cause of all Flutter playback failures.**

### What Was Wrong

`_buildStreamUrl` in `jazzdrive_service.dart` had this comment and code:
```dart
// DO NOT append validationkey — the k= token is self-authenticating  ← WRONG
url = '$url${sep}filename=${Uri.encodeComponent(filename)}';           ← missing validationkey!
```

### What Is Correct (proven by working Node.js reference script)

```javascript
// Node.js — always works:
const directLink = `${finalBaseUrl}${sep}validationkey=${vk}&filename=${encodeURIComponent(name)}`;
```

```dart
// Flutter — now fixed:
url = '${url}${sep}validationkey=${Uri.encodeComponent(validationKey)}'
      '&filename=${Uri.encodeComponent(filename)}';
```

**The `k=` token inside `rawUrl` is NOT sufficient for CDN authentication. `validationkey` must always be appended.**

---

## Flutter Dart Code Audit — File-by-File (Post-Fix)

### `core/security/request_encoder.dart` ✅ CORRECT

XOR encode/decode, RF1 prefix scrambling, padding fix, hourly key rotation — all correct.

### `core/services/jazzdrive_service.dart` ✅ FIXED

| Method | Status | Notes |
|--------|--------|-------|
| `_extractShareKey` | ✅ | Regex matches all URL variants |
| `_loginShare` | ✅ | Checks JSON body for JSESSIONID first, strips node suffix |
| `_loginShare` error detection | ✅ | Detects MED-1011 / FOL-1004 with descriptive throw |
| `_getMedia` | ✅ | 4-pass matching: remote_id → substring → normalised → episode code |
| `_buildStreamUrl` | ✅ FIXED | Now appends `validationkey=` to CDN URL (was missing — caused all failures) |
| Cache strategy | ✅ | 110 min TTL (under ~2h CDN token expiry), 2-layer: memory + SQLite |

### `core/download/download_service.dart` ✅ CORRECT

Both prior bugs (BUG-DL-PATH-B, BUG-DL-RF1) confirmed fixed.

### `core/db/local_db.dart` ✅ CORRECT

RF1 decode on all read paths; `getShareInfo` returns decoded URL + filename + remote_id.

### `screens/player_screen.dart` `_openMedia` ✅ CORRECT

Uses `getShareInfo` → passes `remoteId` + `targetFilename` → `getStreamLink`.

### `test_suite/jazzdrive_dart_test.dart` ✅ FIXED

3 bugs fixed in previous session + Validate 2 flipped:
- Was: "validationkey must NOT be in URL" → WRONG
- Now: "validationkey MUST be in URL" ← CORRECT

---

## When MED-1011 Hits All Share URLs — Root Cause & Fix

**This is NOT geo-blocking and NOT expired share URLs.**

Root cause: Oracle JazzDrive account lost its SAPI `validation_key`.

**Diagnosis:**
```sql
SELECT msisdn,
  CASE WHEN validation_key IS NOT NULL AND validation_key != '' THEN 'HAS_VK' ELSE 'NO_VK' END
FROM accounts;
-- NO_VK = session expired, fix below
```

**Fix (takes ~5 seconds if refresh token is still valid):**
```bash
ssh oracle "sudo supervisorctl restart raddflix_radd && sleep 5"
```

**If Flask restart doesn't fix it** (refresh token also expired → HTTP 401 on all OAuth2 variants):
→ OTP re-login required. Go to Oracle admin panel → Settings → JazzDrive Login.

---

## The 10 Rules — Never Break These

1. **No geo-restriction logic** — JazzDrive shares work globally
2. **MED-1011 on all shares = Oracle SAPI session expired**, not geo-block
3. **`validationkey` MUST be in the final CDN URL** — append it always
4. **JSESSIONID from JSON body first** (`inner['jsessionid']`), Set-Cookie as fallback
5. **Strip node suffix** from JSESSIONID (`.2i182` → stripped)
6. **RF1:xxx URLs must be decoded** before passing to JazzDriveService
7. **Use `getShareInfo()` not `getShareUrl()`** — keeps `filename` + `remote_id`
8. **Share URLs are permanent** — MED-1011 = account issue, not age
9. **XML/DOCTYPE from media call** = stale cookie; `invalidate(fileId)` then retry
10. **`_buildStreamUrl` takes 3 args**: rawUrl, filename, validationKey — never 2

---

## Test Suite

```bash
dart run raddflix_flutter/test_suite/jazzdrive_dart_test.dart
```

Requires Oracle JazzDrive session healthy (HAS_VK). 8 tests: movies + TV seasons.
Expected: `All 8 tests passed.`

If all fail with MED-1011 → do OTP re-login on Oracle first.
