# RaddFlix — Master Plan & Task History

## Phase History

| Phase | Name | Status | Date |
|-------|------|--------|------|
| P1 | Core streaming + admin panel | ✅ Done | — |
| P2 | JazzDrive integration | ✅ Done | — |
| P3 | Subscriptions + user management | ✅ Done | — |
| P4 | Domain doctor + self-heal | ✅ Done | — |
| P5 | Mobile API (auth, billing, notifications) | ✅ Done | — |
| P6 | **Brand Studio** | ✅ Done | 2026-06-01 |

## P6 Brand Studio — Completed Tasks

### Part 1 ✅ — Flask Blueprint
- File: `radd-hub/hub/routes/brand_studio.py`
- Routes: GET /brand/, GET+POST /api/brand/config, POST /api/brand/save,
  POST /api/brand/upload-image, GET /brand/assets/<filename>,
  GET /api/brand/build-status, POST /api/brand/trigger-build
- Brand config stored in SQLite `settings` table (7 brand_ keys)
- Brand assets stored in `DATA_DIR/brand_assets/`

### Part 2 ✅ — Admin Template
- File: `radd-hub/hub/templates/brand_studio.html`
- 3 tabs: Live Config (colors, tagline, logo URL, onboarding JSON editor),
  Icon & Splash (upload + 3 shape previews + phone mockup), Build (trigger + poll)
- Real-time preview updates on color/tagline change
- Build status polled every 8 seconds, APK artifact link shown on success

### Part 3 ✅ — Extend /api/config
- File: `radd-hub/hub/routes/api.py`
- Added: brand_primary_color, brand_tagline, brand_logo_url,
  brand_splash_color, brand_onboarding_pages to /api/config JSON

### Part 4 ✅ — Register blueprint
- File: `radd-hub/hub/app.py`
- Added brand_studio import and `app.register_blueprint(brand_studio.bp)`

### Part 5 ✅ — Sidebar
- File: `radd-hub/hub/templates/base.html`
- Added 🎨 Brand Studio link under APP section

### Part 6 ✅ — Flutter remote_config.dart
- File: `raddflix_flutter/lib/core/remote_config.dart`
- Reads all 5 brand_ fields from /api/config
- Caches individually to SharedPreferences
- Added static convenience getters: getBrandPrimaryColor, getBrandSplashColor,
  getBrandTagline, getBrandLogoUrl, getBrandOnboardingPages

### Part 7 ✅ — Flutter onboarding_screen.dart
- File: `raddflix_flutter/lib/screens/onboarding_screen.dart`
- Loads pages from brand_onboarding_pages JSON in SharedPreferences
- Falls back to hardcoded _kDefaultPages on any error/empty

### Part 8 ✅ — Flutter splash_screen.dart
- File: `raddflix_flutter/lib/screens/splash_screen.dart`
- Reads brand_splash_color from SharedPreferences
- Applies to Scaffold backgroundColor with animated transition
- Re-applies after fresh RemoteConfig.fetch()

### Part 9 ✅ — GitHub Actions build-apk.yml
- File: `.github/workflows/build-apk.yml`
- Added brand_build: true/false workflow_dispatch input
- Added "Apply brand assets" step (conditional on brand_build=true)
- Copies brand_assets/brand_icon.* → ic_launcher_foreground.png
- Copies brand_assets/brand_splash.* → assets/images/splash.png

## Next Possible Phases
- **P7**: Brand Studio v2 — commit brand assets to repo so CI can pick them up
- **P8**: Push notifications (FCM integration)
- **P9**: Analytics dashboard improvements
