# RaddFlix Agent Handoff

## Current State (2026-07-01)

### Oracle
- Flask: RUNNING ✅ healthz: {"ok":true,"version":"3.0.0"}
- DB: schema current (display_name/email/avatar_color/avatar_emoji + all Phase 26 columns)
- Endpoints: PUT /api/auth/profile, POST /api/auth/change-password, GET /api/quota all live

### Flutter / APK
- Latest successful build: Phase 60 (P60 + Kotlin 2.2.0 + minSdk 24 fixes) ✅ CI PASSING · commit 98323a8
- All compile errors resolved
- Phases 17–37 fully merged and building clean

### What was fixed in Phase 37 (2026-06-29)
1. **Share button removed** — `show_detail_screen.dart`: stripped import + SliverAppBar actions block
2. **Quality picker removed** — `settings_screen.dart`: only one fixed video source, no user choice
3. **Free-content gate bug fixed** — 4 call sites in `show_detail_screen.dart` now OR with `widget.item.isFree` so free content is always free even if API episodes lack explicit `is_free:1`
4. **Player transport row overlap fixed** — `player_screen.dart`: Stack centering replaces broken fixed SizedBox(108) right zone
5. **Theme picker cut off fixed** — `profile_screen.dart`: isScrollControlled:true + DraggableScrollableSheet; all 10 themes visible
6. **share_plus kept in pubspec** — `debug_logger.dart` uses `Share` API to export crash logs; only the UI share button was removed

### What was added in Phase 60 (2026-07-01)
1. **Dub Active indicator** — `_AudioTrackPanel` now shows a green-bordered card at the top of its list when `_isDubMode == true`, displaying the active language flag + label
2. **Remove Dub button** — single tap in the Audio Panel calls `_disableDubMode()` and dismisses the panel — no need to reopen the subtitle/dub panel
3. **New props** — `isDubMode`, `dubActiveLang`, `onRemoveDub` added to `_AudioTrackPanel` (all optional / have defaults)

### Build fixes applied alongside Phase 60 (2026-07-01)
- **Kotlin 2.2.0** — bumped `ext.kotlin_version` from `1.9.20` → `2.2.0` in `android/build.gradle` (flutter_tts 4.2.5 stdlib uses Kotlin 2.2.x metadata)
- **minSdkVersion 24** — bumped from 21 → 24 in `android/app/build.gradle` (flutter_tts 4.2.5 declares minSdk 24 in its manifest; Android 5/6 dropped — <2% of Pakistani market)
- Both fixes address a pre-existing break introduced in Phase 59 (flutter_tts was added but build never ran green)

### Open Tasks
None — Phase 60 complete + build green. Awaiting next task from user.

### Known Data Issues
- DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 — upload to JazzDrive + sync still needed

### Key Rules (NEVER BREAK)
- Never add `androidAttachSurfaceAfterVideoParameters: true` (black screen on MediaTek)
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Oracle git pull: always `git stash && git pull && git stash pop`
- Push files SEQUENTIALLY — never parallel (SHA race condition)
- Use `db.setting(k)` not `db.get_setting(k)`
- `DebugDiagnosticsScreen` is intentionally NOT gated by `kDebugMode`
- `ImageCache.clearLive()` does NOT exist in this Flutter version — use `PaintingBinding.instance.imageCache.clear()`
- CachedNetworkImage uses `errorWidget:` not `errorBuilder:`
