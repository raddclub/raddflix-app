# BUG_TRACKER.md
Last updated: 2026-06-17

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
| Long-press framedrop | Always set `framedrop=decoder+vo` BEFORE speed change in `onLongPressStart`. Restore `framedrop=vo` in `onLongPressEnd`. Without this, MediaCodec HW decoder crashes at >1x speed on MediaTek/Infinix → blank screen. |
| _setSpeed channel ordering | `_setSpeed()` MUST use `_np.setProperty('speed', ...)` — NOT `_player.setRate()`. `setRate()` travels a different Dart API path and can arrive at MPV before `framedrop=decoder+vo` is applied → HW decoder crashes at >1× → blank screen. Both framedrop and speed must go through the same NativePlayer (_np) channel. |
| _videoSurfaceReady latch timing | `_videoSurfaceReady` MUST be set `true` immediately after `VideoController` construction in `_initPlayer()`, NOT on first `playing=true` event. The GL surface is live from VideoController ctor (~20ms); `_loadPrefs` → `_applyAudioPrefs` fires at ~70ms (60ms debounce) and finds `_videoSurfaceReady=false` if only latched on playing — changes hwdec → surface destroyed → blank screen. |
| _jazzRetryCount reset | Reset `_jazzRetryCount = 0` inside `_openMedia` on every successful `_player.open()` call. Failure to reset causes any subsequent MPV error to immediately show the error overlay even while video plays. |
| _videoSurfaceReady hwdec gate | `_applyAudioPrefs` hwdec guard MUST include `!_videoSurfaceReady`. Without it, episode-navigation transitions (playing=false + duration=zero) allow hwdec mid-session → permanent blank. |
| _jazzAutoRetry playing guard | `_jazzAutoRetry` MUST check `if (_playing) return` before setting `_streamError`. Mid-play errors are transient; never show error overlay over a live video. |
| hwdec mid-play | **NEVER call `_np.setProperty('hwdec', ...)` while video is playing or media is open.** Correct guard in `_applyAudioPrefs()`: `if (!_playing && !_player.state.playing && _player.state.duration == Duration.zero && !_videoSurfaceReady)`. The `_playing` Flutter state var alone is NOT sufficient — it lags one setState cycle behind MPV state. |
| Flutter icon variants | Only use icon names confirmed in Flutter 3.22.3 source. `replay_15`, `forward_15` (and `_rounded` variants) do NOT exist. Use `replay_10`/`forward_10`/`replay_30`/`forward_30` (all confirmed in source). |
| Dart semicolons | Semicolons MUST come BEFORE inline comments: `expr); // comment` — never after |
| Oracle git pull | Always `git stash && git pull && git stash pop` — Oracle has local uncommitted files |
| Bulk DELETEs | Use direct `sqlite3.connect()` + `BEGIN IMMEDIATE`, NOT `db.conn()` |
| Debug screen | `DebugDiagnosticsScreen` is intentionally NOT gated by `kDebugMode` — it is accessible in release APK via 5-tap on version text in Profile. Do NOT re-add `if (!kDebugMode) return const SizedBox.shrink()`. Other debug-only code (logging widgets, test helpers) should still be gated with `kDebugMode`. |
| Dio validateStatus | All `jazzdrive_service.dart` Dio requests MUST include `validateStatus: (s) => true`. Without it, non-200 responses throw DioException with no body — the real error reason is lost. JazzDrive returns HTML on non-Jazz-SIM; always detect `raw.trimLeft().startsWith('<')` and throw a clear exception. |
| GitHub push method | `git commit` is blocked in main agent. Always use Node.js GitHub Contents API (PUT) for single-file pushes. For multi-file use Trees API: create blobs → create tree → create commit → PATCH ref. Never include `.replit` in pushes (causes 404). Binary files: `buf.toString('base64')`. |

---

## Fixed Bugs (History)

