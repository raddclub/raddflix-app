# Volume IX — Migration Guide

Maps existing Flutter widgets to their redesigned counterparts, so implementation becomes straightforward.

| Existing | Redesigned target | Action |
|---|---|---|
| `_HeroSpotlight` (multi-page auto-scroll) | On Air hero (single-item, swipeable, `Tune`) | Refactor |
| `ContentCard` | `RaddCard` (movie variant) + signal badge slot | Extend (add optional badge param) |
| `SimosaCard` | `RaddCard` provider-strip base | Reuse |
| `ResumeFab` | `RaddCard` (continueWatching variant) | Reuse |
| `RaddTextField` (existing) | `RaddTextField` w/ focus-border token | Reuse |
| `AnimatedEmptyIcons` | Unchanged, apply `Pulse` timing spec | Reuse + standardize timing |
| `NotificationBanner` / `OfflineBanner` | `RaddBanner` | Reuse + apply banner token spec |
| `PinLockScreen` numpad | `RaddLockPad` | Replace |
| `VaultLockScreen` numpad | `RaddLockPad` (source of truth for styling) | Promote to shared component |
| `SettingsScreen` list | `SettingsRow` in unified hub | Refactor |
| `PlayerSettingsScreen` (indigo palette, 35+ flat options — **live**, separate pre-playback settings screen) | Split into Settings hub "Playback" section + Player "More" sheet Playback tab | Split & refactor |
| `VaultSettingsScreen` | Settings hub "Privacy & Vault" section | Refactor (routing only, logic unchanged) |

### Player — corrected 2026-07-08 (see `agent-hub/history/TASK_LOG.md` "Player docs correction")

Earlier drafts of this guide (and `IMPLEMENTATION_PLAN.md`) described the Player as 24 external sheet/panel files. **That was wrong.** A file-by-file import trace against the live `raddflix_flutter` code on 2026-07-08 found the real architecture is very different — the app author had already stripped those external files out of active use. Corrected rows below.

| Existing (verified live) | Redesigned target | Action |
|---|---|---|
| `_SubtitlePanel`, `_AudioTrackPanel`, `_VideoZoomPanel`, `_AudioEffectPanel` (private classes **inline inside** `player_screen.dart`) | One `RaddSheet` "Audio & Video" tab with internal sections (subtitles / audio track / zoom / EQ+lab as sub-sections) | Extract from inline classes into `RaddSheet`, then merge |
| `_QuickShortcutsPanel`, `_SettingsPanel` (inline in `player_screen.dart`) | "Playback" / "Extras" tabs | Extract + merge |
| `_SidebarCustomizerPanel` (inline in `player_screen.dart`) | "Extras" tab → "Customize" entry | Extract + refactor |
| Player sidebar (up to 20 slots, driven by `_SidebarCustomizerPanel`'s order list) | "Extras" tab, default 5-6 shown, rest under "Customize" | Replace default surface, keep logic |
| `color_picker_sheet.dart`, `theme_picker_sheet.dart` (**live** — imported by `PlayerSettingsScreen`, not by `player_screen.dart`) | Settings hub "Playback" section (theme/accent picker) | Reuse, re-host under Settings hub |
| **50 files in `lib/widgets/player/`** (`eq_panel`, `audio_lab_panel`, `audio_lab_sheet`, `audio_mixer_sheet`, `video_enhance_panel`, `video_enhance_suite`, `speed_picker_sheet`, `speed_presets_sheet`, `bookmark_panel`, `scene_bookmarks_panel`, `jump_to_panel`, `jump_to_sheet`, `cinematic_settings_sheet`, `player_hud_settings_sheet`, `quick_settings_panel`, `sleep_timer_sheet`, `silence_skip_sheet`, `smart_enhance_sheet`, `end_action_sheet`, `screenshot_share_sheet`, `gesture_map_sheet`, `sync_panel`, `word_definition_sheet`, `subtitle_overlay`, `ambilight_glow_border`, `cinematic_overlay`, `controls_background`, `ab_loop_panel`, `cast_panel`, `chapter_seek_bar`, `clip_trimmer`, `dual_subtitle_overlay`, `eq_visualizer`, `gesture_hint_overlay`, `immersive_overlay`, `intro_skip_editor`, `karaoke_overlay`, `media_info_overlay`, `network_speed_overlay`, `pip_overlay`, `playback_info_overlay`, `rage_skip_panel`, `reaction_stamps_overlay`, `track_badges`, `transparent_player_layer`, `zoom_crop_overlay`, `zoom_focus_overlay`, `binge_guard`, `picture_profiles_sheet`, `film_grain_overlay`) | N/A — **dead code, not part of the live app** (re-verified 2026-07-08 via full import trace across `lib/` and the test suite: none are imported by `player_screen.dart` or any live screen; only a dead sub-chain rooted at the never-imported `quick_settings_panel.dart` references a few of each other, incl. `picture_profiles_sheet.dart` and `film_grain_overlay.dart`) | **Do not migrate. Do not delete without explicit user approval** — user reviewed the full 50-file list on 2026-07-08 and declined to delete, since several (Sleep Timer, Cast, Zoom/Crop, etc.) look like intentionally-parked unshipped features rather than accidental cruft, not confirmed junk. Treat this list as informational (exclude from Player consolidation planning) unless the user later approves a deletion pass. See `TASKS.md` PLAYER-DEAD-CODE-CLEANUP for the closed decision record. |
| `seek_bar_painter.dart` | N/A — shared painter, used by `player_screen.dart` + `player_settings_screen.dart` | Leave as-is |
| Generic `AlertDialog` usages (if any) | `RaddSheet` | Replace |
| Ad hoc bottom-sheet styling per inline player panel | `RaddSheet` shared shell | Replace shell, keep internal content widgets |
| Hardcoded padding/font-weight literals across screens | `RaddSpace` / `RaddType` tokens | Refactor incrementally, screen by screen |
| `home_screen.dart`, `show_detail_screen.dart` monoliths | Componentized per Volume V wireframes | Refactor (split into sub-widgets matching wireframe sections) |

## Suggested Build Order

Tokens (`RaddType`/`RaddSpace`/color additions) → `RaddSheet` + `RaddLockPad` + `SettingsRow` (shared primitives, everything else depends on them) → Settings hub migration → Player HUD/sheet consolidation → Home hero redesign → Show Detail componentization → Onboarding taste-capture + brand moment.

This mirrors the phase plan in `ROADMAP.md` — update both together if the order changes.
