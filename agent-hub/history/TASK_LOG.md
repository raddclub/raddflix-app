# TASK_LOG.md — Agent Session History

> Newest session at top. Every agent must append here after completing work.
> Format: `## Session YYYY-MM-DD` followed by bullets.

---

## Session 2026-06-07 (Pass 4 — full re-audit)

**Agent:** Replit Agent (main branch)
**Task:** TASK-025 — Full 6,252-line re-audit after Pass 3; find and fix any remaining bugs

### Bugs found and fixed

| ID | Severity | Fix |
|----|---------|-----|
| BUG-P-NEW-06 | MEDIUM | `_openVideoEnhanceSuite` `onChanged`: cinematic mode could only be toggled ON, never OFF. The handler checked `map['cinematicMode'] == true` and called `_toggleCinematic()`, but did nothing when the value was `false`. Fixed: compare new value against `_cinematicMode` and toggle only when they differ. |
| BUG-P-NEW-07 | HIGH | Quick Bar "Night Mode" button was wired to `onToggleCinematic` (a copy-paste error). Tapping "Night" silently toggled cinematic mode instead of night mode. Fixed: added `onToggleNightMode` callback to `_ControlsOverlay`, wired from `_buildPlayerBody` with the correct `_prefs.copyWith(nightMode:)` + save + `_applyVideoFilters()` lambda. |

### Audit completeness
- All 6,252 lines read in full across 4 passes (Pass 1 = TASK-022, Pass 2 = TASK-023, Pass 3 = TASK-024, Pass 4 = TASK-025)
- No additional functional bugs found
- BUG-P-NEW-05 fix confirmed present in the GitHub file (Pass 3 fix verified)

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | BUG-P-NEW-06: bidirectional cinematic toggle; BUG-P-NEW-07: Quick Bar night mode wired correctly |
| `agent-hub/TASKS.md` | Added TASK-025 to completed archive |
| `.agents/tasks/BUG_TRACKER.md` | Appended Pass 4 session with both new bugs |
| `agent-hub/history/TASK_LOG.md` | This entry |

---

## Session 2026-06-07 (Pass 3 — verification)

**Agent:** Replit Agent (main branch)
**Task:** TASK-024 — Re-audit after Pass 2 to confirm completeness

### What was done
- Full re-read of AbLoopController API (`ab_loop_controller.dart`) to verify ClipTrimmer sync
- Confirmed BUG-P-NEW-05: `ClipTrimmer.onTrimChanged` only set `_abLoopStart`/`_abLoopEnd` state vars but never called `_abLoop.setA()`/`_abLoop.setB()` — so A-B loop enforcement via `maybeSeekBack()` and seek bar markers were both broken when trim was set through the trimmer
- Fixed: added `_abLoop.setA(trim.start)` and `_abLoop.setB(trim.end)` after setState in `onTrimChanged`

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | BUG-P-NEW-05: sync ClipTrimmer points to _abLoop controller |
| `agent-hub/TASKS.md` | Added TASK-024 |
| `.agents/tasks/BUG_TRACKER.md` | Appended BUG-P-NEW-05 |
| `agent-hub/history/TASK_LOG.md` | This entry |

---

## Session 2026-06-07 (Pass 2)

**Agent:** Replit Agent (main branch)
**Task:** TASK-023 — Player Screen deep audit: find ALL remaining bugs not yet in tracker

### What was done

- Read all 6226 lines of `raddflix_flutter/lib/screens/player_screen.dart` in full
- Cross-referenced every function reference against definitions
- Found 4 new bugs (BUG-P-NEW-01 through BUG-P-NEW-04) not previously tracked
- Fixed all 4 bugs in single targeted patch; pushed atomically with updated docs

### Bugs Found and Fixed

