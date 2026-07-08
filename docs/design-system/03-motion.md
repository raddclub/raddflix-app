# Volume III — Motion

## "Pulse & Tune" — the named motion language

Two named motion primitives replace ad hoc animation choices, the same way Apple has Human Interface animations and Google has Material Motion.

### Pulse
A slow (1800ms), low-amplitude opacity/scale breathing loop, reserved for anything meant to feel "live": the data-meter, the live-signal badge, the record/on-air indicator on the discovery feed, profile continue-watching ring, active-tab-with-unseen-content, splash screen, empty-state icons.
- Duration: 1800ms loop · Easing: `sin` ease-in-out · Opacity 1↔0.6, scale 1↔1.03
- Respects the existing `AnimConfig` device-tier system: low-tier devices get opacity-only, no scale.

### Tune
A quick (200ms) horizontal snap-settle used for anything that feels like "changing channel": category chip selection, tab switches, quality-fallback toggle, onboarding genre selection.
- Duration: 200ms · Easing: spring, 8% overshoot — like a dial catching its notch.

## Full Animation Table

| Name | Trigger | Duration | Easing | Notes |
|---|---|---|---|---|
| `Pulse` | Live/data-free indicators, splash, active-tab-with-unseen-content | 1800ms loop | `sin` ease-in-out | Opacity 1↔0.6, scale 1↔1.03; gated by `AnimConfig` tier |
| `Tune` | Chip selection, tab switch, quality fallback toggle | 200ms | Spring, 8% overshoot | Snap-to-notch feel |
| Sheet entrance | Any `RaddSheet` open | 260ms | Cubic `(0.16, 1, 0.3, 1)` | No bounce — sheets feel solid |
| Sheet dismiss | Swipe-down / scrim tap | 200ms | Cubic `(0.4, 0, 1, 1)` (accelerate) | |
| Card press | Any `RaddCard` tap | 120ms down / 160ms up | `Tune` curve | Scale 1→0.96→1 |
| Hero transition | Card → Detail navigation | 320ms | Cubic `(0.2, 0, 0, 1)` | Shared-element `Hero`, poster art only |
| Rail stagger | Rail enters viewport | 40ms delay per item, 240ms each | Ease-out | Cap stagger at first 6 visible items |
| Onboarding chip select | Tap | 200ms | `Tune` | Fill + label color crossfade |
| Lock numpad key | Tap | 220ms | Spring, 12% overshoot | Deliberately more playful than sheets — small, frequent, low-stakes interaction |
| Bottom nav active icon swap | Tab change | 180ms | Ease | Icon crossfade outline→fill, no bounce |
| Empty-state icon | On screen mount | 1800ms loop, starts after 400ms delay | `Pulse` params | Delay avoids visual clutter during initial load |

Device-tier gating (existing `AnimConfig`): Potato tier disables `Pulse` scale component and rail stagger delays (opacity/instant only); Premium tier enables all effects including hero parallax micro-motion on scroll.

## Rules (see also Volume X)

- Never animate more than three elements simultaneously in one transition.
- Infinite/looping animation is reserved for exactly three cases: `Pulse`, download progress rings, and live-session indicators (Watch Party).
- Reduced-motion setting disables `Pulse` scale and `Tune` overshoot app-wide, falling back to instant or opacity-only transitions.
