# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-08-04 — Phase J PiP & Cast panel complete)

**Phase J (PiP Overlay & Cast Panel) — ALL 7 DONE:**
- PIP-J1: `_baseSize` captured at `onScaleStart`; scale updates linear, no exponential compounding ✅
- PIP-J2: `MediaQuery.padding` applied in both pan clamp and snap — window stays above status/nav bar ✅
- PIP-J3: 3 s auto-hide timer; resets on each tap (`_startHideTimer`) ✅
- PIP-J4: Close/expand/play buttons wrapped in `GestureDetector(behavior: HitTestBehavior.opaque)` — tapping a button no longer also toggles controls ✅
- CAST-J5: `widget.scanning` bool drives "Searching…" vs "No devices found" — never shown simultaneously ✅
- CAST-J6: Connected device filtered from available-devices list before `ListView.builder` renders it ✅
- CAST-J7: `device.signalStrength.clamp(0, 4)` — signal bars now correct for any out-of-range value ✅ (SHA `4a9efee`, CI pending→green)

**Next priority: Phase C — Audio Player & Panel Fixes**
Start at AUDIO-C1 (vibe entry from audio disc when mode=None) → AUDIO-C2/C3 (missing `didUpdateWidget`) → AUDIO-C4 (SW decoder gate) → AUDIO-C5 (title parser) → AUDIO-C6 (wire dead audio-sync callbacks).

**BG-play Deep Fix — ALL DONE (SHA `27a07e20`, CI green):**
- BG-FIX-1: `_player.play()` after `vid=no` on fullscreen→background path ✅
- BG-FIX-2: `vid=no` + `_player.play()` on minimized player→background path ✅
- BG-FIX-3: `notifReceiver` moved to `onResume()`/`onPause()` so controls work in background ✅
- BG-FIX-4: `artworkUrl` now passed through to lock-screen notification ✅

**Panel active-state & animation bugs — ALL DONE (SHA `94e1ee0b`, CI green):**
- 6 panel freeze bugs fixed (vibe chip, audio track, primary/secondary subtitle highlights, EQ preset deselect, snap→AnimatedContainer animations) ✅

**Phase A (Full UI Theme Engine) — DONE (SHA `e4899225`, CI green):**
- PHASE-A1/A2/A-ENTRY: accent color + seek bar style + QuickSettingsPanel access via sidebar ✅

**Phase A (Subtitle Positioning) — ALL 5 DONE (SHA `5bb40fec`, CI green):**
- SUB-A1: Signed vertical offset in `subtitle_overlay.dart` (no more `abs()`) ✅
- SUB-A2: Panel "Bottom Margin" slider now writes `player_sub_bottom_margin_px`; overlay reads it live ✅
- SUB-A3: `controlsRaiseDp: _showControls ? 120.0 : 0.0` passed to both landscape + portrait `SubtitleOverlay` ✅
- SUB-A4: `onPositionSynced` wired end-to-end; horizontal alignment updates `playerPrefsProvider` live ✅
- SUB-A5: Edge padding now saved to `player_sub_edge_pad_px` and propagated to overlay live ✅
- Phase B wiring (B4/B5): `_saveSubPrefs` now writes `player_sub_line_spacing`, `player_sub_letter_spacing`, `player_sub_shadow_blur`, `player_sub_shadow_dir`; `onStyleSynced` passes them through (partial — verify/add UI sliders next) ✅

---

**Phase B — Subtitle Style Presets & New Styles — ALL DONE (SHA `5c36e4c`, CI ✅):**
- SUB-B1: `_applyPreset` now applies lineSpacing/letterSpacing/shadowBlur/shadowDirIdx ✅
- SUB-B2: Font wiring (`_resolvedFontFamily`, `_buildShadows`, letterSpacing/height) confirmed done from prior session ✅
- SUB-B3: 4 new presets added to `subtitle_style.dart` (YouTube, Netflix, BBC, Large Print) ✅
- SUB-B4: Line Spacing + Letter Spacing sliders added to Style tab custom section ✅
- SUB-B5: Shadow Blur + Shadow Direction controls added to Style tab custom section ✅