| ID | File | Description | Fixed |
|----|------|-------------|-------|
| BUG-BLANK-SURFACE-RACE | `player_screen.dart` | Startup blank screen: `_videoSurfaceReady` only latched on `playing=true` (too late). `_applyAudioPrefs` ran at ~70ms with surface already live but latch still false → hwdec changed → GL surface destroyed → permanent blank with audio. Fix: set `_videoSurfaceReady = true` immediately after `VideoController` ctor in `_initPlayer()`. | 2026-06-17 |
| BUG-BLANK-SPEED-CHANNEL | `player_screen.dart` | Long-press blank screen (channel race): `_player.setRate()` reached MPV before `_np.setProperty('framedrop','decoder+vo')` because they travel different API paths — HW decoder crashed at >1× without framedrop protection. Fix: replaced `_player.setRate(s)` with `_np.setProperty('speed', s.toStringAsFixed(4))` so both commands share the same NativePlayer queue. | 2026-06-17 |
| BUG-BLANK-LP-RECOVERY | `player_screen.dart` | Long-press blank screen (incomplete recovery): 80ms post-release seek too short; no framedrop re-assertion before seek. Fix: delay 80ms→200ms; add explicit `_np.setProperty('framedrop','vo')` before recovery seek in `onLongPressEnd`. | 2026-06-17 |
| BUG-PLAYER-TRIFECTA-A | `player_screen.dart` | Catalog popup over playing video: `_jazzRetryCount` not reset on successful open + `_jazzAutoRetry` set `_streamError` even when `_playing=true`. Fix: reset count after each `_player.open()`; guard with `if (_playing) return` | 2026-06-17 |
| BUG-PLAYER-TRIFECTA-B | `player_screen.dart` | Local video permanent blank: hwdec guard episode-nav race — all three guard conditions (playing=false, state.playing=false, duration=zero) simultaneously true during `_player.open(newEp)` transition. Fix: add `!_videoSurfaceReady` fourth guard (latch never resets). | 2026-06-17 |
| BUG-PLAYER-TRIFECTA-C | `player_screen.dart` | Long-press blank screen: MediaCodec HW decoder crashes at 2× speed on MediaTek/Infinix. Fix: `framedrop=decoder+vo` before `setRate()`, `framedrop=vo` after. | 2026-06-17 |
| BUG-HWDEC-LIVE-TOGGLE | `player_screen.dart` | SW decoder toggle called `setProperty('hwdec',...)` with no guard → blank on mid-play switch. Fix: added `await + seek(position)` post-switch. | 2026-06-17 |
| BUG-FAB-01 | `player_screen.dart` | FAB in Local Media always played first video — watch positions were never written for local files. Fix: write position using `_currentPlaybackUrl` as key for local files. | 2026-06-17 |
| BUG-AUDIT-STALE-ERR | `player_screen.dart` | `_openMedia` never cleared `_streamError` — old error overlay stayed visible while new media loaded | 2026-06-17 |
| BUG-AUDIT-RETRY-MSG | `player_screen.dart` | `_jazzAutoRetry` set `_streamError` to raw MPV error string — now routed through `_buildJazzError` | 2026-06-17 |
| BUG-AUDIT-HTML-MSG | `player_screen.dart` | `_buildJazzError` had no explicit handler for HTML/XML error strings — now classified correctly | 2026-06-17 |
| BUG-AUDIT-JSESSIONID | `jazzdrive_service.dart` | `_loginShare` returned empty-cookie `_ShareSession` when JSESSIONID was missing — now throws early with clear message. | 2026-06-17 |
| BUG-AUDIT-EMPTY-URL | `jazzdrive_service.dart` | `_getMedia` passed empty `rawUrl` to `_buildStreamUrl` — now throws before building URL. | 2026-06-17 |
| BUG-JAZZ-GENERIC-ERROR | `player_screen.dart`, `jazzdrive_service.dart` | All JazzDrive failures showed "Jazz SIM Required" — real error lost due to no `validateStatus` on Dio. | 2026-06-17 |
| BUG-BLACKSCREEN-LP | `player_screen.dart` | Long-press fast-forward leaves black frame after speed returns to 1x — superseded by BUG-BLANK-SPEED-CHANNEL + BUG-BLANK-LP-RECOVERY | 2026-06-17 |
| BUG-BLACKSCREEN-LOCAL | `player_screen.dart` | Local video black after ~2s — superseded by BUG-BLANK-SURFACE-RACE + BUG-PLAYER-TRIFECTA-B | 2026-06-17 |
| BUG-LOGIN-01 | `login_screen.dart` | Wrong password always navigated to home as guest — `_login()` never checked `state.error` | 2026-06-16 |
| BUG-JD-VK | `jazzdrive_service.dart` | `_buildStreamUrl` appended `validationkey=` to CDN URL — breaks CDN authentication | 2026-06-16 |
| BUG-JD-SESSION | `jazzdrive_service.dart` | JSESSIONID `.NODE` suffix was being stripped — causes sticky session routing to fail (HTTP 401) | 2026-06-16 |
| BUG-DL-PATH-B | `download_service.dart` | Path B used `getShareUrl()` losing filename+remote_id → always downloaded episode 1 | 2026-06-16 |
| BUG-DL-RF1 | `download_service.dart` | Path A passed raw `RF1:xxx` URL to JazzDrive without decoding | 2026-06-16 |
| BUG-SYNC-02 | `catalog_provider.dart` | No `_initialized` guard — catalog re-synced on every home visit | 2026-06-15 |
| BUG-BGPLAY-FOREGROUND | `PlaybackService.kt`, `MainActivity.kt`, `AndroidManifest.xml`, `player_screen.dart` | Background play stopped after ~1 min. Fix: PlaybackService.kt foreground service + manifest + lifecycle hooks. | 2026-06-17 |
| BUG-PIP-EXIT | `MainActivity.kt`, `player_screen.dart` | `_inPiP` set true on entry, never reset to false. Fix: `onPictureInPictureModeChanged` in Kotlin + `_initPipChannel` handler in Flutter. | 2026-06-17 |

---

_Add new bugs below this line as they are found._

| BUG-ICON-COMPAT | `player_screen.dart` | `Icons.replay_15_rounded` / `forward_15_rounded` do not exist in Flutter 3.22.3. `replay_15` / `forward_15` also do not exist. Use `replay_10` / `forward_10`. Always verify icons against Flutter 3.22.3 source before using numbered variants. | 2026-06-18 |
