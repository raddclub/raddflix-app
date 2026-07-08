# Volume VII — Developer Guidelines

## Build Order

Ship the token layer first, then shared primitives, then convert screens one at a time:

1. **Tokens** — `RaddType`, `RaddSpace`, semantic colors including `accent.dataFree`, `RaddRadius`, `RaddElevation`, motion tokens. Everything else depends on these existing.
2. **Primitives** — `RaddSheet`, `RaddLockPad`, `SettingsRow` (everything else depends on these), then `RaddButton`, `RaddCard`, `RaddBanner`, `RaddTextField`, `RaddChip`.
3. **Screens, one at a time** — Settings hub, Player HUD/sheet consolidation, Home hero redesign, Show Detail componentization, Search mood chips, Onboarding taste-capture, Downloads/Profile/Lock touch-ups.
4. **Optimization** — performance, accessibility, animation and micro-interaction polish (Volumes VI, XI).

## RaddFlix Engineering Playbook

### Folder structure

```
lib/design_system/
├── theme/          RaddThemeExtension, theme_provider, brand_theme_provider (existing, kept)
├── colors/         semantic tokens: signal.*, surface.*, content.*, accent.dataFree (protected)
├── typography/      RaddType scale definitions
├── spacing/         RaddSpace scale
├── radius/          RaddRadius scale
├── elevation/        RaddElevation presets (card/sheet/modal)
├── motion/          Pulse, Tune, easing curves, durations
├── components/       RaddButton, RaddCard, RaddSheet, RaddBanner, RaddTextField, RaddChip, RaddLockPad, SettingsRow
├── layouts/          breakpoint helpers, responsive builders
└── extensions/       BuildContext shorthand accessors (extends existing RaddColors pattern)
```

### Conventions

- **Naming:** every design-system widget is prefixed `Radd*`; one file per component, filename = `snake_case` of the class.
- **Theme access:** always via `context.t.*` (existing pattern) or a new `context.raddType` / `context.raddSpace` — never a raw `Color(0x...)` or literal `16.0` outside the token files.
- **State management:** design-system components stay presentation-only (no provider/business logic inside `Radd*` widgets); screens own state, components own rendering.
- **Animation:** only use the named `Pulse` / `Tune` / sheet-entrance curves from `motion/` (Volume III); no ad hoc `Duration(milliseconds: ...)` literals in screen code.
- **Documentation:** every `Radd*` component ships a doc comment following the Volume VIII contract (Properties / Behavior / Accessibility / Animation / Tokens / Examples).
- **Testing:** each `Radd*` primitive gets a widget test covering default, disabled, loading, and (where relevant) accessibility-label assertions before it's marked Production in the dashboard below.

## Component Status Dashboard

Update this table as each component ships — it becomes the single source of truth for migration progress instead of relying on memory across sessions.

| Component | Status | Used In | Ready |
|---|---|---|---|
| RaddButton | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| RaddCard | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| RaddSheet | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| RaddBanner | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| RaddTextField | 🚧 | **3 screens** — `login_screen.dart`, `register_screen.dart`, `subscription_screen.dart` (verified 2026-07-08 audit) | Actually in production use already; still needs a real widget-test/device pass before flipping to ✅ |
| RaddChip | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| RaddLockPad | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| SettingsRow | 🚧 | 0 screens | Built, needs widget tests + real-device check before Production |
| Token layer (Type/Space/Radius/Elevation/Motion) | ✅ | 0 screens outside `design_system/` itself | Production per Phase 2 sign-off, but zero real screens/widgets consume it yet — see `TASKS.md` DS-AUDIT-2026-07-08 |

Status legend: ❌ Planned · 🚧 In Progress · ✅ Production.

**Correction (2026-07-08 full-app audit):** this dashboard previously listed `RaddTextField` at "0 screens," which was inaccurate — it was already wired into 3 live screens. See `TASKS.md` DS-AUDIT-2026-07-08 for the full audit of docs-vs-reality across every volume (motion-token value mismatch, Player HUD/interaction-rule violations, 0% screen migration elsewhere).
