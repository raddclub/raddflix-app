# RaddFlix Agent Handoff — JazzDrive SAPI Auth Investigation
Updated: 2026-06-10  |  Flask running port 5000 at /opt/jazzmax/radd-hub

## Critical Status
Account 16 (03257719165, role=flix): validation_key="" => verify_jd_session() always False => uploader never runs.

Root cause: cloud.jazzdrive.com.pk returns HTTP 401 EMPTY BODY (static file, Last-Modified Wed 11 Feb 2026)
for GET /sapi/login/oauth and GET /sapi/login. Both Oracle IP (92.4.95.252) AND Cloudflare WARP exit are blocked.
wg0 routes 54.254.59.168 and 54.179.95.148 through WARP (162.159.192.1:2408) but Cloudflare exit also blocked.

## Endpoint Status (from Oracle via wg0)

| Endpoint | Status | Notes |
|---|---|---|
| GET /sapi/login/oauth?keytype=accesstoken | 401 EMPTY | static file IP-block Feb 11 2026 |
| GET /sapi/login?action=login | 401 EMPTY | same static file IP-block |
| POST /sapi/login?action=login + JSON | 401 HTML | NOT IP-BLOCKED: real Apache auth challenge |
| GET /sapi/media/folder?parentId=0 | 401 HTML | session invalid, NOT IP-blocked for resources |
| GET /sapi/system/information | 200 OK | public, no auth |
| GET /sync (SyncML) | 200 OK | free JSESSIONID — DIFFERENT session store from SAPI |
| POST /sync SyncML | 200 HTTP / 511 SyncML body | not supported; SyncML != SAPI sessions |
| POST /oauth2/refresh_token.php | 200 OK | working, returns new AT+RT |

KEY: POST /sapi/login?action=login is NOT IP-blocked. Need correct Basic auth credentials.
KEY: /sapi/media/folder is NOT IP-blocked — once vk+jid obtained (any source), uploads WILL work from Oracle.

## Account 16 Tokens in DB
- raw_accesstoken: 8c21da83e8d5f147f57d9c1bca2dc9f04f1331f2
- refresh_token:   494a611558addf50a19c0c48c4e0c240cb0f775e
- jsessionid:      14A2632908D98F763F97... (from OAuth2 web flow — NOT a SAPI session)
- validation_key:  "" (empty — SAPI login was blocked during OTP)

NOTE on WWW-Authenticate: POST /sapi/login?action=login returns 401 with NO WWW-Authenticate header.
Apache is using mod_authn custom (not Basic realm challenge). The 401 is app-level, not HTTP-level.

## Next Steps (ordered by promise)

### 1. Decompile JazzDrive Android APK
APK pkg: com.jazz.drive  Download from APKPure/APKMirror
  wget -O /tmp/JazzDrive.apk "https://apkpure.com/.../download"
  sudo apt-get install jadx  (or: pip3 install apktool)
  jadx -d /tmp/jd_src/ /tmp/JazzDrive.apk
  grep -r "sapi/login\|keytype\|validationkey" /tmp/jd_src/ | head -30
  grep -r "Basic\|password\|auth" /tmp/jd_src/ | head -30
Will reveal exact credential format for POST /sapi/login?action=login

### 2. Try more credentials for POST /sapi/login?action=login
Tried+FAILED: MSISDN:AT, MSISDN:RT, MSISDN:MSISDN, MSISDN:empty
NOTE: No WWW-Authenticate header — app-level auth, not HTTP Basic.
Try with:
  - JSON body {"data":{"login":"03257719165","password":"..."}} different password values
  - Form body: login=03257719165&password=...
  - AT as username (not phone number)
  - Check if phone must be in international format (923257719165)
  - Try Funambol mobile-connect auth: maybe password is SHA-256 or MD5 of phone+token

### 3. Manual token injection (QUICKEST FIX — already in UI)
Open /upload page -> Re-login -> enter 03257719165 -> OTP -> verify.
SAPI activation URL appears. Open it on Jazz SIM phone (Pakistani IP — not blocked).
Phone returns JSON: {"data":{"validationkey":"...","jsessionid":"..."}}
Paste JSON in textarea -> Save & Connect.

Direct API inject (after getting vk+jid from Jazz phone):
  POST http://92.4.95.252:5000/upload/api/jazzdrive/tokens
  Body: {"validation_key":"VK","jsessionid":"JID","msisdn":"03257719165"}
  Headers: Cookie: session=ADMIN_SESSION_COOKIE

### 4. Generate current SAPI activation URL
  python3 -c "
  import sqlite3,json,base64,urllib.parse as up
  c=sqlite3.connect('/opt/jazzmax/radd-hub/data/radd_hub.db')
  at=c.execute('SELECT raw_accesstoken FROM accounts WHERE id=16').fetchone()[0]
  j=json.dumps({'data':{'accesstoken':at}})
  print('https://cloud.jazzdrive.com.pk/sapi/login/oauth?action=login&platform=Android&keytype=accesstoken&key='+up.quote(base64.b64encode(j.encode()).decode(),safe=''))
  "

## Web JS Bundle Findings (cloud.jazzdrive.com.pk 6.9MB bundle)
- deviceId.windowsPC = "fol"  (use header X-deviceid: fol-raddhub-XXXXXXXXXX)
- LOGIN endpoint = "/sapi/login?action=login"
- authenticationMethod = {basic:"basic", oauth:"oauth", mobileConnect:"mobileconnect"}
- validationkey stored in cookie (15-day expiry); comes from response.data.validationkey
- All SAPI calls pass ?validationkey=VK in query string

## Key Files
- /opt/jazzmax/radd-hub/hub/jazzdrive.py        auth logic, refresh_session()
- /opt/jazzmax/radd-hub/hub/uploader.py         uploader loop (line 409: if not vk: return False)
- /opt/jazzmax/radd-hub/hub/routes/upload.py    /api/jazzdrive/tokens endpoint
- /opt/jazzmax/radd-hub/hub/templates/upload.html  UI with modal-sapi-row paste feature
- /opt/jazzmax/radd-hub/data/radd_hub.db        SQLite DB

## DB Quick Commands
  sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db \
    "SELECT id,msisdn,validation_key,jsessionid FROM accounts WHERE id=16"
  sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db \
    "SELECT key,value FROM settings WHERE key LIKE '%sapi%' OR key LIKE '%backoff%'"
  sqlite3 /opt/jazzmax/radd-hub/data/radd_hub.db \
    "DELETE FROM settings WHERE key LIKE '%sapi_backoff%'"

## Rules
- db.setting(k) not db.get_setting(k)
- SSH: ssh -i /tmp/oracle_key ubuntu@92.4.95.252
- OAuth2 refresh: POST https://jazzdrive.com.pk/oauth2/refresh_token.php
  body: grant_type=refresh_token&client_id=fnbroot&client_secret=f%26rW23&refresh_token=TOKEN
- Flask runs as systemd service; restart: sudo systemctl restart radd-hub
- 9 test videos in /data/media all is_ready=0 (intentional test state)
