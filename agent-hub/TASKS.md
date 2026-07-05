# RaddFlix Tasks

> This is the single live task board. Start every session at `AGENT_PROMPT.md`.
> Add a row here (⏳ IN PROGRESS) before starting work, mark ✅ DONE + commit SHA when pushed.
>
> **This file is a lean INDEX, not a full history.** Every completed item below has its full
> write-up (root cause, implementation notes, testing checklist) already preserved in
> `agent-hub/history/TASK_LOG.md` — search that file by phase name or ID before re-deriving
> something that may already be documented. Keeping this file short means every future session
> reads less and starts working faster; nothing is lost, it's just filed correctly.
>
> See `agent-hub/ANIMATION_PLAN.md` for animation spec and acceptance criteria.

---

## Open Tasks

**None.** All logged work below is shipped and pushed.

---

## 🛡️ Hard Rules for Every Animation Phase (ANIM-*)

> An agent MUST verify these before marking any ANIM task as DONE:
> 1. ✅ Gated behind `AnimConfig.tier` check
> 2. ✅ Respects `MediaQuery.disableAnimations`
> 3. ✅ No `BackdropFilter` on API < 28 (Tier < 2)
> 4. ✅ No fragment shaders on API < 26 (Tier < 2)
> 5. ✅ `RepaintBoundary` on every isolated animated widget
> 6. ✅ All controllers/listeners disposed in `dispose()`
> 7. ✅ Tested on API-21 emulator — must not crash or jank
> 8. ✅ Duration ≤ 350ms on Tier 0/1

---

## Completed Work Index

Full detail for every row below (root cause, code diffs, testing notes) lives in
`agent-hub/history/TASK_LOG.md` — use the phase name or commit SHA to find it fast.

| Phase / Batch | Summary | Commit(s) | Status |
|---|---|---|---|
| Phase 41 | Performance infra — AnimConfig tiers, animation packages, RepaintBoundary audit | `8396c13` | ✅ DONE |
| Phase 42 | Hero poster transition (home/search → detail) | `50717ac` | ✅ DONE |
| Phase 43 | Staggered grid/list entry animations | `4f55fcd` | ✅ DONE |
| Phase 44 | Card → detail morph via OpenContainer | `2600a39` | ✅ DONE |
| Phase 45 | Neon/glow primary action buttons | `bec1909` | ✅ DONE |
| Phase 46 | Typewriter & animated text (synopsis, chips) | `647ac5c` | ✅ DONE |
| Phase 47 | Frosted glass bottom nav | `af27e1a` | ✅ DONE |
| Phase 48 | 3D tilt hero banner | `a8d4323` | ✅ DONE |
| Phase 49 | Ambient particle background (splash/login) | `f81b0cb` | ✅ DONE |
| Phase 56 | Subscription tier badge (animated glow) | `a34b5f9` | ✅ DONE |
| Audit Fixes | Guest/Free/Premium episode lock logic | `336dbb5` | ✅ DONE |
| 5-Feature Batch | Settings screen, search history, subtitle picker, update check, continue-watching | `1859ec1` / `a6d938b` / `2562512` / `d2f8146` | ✅ DONE |
| Phase 57 | Player audit + fix: dual subtitles (secondary-sid), fake track bugs, EAC3/DTS auto-fallback, codec badges, MKV embedded subtitle selector | audit: N/A · impl: see `TASK_LOG.md` "Phase 57 Implementation" | ✅ DONE |
| Phase 58 | Online subtitle search overhaul (OpenSubtitles XML-RPC, manual search, language chips) | see `TASK_LOG.md` "Phase 58" | ✅ DONE |
| Phase 60 | Remove-dub / dub-active indicator in Audio Panel | `803f09a` | ✅ DONE |
| Build Fix | Kotlin 2.2.0 bump (flutter_tts 4.2.5 compat) | `a8e5bf1` | ✅ DONE |
| Build Fix | minSdkVersion 21 → 24 (flutter_tts 4.2.5 requirement) | `98323a8` | ✅ DONE |
| Full-App Audit | 15 verified bugs fixed across 7 files (dispose leaks, mounted guards, static regex, OOM guard, etc.) | see `TASK_LOG.md` "Full-App Bug & Logic Audit" | ✅ DONE |
| Bug-Fix Batch 2026-07-02-B | Dub visibility, ASS subtitle margin override, free-user `isFree` bool parsing | `b0b01ff` / `7835605` | ✅ DONE |

---

## Repo Consolidation & Resilience Work (2026-07-03)

