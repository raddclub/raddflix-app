# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-26 — BUG-SUB-STYLE-FIXES done `9b3b9a8b`, CI ✅)

**No open tasks.** Two subtitle regression bugs fixed and pushed in commit `9b3b9a8b`. Audio lab chain verified correct (no code change needed — see investigation entry in TASKS.md).

| ID | Fix summary | Commit |
|---|---|---|
| BUG-SUB-STYLE-FIXES (1/2) | `_ps_subtitle_mixin.dart` `onSubPropertyChanged`: dropped the 9-prop whitelist for `sub-ass-override='force'`; now set unconditionally for ALL non-internal MPV sub-* props. Previously `sub-align-x`, `sub-align-y`, `sub-margin-x`, `sub-ass-scale-with-window` were missing → position tab changes had no effect on embedded ASS subs. | `9b3b9a8b` |
| BUG-SUB-STYLE-FIXES (2/2) | `_ps_panels_subtitle.dart` `_saveSubPrefs()`: added `await prefs.setDouble('pref_sub_margin', _subBottomMargin)`. Bottom margin slider was restored on `_loadSubPrefs()` but the write path was absent — the value was only saved via the debounced `_scheduleSavePrefs()` in the parent, not by `_saveSubPrefs()` itself. | `9b3b9a8b` |
| AUDIO-LAB-INVESTIGATION | Full static trace of audio lab code path (panel → `_applyLabAf` → `onLabAfChanged` → `_currentLabAf` → `_applyAllAf` → `_np.setProperty('af',…)`). Chain is complete and correct. Lab state and `_currentLabAf` are correctly restored from SharedPrefs at startup in `player_screen.dart` lines 481–545 + 500 ms deferred `_applyAllAf()`. All prior known bugs (A1–A6, BUG-AUDIO-SILENT-01, Lab EQ coupling) confirmed fixed. No actionable regression found. | — (no code change) |

**Previous session 2026-07-25:** All 5 audit bugs fixed in commit `4a3d53d6` (CI ✅).

**10/10 plan:** All actionable items ✅ done. Two remain blocked: G4 (folder reorg — needs user go-ahead) and K5 (const sweep — needs Flutter SDK).

---

> Full session history: `agent-hub/history/TASK_LOG.md`
