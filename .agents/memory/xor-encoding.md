---
name: XOR Encoding Protocol
description: XOR request/response encoding — both-sides rule, encode_response status kwarg, double-decode risk
---

# XOR Encoding Protocol

## Overview
ALL API calls between Flutter and Oracle are XOR-encrypted. This is an obfuscation layer (not true encryption) using a per-request session key.

## Server Side
- `XorWsgiMiddleware` in `app.py` wraps `app.wsgi_app` — transparently decodes XOR request bodies
- `encode_response()` in `request_encoding.py` — XOR-encodes responses
- `decode_request()` — manual decode (do NOT call if XorWsgiMiddleware is active — causes double-decode)
- `g.xor_session_key` — Flask request context stores the session key set by `decode_request()`

## Flutter Side
- `_XorInterceptor` in `api_client.dart` — encodes POST/PUT/PATCH bodies, sends `X-Encoded: 1` header
- `_AuthInterceptor` — handles 401 refresh with `_isRefreshing` flag (BUG-F04: not atomic)

## Critical Rules

### Never Change One Side Only
If you modify XOR logic in Flutter, you MUST modify the matching server code in the same commit, and vice versa.

**Why:** The encoding is symmetric. If one side changes the key derivation or byte mask, all API calls fail with garbage JSON.

### Always Pass status= to encode_response()
```python
# CORRECT
return encode_response(data, status=200)
return encode_response(error_data, status=400)

# WRONG — drops 4xx/5xx status codes, always returns 200
return encode_response(data)
```
**Why:** Fixed in commit `ae96f15e`. The `status=` kwarg was added to stop 4xx/5xx being swallowed as 200.

### BUG-S06 — Double-Decode Risk (UNFIXED)
`XorWsgiMiddleware` decodes the request body BEFORE Flask sees it.  
If a route also calls `decode_request()` manually, it tries to XOR-decode already-decoded JSON.  
Result: garbage → `json.loads` raises → route sees no body → silent 400.

**Fix pattern:** Remove manual `decode_request()` calls from routes when `XorWsgiMiddleware` is active. Use `request.json` directly (already decoded by middleware).

## How XOR Works
1. Flutter generates a random 16-byte session key per request
2. Sends it in `X-Session-Key` header (hex-encoded)
3. XOR-encodes the JSON body byte-by-byte with the session key (cycling)
4. Server reads `X-Session-Key`, XOR-decodes the body → plain JSON
5. Server XOR-encodes the response with the same session key
6. Flutter XOR-decodes the response