**Next priority: Phase C — Audio Player & Panel Fixes**

Start at AUDIO-C1 (vibe entry from audio disc when mode=None) → AUDIO-C2/C3 (missing `didUpdateWidget`) → AUDIO-C4 (SW decoder gate) → AUDIO-C5 (title parser) → AUDIO-C6 (wire dead audio-sync callbacks).

### Critical bugs confirmed by audit (Phase A — start here):

1. **Subtitle margin slider completely broken** — panel "Bottom Margin" slider writes
   `pref_sub_margin` (px int); `SubtitleOverlay` reads `subtitleVerticalOffset` (different
   key entirely). Changing the slider has zero visible effect. (SUB-A2)
2. **Subtitle vertical offset sign stripped** — `abs(offset)` discards direction; slider
   appears to work in one direction only. (SUB-A1)
3. **Subtitles never raise when seekbar appears** — existing `_applySubtitleMargin()` only
   targeted MPV (disabled, Rule 51); Flutter overlay is `Positioned.fill` with a fixed
   `bottom: 80` — never moves. Subtitles sit on top of the seekbar. (SUB-A3)
4. **Horizontal alignment broken** — panel writes MPV `sub-align-x`; overlay always centers. (SUB-A4)
5. **Edge padding broken** — panel writes MPV `sub-margin-x`; overlay uses hardcoded 24px. (SUB-A5)
6. **`onAudioDelay`, `onOpenSubSync`, `onOpenAudioSync` are dead no-ops** at call site —
   audio/subtitle delay UI rows render but do nothing. (AUDIO-C6)
7. **`onOpenPictureProfiles` and `onOpenWakeDnd` are dead no-ops** — buttons do nothing. (PLAYER-D1)

### Phase summary:

| Phase | Topic | Tasks | Priority |
|---|---|---|---|
| **A** | **Subtitle positioning & margin — all 5 settings completely broken** | 5 | 🔴 P0 |
| **B** | Subtitle style presets — fix preset apply, wire font/style, add 10 new styles, spacing/shadow controls | 5 | 🟡 P1 |
| **C** | Audio player & panel — vibe entry, stale panel state, dead delay callbacks, title parser | 6 | 🟡 P1 |
| **D** | Player settings & Quick Settings — dead no-ops, immersive missing, settings not persisted | 7 | 🟡 P1–P2 |
| **E** | Live TV — orientation bug, HLS bypass, skeleton loading, search UX, stale-data banner | 10 | 🟡 P1–P2 |
| **F** | App-wide (guest/free/subscribed/admin) — 6 cross-cutting issues | 6 | 🟢 P2–P3 |
| **G** | Dual subtitles consistency | 3 | 🟢 P2 |
| **H** | Production hygiene tweaks | 3 | 🟢 P2–P3 |
| **I** | Player gestures & controls — throttle, volume model, lock screen, seek accumulation | 9 | 🟡 P1–P2 |
| **J** | PiP overlay & Cast panel — resize bug, safe-area, auto-hide, duplicate device, signal bars | 7 | 🟢 P2 |
| **K** | Downloads & local media — 4xx accepted as success, file leaks, stale resume, no pause/resume | 7 | 🔴 P1–P2 |
| **L** | Show detail & history — episode sort index, season reload, progress crash, history sync/grouping | 7 | 🟡 P1–P2 |
| **M** | Auth & network reliability — retry loop, offline startup, guest-to-auth state bleed | 4 | 🟢 P2–P3 |
| **N** | Actor, search, mini-player, nav misc — future rebuilt in build(), sync I/O, dead route handler | 7 | 🟢 P2–P3 |

**Total: 86 tasks across 14 phases.**

**After this plan:** Resume `FEATURES_ROADMAP.md` Phase A remaining (A3 button/icon styles,
A4 controls background style). Then Phase B (drag-drop layout editor).

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
