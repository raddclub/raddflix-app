# AI Rules — RaddFlix Design System

Read this before modifying any UI code in `raddflix_flutter`. It's the fast-context version of the design system for any AI assistant (or human) about to touch the app — the full reasoning lives in Volumes I-XII.

## Hard rules

1. **Never hardcode colors, spacing, radii, or type sizes.** Always use `Radd*` design tokens (Volume II) via the theme extension (`context.t.*`, `context.raddType`, `context.raddSpace`). If a token you need doesn't exist yet, add it to the token layer — don't inline a literal.
2. **Prefer existing `Radd*` components over creating new widgets.** Check Volume IV before building anything that looks like a button, card, sheet, banner, chip, text field, or settings row. If a truly new pattern is needed, it should become a new `Radd*` component with a Volume VIII contract, not a one-off screen-local widget.
3. **Follow the Migration Guide (Volume IX)** when touching a screen or widget that's listed there — don't reinvent the mapping.
4. **Maintain Material 3 compatibility.** `Radd*` components wrap/theme Material 3 widgets; they don't replace the Flutter/Material widget tree wholesale.
5. **Preserve accessibility standards (Volume VI)** on every change: semantics labels, 44×48dp touch targets, contrast minimums, reduced-motion support. Don't ship a visual change that regresses any of these.
6. **Preserve performance standards (Volume XI)** — check paint/frame/memory budgets for the screen you're touching before adding new work to its build path (especially the Player and Home).
7. **`accent.dataFree` (signal-green) means exactly one thing: this content/session is free.** Never use it for success, online, active, or downloaded states — see Volume I, Protected Colors.
8. **One primary action per screen, one modal/sheet at a time, no stacked bottom sheets** — see Volume X, Interaction Principles, before adding new navigation or overlay UI.
9. **Run the Volume XII Quality Checklist** against any screen before considering a redesign/migration task done.
10. **Do not create new one-off audit/handoff/status/design files.** Update the relevant volume in this folder and record the change in `CHANGELOG.md` instead — this repo's `AGENT_PROMPT.md` has a hard rule against doc sprawl.

## When in doubt

Fall back to the ten RaddFlix Principles in `01-brand-identity.md` — they resolve ambiguous product/design decisions that aren't explicitly covered by a rule above.

## Documentation status

v1.0 is frozen. Don't rewrite volumes wholesale. If implementation reveals an improvement, update the specific volume in place and log it in `CHANGELOG.md`. Don't start a "v2.0" until a significant portion of the system has actually been implemented and tested — see `ROADMAP.md`.
