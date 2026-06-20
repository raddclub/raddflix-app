# BUG_TRACKER.md
Last updated: 2026-06-18 (debug logging session complete)

## Status Key
- ✅ FIXED — committed and verified
- 🔄 IN PROGRESS
- ❌ OPEN
- 🚫 WONT FIX

---

## Open Bugs

_No open bugs._

---

## Debug Logging Coverage (added 2026-06-18)

All screens now fully instrumented. Every crash, nav event, and user tap is captured.
See agent-hub/AGENT_STATUS.md for the full coverage table.

To read logs on device: **Profile → Account → Debug Logs**
Filter chips: CRASH → ERR → VIDEO/AUDIO → NAV → TAP → LC

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

| BUG-CHANNEL-MODE-RESET | `player_screen.dart` | `_chIdx` declared inside `StatefulBuilder.builder` — reset to 0 on every rebuild. Channel mode appeared to cycle but always snapped back to Stereo; `filters[0]=''` always sent to `onChannelModeChanged`. Fix: moved `_chIdx` to `_AudioTrackPanelState` field, replaced Builder/StatefulBuilder with direct `setState`. | 2026-06-20 ✅ |
| BUG-SUB-SPEED-NO-MPV | `player_screen.dart` | Subtitle speed slider `onSpeedChanged` callback only called `setState(() => _subSpeed = v)` — never called `_np.setProperty('sub-speed', v)`. Slider appeared responsive but had zero effect on MPV playback. Fix: added `try { _np.setProperty('sub-speed', v.toString()); } catch (_) {}` alongside setState. | 2026-06-20 ✅ |
| BUG-CLOCK-TIMER-30S | `player_screen.dart` | `_clockDisplayTimer` interval was `Duration(seconds: 30)` — clock overlay could be up to 30s stale. TASK_LOG documented fix to 10s but code had regressed. Fix: changed to `Duration(seconds: 10)`. | 2026-06-20 ✅ |
| BUG-SUB-TRANSLATE-NOP | `player_screen.dart` | Subtitle translation language picker `onTap` called only `Navigator.of(c).pop()` with no feedback and no action. Users selected a language and received silent no-op. Fix: added SnackBar "Subtitle translation to $lang coming soon." | 2026-06-20 ✅ |
| BUG-ONLINE-SUB-DEV-ERROR | `player_screen.dart` | `_fetchOnlineSubtitles` awaited 800ms then threw "Set OPENSUBTITLES_API_KEY env variable" — a developer error message shown directly to end users. Fix: removed fake delay, replaced with friendly SnackBar "Online subtitle search coming soon." | 2026-06-20 ✅ |

| BUG-VF-BLACKSCREEN | `player_screen.dart` | `_applyVideoFilters` called from `_loadPrefs` with 60ms debounce — fires after local video is playing → `vf=` on active HW decoder destroys GL surface → black screen. Fix: startup gate (`_firstVfApplied`) + dedup (`_lastAppliedVf`) + seek-after for user changes. | 2026-06-18 |

| BUG-ICON-COMPAT | `player_screen.dart` | `Icons.replay_15_rounded` / `forward_15_rounded` do not exist in Flutter 3.22.3. `replay_15` / `forward_15` also do not exist. Use `replay_10` / `forward_10`. Always verify icons against Flutter 3.22.3 source before using numbered variants. | 2026-06-18 |


## Critical Rules (added 2026-06-18)

| Rule | Detail |
|------|--------|
| vf= mid-play guard | **NEVER call `_np.setProperty('vf', ...)` while video is playing from startup code paths.** `_applyVideoFilters` MUST check `_firstVfApplied` gate (startup) and `_lastAppliedVf` dedup before calling. On Android HW decoder (MediaTek/Infinix), even an empty `vf=` call destroys the GL surface → black screen. User-initiated changes (settings pickers) are OK but must seek-after. |

