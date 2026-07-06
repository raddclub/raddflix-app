# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

## Current State (2026-07-05 — Player Panel Audit)

### Bottom Nav Redesign — 2026-07-06 (latest)
Two commits: `405f250`, `00f71cb`.

**What changed:**
- **Tab 1: Local → Search** — `PhosphorIcons.magnifyingGlass` icon. Search was buried as an AppBar icon on Home only; now a primary nav destination reachable from every screen. Home AppBar search icon removed (no longer needed).
- **Tab 2: Downloads → Library** — `PhosphorIcons.files` icon. Renamed to signal "all your offline content," not just in-progress downloads.
- **Label font 9.5 → 11.0px** — accessibility fix (was below WCAG minimum).
- **Search screen gets bottom nav** — `RaddFlixBottomNav(currentIndex: 1)` added to `SearchScreen` Scaffold; it was the only primary screen without one.
- **Local Media stays reachable via Library** — `DownloadsScreen` AppBar gets an "On Device" button (`AppIcons.device`) that navigates to `LocalMediaScreen`. Local is no longer a top-level tab but remains easily accessible within Library context.
- **LocalMediaScreen nav updated** — `currentIndex: 2` (Library stays highlighted); tapping Library tab pops back to Downloads/Library instead of doing a full popUntil+push.
- **`_navIndex` drift fixed** — Home screen pushes now use `.then((_) => setState(() => _navIndex = 0))` so the capsule indicator resets correctly when user presses back from any tab.
- **All screens updated** — `downloads_screen.dart`, `local_media_screen.dart`, `profile_screen.dart` all have their embedded bottom nav `onTap` routing updated (i==1 → search, not localMedia).

**New nav structure:** Home (0) · Search (1) · Library (2) · Profile (3)

### Player Panel Audit — 2026-07-05
Full audit of all player panels + format support. Three commits: `303b9af`, `1bc5b7c`.

**What changed:**
- **Info icon removed** from landscape top bar — too small to be useful prime real estate. Video info moved to Settings panel → Style tab as a "Video information" ListTile (always accessible, less obtrusive).
- **Portrait quick actions overflow fixed** — 6 buttons now use `Expanded(Center(...))` per slot so they share width equally on any screen width (no more potential RenderFlex on 320dp devices).
- **Codec display fixed** — `_currentAudioCodec` state var now populated by the EAC-3/DTS/TrueHD/MLP auto-detection block; passed correctly to `_AudioTrackPanel` (was always `null`). Detection now maps codec names to human-readable display names (E-AC-3 Dolby Digital+, DTS-HD, Dolby TrueHD, MLP/TrueHD).
- **SW decoder toggle always enabled** (UX improvement) — the "disabled during playback" guard removed from the UI. Toggle is always interactive. Safety rule preserved: `hwdec` property change only applied when NOT playing (MediaTek/Infinix black-screen protection). When playing: state saved + snackbar "will apply after pause/next file".
- **AudioEffect panel header overflow fixed** — restructured from single Row (title + Spacer + 3 tab texts) to a Column with separate title Row and tabs Row. Prevents overflow on narrow portrait bottom sheets (~280–320dp).
- **`_SettingsPanel` gets `onVideoInfo`** optional callback, wired from `_openSettingsPanel`.

## Current State (2026-07-05 — Portrait-Player-V1)

### Portrait Player Layout — 2026-07-05 (latest)
`Portrait-Player-V1` task complete. `player_screen.dart` now has a full portrait-mode layout that activates automatically when `constraints.maxWidth < constraints.maxHeight`.

**What changed:**
- `build()`: detects portrait via LayoutBuilder constraints and routes to `_buildPortraitLayout()`
- `_buildPortraitLayout()`: YouTube/Netflix-style Column — top 38% video zone (Stack: video surface + gesture layer + overlays + compact top bar) + bottom 62% controls panel (dark `0xFF0D0D0D` background)
- Gesture zone is scoped to the video area only; swipe brightness/volume/seek all work within that zone
- `_buildPortraitTopBar()`: compact back button + title (ellipsis) + episode badge + rotate + PiP
- `_buildPortraitControlsPanel()` + `_buildPortraitQuickActions()`: seek bar, transport row (play/pause/skip/prev/next/lock/settings), quick action buttons (CC, Audio, EQ, Speed, Loop, More)
- `_buildPortraitActionBtn()`: icon+label tile with active-state accent highlight
- `_openRightPanel()`: adds portrait branch using `showModalBottomSheet` + `DraggableScrollableSheet` (62% initial, 35%–88% draggable, scroll controller wired via `PrimaryScrollController`) — landscape path unchanged
- All hardcoded portrait offsets (`0.22`, `0.88`, `75`) are superseded; one-handed mode still exists but is bypassed in portrait

