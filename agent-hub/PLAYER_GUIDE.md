# RaddFlix Video Player — Agent Reference Guide

  _Last updated: 2026-06-19 | Must-read for any agent touching player code_

  ---

  ## TL;DR for Agents

  | Question | Answer |
  |----------|--------|
  | Which file do I edit? | `raddflix_flutter/lib/screens/player_screen.dart` (v3 — the LIVE player) |
  | Where is the old player? | `raddflix_flutter/lib/screens/player_screen_v1_backup.dart` (7,556 lines — READ ONLY for ideas) |
  | Can I use `vf=` property? | **NEVER.** Destroys GL surface on MediaTek. 15-day black screen bug. |
  | Can I use `hwdec` mid-play? | **NEVER.** Only in initial player config before open(). |
  | Can I use video filters? | Only `ColorFiltered` Flutter widget. No MPV `vf=` ever. |
  | Can I use audio filters? | Yes — `af=equalizer` is safe (audio filter, not video). |

  ---

  ## The Two Players

  ### 🔴 OLD PLAYER — `player_screen_v1_backup.dart` (DO NOT EDIT)
  - **7,556 lines** — the original RaddFlix player
  - **Status:** RETIRED due to 15-day black screen bug on MediaTek devices
  - **Root cause of bug:** `_applyVideoFilters()` ran concurrently with `_player.open()`. The `setProperty('vf', ...)` call arrived while the HW decoder was active → GL surface destroyed → black screen
  - **Why keep it?** It is a goldmine of UI ideas and feature implementations. Always check here before building any new feature — the logic may already exist.
  - **Key features inside the old player (mine these for ideas):**
    - Ambilight glow effect (color sampling from frame edges)
    - Picture-in-Picture (PiP) via platform channel
    - Subtitle picker (file browser + online search stub)
    - Bookmarks (add/delete/jump, stored via SharedPreferences)
    - A-B repeat with visual markers on seek bar
    - Sleep timer dialog with presets (15/30/45/60/90 min + custom)
    - Skip intro / end credits detection stub
    - Voice command hooks (placeholder)
    - Cast to TV placeholder
    - Screenshot via platform channel
    - Speed presets dialog (0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×)
    - Frame-step (advance 1 frame)
    - Long-press to restart from beginning
    - Media button multi-press handler
    - Cinematic mode / immersive mode toggles
    - Watch position save & resume (stored in LocalDb)
    - Binge guard (inactivity prompt after N episodes)
    - 43 DebugLogger call sites for crash diagnosis
  - **How to copy from old to new:** Read the old file for the logic, then rewrite it in new player following the MediaTek safety rules. NEVER copy-paste vf= calls.

  ---

  ### 🟢 NEW PLAYER — `player_screen.dart` (LIVE — EDIT THIS)
  - **3,376 lines** — MX Player-style UI (v3, as of 2026-06-19)
  - **Status:** Active, MediaTek-safe, all 29 feature checks pass
  - **Architecture:**

  ```
  PlayerScreen (StatefulWidget)
  ├── _initPlayer()            ← sets up media_kit player with safe config
  ├── _buildControlsOverlay()  ← entire HUD (top bar, bottom bar, seek, icons)
  │   ├── _buildTopBar()       ← back, title, battery/time, settings
  │   ├── _buildBottomBar()    ← play/pause, skip ±10, time label, speed, next ep
  │   ├── _buildVerticalSeekBar()  ← left-edge vertical seek bar (MX style)
  │   ├── _buildVolumeTriangles()  ← right-edge visual volume indicator
  │   └── _buildRightIconStrip()   ← right-side icon column (smart enhance, audio, sub, zoom, eq, shortcuts)
  ├── _buildSmartEnhanceAnimation()  ← 3-phase overlay: dots→scan line→title text
  ├── _buildVolumeOverlay()    ← top-center orange bar on volume gesture
  ├── _buildBrightnessOverlay()← bottom-center blue bar on brightness gesture
  └── 6 Right Panels (opened via showGeneralDialog + SlideTransition from right):
      ├── _AudioTrackPanel     ← track selector + AV sync slider
      ├── _SubtitlePanel       ← tabs: Open/Text/Settings/Sync/Layout/Customization
      ├── _VideoZoomPanel      ← fit modes: auto/full/original/stretch/crop
      ├── _AudioEffectPanel    ← 6 EQ presets + 5-band custom EQ sliders
      ├── _QuickShortcutsPanel ← 2×4 icon grid: rotate/mute/EQ/sleep/speed/loop/A-B/lock + Smart Enhance toggle
      └── _SettingsPanel       ← tabs: Style/Screen/Controls/Navigation
  ```

  ---

  ## MediaTek Safety Rules (ABSOLUTE — never break these)

  ```dart
  // ✅ SAFE — always do this
  _videoOpened = true;           // Set BEFORE every _player.open() call
  await _player.open(media);     // open() after setting _videoOpened

  // ✅ SAFE — initial config only
  androidAttachSurfaceAfterVideoParameters: false  // in player init config

  // ✅ SAFE — audio filter
  _np.setProperty('af', 'equalizer=0:0:0:5:0:0:0:3:0:0');

  // ✅ SAFE — subtitle / audio sync
  _np.setProperty('sub-delay', delaySeconds.toString());
  _np.setProperty('audio-delay', delaySeconds.toString());

  // ✅ SAFE — speed (with framedrop guard)
  _np.setProperty('speed', speed.toString());
  // Always call: _np.setProperty('framedrop', 'vo') before setSpeed

  // ✅ SAFE — visual enhancement (Flutter widget, NOT MPV)
  ColorFiltered(
    colorFilter: ColorFilter.matrix([...20 values...]),
    child: videoWidget,
  )

  // ❌ FORBIDDEN
  _np.setProperty('vf', anything);        // NEVER — black screen on MediaTek
  _np.setProperty('hwdec', anything);     // NEVER mid-play — only in init config
  _player.open() without _videoOpened=true; // NEVER
  ```

  ---

  ## NativePlayer Getter (CRITICAL naming rule)

  ```dart
  // The getter — already in the file
  NativePlayer get _np => _player.platform as NativePlayer;

  // NEVER name a local variable _np — it shadows the getter silently
  // ❌ Wrong:
  final _np = something;   // shadows the getter!
  // ✅ Correct:
  final np = something;    // or any other name
  ```

  ---

  ## Constructor Parameters (do not add/remove without updating app.dart route)

  ```dart
  const PlayerScreen({
    required this.fileId,         // String — Jazz/catalog file ID
    required this.title,          // String — display title
    this.localPath,               // String? — path to downloaded file (null = stream)
    this.subtitlePath,            // String? — external subtitle file path
    this.episodes,                // List<Episode>? — for series episode navigation
    this.episodeIndex,            // int — current episode index (default 0)
    this.contentType,             // String? — 'movie'/'series'/'local' etc.
  });
  ```

  ---

  ## GitHub Push Workflow (for agents using code_execution)

  ```javascript
  // Step 1: Always fetch fresh SHA before any push
  const res = await fetch(`https://api.github.com/repos/raddclub/raddflix-app/contents/PATH`, { headers });
  const data = await res.json();
  const currentSha = data.sha;
  const currentContent = Buffer.from(data.content, 'base64').toString('utf8');

  // Step 2: Modify content string

  // Step 3: Push with fresh SHA
  const pushRes = await fetch(`https://api.github.com/repos/raddclub/raddflix-app/contents/PATH`, {
    method: 'PUT',
    headers: { Authorization: `token TOKEN`, 'Content-Type': 'application/json', 'User-Agent': 'RaddFlix-Agent' },
    body: JSON.stringify({
      message: 'your commit message',
      content: Buffer.from(newContent, 'utf8').toString('base64'),
      sha: currentSha,  // ← fresh SHA — stale SHA causes 409 conflict
    }),
  });
  ```

  ---

  ## Building the APK

  ### Debug APK (fast, for testing)
  ```bash
  # On Oracle server or CI
  ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252
  cd raddflix_app/raddflix_flutter
  flutter pub get
  flutter build apk --debug
  # Output: build/app/outputs/flutter-apk/app-debug.apk
  ```

  ### Release APK (signed, for distribution)
  ```bash
  flutter build apk --release --obfuscate --split-debug-info=build/symbols
  # Output: build/app/outputs/flutter-apk/app-release.apk
  # ⚠️ Requires signing key in android/key.properties and android/app/upload-keystore.jks
  # ⚠️ Requires JAVA_HOME set (Android build toolchain)
  ```

  ### What to check after build
  1. File size: debug ~80MB, release ~25-35MB (if obfuscated)
  2. Test on physical device: `adb install -r app-release.apk`
  3. MediaTek device test: open a video, watch for black screen on first load

  ---

  ## Monitoring the APK

  ### DebugLogger (built in — `debug_logger.dart`)
  - Stores up to 5,000 log entries in memory + 8MB rotating file
  - Session ID on every entry for multi-session correlation
  - Key log methods: `logTap`, `logNav`, `logLifecycle`, `logFeature`, `logCrash`, `getFiltered`
  - **Log file location on device:** accessible via `DebugLogger.getLogFilePath()`
  - **To retrieve logs from device:**
    ```bash
    adb shell run-as com.raddflix.app cat /data/data/com.raddflix.app/files/raddflix_debug.log
    # Or pull to PC:
    adb pull /data/data/com.raddflix.app/files/raddflix_debug.log ./debug.log
    ```

  ### Logcat (Android real-time)
  ```bash
  adb logcat -s flutter                     # Flutter logs only
  adb logcat -s flutter | grep -i error     # Errors only
  adb logcat *:E                            # All Android errors
  adb logcat | grep -i "RaddFlix\|player\|media_kit\|mpv"  # Player-specific
  ```

  ### Oracle Server (SSH)
  ```bash
  ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252
  # Server hosts: Jazz proxy endpoint, any APK build artifacts, CI scripts
  ```

  ### Crash diagnosis checklist
  When the player goes black screen or crashes:
  1. `adb logcat -s flutter` — look for "GL surface destroyed", "hwdec", "vf="
  2. Check DebugLogger for last 10 entries before crash
  3. Verify `_videoOpened = true` was set before `_player.open()`
  4. Verify no `vf=` call anywhere in the code path
  5. Check if crash happens on MediaTek device but not Snapdragon (= vf= or hwdec issue)

  ---

  ## Key Files Reference

  | File | Purpose |
  |------|---------|
  | `raddflix_flutter/lib/screens/player_screen.dart` | 🟢 LIVE player — edit this |
  | `raddflix_flutter/lib/screens/player_screen_v1_backup.dart` | 🔴 OLD player — read for ideas |
  | `raddflix_flutter/lib/core/services/jazzdrive_service.dart` | Jazz zero-rated stream URL resolver |
  | `raddflix_flutter/lib/core/db/local_db.dart` | LocalDb.getShareInfo, decodeShareUrl, watch position |
  | `raddflix_flutter/lib/core/api/catalog_api.dart` | CatalogApi.getShareUrl |
  | `raddflix_flutter/lib/app.dart` | Route handler for AppRoutes.player |
  | `raddflix_flutter/lib/core/services/debug_logger.dart` | DebugLogger — crash/event logging |
  | `agent-hub/TASKS.md` | Task board — update every session |
  | `agent-hub/history/TASK_LOG.md` | Session history — append every session |
  | `agent-hub/PLAYER_GUIDE.md` | This file |

  ---

  ## Ideas Queue (from old player — not yet in new player)

  These features exist in the old player and should be ported to the new player when needed:

  | Feature | Old player reference | Notes |
  |---------|---------------------|-------|
  | Watch position save/resume | `_saveWatchPosition()`, `_loadWatchPosition()` | Uses LocalDb — safe to port |
  | Bookmarks | `_bookmarks`, `_addBookmark()`, `_deleteBookmark()` | SharedPreferences — safe |
  | Skip intro detection | `_loadSkipSegments()` | Stub — needs backend |
  | Ambilight glow | `_initAmbilight()` | Complex — Flutter widget border glow |
  | Cast to TV | placeholder in old player | Needs flutter_cast_video package |
  | Screenshot | platform channel | Android permission required |
  | Frame step | `_frameStep()` | `_np.setProperty('frame-step', '')` |
  | Long-press restart | GestureDetector onLongPress | Simple to add |
  | Binge guard | `_initBingeGuard()` | Timer + dialog after N eps |
  | Picture-in-Picture | `_initPipChannel()` | Platform channel |
  | Voice commands | placeholder | Needs speech_to_text package |
  | Share timestamp | `_shareTimestamp()` | URL with position param |

  ---

  _This file is maintained by the coding agent. Update it whenever the player architecture changes significantly._
  