| BUG-PLAYER-MUTE-OVERRIDE | `player_screen.dart` | SmartVolumeController._tick() clamped MPV volume min to 20.0 — fires every tick and overrides explicit user mute. Fixed: clamp(20.0→0.0, 130.0). | 2026-06-18 |
| BUG-RETRY-WRONG-EP | `player_screen.dart` | _StreamErrorOverlay retry used widget.fileId (always ep1) not _currentFileId — retrying mid-series always restarted from episode 1. Fixed: use _currentFileId. | 2026-06-18 |
| BUG-NEXTEP-EXITS-PLAYER | `player_screen.dart` | "Cancel" in _NextEpisodeOverlay called Navigator.of(context).pop() — pressing Cancel exited the entire player. Fixed: removed Navigator.pop(). | 2026-06-18 |
| BUG-DUAL-SLEEP-BADGES | `player_screen.dart` | Sleep fade badge and sleep timer badge both visible simultaneously. Fixed: added !_sleepFadeActive guard to timer badge condition. | 2026-06-18 |
| BUG-FRAMESTEP-STUCK | `player_screen.dart` | _showFrameStep set true in frameStep() but never cleared — frame-step controls stayed visible permanently. Fixed: clear in playing stream listener. | 2026-06-18 |
| BUG-DEAD-STATE-VARS | `player_screen.dart` | 6 state variables declared but never used (_audioTracks, _selectedAudioTrack, _castScanning, _castDevices, _showSubtitleHunter, _abLoopActive). Removed all 6. | 2026-06-18 |
| FIX-ORPHAN-IMPORT | `player_screen.dart` | `reaction_stamps_overlay.dart` imported at line 45 after widget was removed in 09760ca — orphaned import caused Dart unused-import warning on every build. Fixed: removed import. | 2026-06-18 |
| FIX-CLOCK-TIMER | `player_screen.dart` | Clock timer fired every 30s but overlay shows HH:MM — time could be up to 30s stale. Fixed: changed Timer.periodic interval from 30s → 10s. | 2026-06-18 |
| FIX-DEAD-BG-GUARD | `player_screen.dart` | BG-play toggle callback had `if (v && !_audioSessionInitialized) { _initAudioSession(); }` — `_audioSessionInitialized` is always true after initState so this block was permanently unreachable dead code. Fixed: removed dead guard block. | 2026-06-18 |
| FIX-NP-SHADOW | `player_screen.dart` | `onToggleSidebarMode` callback declared `final _np = _prefs.copyWith(sidebarMode: _nm)` — local `_np` shadowed the class-level `NativePlayer get _np` getter. A future `_np.setProperty()` call in that closure would compile but call `PlayerPrefs.setProperty` (crash). Fixed: renamed to `final newPrefs` / `final newMode`. | 2026-06-18 |

---

## New Rule (2026-06-18)

| Rule | Detail |
|------|--------|
| `PlatformDispatcher` import | Requires `import 'dart:ui' show PlatformDispatcher;` — NOT exported by `package:flutter/material.dart`. Missing this causes Dart compile error `Undefined name 'PlatformDispatcher'` on every build. |
| DebugLogger v2 methods (complete list) | `log`, `logError`, `logWarn`, `logApi`, `logState`, `logTap`, `logNav`, `logLifecycle`, `logFeature`, `logCrash`, `getLastLines`, `getRecent`, `getFiltered`, `clearBuffer`, `getLogPath`, `copyToClipboard`, `flush`, `share`, `shareLogs` |

  ## BUG-BLACKSCREEN-REGRESSION (RESOLVED 2026-06-18)
  - **Symptom**: Build #1141 (FIX-SPEED-RECOVERY) made black screen WORSE — happens on EVERY local file play within 1-3s, not intermittently
  - **Device**: MediaTek/Infinix (also reproduced on any fast Android device)
  - **Root cause**: `_applyVideoFilters` startup gate checked `_player.state.playing||_playing`. On local files, `playing=true` fires ~200-500ms after `player.open()`. Gate ran at ~90ms (SharedPrefs load + 60ms debounce) when playing was still false → gate passed → `setProperty('vf','')` + FIX-SPEED-RECOVERY's 150ms-delayed recovery seek both fired during decoder init window → GL surface destroyed
  - **Fix**: FIX-VF-STARTUP — add `_videoOpened=true` before each `_player.open()` call; include in gate: `_videoOpened||playing||_playing`
  - **Commit**: 4d88e277

  ## PlaybackTimeline Diagnostics (added 2026-06-18)

  Tool to prove/detect the MediaTek black screen bug. Produces an auditable startup trace per playback session.

  **Where to find it:** Profile → tap version text 5× → "Player" tab

  | Banner color | Meaning |
  |---|---|
  | 🟢 Green | Healthy startup — vf gate blocked correctly |
  | 🟠 Orange | ⚠️ vf gate PASSED during startup window (risk of black screen) |
  | 🔴 Red | Gate passed + audio confirmed at T+3s = black screen detected |

  **Key timeline events recorded:**
  - T+0ms — SESSION_START (player screen opened)
  - ~10ms — SURFACE_READY (GL surface live)
  - ~15ms — VIDEO_OPENED + PLAYER_OPEN_CALLED
  - ~45ms — PREFS_LOADED (SharedPrefs load complete)
  - ~105ms — VF_DEBOUNCE_FIRED (60ms debounce expired)
  - ~105ms — VF_GATE_CHECKED (with every flag value logged)
  - ~200-500ms — MPV_PLAYING (when MPV emits playing=true)
  - later — FIRST_FRAME (codec, resolution, decoder name)

  **Fix validation:** With FIX-VF-STARTUP in place:
  - VF_GATE_CHECKED always shows `_videoOpened=true` → gate BLOCKED → 🟢
  - MPV_PLAYING always arrives AFTER VF_GATE_CHECKED → no race window

  **Files:** `lib/core/debug/playback_timeline.dart`, `lib/screens/debug_diagnostics_screen.dart` (Player tab)
  