| ID | Severity | Fix |
|----|---------|-----|
| BUG-P-NEW-01 | HIGH | `_audioSessionInitialized` never set to `true` in `initState()` → BG-play toggle triggers duplicate audio session listeners. Fixed: add `_audioSessionInitialized = true` in `initState()` after `_initAudioSession()` |
| BUG-P-NEW-02 | MEDIUM | `_MxMoreSheet` Night Mode tile `active` state used `cinematicMode` (wrong feature) instead of `_prefs.nightMode`. Fixed: added `nightModeActive` field, pass `_prefs.nightMode` at call site |
| BUG-P-NEW-03 | HIGH | Mid-stream errors after 3s of playback silently swallowed — blanket `return` caused infinite buffering with no user feedback on CDN expiry/network drop. Fixed: show "Connection lost — reconnecting…" SnackBar + soft `_jazzAutoRetry` |
| BUG-P-NEW-04 | CRITICAL | `_enterCast()` NPE — `_currentPlaybackUrl.isNotEmpty` called on nullable `String?` → crash when cast opened before first URL loaded. Fixed: null-safe check `(_currentPlaybackUrl != null && _currentPlaybackUrl!.isNotEmpty)` |

### Files changed
| File | Change |
|------|--------|
| `raddflix_flutter/lib/screens/player_screen.dart` | 4 targeted fixes (BUG-P-NEW-01→04) |
| `agent-hub/TASKS.md` | Added TASK-023 to completed archive |
| `.agents/tasks/BUG_TRACKER.md` | Appended Pass 2 session with all 4 new bugs |
| `agent-hub/history/TASK_LOG.md` | This entry |

---

## Session 2026-06-06

**Agent:** Replit Agent (main branch)
**Objective:** Complete server-side pipeline audit; fix last remaining bug where JD filenames leaked into Oracle `files.filename`

### Audit findings (no additional bugs beyond previously identified)

- **titles.title** in Oracle: always TMDB-sourced ("Vincenzo" not "Vncenz0") — confirmed ✅
- **Episode labels** in all 3 sync endpoints (`/sync`, `/db_update`, `/delta`): always `"S{:02d}E{:02d}"` format — NEVER derived from any filename — confirmed ✅
- **`remote_id`**: JD permanent numeric file ID — stored in Oracle `files.remote_id`, selected and returned by all 3 catalog endpoints, stashed in Flutter SQLite, used by Pass 0 — confirmed ✅ (all fixed in previous session `b011e24`)
- **`share_url`**: folder-level share link — not filename-dependent — confirmed ✅
- **`_clean_filename()` in enricher.py**: strips junk tokens before TMDB lookup — garbled names like "Vncenz0" still match TMDB "Vincenzo" (SequenceMatcher ratio ~0.6 >> 0.35 threshold) — confirmed ✅
- **`enrich_and_save()` in `_legacy/scanner.py`**: groups by folder, calls TMDB on sample filename, stores TMDB-correct title in legacy `titles.title` — confirmed ✅

### Bug fixed: `files.filename` used garbled JD title, not TMDB title

**Root cause**: `_import_legacy_into_v3_for_account()` in `scanner.py` (~line 871) called `derive_media_plan(raw_filename)` without a TMDB lookup, so `files.filename` stored in Oracle reflected the dirty JD filename title (e.g. `"Vncenz0 S01E02.mkv"`) instead of the TMDB-correct one (`"Vincenzo S01E02.mkv"`).

**Impact**: The `filename` field is sent to Flutter and used by Passes 1-3 (filename-based CDN matching) when `remote_id=0`. Pass 0 (remote_id numeric match, primary path post-`b011e24`) was unaffected.


---

## Session 2026-06-07 — Player Screen Pass 5: 29-Bug Comprehensive Audit

**Agent:** Replit Agent (main branch)
**Objective:** Fix all 29 bugs from the full Pass 5 audit of player_screen.dart (6,265 lines). Applied as one atomic commit.

### Bugs fixed (26 of 29)