| Task | Summary | Commit(s) | Status |
|---|---|---|---|
| Docs consolidation | Archived 15 stale handoff docs, rewrote `AGENT_PROMPT.md` as single safe entry point | `5618f33` | ✅ DONE |
| Script hardening | `push_to_github.sh` / `push_to_oracle.sh` — `set -euo pipefail`, no token-to-disk, branch/merge guards, secret-leak guards, DRY_RUN | `7fed76c`, `c93d075` | ✅ DONE |
| Live push test | Verified real commit+push+revert in isolated `/tmp` clone; fixed lock-file-gets-committed bug | `a56d12c` | ✅ DONE |
| `agent-hub/OPERATIONS.md` | Full connect/edit/push guide for GitHub + Oracle | `1a656f7` | ✅ DONE |
| Bootstrap section | `AGENT_PROMPT.md` now walks a fresh session through secret checks + doc order before waiting for a task | `3c52e22` | ✅ DONE |
| `agent-hub/RESILIENCE.md` | Scaling/fallback playbook — local sub-agents vs. Project Tasks, fallback ladders, verify-before-success, hard boundary on safety | `c0cec01`, `62e46ad` | ✅ DONE |
| Oracle drift fix | Server was 281 commits behind + UU conflict markers + local edits. Backed up server files, `git checkout -f origin/main`, `git pull --ff-only`. Server now at `baf349f`, clean tree, healthz ✅ | — | ✅ DONE 2026-07-03 |
| Bug-Fix Batch 2026-07-03 | Free-content play gate + download failures: episode `is_free` inheritance in all 3 catalog API endpoints; movie/episode play gates bypass for local files; episode download URL decode; retryDownload URL decode; `_isSubExpired` live provider | `8176835` | ✅ DONE |
| MPV-Native Player Upgrades 2026-07-03 | Native `ab-loop-a/b` (removed Dart-side seek polling), background next-episode link prefetch for near-gapless transitions, screenshot-with-subtitles (long-press) | `4cda21c` | ✅ DONE |
| Full Audit Pass 2026-07-03 | Subtitles, player controls, access control, downloads — see `TASK_LOG.md` "Full Audit Pass 2026-07-03" | see below | ✅ DONE |

---

## Auto-Commit Workflow (2026-07-04)

| Task | Summary | Commit(s) | Status |
|---|---|---|---|
| Auto-commit system | `auto_commit.sh` — lightweight GitHub API commit script; Rule 42 added to RULES.md; AGENT_PROMPT.md updated | `a0d2d9f` | ✅ DONE |
| Icon migration — gesture_map_sheet.dart | Replace 2× `Icons.block_rounded` with `AppIcons.block`; add `app_icons.dart` import — completes 100% AppIcons coverage across non-player files | `3ec3c81` | ✅ DONE |
| Test suite — complete run | All 4 test files executed: JS logic 27/27, Dart logic 69/69, Integration 71/71, JazzDrive Dart 0/8 (MED-1011 — Oracle session expired, not a code bug). SSL cert fix applied to `jazzdrive_dart_test.dart` for Nix/Replit Dart | `2ce6ab4` | ✅ DONE |
| Correct wrong info — TTL & validationkey | Fixed: `constants.dart` TTL 180min→110min; `jazzdrive_dart_test.dart` validationkey direction inverted (was claiming vk MUST be in URL, production says DO NOT add); `logic_tests.dart`/`run_tests.js`/`README.md`/`local_db.dart` stale 6h/180min references | `5d37e39`, `19fa4cf` | ✅ DONE |
| Logger secret stripping — final gap closed | `DebugLogger.logApi()` req/resp/error bodies now redacted via `_redactBody()` (validationkey, k= tokens, JSESSIONID, Authorization/Bearer, access_token/refresh_token) before truncation/storage; verified no unredacted secret patterns reach any log call | `015bcea` | ✅ DONE |

---

## Adding new work here

1. Add a row with ⏳ IN PROGRESS *before* starting.
2. When done and pushed, flip to ✅ DONE and fill in the commit SHA — verify the SHA is real by
   re-fetching it from GitHub, don't just paste what the push command echoed.
3. Write the full detail (root cause, files touched, testing notes) into
   `agent-hub/history/TASK_LOG.md`, not into this file — this file stays a one-line-per-item index.
4. If a task is blocked or intentionally not automated (e.g. needs human judgment, touches
   production), mark it ⚠️ OPEN with a one-line reason instead of silently dropping it.
