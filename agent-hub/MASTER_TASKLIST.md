# RaddFlix — Master Task List
> Last Updated: 2026-06-02 (Session 33 — Bug Audit + Docs Update)
> Read REINCARNATION.md first. Read CODE_MAP.md before touching any file.

---

## Status Key
- OK Done and verified
- WIP Built but has known gaps
- TODO Not started
- BLOCKED Blocked (reason noted)
- BUG Known bug needing fix

---

## Phase 0 — Infrastructure & CI

| # | Task | Status | Notes |
|---|------|--------|-------|
| 0.1 | GitHub Actions CI (build-apk.yml + ci-tests.yml) | OK | Running. Node 24, Java 17, Flutter 3.22.x |
| 0.2 | Oracle server (radd-hub port 5000 via nginx 80) | OK | raddflix_radd supervisor. Restarted 2026-06-02 pid 579642 |
| 0.3 | SSH from Replit to Oracle | OK | Use node key reformat (see SKILLS.md Rule 2). Python3 also works. |
| 0.4 | APK keystore | OK | SHA-256: BA:4E:41:2D:...:CD:07 |
| 0.5 | XOR encoding (Flutter + server) | OK | Both sides live. encode_response() accepts status param (fixed ae96f15e) |

---

## Phase 1 — Player (MX Player UI)

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1.1 | MX Player layout | OK | |
| 1.2 | 9 player features (ambilight, track badges, memory, etc.) | OK | |
| 1.3 | Cinematic mode | OK | Opacity(_cinematicOpacity) wrapper |
| 1.4 | Immersive mode | OK | One-tap pause, corner exit, time HUD |
| 1.5 | Cinematic opacity slider | OK | 15%–100% live preview |
| 1.6 | 24 player_screen bugs (BUG-P01..P24) | OK | Fixed Sessions 27–30 |
| 1.7 | Black screen on local video | OK | androidAttachSurfaceAfterVideoParameters: true (d78ec9b1) |
| 1.8 | Open With external video flow | OK | Fixed VideoController for external URIs |
| 1.9 | Vault lock bypass | OK | SHA-256 verification added |
| 1.10 | AudioMixerSheet type mismatch | OK | Fixed (f6143a7d) |
| 1.11 | SleepTimerSheet Duration nullable crash | OK | Fixed (5325153b) |

### Player Customisation (Phase A)

| # | Task | Status | Notes |
|---|------|--------|-------|
| A1 | Accent Color System (24 swatches + hex picker) | OK | color_picker_sheet.dart |
| A2 | 10 Seek Bar Styles (CustomPainter) | OK | seek_bar_painter.dart |
| A3 | 8 Bundled Themes (Sakura, Gold, Matrix, etc.) | OK | player_theme.dart |
| A4 | Theme picker sheet | OK | theme_picker_sheet.dart |
| A5 | Wire accent + seekBarStyle to player_screen.dart | TODO | Accent/seekbar still use hardcoded colors in player |
| A6 | Button/Icon Style System (ButtonShape: circle/squircle/rounded/pill) | TODO | Phase A3 in FEATURES_ROADMAP |
| A7 | Controls Background Style (glass/gradient/solid/mesh) | TODO | Phase A4 in FEATURES_ROADMAP |
| A8 | Drag & Drop Layout Designer | TODO | Phase B in FEATURES_ROADMAP |

---

## Phase 2 — Metadata Enrichment

| # | Task | Status | Notes |
|---|------|--------|-------|
| 2.1 | 6-tier fallback chain (TMDB/OMDB/AI/IMDbAPI/YouTube/Google KG) | OK | |
| 2.2 | metadata_lookup.py | OK | |
| 2.3 | metadata.py + organizer.py + downloader.py | OK | |

---

## Phase 3 — Poster System

| # | Task | Status | Notes |
|---|------|--------|-------|
| 3.1 | PosterService — permanent storage, never re-download | OK | |
| 3.2 | runBackgroundSync() — 100 posters/day | OK | fires once when CatalogStatus.ready |
| 3.3 | saveFromJazzDrive() | OK | |
| 3.4 | Use local poster_path in home_screen | OK | |

---

## Phase 4 — Security (SQLCipher + Keystore)

| # | Task | Status | Notes |
|---|------|--------|-------|
| 4.1 | sqflite_sqlcipher 3.1.0+1 | OK | NEVER upgrade until Flutter 3.27+ on CI |
| 4.2 | Android Keystore key generation | OK | |
| 4.3 | SQLCipher + Keystore key | OK | |
| 4.4 | JazzDrive share folder URLs encrypted | OK | |
| 4.5 | FlutterSecureStorage for auth tokens | OK | |

