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
| JSESSIONID `.NODE` suffix | Never strip it — JazzDrive LB uses it for sticky routing. WITH suffix = 200 OK, WITHOUT = 401 HTML |
| SAPI token | Always use DB `raw_accesstoken` (OTP-issued, 40 hex chars) as SAPI `key=` param. OAuth2-rotated tokens are NOT registered in SAPI and always 401 |
| Authorization header | Must match the `key=` param exactly: `Authorization: oauth <Base64({"data":{"accesstoken":"<raw_at>","refreshtoken":"<rt>","msisdn":"<msisdn>"}})>` |
| CDN stream URL | Do NOT append `validationkey=` — CDN authenticates via self-signed `k=` token already in URL |
| `db.setting(k)` | Use `db.setting(k)` not `db.get_setting(k)` — `get_setting` does not exist |
| X-deviceid format | Always prefix with `fac-` e.g. `fac-fcbf291eddd5d372` (APK confirmed) |
| OAuth portal UA | Use Android WebView UA: `Mozilla/5.0 (Linux; Android 10; Infinix X680F; wv) Chrome/87.0.4280.141` for authorization.php / verify.php |
| SAPI UA | Use `omh android client` for all SAPI calls |
| XOR padding | `final pad = (4 - b64.length % 4) % 4; b64 += '=' * pad;` — never remove from `request_encoder.dart` |
| sqflite_sqlcipher | Never upgrade past `3.1.0+1` |
| VideoController | Never add `androidAttachSurfaceAfterVideoParameters: true` — causes black screen |
| Dart semicolons | Semicolons MUST come BEFORE inline comments: `expr); // comment` — never after |
| Oracle git pull | Always `git stash && git pull && git stash pop` — Oracle has local uncommitted files |
| Bulk DELETEs | Use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()` |
| Debug code | Gate behind `kDebugMode` — stripped from release APK |

---

_Add new bugs below this line as they are found._
