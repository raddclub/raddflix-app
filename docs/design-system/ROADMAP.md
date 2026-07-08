# RaddFlix Design System — Implementation Roadmap

This bridges the design documentation (v1.0, frozen) and actual implementation. Update the checkboxes as work lands; this is the live tracker, not a memory-dependent status.

- [x] **Phase 1 — Documentation** — all 12 volumes written and frozen at v1.0.
- [x] **Phase 2 — Theme Tokens** — `RaddType`, `RaddSpace`, `RaddRadius`, `RaddElevation`, semantic colors (incl. `accent.dataFree`), motion tokens (Volumes II, III). Additive only — no screens migrated yet, existing `AppRadius`/`AppColors`/`AppDurations` untouched.
- [ ] **Phase 3 — Shared Components** — `RaddButton`, `RaddCard`, `RaddSheet`, `RaddBanner`, `RaddTextField`, `RaddChip`, `RaddLockPad`, `SettingsRow` (Volumes IV, VIII). Update the Component Status Dashboard in `07-developer-guidelines.md` as each ships.
- [ ] **Phase 4 — Home** — On Air hero, signal-green card badges, componentized rails (Volume V).
- [ ] **Phase 5 — Search** — mood chips, unchanged core search/filter UX.
- [ ] **Phase 6 — Player** — HUD consolidation to 5 controls + "More" sheet (Playback/Audio & Video/Extras tabs), sidebar → Extras tab.
- [ ] **Phase 7 — Settings** — unified hub replacing the three fragmented settings screens, built on `SettingsRow`.
- [ ] **Phase 8 — Remaining screens** — Show Detail componentization, Profile Switcher photo avatars + Pulse ring, `RaddLockPad` rollout to both PIN and Vault lock, Onboarding taste-capture + brand moment, Downloads badge treatment.
- [ ] **Phase 9 — Polish** — accessibility audit pass (Volume VI), performance budget verification (Volume XI), motion/micro-interaction pass, run Volume XII checklist against every screen before release.

## Process notes
- One screen at a time — do not start a new phase's screen work until the prior phase's shared primitives it depends on are marked Production in the Component Status Dashboard.
- Test on real devices across the `AnimConfig` tiers (Potato/mid/Premium), not just the simulator/emulator default.
- Iterate based on actual usage once shipped — this roadmap is expected to evolve; log changes in `CHANGELOG.md` rather than rewriting history silently.
