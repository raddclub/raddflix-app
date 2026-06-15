# JazzDrive Fix Guide — Common Failures

> Exact root cause + fix for every failure mode we've encountered.
> Use this before making any assumptions or changes.

---

## Symptom: Upload hangs at 0% "queued" indefinitely

**Root cause**: `verify_jd_session()` returned False but the uploader did not surface the error.

**Check**: Look for `session_dead` state in the upload jobs table. Check logs for
`upload_pending: refresh failed`.

**Fix**:
1. Check `accounts` table: is `validation_key` non-empty? Is `jsessionid` non-empty?
2. If both are empty: re-login via OTP.
3. If VK empty but `raw_accesstoken` present: `sapi_direct_login()` will run on next Flask restart's `startup_refresh`.
4. If `raw_accesstoken` empty: must do fresh OTP login.

---

## Symptom: startup_refresh logs `invalid_grant` but uploads are working

**Root cause**: `refresh_token` chain is dead (burned by multiple rapid restarts), but VK+JID in DB are still valid.

**What's happening**: `startup_refresh` tries `android_refresh_session()` → `invalid_grant` → tries `sapi_direct_login()`. If `sapi_direct_login` also fails (rate limit, transient), it logs WARNING. But `verify_jd_session()` reads VK directly and succeeds.

**Action required**: None immediately. The session is alive. When VK eventually expires (days from now), the next `sapi_direct_login()` call will renew it. For a permanent fix: do a fresh OTP login to renew the `refresh_token` chain.

---

## Symptom: SAPI login HTTP 401 with empty body

**Root cause**: The token in the `key=` URL parameter is the OAuth2-rotated `access_token`, NOT the OTP-issued `raw_accesstoken`. These are different tokens. Only the OTP-issued one is registered in the SAPI session store.

**Check in DB**:
```sql
SELECT raw_accesstoken, refresh_token, validation_key FROM accounts WHERE id=11;
```
- `raw_accesstoken` should be 40 hex chars. This is the correct SAPI token.
- `refresh_token` should be 40 hex chars. This is for OAuth2 only.

**Fix**: Ensure `_android_refresh_session_inner()` uses `_db_raw_at` (from DB column `raw_accesstoken`) as `sapi_at`, NOT the OAuth2-derived `raw_at`. The code already does this correctly. If you see 401 after a code change, verify the `key=` param is built from `_db_raw_at`.

---

## Symptom: SAPI login HTTP 401 with JSON error body

**Root cause**: VK is expired/invalid OR session doesn't exist on the SAPI server.

**Fix**: Call the full `refresh_session()` → `android_refresh_session()` → `sapi_direct_login()` chain.
If all fail: fresh OTP login required.

---

## Symptom: OTP submit works (200) but VK is empty / zero

**Root cause**: One of two possibilities:
1. `Authorization` header was missing from the SAPI login call inside `android_refresh_session()`. (Fixed 2026-06-15, commit 1f0189e.)
2. `keytype=accesstoken` SAPI login received the OAuth2-rotated token instead of DB `raw_accesstoken`. (Fixed 2026-06-15, commit c4002bc.)

**Check the logs**: Look for `[JD:OAUTH2] SAPI login using DB token=True` — if it says `DB token=False`, the DB `raw_accesstoken` column is empty and the code fell through to the OAuth2 token as a last resort.

**Fix**: Ensure `raw_accesstoken` is populated in the `accounts` table. If empty, do a fresh OTP login and verify that `submit_otp()` saves it.

---

## Symptom: `verify.php` OTP submission returns "invalid" or wrong OTP error

