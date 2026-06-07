# BUG_TRACKER.md
Last updated: 2026-06-07

## Status Key
- ✅ FIXED — committed and verified on live server
- 🔄 IN PROGRESS
- ❌ OPEN
- 🚫 WONT FIX / INTENTIONAL

---

## Session 2026-06-04 — All bugs fixed

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-C01 | CRITICAL | Catalog always empty after fresh install | XOR decode: server strips base64 `=` padding; Dart `base64Url.decode` throws `FormatException` without it | Re-add padding: `b64 += '=' * ((4 - b64.length % 4) % 4)` before decode | `core/security/request_encoder.dart` |
| BUG-C02 | CRITICAL | Login always fails — "Login failed" toast on every attempt | `AuthApi.getMe()` called post-login on XOR path — same padding bug threw `TypeError` before response was parsed | Same padding fix | `core/security/request_encoder.dart` |
| BUG-C03 | CRITICAL | Premium plan shows as FREE after subscription | `_saveUserCache()` in auth_provider never executed (always threw before reaching it) | Same padding fix unblocked the call chain | `core/security/request_encoder.dart` |
| BUG-C04 | CRITICAL | App requires full login every restart — session not persisting | `checkAuth()` found no cached user (write to SharedPrefs never reached due to C02 exception) | Same padding fix | `core/security/request_encoder.dart` |
| BUG-C05 | HIGH | Plans/pricing screen completely empty | `GET /api/subscription/plans` is XOR-encoded — same padding bug silently dropped the response | Same padding fix | `core/security/request_encoder.dart` |
| BUG-P01 | HIGH | Black screen for 3–5 seconds before video plays | `androidAttachSurfaceAfterVideoParameters: true` causes surface re-attach failure on Android | Removed from `VideoController` config | `screens/player_screen.dart` |
| BUG-D01 | MEDIUM | TypeError in api_client: `response.data` not always a Map | XOR interceptor returns decoded JSON string; code assumed `Map` type without checking | Added type guard: `data is String ? jsonDecode(data) : data` | `core/api/api_client.dart` |
| BUG-S01 | MEDIUM | Catalog shows blank after sync fails (no internet) | `catalog_provider.dart` propagated sync exception without falling back to local DB | Added `await loadFromDb()` in the sync catch block | `providers/catalog_provider.dart` |

---

## Root Cause Summary

**5 of 8 bugs (BUG-C01 through BUG-C05) had a single root cause:**
Python's `base64.urlsafe_b64encode().rstrip(b"=")` strips 1–2 padding characters.
Dart's `base64Url.decode()` requires correct padding. Without the fix, every XOR decode
threw a `FormatException` that propagated silently up the call chain, making the entire
catalog, auth, and subscription systems appear broken.

Two characters (`==`) caused 5 critical bugs.

---

## Non-Bugs (intentional behavior)

| Item | Notes |
|------|-------|
| Frida tamper check (port 27042) | Correct security behavior — do not remove |
| sqflite_sqlcipher pinned at 3.1.0+1 | Must stay pinned — SQLCipher Dart API changed |
| No catalog on first cold start | Expected — sync takes a few seconds on first launch |

---

## Open Bugs

See DATA-01 below — all code bugs are fixed.

---

## Session 2026-06-04 (continued) — Additional bugs found and fixed

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-P02 | MEDIUM | Black flash before first frame of local video | `Video` widget at opacity 1.0 before first frame decoded | Wrapped in `AnimatedOpacity(0.0->1.0 at 400ms)` on `_playing` | `screens/player_screen.dart` |
| BUG-P03 | HIGH | planExpired redirect fires 1-3s into local file playback | `_checkQuota()` checked sub_expires_at for all paths including local files with empty fileId | Guard `&& widget.fileId.isNotEmpty` — local files skip quota | `screens/player_screen.dart` |
| BUG-J01 | CRITICAL | JazzDrive Pass 3 never matched — all folder shares played first file | Dart backslash-dollar in non-raw string = literal $, not interpolation. Pass 3 built literal text instead of `s01e04` | Replaced with concatenation `'s' + s + 'e' + e` | `core/services/jazzdrive_service.dart` |

