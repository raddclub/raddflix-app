# Next Agent Brief — RaddFlix / JazzDrive
**Date**: 2026-06-11 | **Priority**: HIGH

## Context
RaddFlix is a Pakistani streaming app targeting Jazz SIM users (zero-rated traffic via Jazz Drive).
Oracle backend (`92.4.95.252`, Flask, `/opt/jazzmax/radd-hub/hub/`) proxies JazzDrive SAPI calls.
APK (Jazz Drive 8.0.1) has been fully reverse-engineered this session.

## 4 Tasks in Priority Order

### TASK 1: Add 4 Missing HTTP Headers to Oracle (jazzdrive.py)
The real Android app sends these on EVERY request. Oracle doesn't. Server may gate features on them.
```python
# sapi_request() in radd-hub/hub/jazzdrive.py
import uuid, base64

# Add to every outbound request:
"User-Agent":   "omh android client",
"x-request-id": str(uuid.uuid4()),   # fresh UUID per call
"X-deviceid":   "fac-oracle-proxy",  # stable fake device
"X-devicename": "OracleProxy",
```

### TASK 2: MobileConnect Login (Jazz SIM → zero-rated auth)
```
POST /sapi/credential/mobileconnect?action=validate
Body: {"data": {"code": "<code>", "state": "<state>"}}
Response: {access_token, refresh_token, msisdn: "92XXXXXXXXXX", expires_in, lastrefreshdate}
```
This is how Jazz SIM users log in (network injects MSISDN, no password needed).
Add a new route `/jd/mobileconnect/validate` that forwards to SAPI.

### TASK 3: validationkey Refresh from Every Response
In `sapi_request()`, after every successful call, check response JSON for `data.validationkey`
and store/update it. The real app does this in AbstractC12813a.m51847w():
```python
vk = response_json.get("data", {}).get("validationkey")
if vk:
    db.set_setting("validationkey", vk)
```

### TASK 4: OAuth2 Token Exchange Endpoint
```python
@app.route("/jd/oauth2/token", methods=["POST"])
def oauth2_token():
    code = request.json.get("code")
    resp = requests.post("https://jazzdrive.com.pk/oauth2/token.php", data={
        "grant_type":    "authorization_code",
        "code":          code,
        "redirect_uri":  "https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html",
        "client_id":     "fnbroot",
        "client_secret": "f&rW23",
    })
    return jsonify(resp.json())
```

## Key Credentials (DO NOT commit to public repo)
- client_id = `fnbroot`
- client_secret = `f&rW23`

## Memory Files
- `/opt/jazzmax/.agents/memory/jazzdrive-api.md` — upload flow
- `/opt/jazzmax/.agents/memory/jazzdrive-login-flow.md` — login flow + all headers

## Research
- `jazzdrive_research/LOGIN_FLOW.md` — complete login flow (all 3 paths)
- `jazzdrive_research/UPLOAD_FLOW.md` — upload flow
- `jazzdrive_research/FIX_GUIDE.md` — 6 bugs already fixed