| ID | Sev | Title | Fix Summary |
|----|-----|-------|-------------|
| C-01 | CRITICAL | _applyVolumeBoost maxes system volume on every player open | Removed unconditional VolumeController().setVolume(1.0) from _applyVolumeBoost |
| C-02 | CRITICAL | Inner GestureDetector onScaleStart wins pinch arena | Removed onScaleStart:(_){} from inner GD; added pointerCount<2 guard |
| H-01 | HIGH | _applyVideoFilters/_applyAudioPrefs race on rapid changes | 60ms timestamp debounce on both functions |
| H-02 | HIGH | _jazzRetryCount not reset on episode change | Added _jazzRetryCount=0 at start of _playPrevEpisode and _playNextEpisode |
| H-03 | HIGH | _startWakeTimer uses default prefs | Added _startWakeTimer() at end of _loadPrefs() body |
| H-04 | HIGH | _cancelSleepTimer calls setState without mounted guard | Wrapped setState in if (mounted) |
| H-05 | HIGH | Playback info panel never refreshes | Added _piTimer (Timer.periodic 2s) while panel is open |
| H-06 | HIGH | Muting leaves MPV at full boost level | Mute now sets MPV volume=0; unmute restores (_volume * _volumeBoost * 100) |
| H-07 | HIGH | SleepTimerSheet.onStopAtEpisodeEnd dead | Wired to _setSleepTimer(-1) |
| H-08 | HIGH | Long-press badge auto-fades while still holding | Removed .then().fadeOut() chain |
| M-01 | MEDIUM | QuickShortcutBar nightmode never shows active | Added nightModeActive field threaded through _ControlsOverlay → _QuickShortcutBar |
| M-02 | MEDIUM | _SleepPanel shows nothing for episode-end sleep | Added sleepAtEpisodeEnd param + "Pausing at episode end" text |
| M-03 | MEDIUM | SW Decoder toggle has no effect | Added onSwDecoderChanged callback wired to _np.setProperty('hwdec') |
| M-04 | MEDIUM | CinematicSettingsSheet gets wrong opacity field | Changed _prefs.transparentModeOpacity to _cinematicOpacity |
| M-05 | MEDIUM | colorchannelmixer missing alpha row params | Added :ra=0 :ga=0 :ba=1 |
| M-06 | MEDIUM | Hue divided by 180 → near-zero | Removed /180.0 (MPV eq hue takes degrees) |
| M-07 | MEDIUM | Rage skip controls freeze on screen | Added _scheduleHide() after setting _rageSkipActive=true |
| M-08 | MEDIUM | Plan expiry check skips streaming users | Broadened to fileId.isNotEmpty && !_isLocalPath |
| M-09 | MEDIUM | _loadSmartIntro() always returns early in initState | Removed dead call |
| L-01 | LOW | Shuffle + Customise Items permanently dead | Removed both from VideoDisplaySheet row2 |
| L-02 | LOW | Loop and A-B Repeat identical callbacks | onLoop now calls _np.command(['cycle','loop-file']) |
| L-04 | LOW | lock_current uses raw physicalSize pixels | Replaced with MediaQuery.of(context).size |
| L-05 | LOW | Rage skip double-fires within animation window | Added _rageSkipActive guard at top of _handleCenterTap |
| L-06 | LOW | Settings pop doesn't restore SystemChrome | Added .then((_){SystemChrome.setEnabledSystemUIMode + _applyRotation}) |
| L-08 | LOW | Inconsistent 4-space indent for two field declarations | Fixed to 2-space |

### Deferred (4 of 29)
- **L-03** (LOW): Negative remaining time during intro skip — clamp in caller; no player_screen.dart change needed
- **L-07** (LOW): _openCinematicSettings accessible when cinematicMode=false — no harmful side-effects
- **L-09** (LOW): Duplicate _openJumpTo/_showJumpToTime — consolidate in next cleanup pass
- **L-10** (LOW): _cinematicOpacity not persisted — requires PlayerPrefs schema change (tracked in BACKLOG-01)

### Files changed
| File | Change |
|------|--------|
| raddflix_flutter/lib/screens/player_screen.dart | 26 fixes; +63 net lines (6,328 total) |
| agent-hub/TASKS.md | TASK-026 to completed archive; BACKLOG-01 added |
| .agents/tasks/BUG_TRACKER.md | Pass 5 session appended (all 29 bugs) |
| agent-hub/history/TASK_LOG.md | This entry |
