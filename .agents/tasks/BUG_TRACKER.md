# BUG_TRACKER.md
Last updated: 2026-06-16

## Status Key
- ✅ FIXED — committed and verified
- 🔄 IN PROGRESS
- ❌ OPEN
- 🚫 WONT FIX

---

## Open Bugs

_No open bugs._

---

## Critical Rules (learned from past bugs — never break these)

| Rule | Detail |
|------|--------|
| JSESSIONID `.NODE` suffix | **NEVER strip it** — JazzDrive LB uses it for sticky routing. WITH suffix = HTTP 200 OK, WITHOUT = HTTP 401 HTML from wrong node. This is the single most common cause of media fetch failures. |
| SAPI token | Always use DB `raw_accesstoken` (OTP-issued, 40 hex chars) as SAPI `key=` param. OAuth2-rotated tokens are NOT registered in SAPI and always return 401 |
| Authorization header | Must match the `key=` param exactly: `Authorization: oauth <Base64({"data":{"accesstoken":"<raw_at>","refreshtoken":"<rt>","msisdn":"<msisdn>"}})>` |
| CDN stream URL | Do NOT append `validationkey=` — CDN authenticates via self-signed `k=` token already in URL. Adding validationkey= breaks CDN URLs. |
| `db.setting(k)` | Use `db.setting(k)` not `db.get_setting(k)` — `get_setting` does not exist |
| X-deviceid format | Always prefix with `fac-` e.g. `fac-fcbf291eddd5d372` (APK confirmed) |
| OAuth portal UA | Use Android WebView UA: `Mozilla/5.0 (Linux; Android 10; Infinix X680F; wv) Chrome/87.0.4280.141` for authorization.php / verify.php |
| SAPI UA | Use `omh android client` for all SAPI calls |
| XOR padding | `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove from `request_encoder.dart` |
| sqflite_sqlcipher | Never upgrade past `3.1.0+1` |
| VideoController | Never add `androidAttachSurfaceAfterVideoParameters: true` — causes black screen |
| hwdec mid-play | **NEVER call `_np.setProperty('hwdec', ...)` while `_playing == true`** — changing hwdec on Android while playing destroys GL surface texture → blank screen (audio continues). Guard with `if (!_playing)` in `_applyAudioPrefs()`. |
| Dart semicolons | Semicolons MUST come BEFORE inline comments: `expr); // comment` — never after |
| Oracle git pull | Always `git stash && git pull && git stash pop` — Oracle has local uncommitted files |
| Bulk DELETEs | Use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()` |
| Debug screen | `DebugDiagnosticsScreen` is intentionally NOT gated by `kDebugMode` — it is accessible in release APK via 5-tap on version text in Profile. Do NOT re-add `if (!kDebugMode) return const SizedBox.shrink()`. Other debug-only code (logging widgets, test helpers) should still be gated with `kDebugMode`. |

---

## Fixed Bugs (History)

| ID | File | Description | Fixed |
|----|------|-------------|-------|
| BUG-LOGIN-01 | `login_screen.dart` | Wrong password always navigated to home as guest — `_login()` never checked `state.error` before pushing home route | 2026-06-16 |
| BUG-JD-VK | `jazzdrive_service.dart` | `_buildStreamUrl` appended `validationkey=` to CDN URL — breaks CDN authentication | 2026-06-16 |
| BUG-JD-SESSION | `jazzdrive_service.dart` | JSESSIONID `.NODE` suffix was being stripped — causes sticky session routing to fail (HTTP 401) | 2026-06-16 |
| BUG-DL-PATH-B | `download_service.dart` | Path B used `getShareUrl()` losing filename+remote_id → always downloaded episode 1 | 2026-06-16 |
| BUG-DL-RF1 | `download_service.dart` | Path A passed raw `RF1:xxx` URL to JazzDrive without decoding | 2026-06-16 |
| BUG-SYNC-02 | `catalog_provider.dart` | No `_initialized` guard — catalog re-synced on every home visit | 2026-06-15 |

---

_Add new bugs below this line as they are found._