---

## Phase 5 — Mobile API

| # | Task | Status | Notes |
|---|------|--------|-------|
| 5.1 | Auth endpoints (register/login/refresh/logout/device) | OK | |
| 5.2 | Catalog sync + delta | OK | 24 published titles, 44 files with share_url |
| 5.3 | History API | OK | history_api.dart, watched_at in epoch seconds (multiply x1000) |
| 5.4 | Recommendations API | OK | GET /api/recommend |
| 5.5 | Download quota enforcement | OK | _checkDownloadQuota() before each download |
| 5.6 | Notifications | OK | read endpoint marks specific IDs not all |
| 5.7 | Domain Doctor | OK | /api/domain-doctor/health + /probe |

---

## Phase 6 — Brand Studio

| # | Task | Status | Notes |
|---|------|--------|-------|
| 6.1 | Flask blueprint brand_studio.py | OK | All routes: /brand/, /api/brand/* |
| 6.2 | Admin template brand_studio.html | OK | 3 tabs: Live Config, Icon & Splash, Build |
| 6.3 | Flutter reads brand config from /api/config | OK | Splash color, onboarding pages |

---

## Phase 7 — WhatsApp Bot

| # | Task | Status | Notes |
|---|------|--------|-------|
| 7.1 | Bot running | OK | raddflix_wa_bot supervisor |
| 7.2 | WhatsApp pairing | BUG | Pairing code rotates — check logs for current code |

---

## Known Issues / Remaining Work

| # | Issue | Priority |
|---|-------|----------|
| R1 | Wire accent color + seekBarStyle into player_screen.dart seek bar + play button | High |
| R2 | All 24 catalog titles is_free=0 — no free content for guests | Medium |
| R3 | folder_share_url=NULL for all titles | Low |
| R4 | SSL/HTTPS — self-signed cert — need Let's Encrypt when domain ready | Low |
| R5 | WA Bot WhatsApp pairing pending | Low |
| R6 | JazzDrive SAPI 401 — server cannot upload new files (does not affect streaming) | Low |

---

## Audit Bug Fixes (Sessions 38–39)

| ID | File(s) | Description | Status |
|----|---------|-------------|--------|
| AUDIT-08 | request_encoding.py | XOR hour-boundary: encode_response uses g.xor_session_key set by decode_request | OK |
| AUDIT-09 | jazzdrive_service.dart | warmTopFreeItems 60-min static guard — prevents 3x cold-start redundant calls | OK |
| AUDIT-10 | home_screen.dart | Removed duplicate PosterService.runBackgroundSync (catalog_provider is sole caller) | OK |
| AUDIT-11 | thumb_service.dart, local_media_service.dart | VideoThumbnail calls wrapped in try-catch | OK |
| AUDIT-12 | player_screen.dart | _qualityFromRes maps resolution → quality label; passed to UsageService | OK |
| AUDIT-13 | player_screen.dart | Removed duplicate speed_presets_sheet.dart import | OK |
| AUDIT-14 | request_encoder.dart | Updated stale comment — server IS deployed and active | OK |
| AUDIT-15 | profile_screen.dart | late final _connectivitySub lazy init — functional, no change needed | OK |
| AUDIT-16 | keystore.dart | clearAll() docs — cosmetic only | OK |
| AUDIT-17 | local_db.dart, player_screen.dart | _inlineShareUrl may be RF1:xxx encoded — added decodeShareUrl() + decode before JazzDrive | OK |
| AUDIT-18 | app.dart, local_folder_screen.dart | Player route: null-safe args cast; episodes List<Map<String,Object>> crash → Map<String,dynamic>.from() | OK |
| AUDIT-19 | player_prefs.dart | copyWith() missing channelBalance + abLoopEnabled in return body | OK |

---

## Phase 8 — Real-time Catalog Sync

| # | Task | Status | Notes |
|---|------|--------|-------|
| 8.1 | Foreground resume sync (WidgetsBindingObserver) | OK | 5-min debounce prevents hammering on quick screen cycles |
| 8.2 | 15-min foreground poll timer | OK | Timer.periodic in CatalogNotifier.initialize(); cancelled on dispose |
| 8.3 | Connectivity-restore sync | OK | Was already in CatalogNotifier; now co-exists with 8.1/8.2 |
| 8.4 | 6-hour WorkManager background sync | OK | callbackDispatcher top-level fn; ExistingWorkPolicy.keep |
| 8.5 | Post-sync silentRefresh (subscription/quota) | OK | authProvider.silentRefresh() after every successful SyncService.sync() |
| 8.6 | workmanager ^0.5.7 added to pubspec | OK | |
