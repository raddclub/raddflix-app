# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-30 — audio disc UI bugs fixed × 2 rounds)

All three background audio tasks (BGAUDIO-UI, BGAUDIO-SESSION, BGAUDIO-VID) are done. CI ✅ on `321b78e`. No open tasks remain.

- **BUG-SUB-STYLE-REAPPLY**: All three `_reapplySubtitleStyleAfterLifecycle()` call sites confirmed in code — `stream.tracks.listen` microtask, `_applyCompanionSub()`, `onSubtitleTrackSelected`. No code change needed; marked done.
- **HS-01**: SIMOSA dismiss persists 24 h via SharedPreferences. `_onDismiss()` async, writes `simosa_dismissed_until` (Unix ms + 24 h). `_loadDismissed()` in `initState`. `_onClaim()` clears key.
- **HS-02**: Card height reduced from ~83 px to ~58 px. Inner padding 8→6 px, Claim button vertical 7→5 px, dismiss icon 15→12 px / hit-area padding 4→3 px. Body text `maxLines:1` + `overflow:ellipsis`.
- **HS-03**: Already resolved by HS-06 (96 px bottom clearance, `10aaa85`). Marked done.
- **HS-04–HS-11**: Completed in `10aaa85` (prior session). TASKS.md rows were stale — corrected.

| Status | Count | Task IDs |
|---|---|---|
| ✅ DONE | 15 | HOME-REDESIGN-2026 (`65c5588`), AUTH-UX-2026 (`39343b04`), HS-01–HS-11 (`10aaa85`, `b6934fb`, `b5e83bc`), BUG-SUB-STYLE-REAPPLY (confirmed at HEAD), SUB-OVERLAY-FIX (`defb61e`) |
| ✅ DONE — prior audit backlog | 14 | SEC-02, SEC-03, BUG-FREE-EP-02, BUG-DOWNLOAD-SIZE, BUG-CATALOG-LISTENER, BUG-EPISODE-SORT, BUG-BINGE-TIMER, BUG-TIMELINE-SYNC, BUG-DB-DELETE-RISK, BUG-VOICE-STUB, BUG-PLAYER-AUTODISPOSE, BUG-PROFILE-PIN, BUG-LOCAL-MEDIA-IO, BUG-XOR-CLOCK |
| ⛔ BLOCKED — external dependency | 3 | SEC-01 (needs domain + TLS cert), SEC-05 (needs release keystore SHA-256), SEC-04 (vault PIN migration) |

### Blocked tasks (no agent can fix these without external input)

- **SEC-01:** Plain HTTP API. Needs a registered domain + cert provisioned on Oracle. Until then `kBaseUrl` stays HTTP — do NOT flip to HTTPS prematurely.
- **SEC-05:** APK tamper-detection placeholder (`RADDFLIX_CERT_SHA256_PLACEHOLDER`). Needs `keytool -printcert -jarfile app-release.apk` run against the release build.
- **SEC-04:** Vault PIN SHA-256 static salt. Fix requires PBKDF2 + per-user random salt but would break all existing vault PINs — migration decision needed from owner.

### This Session's Commits

| SHA | Description |
|---|---|
| `e3b828ea` | **INPUT-STYLE**: standardise all input boxes to match login page `RaddTextField` style — 5 files |
| `2649a0f1` | DOCS: INPUT-STYLE task row, TASK_LOG entry, AGENT_HANDOFF |
| `996272fc` | DOCS: record CI green on e3b828ea |
| _(pending)_ | DOCS: INPUT-STYLE doc sweep — blueprint, memory, player-exemption topic |

**CI:** `e3b828ea` → `build-apk.yml` ✅ success. No Oracle deployment needed — Flutter only.

### INPUT-STYLE — What changed

Five screens patched to match the login page `RaddTextField` visual spec (52dp height, `t.surface` fill, `t.border` 1px enabled → `AppColors.primary` 1.5px animated focus, `RaddRadius.mdRadius` corners):

| Screen | Change |
|---|---|
| `live_tv_screen.dart` | `_buildSearchBar`: `Container(h:44)` + `border.withOpacity(0.4)` → `AnimatedContainer(h:52)` with `FocusNode`-driven animated border |
| `vault_screen.dart` | Create-folder + rename-file dialog TextFields: `t.bg` → `t.surface`, circular-10 → `mdRadius`, add focus border |
| `vault_settings_screen.dart` | `_pinField()`: same fill/radius/focus-border fix; `letterSpacing:8` and `obscureText` preserved |
| `local_folder_screen.dart` | `_buildSearchBar()`: `BorderSide.none` → proper `t.border` / `AppColors.primary` border pair |
| `local_media_screen.dart` | `_buildSearchBar()` + URL dialog: `smRadius` → `mdRadius`, consistent enabled/focused borders |

**Exempt (intentional different style):**
- All five player overlay sheets (`jump_to_panel`, `jump_to_sheet`, `sleep_timer_sheet`, `color_picker_sheet`, `subtitle_hunter_sheet`) — white-on-dark player overlay context
- `search_screen.dart` — premium glass-pill with `BackdropFilter` + animated glow

### Previous sessions (for full history see TASK_LOG.md)
- `fd21ebb6` — BUG-APPLYALLAF: fix CI red; CI ✅
- `77c63061` — BUG-SUBLINE-ABSTRACT
- `37aa08f0` — AUDIO-FIX-3
- `6d8b7f4f` — AUDIO-FIX-2
- `c84e7f13` — AUDIO-FIX-1
- `defb61e` — SUB-OVERLAY-FIX (subtitle architecture; see Rule 51 + memory/subtitle-overlay-architecture.md)

---

> Full session history: `agent-hub/history/TASK_LOG.md`
