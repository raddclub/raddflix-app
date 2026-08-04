# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-08-04 — Panel active-state & animation fixes shipped)

**Phase A (Full UI Theme Engine) — DONE (SHA `e4899225`, CI green):**
- PHASE-A1: `_accentColor` getter wired to `PlayerPrefs.accentColor` ✅
- PHASE-A2: seek bar wired to `PlayerPrefs.seekBarStyle` ✅
- PHASE-A-ENTRY: `QuickSettingsPanel` accessible via 'style' sidebar shortcut ✅

**Current priority: BG-play deep fix (4 tasks across 3 phases)**

Research session (2026-08-03) identified 4 concrete bugs in the background-play stack via code
audit + web research. Plan is now in TASKS.md under "BG-play Deep Fix". Tasks are ready to
implement — waiting for approval to start coding.

Root cause summary (see TASKS.md for full detail):
1. media_kit internally pauses MPV when surface is destroyed; `_player.play()` is never called
   to recover — audio dies immediately on background.
2. Minimized-player path (playback_service.dart) never sets `vid=no` before starting the
   foreground service — same surface-stall problem on a separate code path.
3. `notifReceiver` in MainActivity is unregistered in `onStop()`, so notification play/pause/seek
   buttons are dead while app is in background.
4. `artworkUrl` is passed from Flutter but silently dropped in `startPlaybackService()` — no
   poster art in the lock-screen notification (cosmetic).

**Next after BG-play fix:** Resume FEATURES_ROADMAP.md Phase A remaining (A3 button/icon
styles, A4 controls background style — already in PlayerPrefs + QuickSettingsPanel, just need
wiring to player rendering). Then Phase B (drag-drop layout editor).

---

## Previous State (2026-08-01 — ALL Vibe Phases 0–5 DONE)

Phase 0 (critical bug fixes) and the full Vibe Modes feature (Phases 1–5, all 20 tasks) are
complete. The entire `VIBE_BUGS_PLAN.md` is shipped.

VIBE-5D is spec-complete: the live voice parser has explicit direct mappings for `slowed`,
`nightcore`, `lofi`, `reverb`, and `no vibe`, with regression coverage for the five phrases
and case/whitespace normalization. The remaining aliases are preserved separately.

**Next session: pick up the FEATURES_ROADMAP.md — Phase A (Full UI Theme Engine) is the
highest-priority unstarted work.** Start with A1 (Accent Color System) → A2 (Seek Bar Styles)
→ A5 (Saved Themes / "Sakura"). See `agent-hub/FEATURES_ROADMAP.md` for full spec.

---

### Phase 0 — Critical Bug Fixes — ALL DONE (CI green)

| Task | Final Commit | Notes |
|---|---|---|
| SUB-GRAY-SCREEN | `170a32d3` | `subtitle_overlay.dart`: removed inner `Positioned.fill`, guard uses `.trim()` |
| PLAYER-PERF | `15edbb83` | ValueNotifier + RepaintBoundary + debounce + `ref.select()` scope |
| THUMB-PERF | `5e1ce080` | Kotlin MMR fast path + batch→2 + shimmer + disk cache eviction |
| DUAL-SUB-TRIM | `52170dd2` | `dual_subtitle_overlay.dart`: `.isEmpty` → `.trim().isEmpty` |
| DUAL-SUB-STACK | `204c7c3a` | `DualSubtitleOverlay` wired into both landscape+portrait stacks |

---

### Phase 1 — Vibe Modes Foundation — ALL DONE

| Task | Status | Commit |
|---|---|---|
| VIBE-1A — af-pipeline slot for vibe | ✅ DONE | `0e338263` |
| VIBE-1B — PlaybackVibeMode enum + prefs | ✅ DONE | `6064bf82` |
| VIBE-1C — `_applyVibeMode()` + `_applyVibeBassBoost()` | ✅ DONE | `4c61c79a` |
| VIBE-1D — `_adjustSubSyncForVibe()` sub-speed compensation | ✅ DONE | `4c61c79a` |
| VIBE-1E — reset vibe on episode nav | ✅ DONE | `7ea55258` |

