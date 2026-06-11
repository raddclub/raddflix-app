# Jazz Drive 8.0.1 — Authentication Flow
> From OAuth2ScreenController (C10831ud.java), AuthenticatorInterceptor, scanner.py, jazzdrive.py

## Full Login Flow (First-Time / OTP)



## Silent Re-login (No OTP — using raw_accesstoken)



## Token Refresh (using refresh_token)



**IMPORTANT** (): credentials go in POST body, NOT in Authorization header.

## Session Maintenance

### JSESSIONID Keep-Alive
- JSESSIONID has 60-minute idle timeout
- Oracle keepalive.py pings every 15 minutes
- Ping: 

### ValidationKey Rotation (SEC-1003)
When server rotates the validationkey:
- Response: 
- Extract new  from 
- Also check  in response
- Update DB and retry the request

### 401 Recovery Flow (Oracle sapi_request)


## Client Credentials Reference

| Field | Value |
|-------|-------|
|  |  |
|  (raw) |  |
|  (URL-encoded) |  |
|  (double URL-encoded in token.php body) |  |
|  |  |
|  |  |
|  |  |

**Why double-encoding**: When building the form body, the  in  becomes . When URL-encoding the form field value itself,  becomes , giving . Verify against live traffic with mitmproxy.
