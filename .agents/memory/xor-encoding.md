---
name: XOR Encoding Layer
description: How the Flutter↔Oracle XOR security layer works, and which paths must skip it
---

## Architecture
- `RequestEncoder.enabled = true` in Flutter (`lib/core/security/request_encoder.dart`)
- Flutter `_XorInterceptor` (in `api_client.dart`): adds `X-Encoded: 1` + `X-Device-Id` headers; XOR-encodes POST/PUT/PATCH bodies as `text/plain`
- Server `XorWsgiMiddleware` (in `request_encoding.py`): decodes request bodies when `X-Encoded: 1` + valid `X-Device-Id` present; sets `CONTENT_TYPE = application/json`
- Server `after_request _xor_encode_response` (in `app.py`): XOR-encodes JSON responses for any `/api/*` request that has `X-Encoded: 1` + `X-Device-Id`
- Session key: `SHA-256("raddflix_xor_v1:deviceId:UTC_day:UTC_hour")[:32]` — hourly rotation

## Critical rule: auth endpoints must skip XOR body encoding
Auth paths (`/api/auth/register`, `/api/auth/login`, `/api/auth/refresh`, `/api/auth/guest`) must NOT have their request bodies XOR-encoded. If `X-Device-Id` is empty/missing at the moment the request fires, the server middleware can't decode the body → validation fails → 400 error even though the request reached the server.

Fix applied: `_XorInterceptor._noXorPaths` list in `api_client.dart` skips XOR encoding for these paths entirely (no `X-Encoded: 1` header either, so server's after_request also skips encoding the response).

## Circular import warning
`request_encoding.py` imports from `mobile_api.py` (for `_verify_jwt`). Do NOT import `request_encoding` from `mobile_api.py` — it creates a circular import that crashes with 500 Internal Error.

**Why:** Auth endpoints are already over HTTPS; adding XOR for them gains nothing and causes parse failures when device-id isn't ready on first launch.