---

### Phase 2 — Core 4 Vibe Modes — ALL DONE

| Task | Status | Notes |
|---|---|---|
| VIBE-2A — Slowed (0.82×, pitch natural) | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |
| VIBE-2B — Slowed + Reverb | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |
| VIBE-2C — NightCore (1.25×, pitch up) | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |
| VIBE-2D — Lofi (0.93×, lowpass + subtle reverb) | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |

---

### Phase 3 — Extended Vibe Modes — ALL DONE

| Task | Status | Notes |
|---|---|---|
| VIBE-3A — 8D Audio (apulsator panning) | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |
| VIBE-3B — Phonk (0.90×, heavy bass boost) | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |
| VIBE-3C — Club Mix (extra-stereo + slight speed) | ✅ DONE | in `_applyVibeMode()` (`4c61c79a`) |

---

### Phase 4 — Vibe Modes UI — ALL DONE

| Task | Status | File |
|---|---|---|
| VIBE-4A — "Vibe" tab in Audio Effect panel (4-col GridView) | ✅ DONE | `_ps_panels_audio.dart` |
| VIBE-4B — `_VibeModeCard` widget (icon + name + active glow border) | ✅ DONE | `_ps_panels_audio.dart` |
| VIBE-4C — Quick bar integration (sidebar item shows active mode name) | ✅ DONE | `_ps_ui_mixin.dart` |
| VIBE-4D — Audio-only backdrop Vibe chip (tap to cycle, shows name) | ✅ DONE | `audio_mode_backdrop.dart` |

---

### Phase 5 — Vibe Modes Polish — ALL DONE

| Task | Status | File |
|---|---|---|
| VIBE-5A — "Remember Vibe" toggle in Settings (default OFF) | ✅ DONE | `settings_screen.dart` |
| VIBE-5B — Vibe mode HUD badge (purple pill when mode ≠ none) | ✅ DONE | `_ps_ui_mixin.dart` |
| VIBE-5C — Filter stacking safety (skip reverb+extrastereo conflicts) | ✅ DONE | `_ps_audiolab_mixin.dart` |
| VIBE-5D — Voice commands (direct phrase mappings + `vibeNext`/`vibeOff`) | ✅ DONE | `voice_commands_service.dart` + `_ps_ui_mixin.dart` + parser tests |

---

### Blocked tasks (no agent can fix without external input)

- **SEC-01:** Plain HTTP API. Needs domain + TLS cert provisioned on Oracle.
- **SEC-04:** Vault PIN SHA-256 static salt. Needs PBKDF2 migration decision from owner.
- **SEC-05:** APK tamper-detection placeholder. Needs `keytool` run against release keystore.

---

### Previous session commits (for full history see TASK_LOG.md)

| SHA | Description |
|---|---|
| `52170dd2` | DUAL-SUB-TRIM: `.isEmpty` → `.trim().isEmpty` in DualSubtitleOverlay |
| `204c7c3a` | DUAL-SUB: wire DualSubtitleOverlay into both player stacks |
| `4c61c79a` | VIBE-1C/1D + Phases 2–3: all 7 modes in `_applyVibeMode()`, bass boost, sub-sync |
| `7ea55258` | VIBE-1E: reset vibe mode on episode navigation |
| `0e338263` | VIBE-1A: af-pipeline slot |
| `6064bf82` | VIBE-1B: PlaybackVibeMode enum + prefs |
| `15edbb83` | Phase 0B PLAYER-PERF: ref.select() on subtitle Consumer |
| `5e1ce080` | Phase 0C THUMB-PERF: disk cache eviction |
| `170a32d3` | Phase 0A SUB-GRAY-SCREEN: SubtitleOverlay fix |
| `d5b93d29` | AUDIO-DISC-BUGS-2 (CI ✅) |
| `f59bebf`  | AUDIO-DISC-BUGS (CI ✅) |

---

> Full session history: `agent-hub/history/TASK_LOG.md`
