---
name: JazzDrive session validation_key
description: VK required for all SAPI calls; how to get it, what breaks without it, fixes applied 2026-06-06 and 2026-06-13.
---

## The Rule
Every JazzDrive SAPI call requires **both** `validation_key` (32-char hex) AND `JSESSIONID` (38-char). JSESSIONID alone returns HTTP 401. Guards at `if not vk or not jid: return error` in `upload_json_to_jazzdrive` and `upload_to_jazzdrive`.

**Why:** Confirmed live — curl with Cookie: JSESSIONID only → 401. With both → 200.

## How Accounts Get validation_key

### OTP login (correct path after 2026-06-13 fix)
1. OAuth2 flow (`jazzdrive.com.pk/verify.php`) → returns `refresh_token` + `access_token` but `vk=False`
2. **Immediately after**, call `mobile_direct_verify_otp(msisdn, otp)` with same OTP
3. This hits `/sapi/login/oauth?keytype=otp` (geo-unrestricted, works from Oracle IP)
4. Returns VK + JSESSIONID → merged into OAuth2 tokens before DB save
5. Result: user gets `refresh_token` (OAuth2) + `VK` (SAPI direct-OTP) in one OTP flow

### Why `keytype=accesstoken` NEVER works
- Oracle server uses fnbroot OAuth2 `access_token` (40-char hex)
- SAPI `keytype=accesstoken` expects this wrapped as `base64({"data":{"accesstoken":"<hex>"}})` 
- Produces `eyJ...` JWT-looking string → **always 401** regardless of IP
- This is a fundamental token format mismatch — not a geo issue, not fixable by proxy

### Silent refresh cannot get VK
`android_refresh_session()` → `token.php` → new `access_token` → tries `keytype=accesstoken` → 401.
**VK is only obtainable during OTP login.** Monitor this.

## Files Fixed (2026-06-13, commit 0ceb1544)
- `hub/scanner.py verify_otp()`: after OAuth2 gives vk=False → calls mobile_direct_verify_otp() → merges VK
- `hub/_legacy/scanner.py jazzdrive_verify_otp()`: both early-return guards now require BOTH JID+VK from cookies (not just JID)

## Files Fixed (earlier session, 2026-06-06)
- `hub/jazzdrive.py sapi_request()`: VK rotation handled — saves new VK from every SAPI response back to DB
- `hub/scanner.py verify_otp()`: validates session after OTP with trigger_heartbeat

## How to Apply
- At OTP verification: always call mobile_direct_verify_otp() even if OAuth2 succeeded
- Never rely on `keytype=accesstoken` — it is permanently broken for our token format
- If VK goes missing: user clicks 🍪 Clear Cookies → keepalive tries silent refresh (gets new JID but NOT VK) → if uploads still fail → user must re-OTP
- Check VK in DB: `SELECT id, msisdn, validation_key FROM accounts;` — empty = broken