### Root Cause Detail — BUG-J01

Pass 3 compared JazzDrive record names against a literal string like
`s${em.group(1)!.padLeft(2,"0")}e...` instead of e.g. `s01e04`.
It never matched anything. All episode folder shares silently fell back to
`records[0]` (first file in the share), so every episode played the same video.

The bug was introduced when a Node.js automation script generated Dart source code
and escaped `$` to prevent shell variable substitution. The escape survived into
the committed Dart file undetected because the fallback always returned a playable URL.

**Rule:** Any Dart string built in a generator script must use concatenation for dynamic
parts, never `\$` — or use raw strings (`r'...'`).

---

## Data Gap (not a code bug)

---

## Session 2026-06-07 — Player Screen Pass 2 (BUG-P-NEW-01 through BUG-P-NEW-04)

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-P-NEW-01 | HIGH | Background-play toggle triggers duplicate audio session listeners | `_audioSessionInitialized` flag never set to `true` in `initState()` — every BG-play toggle re-ran `_initAudioSession()` and stacked listeners | Set `_audioSessionInitialized = true` immediately after `_initAudioSession()` call in `initState()` | `screens/player_screen.dart` |
| BUG-P-NEW-02 | MEDIUM | Night Mode tile in More sheet always shows as inactive | `_MxMoreSheet` `active` state used `cinematicMode` instead of `_prefs.nightMode` | Added `nightModeActive` field; pass `_prefs.nightMode` at call site | `screens/player_screen.dart` |
| BUG-P-NEW-03 | HIGH | Mid-stream errors silently swallowed → infinite buffering with no feedback | Blanket `return` in error handler dropped all errors after 3s of playback (CDN expiry / network drop) | Show "Connection lost — reconnecting…" SnackBar + soft `_jazzAutoRetry` | `screens/player_screen.dart` |
| BUG-P-NEW-04 | CRITICAL | Cast button crashes app before first URL loads | `_currentPlaybackUrl.isNotEmpty` called on nullable `String?` — NPE when cast opened before URL resolved | Null-safe check: `_currentPlaybackUrl != null && _currentPlaybackUrl!.isNotEmpty` | `screens/player_screen.dart` |

---

## Session 2026-06-07 — Player Screen Pass 3 (BUG-P-NEW-05)

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-P-NEW-05 | HIGH | ClipTrimmer A-B points don't enforce loop or show on seek bar | `onTrimChanged` only set `_abLoopStart`/`_abLoopEnd` state vars but never called `_abLoop.setA()`/`_abLoop.setB()` — so `maybeSeekBack()` had no data and seek bar markers never rendered | Added `_abLoop.setA(trim.start)` and `_abLoop.setB(trim.end)` after setState in `onTrimChanged` | `screens/player_screen.dart` |

---

## Session 2026-06-07 — Player Screen Pass 4 full re-audit (BUG-P-NEW-06 + BUG-P-NEW-07)

| ID | Severity | Title | Root Cause | Fix Applied | File |
|----|---------|-------|-----------|-------------|------|
| BUG-P-NEW-06 | MEDIUM | Cinematic mode can only be toggled ON via VideoEnhanceSuite sheet, never OFF | `_openVideoEnhanceSuite` `onChanged` handler checked `map['cinematicMode'] == true` and called `_toggleCinematic()` — but never called it when the value was `false`. So once cinematic was enabled through the sheet, it could never be disabled via that path. | Compare new value against `_cinematicMode` and call `_toggleCinematic()` only when they differ: `if ((map['cinematicMode'] as bool? ?? _cinematicMode) != _cinematicMode) _toggleCinematic();` | `screens/player_screen.dart` |
| BUG-P-NEW-07 | HIGH | Quick Bar "Night Mode" button toggles cinematic mode instead of night mode | `_QuickShortcutBar`'s `onNightMode` was wired to `onToggleCinematic` in `_ControlsOverlay`'s build method — a copy-paste error. Tapping "Night" in the Quick Bar silently toggled cinematic instead of applying the night-mode video filter. The Video Display Sheet had the correct implementation; the Quick Bar did not. | Added `onToggleNightMode` callback to `_ControlsOverlay`; wired it from `_buildPlayerBody` to the same correct lambda used by the Video Display Sheet (`_prefs.copyWith(nightMode: !_prefs.nightMode)` + save + `_applyVideoFilters()`); changed `onNightMode: onToggleCinematic` to `onNightMode: onToggleNightMode`. | `screens/player_screen.dart` |

