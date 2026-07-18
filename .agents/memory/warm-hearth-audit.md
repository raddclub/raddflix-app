---
name: Warm Hearth theme audit
description: Full audit of Warm Hearth palette and all other themes completed 2026-07-18; what was fixed and what remains intentional
---

## Fixed in commit 6febd59e (2026-07-18)

### Critical
- `sync_panel.dart` — Reset button bg was old red `0x22E8002D` → `0x22D4784A` (Warm Hearth primary glow)

### Player panel cold-color sweep (midnight/neutral darks → Warm Hearth tokens)
- `player_settings_screen.dart` — scaffold `0xFF0D0D1A`, appbar `0xFF12121E`, dialog `0xFF1E1E2E`, section container `0xFF12121E`
- `video_enhance_panel.dart` — panel bg `0xFF0F0F1A`
- `video_enhance_suite.dart`, `speed_picker_sheet.dart`, `zoom_crop_overlay.dart` — `0xFF12121E`
- `word_definition_sheet.dart` — `0xFF141420`
- `speed_presets_sheet.dart` — `0xFF161616`
- `_ps_panels_sidebar.dart` — card bg `0xFF0D1117`
- `_ps_panels_audio.dart` — dialogs `0xFF1C1C1C` (×2), EQ unselected `0xFF2A2A2A`
- `_ps_playback_mixin.dart` — dialogs `0xFF1C1C1C` (×2), snackbar `0xFF2A2A2A`, Resume text `0xFFE8950A`→primary
- `_ps_panels_subtitle.dart` — AI preview card gradient `0xFF0D1F35/0xFF122012/0xFF1F0D35`
- `resume_fab.dart` — `0xFF1A1A1A`, `0xFF2C2219`
- `end_of_video_actions.dart`, `frame_navigation_service.dart`, `shared_bookmarks_service.dart`, `watch_party_service.dart` — `0xFF1C1C1C`, `0xFF1E1E1E`, `0xFF1A1A1A`

### Warm Hearth hex literals → AppColors named tokens
- `layout_designer_screen.dart`, `debug_diagnostics_screen.dart`, `app_lock_screen.dart`, `home_screen.dart`

### Semantic color token misses
- `splash_screen.dart` — logo RadialGradient used literal hex instead of `AppColors.primary/primaryDark`
- `profile_screen.dart` — subscription remaining days used `0xFFFFB300`/`0xFF00C853` instead of `AppColors.warning/success`
- `login_screen.dart` — "or" divider used `Color(0x33FFFFFF)` instead of `t.border`

## Intentional / by design (do NOT change)
- Player overlay whites (`Colors.white12/24/38/54/70`) — overlays on video, brightness-independent
- `subtitle_style.dart` — subtitle preset colors (`0xFFFFEB3B`, `0xFF111111`, etc.) — user-selectable presets
- `subtitle_hunter_sheet.dart` — info blue `0xFF4DB6FF`, purple badge, blue download button — AI subtitle service branding
- `debug_diagnostics_screen.dart` log category colors — semantic color coding (green/blue/purple/cyan/amber)
- `profile_switcher_screen.dart` avatar palette — intentional multi-color user avatar options
- `simosa_card.dart` / `simosaAccent` — Simosa partner brand colors
- `tier_badge.dart` — plan tier badge colors (gold/silver/grey)
- `radd_lock_pad.dart` — vault purple gradient `0xFF7C3AED` — Vault branding
- `_ps_panels_audio.dart` EQ preset selected `0xFF3A6ECC` — blue is conventional EQ hardware indicator
- `search_screen.dart` genre gradient dark ends — decorative card gradients, aesthetic choice
- All WhatsApp `0xFF25D366` references — brand color, should stay

## Theme system summary
- 9 themes: dark (Warm Hearth default), amoled, light, midnight, navy, forest, cobalt, rose, charcoal
- Brand colors live in `AppColors` (constants.dart) and `BrandThemeState.defaults` (brand_theme_provider.dart) — must stay in sync
- `AppGradients.hero` and `AppColors.heroGradient` hardcode `0xFF130F0C` (Warm Hearth bg) — these are used for hero overlays on content cards; on non-Warm-Hearth themes the hero fade won't match the bg exactly (minor visual issue, not worth fixing without full gradient token system)
- AMOLED theme uses Warm Hearth text colors (cream/tan) — intentional, warm text on OLED black
