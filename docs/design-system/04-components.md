# Volume IV — Components

The component catalog: a finite, named vocabulary of components that any future feature reuses instead of inventing new UI.

## RaddButton

| Variant | Fill | Text/Icon | Use case |
|---|---|---|---|
| **Signal** | `signal.primary` solid | White, w700 | The one primary action per screen: Play, Continue, Confirm |
| **Ghost** | `glass` (8% white), 1px border | `content.primary` | Secondary actions: Watchlist, Cancel |
| **Tonal** | `signal.primary` @ 12% fill | `signal.primary` text | Medium-emphasis actions alongside a Signal button on the same screen |
| **Icon** | `glass` circular, 44dp | `content.secondary` outline / `signal.primary` fill when active | Toolbar/HUD actions (share, more, CC) |
| **Destructive** | `accent.error` @ 12% fill, 1px border | `accent.error` text | Remove from Watchlist, Delete Download, Clear History |
| **Success** | `accent.dataFree` @ 12% fill | `accent.dataFree` text | Confined to data-free/zero-rating confirmations only |
| **Floating** | `signal.primary` solid, circular, 56dp, elevated glow | White icon | Rare, single-purpose FABs where no persistent bottom bar exists |

Sizes: small=40dp / medium=48dp / large=52dp. Base spec (all variants): height per size, `pill` radius, 24dp horizontal padding, press scale 0.97/120ms, disabled = 40% opacity.

## RaddCard

One base geometry (2:3 poster, `md` radius, `cardBorder` outline, `Tune` press scale) with content-driven variants:

| Variant | Distinguishing elements | Screens |
|---|---|---|
| Movie/Show Card | Base card + optional signal-free badge | Home rails, Search results |
| Episode Card | 16:9, thumbnail + title + runtime row below, no badge | Show Detail episode list |
| Continue Watching Card | Base card + bottom progress bar (3dp, `signal.primary` on `glass` track) | Home "Continue Watching" rail |
| Collection Card | Wider (3:2), stacked-poster composite art | Home curated collections |
| Actor Card | Circular avatar, name below | Detail cast rail |
| Folder Card | 1:1, folder-glyph placeholder, item-count badge | Local Media / Downloads |
| Recommendation Card | Base card + "Because you watched X" strip | Detail "More Like This" |
| Hero Card | Full-bleed, no border/radius | Home hero |
| Compact Card | 3:4.5, taller/narrower | Tablet/desktop dense grids |
| Mini Card | 96×144dp fixed, no title | Search recent searches, Player "Up Next" |

Signal-free badge: 20×20dp pill, top-right, 6dp inset, `accent.dataFree` fill, white checkmark icon 12dp.

## RaddBanner

One shared shell (44dp height, slide-down entrance, dismiss action) with a fixed semantic palette per variant:

| Variant | Fill | Icon | Trigger |
|---|---|---|---|
| Offline | `accent.warning` @ 12% | wifi-off | Connectivity provider reports offline |
| Downloading | `signal.primary` @ 12% | download, animated ring | Active background download |
| Subscription | `accent.warning` @ 12% | crown/star | Plan expiring, quota threshold |
| Free Data | `accent.dataFree` @ 12% | signal/bolt | Entering a zero-rated session (once per session) |
| Update Available | neutral glass | arrow-up | New app version |
| Watch Party | `signal.primary` @ 12%, `Pulse` on icon | people | Party invite/active session |
| Sync | neutral glass, spinner | — | Profile/watchlist sync in progress |
| Warning | `accent.warning` @ 16% | triangle-alert | Generic non-fatal warning |
| Error | `accent.error` @ 16% | circle-alert | Generic fatal/blocking error, no auto-dismiss |

Rule: only one banner visible at a time — priority queue Error > Subscription > Offline > everything else.

## RaddSheet

Single shared component for all modals/bottom sheets.
- Drag handle: 32×4dp, `content.muted`, 12dp top margin, centered.
- Header: `title` scale label, optional trailing close icon, 16dp padding.
- Background: `elevation.sheet` (blur sigma 20, `surfaceHigh` @ 92%, 1px top border).
- Corner radius: `lg` top corners only, full-bleed to screen edges. Max height 85% viewport.
- Sub-variants: `RaddSheet.tabbed` (Player "More", Filters) and `RaddSheet.list` (Settings sub-screens).

## RaddLockPad

One component, two skins driven by a single `accent` param: `signal.primary` for standard app lock, purple→crimson gradient for Vault — same geometry, motion, and layout throughout. Numpad key: 64×64dp circle, `glass` @ 7% fill, 1px border, elastic scale-in on tap.

## SettingsRow

Single row primitive: leading icon (24dp) + label (`body`) + trailing (chevron / switch / value text), 56dp height. Every settings-style list in the app renders from this, no exceptions.

## RaddTextField

Height 52dp, `md` radius, `surface` fill, 1px `border`, focus state → 1.5px `signal.primary`. Error state: border → `accent.error`, helper text in `accent.error`.

## RaddChip

Height 36dp, `pill` radius, 16dp horizontal padding. Inactive: `glass` fill, `content.secondary` text. Active: `signal.primary` fill, white text, transition via `Tune`. Mood-search "Free tonight" variant uses `accent.dataFree` fill instead of crimson when active — deliberate exception to keep signal-green meaningful.
