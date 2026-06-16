# JazzDrive — Confirmed Findings & Discoveries

> All entries confirmed by live HTTP tests, APK decompile, or direct Oracle
> server tests. Date noted for each entry.

---

## F-001 — JazzDrive is NOT geo-restricted (2026-06-14)

**Confirmed**: Tested from Replit (USA), Oracle (India/Mumbai 92.4.95.252), and Oracle's
wg0 exit (Cloudflare).

All three IP types receive identical responses from JazzDrive endpoints. There is no
Apache-level geo-block. The restriction is purely a **User-Agent gate**.

**The UA gate**:
- `User-Agent: omh android client` → endpoint responds (200 or 400/error, but live)
- Any other UA (including `Dalvik/2.1.0...` Android SDK default) → HTTP 401, static empty
  file, `Last-Modified: Feb 11 2026` — a pre-generated static block file, not a live reject.

**Source**: `hub/_legacy/scanner.py` `mobile_direct_verify_otp()` fix (commit c8490d9).

---

## F-002 — OAuth2-rotated token is NOT valid for SAPI login (2026-06-15)

**Confirmed by live HTTP test** (account 11, Oracle):

| Token | Source | SAPI HTTP response |
|-------|--------|--------------------|
| `490590b2...` (40 hex) | OTP login → DB `raw_accesstoken` | **HTTP 200** ✅ |
| OAuth2-rotated `access_token` | `token.php` refresh response | **HTTP 401 (empty body)** ❌ |

**Why**: `token.php` issues a new Bearer token for the OAuth2 authorization layer only.
This token is NEVER registered in the SAPI session store. The SAPI `keytype=accesstoken`
endpoint validates tokens against its own session database. Only the OTP-issued
`raw_accesstoken` was registered there at OTP time.

**Impact**: After an OAuth2 refresh, if you use the new `access_token` (not the DB
`raw_accesstoken`) in the SAPI login `key=` parameter → always 401 with an empty body
(no JSON error message, which makes debugging very hard).

**Source**: `hub/jazzdrive.py` `_android_refresh_session_inner()` comment block.

---

## F-003 — refresh_token rotates on every token.php call (confirmed, date unknown)

**Behavior**: Every successful `POST /oauth2/token.php?grant_type=refresh_token` returns a
NEW `refresh_token`. The old one is immediately invalidated. Calling twice with the same RT
→ second call returns `{"error":"invalid_grant","error_description":"Invalid refresh token"}`.

**Guard in code**: Per-account lock (`_refresh_locks`) and cooldown (`_REFRESH_COOLDOWN_S = 120s`)
prevent double-burn when two threads race.

**Emergency backup**: After step 1 of `android_refresh_session()` succeeds, the new
`refresh_token` is saved to DB IMMEDIATELY (before SAPI step 2). This prevents chain loss
if step 2 fails. Also written to an emergency file outside the DB transaction.

---

## F-004 — SAPI direct login returns the SAME raw_accesstoken (2026-06-15)

When `/sapi/login/oauth?keytype=accesstoken` succeeds, the `access_token` field in the
response decodes to the SAME `raw_accesstoken` you sent in — SAPI does not issue a new one.

```json
response: {
  "access_token": "<base64({\"data\":{\"accesstoken\":\"<same token>\",\"refreshtoken\":\"<same rt>\",...}})>"
}
```

This means `raw_accesstoken` is effectively permanent from SAPI's perspective. There is no
documented expiry for it in SAPI. It was issued at OTP time and remains valid indefinitely
until the account is manually reset.

---

## F-005 — keytype=otp was removed in JazzDrive 8.0.1 (2026-06-14)

**Finding**: Decompile of JazzDrive APK 8.0.1 shows NO `keytype=otp` in any endpoint
construction string. The endpoint `/sapi/login/oauth?keytype=otp` does not exist in the
current codebase.

**Old scanner.py code** (now removed): Called `keytype=otp` with the raw OTP integer.
This code path was dead.

