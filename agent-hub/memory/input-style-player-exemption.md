---
name: Input style — player overlay exemption
description: Which TextFields are exempt from the login-page RaddTextField visual spec, and why.
---

## Rule

All `TextField` widgets inside the fullscreen video player layer use **white-on-dark** styling and are **permanently exempt** from the login-page `RaddTextField` spec. Do not change their colours, borders, or fill to match `t.surface`/`t.border`/`AppColors.primary`.

## Exempt files (as of 2026-07-29)

| File | Context |
|---|---|
| `widgets/player/jump_to_panel.dart` | Player overlay — dark warm bg, white text |
| `widgets/player/jump_to_sheet.dart` | Player overlay — dark warm bg, white text |
| `widgets/player/sleep_timer_sheet.dart` | Player overlay — dark warm bg, white text |
| `widgets/player/color_picker_sheet.dart` | Player overlay — dark warm bg, white text |
| `core/subtitles/subtitle_hunter_sheet.dart` | Player overlay — dark warm bg, white text |
| `core/player/frame_navigation_service.dart` | AlertDialog inside player — `Color(0xFF2C2219)` bg |
| `core/player/shared_bookmarks_service.dart` | Bottom sheet inside player — `Colors.white.withOpacity(0.07)` fill |
| `core/player/watch_party_service.dart` | Player overlay modal — dark bg, `_inputDeco()` helper |
| `screens/player/_ps_panels_subtitle.dart` | Subtitle + saved-words panels inside player |
| `screens/player/_ps_ui_mixin.dart` | Jump-to-position dialog + channel search inside player |

## Also exempt (different reason)

| File | Reason |
|---|---|
| `screens/search_screen.dart` | Deliberate premium glass-pill with `BackdropFilter` + animated glow — intentionally more polished than standard fields |

## Login-page spec (for non-exempt screens)

- Height **52dp**, `AnimatedContainer` with `duration: 180ms, curve: Curves.easeOutCubic`
- Fill: `t.surface`
- Border at rest: `t.border`, **1px**
- Border on focus: `AppColors.primary`, **1.5px**
- Corner radius: `RaddRadius.mdRadius`
- Inner `TextField`: all Flutter-native borders cleared (`InputBorder.none` for border/enabledBorder/focusedBorder), `isCollapsed: true`, `filled: false`

**Why:** The player UI lives over a dark video surface — forcing light-bg `t.surface` inputs there would make them look wrong and reduce readability against video frames. The glass-pill search screen is a deliberate premium design decision made by the owner.

**How to apply:** Before touching any `TextField`, check whether it lives inside `lib/widgets/player/`, `lib/core/player/`, or `lib/screens/player/`. If yes → leave as-is. If no, and it's not `search_screen.dart` → apply the login-page spec.