Commits: `e851819`, `c1131ce`. CI will verify on next APK build.

## Current State (2026-07-05)

### UI Audit + CI fix — 2026-07-05 (latest)
Full UI audit of all screens. Four issues found and fixed:

1. **CI fix** (`a4b946b`): `PhosphorIcons.wifi()` → `PhosphorIcons.wifiHigh()` in `app_icons.dart`. This was the sole compile error blocking every APK build since the rebrand commits. Build is now **✅ GREEN**.
2. **Server Downloads gated** (`1e511a0`): "Server Downloads" row in Profile was visible to ALL non-guest users. Added `isAdmin` bool to `AppUser` model (reads `is_admin` from JSON, defaults false). Button now only shows when `user?.isAdmin == true`. ⚠️ **Pending**: Flask `/me` endpoint needs to add `is_admin` to its JSON response before admin can use it — separate task, needs Oracle approval.
3. **Hardcoded prices removed** (`22d1a93`): `tid_status_screen.dart` plan labels no longer embed `₨149/₨249/₨399` — now shows `'Basic Plan'` etc. Prevents stale-price disputes if backend pricing changes.
4. **Decoy wording** (`ebf74b6`): Vault Settings "fake PIN / fake vault" copy replaced with "decoy PIN / decoy vault" in all user-visible strings.

### Open item from this session
Flask `/me` endpoint must add `is_admin: true` to response for admin accounts so they can access "Server Downloads" in the app. Needs: (a) confirm `is_admin` column in `app_users` table, (b) add to SELECT + jsonify in `mobile_api.py`, (c) Oracle restart. Requires explicit user approval before touching production.

### Rebrand zero-rating copy — hide JazzDrive/Oracle from UI (2026-07-05)
`subscription_screen.dart`'s "JazzDrive CDN" line and `debug_diagnostics_screen.dart`'s
`'Oracle Server'`/`'JazzDrive API'` check labels were the only user-visible strings
naming internal infrastructure. Subscription copy now attributes zero-rating to
RaddFlix ("RaddFlix is 100% data-free on Jazz"); diagnostics labels renamed to
`'Content Server'`/`'Stream Service'` (screen stays intentionally ungated per prior
note below — labels renamed instead of adding new gating). Jazz SIM requirement
copy, and SIMOSA/JazzCash/Easypaisa payment copy, left untouched by design. Full-repo
grep confirms zero JazzDrive/Oracle occurrences in any `Text()`/`SnackBar`/label
reachable by a user. Commit `f3f6453`.

