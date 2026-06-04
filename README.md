# RaddFlix

Pakistan ka entertainment, data-free — a Flutter streaming app zero-rated on Jazz SIM.

## Stack

- Flutter 3.x · Dart 3 · Riverpod (state management)
- SQLite encrypted via SQLCipher (sqflite_sqlcipher **3.1.0+1** — pinned, never upgrade)
- media_kit ^1.1.10 + media_kit_video ^1.2.4 for video playback
- Dio for HTTP · flutter_secure_storage (Android Keystore) for tokens
- Oracle server: Flask + XOR WSGI middleware at `http://92.4.95.252`

## Architecture

### XOR Encoding
Every `/api/*` request adds `X-Encoded:1` + `X-Device-Id` headers.  
The server XOR-encodes all responses and sets `Content-Type: application/octet-stream`.  
Key = SHA-256(`raddflix_xor_v1:deviceId:UTCday:UTCgour`)[:32].  
**Critical**: server strips base64 padding (`rstrip(b"=")`). Client must re-add before decoding.  
Auth paths (`/api/auth/login`, `/register`, `/refresh`, `/guest`) are excluded from XOR.

### Authentication & Session Persistence
- Tokens stored in Android Keystore via `flutter_secure_storage` (encrypted)
- Access token: 7-day JWT · Refresh token: 90-day JWT (auto-refreshed transparently)
- `checkAuth()` restores session instantly from `SharedPreferences` cache (offline-safe)
- User plan/phone cached in SharedPrefs; only updated after successful `AuthApi.getMe()`

### Local Database
- SQLCipher-encrypted SQLite, key generated once on install (never leaves the device)
- Tables: `titles`, `episodes`, `sync_meta`, `watch_positions`, `downloads`, `stream_cache`, `usage_log`, `quota_cache`, `show_ep_seen`
- DB version: 17 (schema in `LocalDb._createAll()`, migrations in `LocalDb._migrate()`)
- Catalog sync: every 6 hours or on app resume

### Content Delivery
- Video files hosted on JazzDrive (zero-rated CDN for Jazz users)
- Stream links generated on-demand via Oracle, cached 180 min in `stream_cache`
- Poster images served from JazzDrive `poster_share_url` (permanent, zero-rated)

## Bugs Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Catalog always empty | XOR decode: server strips base64 `=` padding; Dart `base64Url.decode` throws without it | Re-add padding before decode in `RequestEncoder.decode()` |
| Login always shows "Login failed" | `AuthApi.getMe()` after login used XOR — same padding bug — threw TypeError | Same padding fix |
| Premium shows as free | `_saveUserCache()` never ran because `getMe()` always threw | Same padding fix |
| App requires login every restart | `checkAuth()` had no cached user (never written) — fell through to unauthenticated | Same padding fix |
| Plans screen empty | `/api/subscription/plans` is XOR-encoded — same bug | Same padding fix |
| Player black screen 3-5s | `androidAttachSurfaceAfterVideoParameters:true` causes surface re-attach failure on Android | Removed from `VideoController` config |

**All 5 catalog/auth/plans bugs had one root cause: 2 missing `=` padding characters.**

## Build & Run

```bash
# Debug APK (includes diagnostic screen — shows internal stats)
flutter build apk --debug

# Release APK (diagnostic screen stripped completely — for public)
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

## Security

- Tamper detection: Frida port 27042 check active; signature check placeholder (disabled)
- XOR encoding over HTTPS adds obfuscation layer for API traffic
- Debug diagnostic screen is gated behind `kDebugMode` — physically absent from release APK
- DB key tied to device install — uninstalling makes encrypted DB unreadable

## Where Things Live

| Purpose | File |
|---------|------|
| XOR encode/decode | `lib/core/security/request_encoder.dart` |
| HTTP client + interceptors | `lib/core/api/api_client.dart` |
| Auth state + session restore | `lib/providers/auth_provider.dart` |
| DB schema + CRUD | `lib/core/db/local_db.dart` |
| Catalog sync | `lib/core/db/sync_service.dart` |
| Video player | `lib/screens/player_screen.dart` |
| Subscription plans screen | `lib/screens/subscription_screen.dart` |
| Debug diagnostics (debug only) | `lib/screens/debug_diagnostics_screen.dart` |