**Root cause**: OTP was already consumed by PRE-SAPI `mobile_direct_verify_otp()` call. (Rare — the two endpoints are independent on Jazz's side.)

**Or**: OTP expired (>10 minutes since trigger). State file is cleared.

**Fix**: Request a new OTP. Check `_OTP_STATE_FILE` still exists before submitting.

---

## Symptom: OTP verify always fails with `Connection aborted` / `RemoteDisconnected`

**Root cause**: `verify_otp` tried the OTP with a proxy that failed. Oracle's raw IP may be rate-limited by Jazz for OTP calls (MED-1011 — documented in proxy_pool).

**Fix**: Check `JAZZDRIVE_PROXY_BYPASS` setting. If `1`, wg0 is used for OTP calls. If wg0 is down, calls fail. Restart wg0. If proxy pool is enabled and all proxies are dead, the circuit breaker falls back to direct — which may fail for OTP from non-wg0 IPs.

---

## Symptom: SEC-1003 error in SAPI response

**Root cause**: Server rotated the `validationkey`. This is normal JazzDrive behavior.

**Action**: Nothing. `sapi_request()` handles SEC-1003 automatically — extracts new VK from `error.data`, saves to DB, and retries the request transparently.

---

## Symptom: `token_expires_at` is in the past but session still works

**Root cause**: `token_expires_at` is a value OUR CODE sets (30 days for RT, 55 min without RT). It is NOT the actual JazzDrive token expiry. JazzDrive does not return an actual expiry time.

**What actually determines expiry**:
- JSESSIONID: expires after 3600s without ANY SAPI call. Keepalive prevents this.
- `validation_key`: rotated by SEC-1003, lasts days/weeks of active use.
- `raw_accesstoken`: appears permanent in SAPI (no documented expiry).
- `refresh_token`: ~90 days, dies with `invalid_grant`.

---

## Symptom: Scan finds files but none appear in Flutter app

**Root cause**: Title `is_published=0` (default after scan). Must be published.

**Fix**: `_auto_publish_titled_files(account_id)` is called automatically at scan completion. If it wasn't called, run manually:
```sql
UPDATE titles SET is_published=1, updated_at=strftime('%s','now')
WHERE id IN (
    SELECT DISTINCT title_id FROM files
    WHERE account_id=<id> AND title_id IS NOT NULL
      AND share_url IS NOT NULL AND share_url != ''
)
AND is_published=0;
```
Then bump catalog version: `POST /api/catalog/force-version-bump`

---

## Symptom: Files table error `no such column: file_name`

**Root cause**: The column is named `filename` (no underscore), NOT `file_name`.

```sql
SELECT id, filename, state FROM files ORDER BY id DESC LIMIT 10;
```

---

## Symptom: Flask restart kills the session after rapid restart sequence

**Root cause**: Each `startup_refresh` call invokes `android_refresh_session()` which calls `token.php`. If Flask restarts 3+ times quickly, the `refresh_token` is burned on each restart (each call rotates it). By the 3rd restart, `invalid_grant`.

**Prevention**: The cooldown guard (`_REFRESH_COOLDOWN_S = 120s`) prevents a second refresh call within 120s. But if Flask fully restarts, the in-memory cooldown state is lost.

**Recovery**: If VK+JID are still valid (session alive), wait — the session will keep working. The `sapi_direct_login()` fallback in `refresh_session()` will use `raw_accesstoken` to get a fresh VK+JID when the current ones expire. Fresh OTP login is needed to renew the `refresh_token` chain.

---

## Emergency Recovery — Manual SAPI Login via Python (Oracle)

If the uploader is blocked and you need to manually restore the session:

```python
import requests, base64, json, sqlite3, uuid, time, urllib.parse

CLOUD = 'https://cloud.jazzdrive.com.pk'
DB_PATH = '/opt/jazzmax/radd-hub/data/radd_hub.db'

conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row
row = conn.execute('SELECT * FROM accounts WHERE id=11').fetchone()
raw_at = row['raw_accesstoken']
rt     = row['refresh_token']
msisdn = row['msisdn']

cred_obj = {'data': {
    'accesstoken':    raw_at,
    'refreshtoken':   rt,
    'platform':       'android',
    'expiresin':      '3600',
    'lastrefreshdate': int(time.time() * 1000),
    'msisdn':         msisdn,
}}
auth_b64 = base64.b64encode(json.dumps(cred_obj, separators=(',',':')).encode()).decode()

at_json = json.dumps({'data': {'accesstoken': raw_at}})
at_b64  = urllib.parse.quote(base64.b64encode(at_json.encode()).decode(), safe='')

url = f'{CLOUD}/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key={at_b64}'
headers = {
    'User-Agent':        'omh android client',
    'x-request-id':      str(uuid.uuid4()),
    'X-deviceid':        'fac-raddhub-oracle',
    'X-devicename':      'Infinix Hot 9 Play',
    'Authorization':     f'oauth {auth_b64}',
    'Accept':            'application/json, text/plain, */*',
    'X-Requested-With':  'com.jazz.drive',
}
r = requests.get(url, headers=headers, timeout=30)
print(r.status_code, r.text[:500])

if r.status_code == 200:
    data = r.json()['data']
    new_vk  = data['validationkey']
    new_jid = data['jsessionid']
    conn.execute(
        'UPDATE accounts SET validation_key=?, jsessionid=?, token_expires_at=? WHERE id=11',
        (new_vk, new_jid, int(time.time()) + 86400 * 30)
    )
    conn.commit()
    print('Saved. VK:', new_vk[:20], 'JID:', new_jid[:20])

conn.close()
```
