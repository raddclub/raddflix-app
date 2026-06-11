# JazzDrive Authentication Flow

## Android OAuth2 Credentials (from APK)
- Client ID: `fnbroot`
- Client Secret: `f&rW23`
- Redirect URI: `https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html`

## Login Flow
1. `GET /ui/html/index.html` → get JSESSIONID cookie
2. `POST /ui/j_spring_security_check` with msisdn/password → auth
3. `GET /ui/html/clientoauth.html?...` → extract auth code
4. `POST /oauth2/access_token.php` with `code=<code>&client_id=fnbroot&...` → tokens
   Response: `{"access_token": "...", "refresh_token": "...", "validationkey": "..."}`

## Token Types
- `validationkey` — short-lived, rotates on SEC-1003 response
- `jsessionid` — session cookie, valid ~hours
- `refresh_token` — long-lived (~90 days), exchange for new tokens
- `access_token` — Bearer token

## Token Rotation
- SEC-1003 response: `{"error": {"code": "SEC-1003", "data": "<new_vk>"}}`
  → Update validationkey, retry request
- 401 response: try refresh_token first, then jsessionid refresh

## Oracle Implementation
- `sapi_request()` handles SEC-1003 and 401 transparently
- Refresh via `POST /oauth2/refresh_token.php` with `refresh_token=<token>`
