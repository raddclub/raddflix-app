# Volume II — Visual Language

## Color

Keep the 8 existing theme variants (Dark, Amoled, Light, Midnight, Navy, Forest, Cobalt, Rose) — this multi-theme depth is a real strength; deepen it, don't discard it. Formalize the semantic layer on top so every screen pulls meaning, not raw hex:

| Token | Dark theme value | Role |
|---|---|---|
| `signal.primary` | `#E8002D` | The one "always on" color — CTAs, active states, live indicators, the signal-strength motif |
| `signal.primaryGlow` | `#E8002D` @ 40% blurred | Ambient glow behind hero art, "on-air" pulse ring |
| `surface.base` / `.alt` / `.high` | `#08080E` / `#0D0D1A` / `#161628` | Existing scale, keep as-is |
| `content.primary/secondary/muted/disabled` | existing text scale | Keep as-is |
| `accent.dataFree` | `#3DDC97` (signal-green) | Reserved exclusively for zero-rated/data-free indicators — see Volume I, Protected Colors |
| `accent.warning` / `.error` | existing subscription palette | Keep |

## Typography — `RaddType` scale

| Role | Size / Weight | Usage |
|---|---|---|
| `display` | 34sp / w900, -0.5 tracking | Hero title on Home, splash wordmark |
| `headline` | 24sp / w800 | Screen titles, Detail show title |
| `title` | 18sp / w700 | Section headers ("Trending", "Continue Watching") |
| `body` | 15sp / w500 | Descriptions, synopsis |
| `bodyStrong` | 15sp / w700 | Metadata emphasis (runtime, rating) |
| `label` | 13sp / w600, +0.2 tracking, uppercase | Chips, badges, tab labels |
| `caption` | 12sp / w500 | Timestamps, secondary metadata |
| `signalNumeral` | 32sp / w900, tabular figures | Reserved for the data-saved counter and quota numbers — a distinct "big number" style used nowhere else so it always reads as a headline stat |

## Spacing — `RaddSpace` scale

`xs=4 · sm=8 · md=16 · lg=24 · xl=32 · xxl=48` — replaces hardcoded padding values app-wide. Card gutters = `sm`, section padding = `md`, screen-edge margins = `md`, hero breathing room = `xl`.

## Radius & Elevation

- Radius: `sm=8` (chips, badges) · `md=12` (cards, inputs) · `lg=16` (sheets, dialogs) · `pill=999` (buttons, tags).
- Elevation presets (replace per-widget shadow tuning):
  - `elevation.card` — 0 blur, `cardBorder` outline only, subtle inner glass, no drop shadow. Cards feel *lit*, not *lifted*.
  - `elevation.sheet` — `BackdropFilter` blur sigma 20 + 1px top border, matches the existing player glass work.
  - `elevation.modal` — blur sigma 24 + soft crimson-tinted glow at 8% opacity, ties dialogs to the signal-color identity even when neutral in content.

## Icon System

Phosphor icon set. Rule: **outline weight = inactive/secondary, fill weight = active/primary state**, applied with zero exceptions across nav, player controls, and settings. Default size 24dp, compact 20dp, hero 32dp, 1.5px stroke at 24dp.

## Rules

- One primary (`Signal`) action per screen.
- One accent hue in play at a time — crimson (`signal.primary`) is the only interactive hue; theme variants change background mood, not the interactive accent.
- Maximum three distinct type sizes visible within a single screen section.
- Do not bold more than one element per row/card.
- Never set body text in uppercase (reserved for `label` scale only).