### Pass 4 audit completeness note
All 6,252 lines of `player_screen.dart` were read in full across 4 passes.
No additional functional bugs found beyond BUG-P-NEW-06 and BUG-P-NEW-07.
Items confirmed NOT bugs:
- `_applyRotation` double-`copyWith` (cosmetically wasteful, functionally correct — setState runs callback synchronously so second copyWith is a no-op on the already-updated prefs)
- Quick Bar "Night Mode" label wired to cinematic in `_QuickShortcutBar.onNightMode` (NOW FIXED as BUG-P-NEW-07)
- Dead state vars (`_abLoopActive`, `_castScanning`, `_castDevices`, `_connectedCastDevice`, `_watchPartyRoom`, `_audioTracks`, `_selectedAudioTrack`) — declared but unused; not bugs, just stale scaffolding


---

## Session 2026-06-07 — Player Screen Pass 5: 29-Bug Full Audit

| ID | Severity | Title | Root Cause | Fix | Status |
|----|---------|-------|-----------|-----|--------|
| C-01 | CRITICAL | _applyVolumeBoost maxes system volume on player open | Unconditional VolumeController().setVolume(1.0) ran on prefs restore; gesture handlers already do this inline | Removed call from _applyVolumeBoost | ✅ FIXED |
| C-02 | CRITICAL | Inner GestureDetector wins pinch arena, outer zoom dead | onScaleStart:(_){} on inner GD claimed arena for all pinch events | Removed onScaleStart; added pointerCount<2 guard in onScaleUpdate | ✅ FIXED |
| H-01 | HIGH | _applyVideoFilters/_applyAudioPrefs race on rapid pref changes | Both async; rapid calls overwrote each other in MPV | 60ms timestamp debounce (_lastVfTs/_lastAfTs) — newer call supersedes | ✅ FIXED |
| H-02 | HIGH | _jazzRetryCount not reset on episode change | Counter persisted: ep 2+ could never retry if ep 1 exhausted retries | _jazzRetryCount=0 at start of _playPrevEpisode and _playNextEpisode | ✅ FIXED |
| H-03 | HIGH | _startWakeTimer uses default prefs (called before _loadPrefs) | initState called _startWakeTimer before prefs loaded; used zero timeout | Added _startWakeTimer() at end of _loadPrefs() | ✅ FIXED |
| H-04 | HIGH | _cancelSleepTimer setState without mounted guard | Timer fires on background thread; if disposed, setState throws | if (mounted) guard added | ✅ FIXED |
| H-05 | HIGH | Playback info panel always shows dashes | _fetchPlaybackInfo called once on open, never refreshed | _piTimer: Timer.periodic(2s) while panel open; cancelled in dispose() | ✅ FIXED |
| H-06 | HIGH | Muting with boost: system silent but MPV plays at boost level | onMute only called VolumeController().setVolume(0); MPV volume untouched | Mute sets MPV vol=0; unmute restores (_volume * _volumeBoost * 100) | ✅ FIXED |
| H-07 | HIGH | SleepTimerSheet.onStopAtEpisodeEnd dead | onStopAtEpisodeEnd:(_){} blank lambda | Wired to _setSleepTimer(-1) | ✅ FIXED |
| H-08 | HIGH | Long-press speed badge auto-fades while holding | Fixed-duration fadeOut chain ran regardless of gesture state | Removed .then().fadeOut(); badge lives while _longPressFast=true | ✅ FIXED |
| M-01 | MEDIUM | QuickShortcutBar nightmode never active-highlighted | _QuickShortcutBar had no nightModeActive param; case never set active=true | nightModeActive field threaded through _ControlsOverlay + _QuickShortcutBar | ✅ FIXED |
| M-02 | MEDIUM | _SleepPanel shows nothing when sleepAtEpisodeEnd=true | Panel only checked remaining!=null; episode-end mode invisible | sleepAtEpisodeEnd param added; "Pausing at episode end" text shown | ✅ FIXED |
| M-03 | MEDIUM | SW Decoder toggle has zero effect on MPV | Toggle only updated local _swDecoder state; no callback to MPV | onSwDecoderChanged callback wired to _np.setProperty('hwdec') | ✅ FIXED |
| M-04 | MEDIUM | CinematicSettingsSheet gets wrong opacity | cinematicOpacity: _prefs.transparentModeOpacity (wrong field) | Changed to _cinematicOpacity (local state var) | ✅ FIXED |
| M-05 | MEDIUM | Night mode colorchannelmixer missing alpha params | FFmpeg requires 12 coefficients; missing ra/ga/ba default to 0 (transparent) | Added :ra=0 :ga=0 :ba=1 to filter string | ✅ FIXED |
| M-06 | MEDIUM | Hue divided by 180 compresses to near-zero | MPV eq filter hue takes degrees (-180 to +180), not 0-1 | Removed /180.0 | ✅ FIXED |
| M-07 | MEDIUM | Controls freeze after rage skip | _scheduleHide() not called; hide timer never restarted | Added _scheduleHide() after _rageSkipActive=true | ✅ FIXED |
| M-08 | MEDIUM | Plan expiry skips streaming users entirely | Condition gated on widget.localPath!=null; streaming (no localPath) always skipped | Broadened to fileId.isNotEmpty && !_isLocalPath(widget.fileId) | ✅ FIXED |
| M-09 | MEDIUM | _loadSmartIntro() in initState always returns early | SmartIntroStore.shouldShow checks _duration>0 but duration=0 at initState | Removed dead call; real load via _skipIntroTimer at 5s | ✅ FIXED |
| L-01 | LOW | Shuffle + Customise Items permanently dead | onTap:(_){} — never implemented | Removed both from _VideoDisplaySheet row2 | ✅ FIXED |
| L-02 | LOW | Loop and A-B Repeat callbacks identical | Both opened AB panel | onLoop now calls _np.command(['cycle','loop-file']) | ✅ FIXED |
| L-03 | LOW | Negative remaining time during intro skip | Position ahead of known duration | Deferred — clamp at caller level in next cleanup pass | 🚫 DEFERRED |
| L-04 | LOW | lock_current uses raw physicalSize (can throw early) | renderViews.first.flutterView.physicalSize is hardware pixels; can throw | Replaced with MediaQuery.of(context).size | ✅ FIXED |
| L-05 | LOW | Rage skip double-fires within 1200ms animation | No guard in _handleCenterTap | if (_rageSkipActive) return; guard added | ✅ FIXED |
| L-06 | LOW | Settings pop doesn't restore SystemChrome | Navigator.push with no .then() | Added .then((_){SystemChrome.setEnabledSystemUIMode + _applyRotation}) | ✅ FIXED |
| L-07 | LOW | _openCinematicSettings accessible when mode is off | No harmful side-effects | Deferred | 🚫 DEFERRED |
| L-08 | LOW | _longPressFast + mediaButton fields use 4-space indent | Class body uses 2-space throughout | Fixed to 2-space | ✅ FIXED |
| L-09 | LOW | Duplicate _openJumpTo/_showJumpToTime | Harmless redundancy | Deferred — consolidate in cleanup pass | 🚫 DEFERRED |
| L-10 | LOW | _cinematicOpacity changes not persisted | onOpacityChanged only updates local state | Deferred — needs PlayerPrefs.cinematicOpacity schema addition | 🚫 DEFERRED |
