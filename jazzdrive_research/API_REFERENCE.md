# JazzDrive API Reference

> All endpoints verified from live HTTP tests and/or APK decompile (JazzDrive 8.0.1).
> Base host: `https://cloud.jazzdrive.com.pk` unless noted.
> All requests require `User-Agent: omh android client`.

---

## Authentication Endpoints

### OTP Trigger (Web Portal)

JazzDrive uses a web-based OTP trigger flow, not a direct API endpoint.
The `jazzdrive_login()` function drives a `requests.Session` through the web portal.
The resulting session cookies are saved and reused for OTP submission.

---

### SAPI Login — OTP-issued token

```
GET /sapi/login/oauth
    ?action=login
    &platform=Android
    &keytype=accesstoken
    &key=<url_encoded(base64({"data":{"accesstoken":"<raw_accesstoken>"}}))>
```

**Headers** (ALL required):
```
User-Agent: omh android client
x-request-id: <UUID>
X-deviceid: <device_id>
X-devicename: Infinix Hot 9 Play
X-Requested-With: com.jazz.drive
Authorization: oauth <base64({"data":{"accesstoken":"<raw_accesstoken>","refreshtoken":"<rt>","platform":"android","expiresin":"3600","lastrefreshdate":<ms>,"msisdn":"<phone>"}})>
```

**Token rules**:
- `key=` param and `Authorization.data.accesstoken` MUST be the SAME token.
- ONLY the OTP-issued `raw_accesstoken` works → HTTP 200.
- OAuth2-rotated `access_token` → HTTP 401 (empty body, no JSON error message).

**Success response** (HTTP 200):
```json
{
  "data": {
    "roles": [{"name":"sync_user"},{"name":"trial"}],
    "access_token": "<base64-JSON>",
    "jsessionid":   "<38-char session ID>",
    "validationkey": "<32-char hex>",
    "encryption-token": "..."
  }
}
```

**Decoded `access_token` field** (base64):
```json
{
  "data": {
    "accesstoken":    "<same raw_accesstoken>",
    "refreshtoken":   "<current refresh_token>",
    "platform":       "android",
    "expiresin":      "3600",
    "lastrefreshdate": <Unix ms>,
    "msisdn":         "<phone>"
  }
}
```

Note: The SAPI response `access_token` wraps the SAME `raw_accesstoken` you sent in — it does NOT issue a new one.

---

### OAuth2 Token Refresh

```
POST https://jazzdrive.com.pk/oauth2/token.php
Content-Type: application/x-www-form-urlencoded

grant_type=refresh_token
&client_id=fnbroot
&client_secret=f%26rW23
&refresh_token=<current_refresh_token>
```

Note: `jazzdrive.com.pk` has an SSL hostname mismatch — `verify=False` is used for this call only.

**Success response** (HTTP 200):
```json
{
  "access_token":  "<base64-JSON or raw hex>",
  "refresh_token": "<NEW rotated 40-char hex>",
  "expires_in":    3600,
  "token_type":    "bearer"
}
```

**CRITICAL**: `refresh_token` rotates on EVERY successful call. Save the new one immediately. Calling twice with the same RT → `{"error":"invalid_grant"}`.

**Credentials** (from APK AES-128-CBC decryption, `classes2.dex C4622a / C3912s`):
```
client_id:     fnbroot
client_secret: f&rW23
```

---

## SAPI Endpoints

All SAPI requests go to `https://cloud.jazzdrive.com.pk/sapi/<endpoint>`.
All require: `validationkey=<vk>` URL param + `JSESSIONID=<jid>` cookie + full auth headers.

### System Info (Keepalive probe)
```
GET /sapi/system/information?action=get&validationkey=<vk>&responsetime=true
```
Returns 200 even with an expired JSESSIONID (VK-only check). Used for keepalive heartbeat.

### Folder List
```
GET /sapi/media/folder?action=get&parentId=<id>&validationkey=<vk>&responsetime=true
```
- `parentId=0` → returns root-level folders (first item is the real root folder, name="/").
- Requires LIVE JSESSIONID (not just VK) — used by `verify_jd_session()` to prove session is fully alive.

### File Upload
```
POST /sapi/upload/video?action=upload&validationkey=<vk>&responsetime=true
Content-Type: multipart/form-data

fields:
  filesize    = <bytes>
  name        = <filename.ext>
  parentId    = <folder_id>
  file        = <binary stream>
```
Returns `{"data":{"id":<remote_file_id>,...}}` — `id` is the permanent JazzDrive file ID.

### Pre-upload Metadata Save
```
POST /sapi/upload/video?action=save-metadata&validationkey=<vk>
Content-Type: application/json

{"data": {"name":"<filename>","size":<bytes>,"folderid":<parent_id>}}
```
Creates a placeholder entry before binary upload starts. Returns a session upload token.

### File Rename
```
POST /sapi/upload/video?action=save-metadata&validationkey=<vk>
Content-Type: application/json

{"data": {"id":<file_id>,"name":"<new_name.ext>","folderid":<parent_id>}}
```
Note: `POST /sapi/media/video?action=rename` returns HTTP 200 but does NOT rename — it is broken. Only `save-metadata` works.

### File Soft Delete (Trash)
```
POST /sapi/media/video?action=delete&softdelete=true&validationkey=<vk>
Content-Type: application/json

{"data": {"ids": [<file_id>, ...]}}
```

### Folder Create
```
POST /sapi/media/folder?action=create&validationkey=<vk>
Content-Type: application/json

{"data": {"name":"<folder_name>","parentid":<parent_id>}}
```

### Create Share Link
```
POST /sapi/media/folder/share?action=create&validationkey=<vk>
Content-Type: application/json

{"data": {"id":<folder_id>,"type":"public","folderid":<folder_id>}}
```
Returns share URL in form: `https://cloud.jazzdrive.com.pk/share/f/<share_key>`

---

## Error Codes

| Code | Meaning |
|------|---------|
| `SEC-1003` | Validation key rotated — `error.data` contains the new VK. Handled automatically by `sapi_request()`. |
| `AUTH-001` | No `validationkey` available for this request (VK missing from DB). |
| `AUTH-002` | Account not found in DB. |
| HTTP 401 (empty body) | SAPI login called with wrong token type (OAuth2-rotated, not OTP-issued). |
| HTTP 401 (JSON) | Genuine session expired — VK or JID invalid. |
| `invalid_grant` | refresh_token already consumed or expired. Must do fresh OTP login. |
| `invalid_client` | Wrong `client_id` or `client_secret`. Current: `fnbroot` / `f&rW23`. |

---

## Share URL Format

```
https://cloud.jazzdrive.com.pk/share/f/<share_key>
```

**Share key format**: `<random_prefix><encoded_suffix>`
- The suffix encodes the JazzDrive account/tenant context.
- The suffix is IDENTICAL across all share URLs for the same account.
- NEVER truncate share keys — the suffix is required for the link to work.
- Example: `hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA`
  - Short: `hoIyg7SgSFiDPHltBZOl8` → HTTP 400
  - Full: `hoIyg7SgSFiDPHltBZOl8zc1MjIwNTczNTg3NzFfMjYyMTAwMA` → HTTP 200

---

## File ID

`remote_id` (stored in `files.remote_id`) = the `id` field from SAPI upload/list responses.
This is the permanent JazzDrive file ID. It never changes on rename or move.
Used for:
- Direct file matching (`Pass 0` in `generate_direct_link()`).
- Delete, rename, move operations.
- Flutter player `getStreamLink(remoteId: remoteId)`.
