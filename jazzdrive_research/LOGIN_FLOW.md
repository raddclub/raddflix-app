# JazzDrive Login Flow (OTP)

> Source: `hub/jazzdrive.py` (`trigger_otp_flow`, `submit_otp`) and
> `hub/scanner.py` (`send_otp`, `verify_otp`). Verified 2026-06-15.

---

## Overview

JazzDrive uses an SMS OTP flow. There are **two entry points** in the codebase:

| Entry point | Used by | File |
|-------------|---------|------|
| `trigger_otp_flow()` + `submit_otp()` | Upload page (`/upload`) | `hub/jazzdrive.py` |
| `send_otp()` + `verify_otp()` | Scan page (`/scan`) | `hub/scanner.py` |

Both paths produce the same token set and write to the same `accounts` table row.

---

## Step-by-Step: Full OTP Login

### Step 0 — Prerequisites

- `JAZZDRIVE_MSISDN` must be set in DB settings (or passed as param).
- `wg0` VPN must be up (`require_wg0()` is called — hard-fails if not).
- JazzDrive master switch must be ON (`require_jd_active()`).

---

### Step 1 — Trigger OTP (`trigger_otp_flow`)

**What happens:**

1. Old `jazzdrive_session.json` is deleted (clean slate — stale cookies confuse Jazz).
2. MSISDN normalized to `03xxxxxxxxx` format.
3. Web session (`requests.Session`) is created with browser `User-Agent`.
4. `radd_flix.trigger_otp()` (or `jazzdrive_login()` fallback) POSTs to JazzDrive web portal.
5. JazzDrive sends an SMS OTP to the phone.
6. The resulting session cookies + `verify_url` are saved to `_OTP_STATE_FILE` (temp JSON).

**Proxy behavior:**
- `JAZZDRIVE_PROXY_BYPASS=1` (current setting on Oracle) → direct via wg0 VPN.
- Otherwise → tries proxy chain (primary proxy → pool proxies → direct as last resort).

**Returns:** `{"ok": True, "message": "OTP sent to 03xxxxxxxxx. Check SMS then submit below."}`

---

### Step 2 — PRE-SAPI VK Capture (`verify_otp` — scan path only)

> This step exists ONLY in `hub/scanner.py:verify_otp()`, NOT in `submit_otp()`.

**Why it exists:**
- `verify.php` (OAuth2 code exchange in Step 3) consumes the OTP for the OAuth2 layer.
- `keytype=accesstoken` SAPI login DOES NOT consume the OTP — it uses the raw_accesstoken.
- By calling `mobile_direct_verify_otp()` BEFORE Step 3, we get VK while OTP is fresh.

**What it calls:**
```
GET https://cloud.jazzdrive.com.pk/sapi/login/oauth
    ?action=login
    &platform=Android
    &keytype=otp       ← NOTE: This is not in JD 8.0.1 APK. Use keytype=accesstoken instead.
    &key=<otp_digits>
```

**Result:** If VK is returned, it is stored as `_pre_vk` and injected after Step 3.

---

### Step 3 — Submit OTP + OAuth2 Exchange (`submit_otp` / `verify_otp`)

**What happens:**

1. **Load OTP state** from `_OTP_STATE_FILE` (or `_otp_sessions` dict in scanner path).
2. **TTL check**: OTP sessions expire after 600 seconds (10 minutes).
3. **POST to `verify_url`** with the OTP code (the web portal verification page).
4. **Android OAuth2 exchange**: calls `jazzdrive_verify_otp()` with `client_id=fnbroot`, `client_secret=f&rW23`.
   - The server returns an `access_token` (base64-JSON wrapping raw_accesstoken+refreshtoken) and a `refresh_token`.
5. **Decode access_token**: `base64.b64decode(access_token)` → `{"data":{"accesstoken":"<40hex>","refreshtoken":"<40hex>","expiresin":"3600",...}}`
   - `accesstoken` field = `raw_accesstoken` (40-char hex, OTP-issued, SAPI-registered)
   - `refreshtoken` field = `refresh_token` (40-char hex, OAuth2 layer only)
