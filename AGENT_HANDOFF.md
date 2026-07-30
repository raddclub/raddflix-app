# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-30 — task planning: bug fixes + Vibe Modes)

Full plan written to `agent-hub/VIBE_BUGS_PLAN.md`. Task rows added to `agent-hub/TASKS.md`.
No code changes this session — planning only.

Three critical bugs identified and fully root-caused (Phase 0). Vibe Modes feature planned in
detail (Phases 1–5). All 20 tasks are OPEN, ready to pick up.

**Next session: start with SUB-GRAY-SCREEN (0A) — it is the highest-priority single fix.**

### Open Tasks Summary

| Phase | Tasks | Count |
|---|---|---|
| 0 — Critical Bugs | SUB-GRAY-SCREEN, PLAYER-PERF, THUMB-PERF | 3 |
| 1 — Vibe Foundation | VIBE-1A through VIBE-1E | 5 |
| 2 — Core Vibe Modes | VIBE-2A through VIBE-2D | 4 |
| 3 — Extended Modes | VIBE-3A through VIBE-3C | 3 |
| 4 — Vibe UI | VIBE-4A through VIBE-4D | 4 |
| 5 — Vibe Polish | VIBE-5A through VIBE-5D | 4 |

### Phase 0 Root Cause Summary (for next agent — read before touching files)

**SUB-GRAY-SCREEN:** `SubtitleOverlay.build()` returns `Positioned.fill(...)` itself, but
the parent already wraps it in `Positioned.fill → IgnorePointer`. In release builds, a
`Positioned` outside a Stack silently fills its parent — the entire player area becomes a
gray-tinted overlay. Secondary: whitespace-only lines pass the `.isEmpty` guard. Fix is
in `subtitle_overlay.dart` only — remove inner `Positioned.fill`, use `Align + Padding`
directly; change guard to `.trim().isEmpty`. See `agent-hub/VIBE_BUGS_PLAN.md` §0A.

**PLAYER-PERF:** Three causes: `setState()` on every subtitle stream tick (use
`ValueNotifier` instead), Consumer blocks rebuilding on unrelated PlayerPrefs changes
(use `ref.select()`), missing `RepaintBoundary` around subtitle overlay. See §0B.

**THUMB-PERF:** Fallback thumbnail path uses `MediaKitThumbnailExtractor` which spins up
a full libmpv `Player()` per thumbnail (~2–4s each). Fix: add `MediaMetadataRetriever`
via Kotlin coroutine in `MediaStorePlugin.kt` as the true fallback. See §0C.

### Previously Completed (this session context)

All audio disc UI bugs (AUDIO-DISC-BUGS, AUDIO-DISC-BUGS-2), background audio fixes
(BGAUDIO-SESSION, BGAUDIO-VID, BGAUDIO-UI), and input style standardization (INPUT-STYLE)
are ✅ DONE. CI green on `d5b93d29`. No Oracle deployment needed — Flutter only. No open
tasks before this session's planning work.

### Blocked tasks (no agent can fix without external input)

- **SEC-01:** Plain HTTP API. Needs domain + TLS cert provisioned on Oracle.
- **SEC-05:** APK tamper-detection placeholder. Needs `keytool` run against release APK.
- **SEC-04:** Vault PIN SHA-256 static salt. Needs PBKDF2 migration decision from owner.

### This Session's Commits

| SHA | Description |
|---|---|
| _(pending)_ | Add VIBE_BUGS_PLAN.md + TASKS.md entries + AGENT_HANDOFF update |

**CI:** No code changes this session — no CI run needed.

---

### Previous sessions (for full history see TASK_LOG.md)
- `d5b93d29` — AUDIO-DISC-BUGS-2 (CI ✅)
- `f59bebf` — AUDIO-DISC-BUGS (CI ✅)
- `321b78e` — BGAUDIO-SESSION + BGAUDIO-VID (CI ✅)
- `e3b828ea` — INPUT-STYLE (CI ✅)
- `fd21ebb6` — BUG-APPLYALLAF (CI ✅)
- `defb61e` — SUB-OVERLAY-FIX (subtitle architecture overhaul)

---

> Full session history: `agent-hub/history/TASK_LOG.md`
