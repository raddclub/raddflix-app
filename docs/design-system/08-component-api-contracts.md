# Volume VIII — Flutter Component API Contracts

The "developer contract" — every component in Volume IV gets this treatment when implemented: Properties, Behavior (Disabled/Loading/Accessibility/Animation), Theme Tokens Used, Examples. Below are the reference contracts for the core components; use them as the template for the rest.

## RaddButton

**Properties**
| Name | Type | Default | Notes |
|---|---|---|---|
| `variant` | `RaddButtonVariant` (signal/ghost/tonal/icon/destructive/success/floating) | `signal` | Drives fill/text/border from theme tokens, never hardcoded |
| `size` | `RaddButtonSize` (small=40dp/medium=48dp/large=52dp) | `medium` | |
| `label` | `String?` | `null` | Required unless `variant == icon` |
| `leadingIcon` / `trailingIcon` | `PhosphorIconData?` | `null` | 20dp, 8dp gap from label |
| `loading` | `bool` | `false` | Replaces label with spinner, preserves button width |
| `enabled` | `bool` | `true` | Disabled = 40% opacity, `onPressed` ignored, no haptic |
| `fullWidth` | `bool` | `false` | |
| `pulse` | `bool` | `false` | Applies `Pulse` motion — reserved for live/urgent CTAs only |
| `tooltip` | `String?` | `null` | Required when `variant == icon` with no visible label |
| `heroTag` | `Object?` | `null` | For shared-element transitions (rare on buttons) |
| `onPressed` | `VoidCallback?` | — | `null` implies disabled state automatically |

**Behavior**
- *Disabled:* opacity 40%, `onPressed` short-circuited before callback logic runs, semantics marked `enabled: false`.
- *Loading:* `onPressed` disabled during load; spinner uses the variant's text color; minimum 400ms display even if the action resolves faster (prevents flicker).
- *Accessibility:* minimum 44×48dp hit area regardless of visual `size`; `Semantics(button: true, label: ...)`; icon-only buttons require `tooltip`.
- *Animation:* press scale 0.97 over 120ms (`Tune` curve) on pointer-down, reverses on pointer-up/cancel.
- *Theme tokens used:* `signal.primary`, `glass`, `accent.error`, `accent.dataFree`, `RaddType.label`, `RaddSpace.md`.
- *Example:*
```dart
RaddButton(
  variant: RaddButtonVariant.signal,
  label: "Play",
  leadingIcon: PhosphorIcons.play,
  fullWidth: true,
  onPressed: () => player.start(),
)
```

## RaddCard

**Properties**
| Name | Type | Default |
|---|---|---|
| `variant` | `RaddCardVariant` | `movie` |
| `imageUrl` | `String` | required |
| `title` | `String?` | `null` |
| `isDataFree` | `bool` | `false` |
| `progress` | `double? (0.0–1.0)` | `null` |
| `onTap` | `VoidCallback` | required |
| `heroTag` | `String` | required for `movie`/`hero` variants |

**Behavior**
- *Disabled:* not applicable — if content is unavailable, don't render the card (use an empty state instead).
- *Loading:* geometry-matched shimmer skeleton until `imageUrl` resolves; never a generic gray box.
- *Accessibility:* `Semantics(label: "$title, $variant")`; `isDataFree` appends ", data-free" to the label rather than relying on color alone.
- *Animation:* press scale 0.96/120ms; `Hero` transition only on `movie`/`hero` variants.
- *Theme tokens used:* `RaddSpace.sm`, `md` radius, `cardBorder`, `accent.dataFree`.
- *Example:*
```dart
RaddCard(
  variant: RaddCardVariant.continueWatching,
  imageUrl: show.thumbnailUrl,
  title: show.title,
  progress: show.watchProgress,
  isDataFree: show.isZeroRated,
  heroTag: 'card-${show.id}',
  onTap: () => Navigator.push(...),
)
```

## RaddSheet

**Properties**
| Name | Type | Default |
|---|---|---|
| `style` | `RaddSheetStyle` (list/tabbed) | `list` |
| `title` | `String` | required |
| `tabs` | `List<RaddSheetTab>?` | `null` (required if `style == tabbed`) |
| `initialTab` | `int` | `0`, or last-persisted tab if applicable (Player "More") |
| `maxHeightFraction` | `double` | `0.85` |
| `dismissible` | `bool` | `true` |
| `onDismiss` | `VoidCallback?` | `null` |

**Behavior**
- *Accessibility:* traps focus while open; drag handle marked `excludeSemantics`; first focusable element in content receives initial focus.
- *Animation:* entrance 260ms cubic `(0.16,1,0.3,1)`, dismiss 200ms cubic `(0.4,0,1,1)`; tab switch uses `Tune` (200ms) horizontal crossfade.
- *Interaction rule (Volume X):* never stack — opening a `RaddSheet` while one is already open must dismiss the first, not layer a second.
- *Theme tokens used:* `elevation.sheet`, `lg` radius (top corners), `content.muted`.

## RaddBanner

**Properties**
| Name | Type | Default |
|---|---|---|
| `variant` | `RaddBannerVariant` | required |
| `message` | `String` | required |
| `actionLabel` | `String?` | `null` |
| `onAction` | `VoidCallback?` | `null` |
| `dismissible` | `bool` | `true`, forced `false` for `error` until resolved/retried |

**Behavior**
- *Priority queue:* only one banner renders at a time; `error` > `subscription` > `offline` > all others; lower-priority banners queue silently rather than being dropped.
- *Accessibility:* announced via `SemanticsService.announce` on appearance.
- *Animation:* slide down/up 220ms `Tune`.
- *Theme tokens used:* fixed per-variant palette from Volume IV — never an arbitrary color.

The same seven-section template applies to `RaddLockPad`, `SettingsRow`, `RaddTextField`, and `RaddChip` when they're implemented — write their contracts here as each one is built.
