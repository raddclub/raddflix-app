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
| `PlayerSettingsScreen` (indigo palette, 35+ flat options) | Split into Settings hub "Playback" section + Player "More" sheet Playback tab | Split & refactor |
| `VaultSettingsScreen` | Settings hub "Privacy & Vault" section | Refactor (routing only, logic unchanged) |
| `eq_panel`, `audio_lab_panel`, `audio_mixer_sheet`, `video_enhance_panel` | One `RaddSheet` "Audio & Video" tab with internal sections | Merge |
| `speed_picker_sheet`, `speed_presets_sheet` | One control in "Playback" tab | Merge |
| Player sidebar (`_buildSidebar`, up to 20 slots) | "Extras" tab, default 5-6 shown, rest under "Customize" | Replace default surface, keep logic |
| `bookmark_panel`, `scene_bookmarks_panel` | One "Bookmarks" entry in Extras tab | Merge |
| `jump_to_panel`, `jump_to_sheet` | One "Jump To" entry in Extras tab | Merge |
| Generic `AlertDialog` usages (if any) | `RaddSheet` | Replace |
| Ad hoc bottom-sheet styling per player panel | `RaddSheet` shared shell | Replace shell, keep internal content widgets |
| Hardcoded padding/font-weight literals across screens | `RaddSpace` / `RaddType` tokens | Refactor incrementally, screen by screen |
| `home_screen.dart`, `show_detail_screen.dart` monoliths | Componentized per Volume V wireframes | Refactor (split into sub-widgets matching wireframe sections) |

## Suggested Build Order

Tokens (`RaddType`/`RaddSpace`/color additions) → `RaddSheet` + `RaddLockPad` + `SettingsRow` (shared primitives, everything else depends on them) → Settings hub migration → Player HUD/sheet consolidation → Home hero redesign → Show Detail componentization → Onboarding taste-capture + brand moment.

This mirrors the phase plan in `ROADMAP.md` — update both together if the order changes.