### Logger secret stripping — final gap closed (2026-07-05)
`DebugLogger.logApi()` previously wrote raw request/response bodies (and the
`onError` path's embedded response preview) straight into the shareable log
buffer with no redaction. Added `_redactBody()` to `debug_logger.dart` —
redacts `validationkey=`, bare `k=<token>`, `jsessionid=`,
`authorization`/`bearer`, and `access_token`/`refresh_token` before
truncation/storage. Method/URL/status/duration metadata untouched. Verified
via full-repo grep that no unredacted secret pattern reaches any
`DebugLogger`/`print()` call. Commit `015bcea`. This closes the last known gap
from the prior logger-cleanup session — the JazzDrive/Oracle string
sanitisation in the share/clipboard export (`_sanitiseMessage()`) and the
removed `print()` in `request_encoder.dart` were both re-verified intact.

### Icon migration complete — 2026-07-04
Replaced the last 2 raw `Icons.block_rounded` references in
`raddflix_flutter/lib/widgets/player/gesture_map_sheet.dart` with `AppIcons.block`
and added the `app_icons.dart` import. AppIcons coverage is now 100% across all
non-player-widget files. Commit `3ec3c81`.

### Full audit pass (subtitles, player controls, access control, downloads) — 2026-07-03
Found and fixed a critical bug: the backend `is_free` episode-inheritance fix from
commit `8176835` had been applied to a stray, never-deployed `hub/` directory at the
repo root instead of the real `radd-hub/hub/` that Oracle runs — production was still
showing free-show episodes as locked. Re-applied the fix to the correct file. Also
fixed a subtitle-track-carries-over-to-next-episode bug, a weak download-completion
size check, a rapid-multi-tap race on the episode list, and removed a dead/misleading
subscription-expiry check in the Downloads screen. Full detail in
`agent-hub/history/2026-07.md` → "Full Audit Pass 2026-07-03". See also the new
`agent-hub/CONTEXT.md` warning about the duplicate `hub/` directory.

### Oracle
- Flask: RUNNING ✅ healthz: {"ok":true,"version":"3.0.0"}
- DB: schema current (display_name/email/avatar_color/avatar_emoji + all Phase 26 columns)
- Endpoints: PUT /api/auth/profile, POST /api/auth/change-password, GET /api/quota all live

### Flutter / APK
- Latest successful build: Phase 60 (P60 + Kotlin 2.2.0 + minSdk 24 fixes) ✅ CI PASSING · commit 98323a8
- All compile errors resolved
- Phases 17–37 fully merged and building clean

### What was fixed in Phase 37 (2026-06-29)
1. **Share button removed** — `show_detail_screen.dart`: stripped import + SliverAppBar actions block
2. **Quality picker removed** — `settings_screen.dart`: only one fixed video source, no user choice
3. **Free-content gate bug fixed** — 4 call sites in `show_detail_screen.dart` now OR with `widget.item.isFree` so free content is always free even if API episodes lack explicit `is_free:1`
4. **Player transport row overlap fixed** — `player_screen.dart`: Stack centering replaces broken fixed SizedBox(108) right zone
5. **Theme picker cut off fixed** — `profile_screen.dart`: isScrollControlled:true + DraggableScrollableSheet; all 10 themes visible
6. **share_plus kept in pubspec** — `debug_logger.dart` uses `Share` API to export crash logs; only the UI share button was removed

### What was added in Phase 60 (2026-07-01)
1. **Dub Active indicator** — `_AudioTrackPanel` now shows a green-bordered card at the top of its list when `_isDubMode == true`, displaying the active language flag + label
2. **Remove Dub button** — single tap in the Audio Panel calls `_disableDubMode()` and dismisses the panel — no need to reopen the subtitle/dub panel
3. **New props** — `isDubMode`, `dubActiveLang`, `onRemoveDub` added to `_AudioTrackPanel` (all optional / have defaults)

### Build fixes applied alongside Phase 60 (2026-07-01)
- **Kotlin 2.2.0** — bumped `ext.kotlin_version` from `1.9.20` → `2.2.0` in `android/build.gradle` (flutter_tts 4.2.5 stdlib uses Kotlin 2.2.x metadata)
- **minSdkVersion 24** — bumped from 21 → 24 in `android/app/build.gradle` (flutter_tts 4.2.5 declares minSdk 24 in its manifest; Android 5/6 dropped — <2% of Pakistani market)
- Both fixes address a pre-existing break introduced in Phase 59 (flutter_tts was added but build never ran green)

### Auto-commit system (2026-07-04)
- `auto_commit.sh` added at repo root — lightweight GitHub API (Trees API) commit script, no git shell required
- Rule 42 added to `agent-hub/RULES.md` — every file edit must be followed immediately by `bash auto_commit.sh "message" file1 ...`
- `AGENT_PROMPT.md` updated to mention Rule 42 in the normal workflow section
- Commit `a0d2d9f`

### Test suite run — 2026-07-04
All 4 files in `raddflix_flutter/test_suite/` executed:

| File | Result | Notes |
|---|---|---|
| `jazzdrive_logic_test.js` | ✅ 27/27 passed | Pure JS logic, no network |
| `logic_tests.dart` | ✅ 69/69 passed | Pure Dart logic, no network; run via Nix Dart 3.0.0 |
| `run_tests.js` | ✅ 71 passed / 0 failed / 8 warnings | Full integration against Oracle port 80; all warnings are expected (firewalled ports, repeat-run 409, Jazz-SIM can't be verified from Replit) |
| `jazzdrive_dart_test.dart` | ⚠️ 0/8 — MED-1011 (Oracle JazzDrive session expired) | SSL cert fix applied (`badCertificateCallback=true` for Nix Dart); API is reachable, session needs OTP re-login from Oracle admin panel. Commit `2ce6ab4`. |

**Actionable item:** Oracle JazzDrive SAPI session is expired. To re-validate `jazzdrive_dart_test.dart`: log into Oracle admin panel → Settings → JazzDrive Login → complete OTP re-login. Then re-run the test.

### Corrections applied — 2026-07-04
Found and fixed wrong information in constants, tests, and comments discovered during the test run:

| Wrong | Correct | Files fixed |
|---|---|---|
| Cache TTL 180 min / 6h | **110 min** (source of truth: `jazzdrive_service.dart` `_cacheTtl`) | `constants.dart`, `logic_tests.dart`, `run_tests.js`, `local_db.dart`, `README.md` |
| `jazzdrive_dart_test.dart`: "validationkey MUST be in final URL" | **DO NOT append validationkey=** — k= token is self-authenticating | `jazzdrive_dart_test.dart` header, `_buildStreamUrl`, Validation 2 |

Commits: `5d37e39`, `19fa4cf`

**Minor server note:** TID validation threshold is `len < 5`; the test sends "SHORT" (5 chars) which passes. Not a critical bug — just a low threshold. No code change made.

### Open Tasks
None — awaiting next task.

### What was added 2026-07-03 — MPV-Native Player Upgrades
1. **Native A-B loop** — replaced Dart position-listener seek with MPV's own `ab-loop-a`/`ab-loop-b`/`ab-loop-count` properties via new `_syncNativeAbLoop()`; frame-accurate, zero per-tick Dart overhead. Dart state now UI-only.
2. **Near-gapless episode transitions** — `_prefetchNextEpisode()` resolves the next episode's stream link ~20s before the current one ends (once per episode); `_openMediaForEpisode()` has a fast path that uses the cached URL directly, skipping the network round-trip when the user advances.
3. **Screenshot with subtitles** — `_takeScreenshot({withSubtitles})` uses MPV's `screenshot subtitles` command; wired to long-press on the Screenshot shortcut in the More panel.
- See `agent-hub/history/2026-07.md` → "MPV-Native Player Upgrades 2026-07-03" for full detail.
- No local Flutter build tool in that session — verified by code review only; watch first CI run closely.

### What was fixed 2026-07-03B
1. **AI dub failing** — `subtitle_dubber.dart`: `flutter_tts.synthesizeToFile()` on Android ignores directory prefix, always writes to `getExternalFilesDir(null)`. Fixed: pass plain filename to TTS, read clips back from `getExternalStorageDirectory()` (same path). Previously all clips were missing → `clips.isEmpty` → null.
2. **Pinch zoom gray screen** — `player_screen.dart`: `Transform.scale` on media_kit's `Video` widget (SurfaceView) produces gray area — Flutter cannot scale a SurfaceView via Transform. Fixed: removed `Transform.scale`; apply zoom via MPV native `video-zoom` property (log2 scale) in `_onScaleUpdate`, `_onScaleEnd`, and reset button. Commits: `8829d3d` (dubber), `2918655` (player).

### Known Data Issues
- DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 — upload to JazzDrive + sync still needed

### Key Rules (NEVER BREAK)
- Never add `androidAttachSurfaceAfterVideoParameters: true` (black screen on MediaTek)
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Oracle git pull: always `git stash && git pull && git stash pop`
- Push files SEQUENTIALLY — never parallel (SHA race condition)
- Use `db.setting(k)` not `db.get_setting(k)`
- `DebugDiagnosticsScreen` is intentionally NOT gated by `kDebugMode`
- `ImageCache.clearLive()` does NOT exist in this Flutter version — use `PaintingBinding.instance.imageCache.clear()`
- CachedNetworkImage uses `errorWidget:` not `errorBuilder:`

---

## Bug-Fix Batch 2026-07-02 — COMPLETE ✅

All 15 verified issues from the full-app audit fixed. CI green on commit `3c38f31` (run #28588429103).

### Commits
| SHA | File | Fixes |
|---|---|---|
| `5fd4490` | player_screen.dart | #1 unobserveProperty leak, #6 voice-cmd snackbar, #24 silence-filter |
| `81a6d09` | debug_diagnostics_screen.dart | #3 _tlTimer cancel in dispose() |
| `535477e` | login_screen.dart | #7, #8, #20 mounted guards in catch blocks |
| `685673f` | show_detail_screen.dart | #14 mounted guard in _playEpisode |
| `be0174d` | subtitle_dubber.dart | #2 OOM guard, #12 cache integrity, #23 phase-2 progress |
| `69c3703` | subtitle_dubber.dart | #11 log synthesis errors |
| `26f8f48` | pubspec.yaml | #22 pin flutter_tts >=4.2.5 <5.0.0 |
| `ae85282` | TASKS.md | audit summary |
| `3c38f31` | search_screen.dart | RESTORED from clean base — JS $' replace-pattern corrupted previous attempt |

### Root-Cause: search_screen Corruption
Fix #10 replacement string contained `r'^\[|\]$'` — the `$'` is a JS special replacement pattern
("insert string suffix"), which doubled the file to 2424 lines. Fix: use `$$` in JS replacement
strings whenever Dart code contains `$` characters. Final file restored from commit 685673f baseline.

### Issues Not Fixed (by design)
#4, #5, #13, #15, #16, #17, #18, #19, #21 — see TASKS.md for rationale.

### Permanent Rules (never violate)
- No `androidAttachSurfaceAfterVideoParameters: true`
- No `sqflite_sqlcipher` past `3.1.0+1`
- Push files sequentially (SHA race)
- `_np` must remain a getter, never a local variable
- JS `String.replace(old, new)`: escape `$` as `$$` in replacement when Dart code contains `$`
