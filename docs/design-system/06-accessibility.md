# Volume VI — Accessibility

Grounded in WCAG 2.2 and the European Accessibility Act (in force since June 2025), which streaming platforms increasingly need to meet.

## Contrast
- Formal minimums per theme: 4.5:1 for body text, 3:1 for large text (18sp+/w700+).
- Add a dedicated high-contrast theme variant, distinct from Amoled (Amoled is about battery/black levels, not contrast).

## Text Scaling
- Support UI text scale independent of system font scale, for users who want larger UI text without breaking layouts.

## Screen Readers (VoiceOver / TalkBack)
- Audit and label every icon-only button (`RaddButton` icon variant requires `tooltip`).
- Audit focus order/traversal for TalkBack navigation across all screens, especially dense ones (Player Settings, Search filters).
- `RaddCard`: `Semantics(label: "$title, $variant")`; append ", data-free" to the label when `isDataFree` is true rather than relying on a color-only cue.
- `RaddSheet` traps focus while open; first focusable element in content receives initial focus.
- `RaddBanner` appearance is announced via `SemanticsService.announce` — screen-reader users don't rely on the visual slide-in.

## Motion Reduction
- A system-wide "Reduce Motion" toggle, built on top of the existing `AnimConfig` tier system, disables `Pulse` scale and `Tune` overshoot app-wide, falling back to instant or opacity-only transitions.

## Touch Targets
- Minimum 44×48dp hit area enforced across all `RaddButton`, `RaddCard`, and `SettingsRow` instances, regardless of their visual size.
- Verify touch targets specifically in the dense Player Settings screen (35+ options), a known failure point for "power user" screens.

## Color-Independent Communication
- Promote the player's existing dyslexia-friendly subtitles and color-blind filter into an app-wide Accessibility settings section — this work already exists but is currently hidden inside the player and undiscoverable elsewhere.
- Never communicate state through color alone (e.g. the data-free badge pairs its green fill with a checkmark icon and an accessible label, not color alone).

## Audio/Captions
- Caption background opacity control (not just style).
- Audio description track support toggle where content is available.
- Captions-on-by-default option for hearing-impaired profiles.