**Correct approach**: Use `keytype=accesstoken` with the OTP-issued `raw_accesstoken`.
The `validate_otp` endpoint for consumer verification is via the web portal `verify.php`,
not a SAPI direct endpoint.

---

## F-006 — system/information is NOT a valid session health check (2026-06-13)

**Finding**: `GET /sapi/system/information?action=get` returns HTTP 200 even with an
EXPIRED or MISSING JSESSIONID. It validates only the `validationkey` parameter.

**Consequence**: Using `system/information` to check if a session is alive gives a false
positive when JSESSIONID is dead but VK is still valid.

**Correct probe**: `GET /sapi/media/folder?action=get&parentId=0` requires a LIVE
JSESSIONID. This is what `verify_jd_session()` uses.

---

## F-007 — Android OAuth2 client credentials (from APK AES-CBC decrypt)

```
client_id:     fnbroot
client_secret: f&rW23
Endpoint:      https://jazzdrive.com.pk/oauth2/token.php
```

Decrypted from `classes2.dex` class `C4622a` / `classes3.dex` class `C6516a` (AES-128-CBC,
PKCS7 padding). Confirmed valid: `token.php` returns `invalid_grant` (not `invalid_client`)
meaning credentials are correct but the token was spent.

---

## F-008 — SSL hostname mismatch on jazzdrive.com.pk (confirmed, date unknown)

`https://jazzdrive.com.pk` has an SSL certificate issued for a subdomain, not the bare domain.
Python's `requests` raises `ssl.SSLError` unless `verify=False` is passed.

This is set ONLY for the OAuth2 `token.php` call to `jazzdrive.com.pk`. All calls to
`cloud.jazzdrive.com.pk` use verified SSL (correct cert).

---

## F-009 — Folder root ID is NOT 0 (confirmed, date unknown)

`GET /sapi/media/folder?action=get&parentId=0` returns a list of folders. The first item
is a special folder with `name="/"` whose `id` field is the REAL root folder ID.

This real ID must be used as `parent_id` when creating top-level folders. Passing `0` as
a literal parent_id to create/move operations does not work correctly on all JD accounts.

Cached in `_root_folder_id_cache` (keyed by JSESSIONID prefix) to avoid repeated lookups.

---

## F-010 — Share key suffix encodes account/tenant context (2026-06-06)

JazzDrive share keys have a structure:
```
<random_prefix><fixed_suffix>
```

The suffix (`zc1MjIwNTczNTg3NzFfMjYyMTAwMA` for account 11) is identical across ALL
share links for the same JazzDrive account. It encodes the account/tenant identifier.

Truncating the share key (keeping only the random prefix) → HTTP 400.
Full key required for every share link operation.

---

## F-011 — wg0 routes only 3 Jazz IPs, not all traffic (confirmed, 2026-06-10)

Oracle's wg0 VPN is NOT a full VPN. It only routes these 3 Jazz datacenter IPs:
```
54.179.95.148   ← Jazz SAPI / OAuth2
54.254.59.168   ← Jazz SAPI / OAuth2
175.41.133.62   ← Jazz SAPI / OAuth2
```

All other traffic (including `cloud.jazzdrive.com.pk` upload host) goes direct from
Oracle's raw IP (92.4.95.252, Indian). Upload calls are not zero-rated and go direct.

This is enforced by `require_wg0()` which checks that these IPs route through wg0
and raises `WG0NotRoutingJDError` if not.

---

## F-012 — SAPI 401 empty body means wrong token, not expired session (2026-06-15)

A genuine session expiry (VK or JID invalid) returns HTTP 401 WITH a JSON error body.
An OAuth2-rotated token used as SAPI key returns HTTP 401 with an EMPTY BODY.

This distinction is critical for debugging:
- 401 + JSON error body → session expired, call `refresh_session()`
- 401 + empty body → wrong token type, check if you're using OAuth2 token instead of DB `raw_accesstoken`