6. **SAPI login call** (inside `android_refresh_session` → `_android_refresh_session_inner`):
   ```
   GET https://cloud.jazzdrive.com.pk/sapi/login/oauth
       ?action=login
       &platform=Android
       &keytype=accesstoken
       &key=<url_encoded(base64({"data":{"accesstoken":"<raw_accesstoken>"}}))>
   Headers:
       User-Agent: omh android client
       x-request-id: <uuid>
       X-deviceid: <device_id>
       X-devicename: Infinix Hot 9 Play
       Authorization: oauth <base64({"data":{"accesstoken":"<raw_accesstoken>","refreshtoken":"<rt>","platform":"android","expiresin":"3600","lastrefreshdate":<ms>,"msisdn":"<phone>"}})>
   ```
   - **Returns**: `{"data":{"validationkey":"<32hex>","jsessionid":"<38char>","access_token":"<b64>","roles":[...],...}}`
7. **Token persistence**: all 4 tokens saved to `accounts` table + `jazzdrive_session.json`.

---

### Token Extraction Summary

After successful OTP login, the `accounts` table gets:

| Column | Value | Source |
|--------|-------|--------|
| `validation_key` | 32-char hex | SAPI login response `data.validationkey` |
| `jsessionid` | 38-char | SAPI login response `data.jsessionid` |
| `raw_accesstoken` | 40-char hex | Decoded from OAuth2 `access_token` field |
| `refresh_token` | 40-char hex | OAuth2 response `refresh_token` field |
| `token_expires_at` | `now + 30 days` | Set by our code (not from Jazz API) |

---

### Step 4 — Post-Login

- `clear_sapi_backoff(account_id)` — clears the 30-min SAPI backoff immediately.
- `keepalive.trigger_heartbeat(account_id)` — resets stale "offline" UI state immediately.
- Scan page: `_otp_sessions.pop(account_id)` — clears pending OTP state.
- Upload page: `_OTP_STATE_FILE.unlink()` — deletes temp state file.

---

## Token Type Reference

| Name | Length | Layer | Registered in SAPI | Expiry | Rotates? |
|------|--------|-------|--------------------|--------|----------|
| `validation_key` (VK) | 32 hex | SAPI | Yes (is a SAPI session key) | ~15 days idle; extended by SEC-1003 | Yes — server rotates via SEC-1003 error or `X-Funambol-ValidationKey` header |
| `jsessionid` (JID) | 38 char | SAPI | Yes (is the SAPI session cookie) | 3600s idle | No — fixed per SAPI session |
| `raw_accesstoken` | 40 hex | SAPI | **Yes (OTP-issued)** | Unknown; appears permanent in SAPI | No |
| `refresh_token` | 40 hex | OAuth2 | **No** (OAuth2 layer only) | ~90 days; dies with `invalid_grant` | **Yes — rotates on every `token.php` call** |
| `access_token` (OAuth2) | base64-JSON | OAuth2 | **No** | 3600s | Yes — new one returned with each refresh |

---

## Common Mistakes

| Mistake | Consequence |
|---------|-------------|
| Using OAuth2-rotated `access_token` as SAPI `key=` | 401 empty body — token not registered in SAPI session store |
| Calling `token.php` twice with the same `refresh_token` | Second call: `{"error":"invalid_grant"}` — RT chain burned |
| Sending wrong `User-Agent` (e.g. `Dalvik/...`) | 401 static empty response from SAPI UA gate |
| Not including `Authorization` header in SAPI login | 401 from SAPI — required by `OAuth2AuthenticatorInterceptor` |
| Using `Authorization` header with different token than `key=` | 401 — header and key must wrap the same token |
| Calling OTP verify after 10 minutes | State file expired — must trigger a new OTP |
| Not clearing `jazzdrive_session.json` before new OTP | Jazz rejects re-login with stale cookie |
