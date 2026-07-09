# UI/UX Design-System Migration — Phased Task List

Canonical execution checklist for turning `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` (analysis)
into shipped code. Read the blueprint first for evidence/rationale — this file is the checklist,
kept short on purpose (Rule per `RESILIENCE.md` §5: docs are a memory system, not a diary).

**Built for cross-agent/cross-account continuation.** Any agent (Replit or otherwise, any
account) picking this up should: read `AGENT_PROMPT.md` → `AGENT_HANDOFF.md` →
`agent-hub/TASKS.md` → this file, find the first unchecked `[ ]` item in the first phase that
has any unchecked items, and continue from there. Do not skip ahead to a later phase while an
earlier one has open items, unless this file explicitly marks phases as parallelizable (see
Phase 3/5 note below). Every item follows the mandatory Rule 42 workflow
(`log_pending.sh` → edit → `auto_commit.sh`) — one commit per logical change, never batched.

Check a box only after the change is edited AND pushed (`auto_commit.sh` succeeded) AND, if it
touches `raddflix_flutter/**`, the GitHub Actions build for that push is confirmed green
(`AGENT_PROMPT.md` rule on build verification). Update the "Status" line under the phase whenever
you start or finish an item — that line is what the next agent reads first.

---

## Phase 0 — Unblock (build/test tooling)
**Status:** ⏳ NOT STARTED — no Flutter SDK available in the current Replit environment.
- [ ] Get a Flutter SDK available in some environment (Replit or the human's machine) capable of
      running `flutter analyze` / `flutter test` against `raddflix_flutter/`.
- [ ] Render each of the 8 `Radd*` components in a throwaway test screen to confirm they compile
      and look correct before any screen depends on them further.
- [ ] Until this phase is done, every change below MUST be verified by (a) careful manual
      read-through of the diff, and (b) the GitHub Actions `build-apk.yml` result after push —
      that workflow does have a working Flutter toolchain even though this Replit doesn't.

## Phase 1 — Investigation gaps
**Status:** ⏳ NOT STARTED
- [ ] Confirm current Player HUD footprint against the Volume V "center third kept clear" rule
      (re-measure, don't assume the earlier audit's read is still accurate).
- [ ] Decide and document duration tokens for `RaddMotion` (currently curves-only — a token-layer
      gap per blueprint §3.5). Needs a design decision, not just code.
- [ ] Scoped pass on accessibility, responsiveness-at-breakpoints, and error/feedback UX per
      blueprint §6 — these were flagged as "not measurable from static code" and need a real pass.

## Phase 2 — Foundational, low-risk consolidation
**Status:** ⏳ IN PROGRESS
- [x] Migrate `pin_lock_screen.dart` (`PinLockScreen` + `PinSetupScreen`) onto `RaddLockPad`.
- [ ] Migrate `vault_lock_screen.dart` onto `RaddLockPad`.
- [ ] Resolve `ContentCard` (6 usages) vs `SimosaCard` (2 usages) duplication onto `RaddCard` —
      pick one call-site set to convert first (start with the 2 `SimosaCard` usages, smaller
      blast radius), verify visually, then convert the 6 `ContentCard` usages.
- [ ] Confirm which of the ~47 files under `lib/widgets/player/` are truly unreachable (grep the
      import graph — no Flutter SDK to run `flutter analyze` yet) and delete/archive them per
      the existing `PLAYER-DEAD-CODE-CLEANUP` task in `agent-hub/TASKS.md`.

## Phase 3 — Auth + small screens token/component pass
**Status:** ⏳ NOT STARTED — parallelizable once Phase 0 is done (each screen below is independent;
multiple agents/sessions can take one screen each without colliding, as long as each follows
Rule 42's one-commit-per-change discipline).
- [ ] `login_screen.dart` — remove remaining 17 `AppColors.*` / 7 raw `Color()` / 22 `Colors.*`.
- [ ] `register_screen.dart` — remove remaining 7 `AppColors.*` / 11 `Colors.*`.
- [ ] `watchlist_screen.dart`, `history_screen.dart` — token pass (small, low risk).
- [ ] `splash_screen.dart` — token pass.
- [ ] `settings_screen.dart` — fix section taxonomy to match Volume V (Playback / Privacy & Vault
      / Account / Data & Downloads / Accessibility / About) AND adopt `SettingsRow` for every row
      (0 usages today).

## Phase 4 — Player (isolated, high-risk, do not parallelize within the file)
**Status:** ⏳ NOT STARTED — blocked on Phase 2's dead-code cleanup item finishing first.
- [ ] Delete/archive confirmed-dead `lib/widgets/player/` files (from Phase 2) before starting
      any in-file migration, so effort isn't spent on code about to be removed.
- [ ] Migrate `player_screen.dart` color tokens (520 raw `Colors.*`, 76 raw `Color()`).
- [ ] Migrate `player_screen.dart` radius tokens (80 raw `BorderRadius.circular()`).
- [ ] Migrate `player_screen.dart` spacing/type tokens.
- [ ] Re-verify HUD-rule compliance from Phase 1's re-measurement.
- [ ] Only after the above: evaluate whether splitting the 9,280-line file into smaller widgets
      is warranted — this is a separate architectural decision, not a requirement of this
      migration, and should get its own task row if pursued.

## Phase 5 — Remaining large screens (parallelizable once Phase 3's pattern is proven)
**Status:** ⏳ NOT STARTED
Migrate in this order (highest raw-literal count first, per blueprint §2/§4):
- [ ] `show_detail_screen.dart` (93 `Colors.*`, 59 `AppColors.*`, 13 raw `Color()`)
- [ ] `local_folder_screen.dart` (71 `Colors.*`, 51 `AppColors.*`)
- [ ] `subscription_screen.dart` (61 `Colors.*`, 52 `AppColors.*`) — flag to design: no Volume V
      wireframe exists for this screen; get one before/while migrating.
- [ ] `home_screen.dart` (71 `Colors.*`, 33 `AppColors.*`, 3 raw `Color()`)
- [ ] `local_media_screen.dart` (55 `Colors.*`, 33 `AppColors.*`, 6 raw `Color()`)
- [ ] `search_screen.dart` (46 `Colors.*`, 33 `AppColors.*`) — also adopt `RaddSheet` for filters
      (currently no detected `RaddSheet`/`showModalBottomSheet` match).
- [ ] `profile_screen.dart` (44 `Colors.*`, 36 `AppColors.*`, 29 raw `Color()` — highest literal
      count in the app) — flag to design: no Volume V wireframe exists; get one before/while
      migrating.
- [ ] `downloads_screen.dart` (60 `Colors.*`, 40 `AppColors.*`)
- [ ] `vault_screen.dart`, `vault_settings_screen.dart`, `season_folder_screen.dart`,
      `edit_profile_screen.dart`, `add_edit_profile_screen.dart`, `profile_switcher_screen.dart`,
      `tid_status_screen.dart`, `admin_queue_screen.dart`, `actor_screen.dart`,
      `plan_expired_screen.dart`, `quota_full_screen.dart`, `layout_designer_screen.dart` (both
      copies — confirm which is live first), `player_settings_screen.dart` — remaining screens,
      lower literal counts, can go in any order.

## Phase 6 — Onboarding rebuild (new feature, not a migration)
**Status:** ⏳ NOT STARTED — blocked on Phase 3 (prove `RaddCard`/`RaddButton`/`RaddChip` in
production first).
- [ ] Build the documented 3-step reciprocity flow (genre taste capture → starter watchlist build
      → save/signup) per Volume V, replacing the current generic `PageView` marketing carousel.
      Progress bar must open at ~25%, never 0%, per the design doc's stated behavioral intent.

## Phase 7 — Final polish & readiness re-audit
**Status:** ⏳ NOT STARTED — do last.
- [ ] Re-run the same grep queries used in `docs/DESIGN_SYSTEM_MIGRATION_BLUEPRINT.md` §2/§4
      against the final state of the codebase.
- [ ] Update the Release Readiness Dashboard (blueprint §1) with final numbers.
- [ ] Produce a short delta report (before → after) as a `TASK_LOG.md` entry — not a new file.

---

## Notes for the next agent (any session, any account)

- This plan assumes no Flutter SDK in this Replit — every change here has been done via careful
  manual read-through + reliance on the GitHub Actions build (`build-apk.yml`) as the real
  compiler check. If a future session DOES have Flutter SDK access, run `flutter analyze` locally
  before pushing instead of relying solely on CI — faster feedback loop.
- If you hit your context/usage limit mid-phase: you do not need to leave a note beyond what
  Rule 42 already gives you. `agent-hub/UNPUSHED.txt` (via `log_pending.sh`) plus this file's
  checkboxes are the full handoff — the next agent (even a fresh Replit account) reads this file,
  sees the first unchecked item, and continues. Do not create a separate "where I left off" file.
- If `agent-hub/UNPUSHED.txt` is non-empty when you start a session, run `bash recover_push.sh`
  FIRST, before reading anything else — a prior session's edit may not have been pushed yet.
