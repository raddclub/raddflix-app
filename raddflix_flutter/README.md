# RaddFlix Flutter App

Flutter Android app for the RaddFlix streaming platform.

**Package ID:** `com.raddflix.app`  
**Min Android SDK:** 21 (Android 5.0)  
**Target SDK:** 36  
**Flutter version (CI):** 3.22.x  

## Build

APK is built automatically by GitHub Actions on every push to `main`:  
→ `.github/workflows/build-apk.yml`

Download the latest APK from:  
**GitHub → Actions → Build RaddFlix APK → latest successful run → Artifacts**

To build locally:
```bash
cd raddflix_flutter
flutter pub get
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

## Key Folders

```
lib/
├── core/
│   ├── api/          ← HTTP client (Dio + XOR encoding)
│   ├── db/           ← Local SQLite (SQLCipher AES-256) + sync
│   ├── services/     ← JazzDrive stream links, poster cache
│   ├── security/     ← Device ID, Android Keystore wrapper
│   ├── player/       ← Player prefs, A-B loop, bookmarks
│   └── theme/        ← App colors, text styles
├── models/           ← Data models (Title, Episode, User, etc.)
├── providers/        ← Riverpod state (catalog, auth, subscription)
├── screens/          ← All app screens
│   └── player/       ← Video player (player_screen.dart)
└── widgets/          ← Shared UI components
android/
├── app/build.gradle  ← compileSdk 36, signing config (KEYSTORE_* env vars)
└── gradle-wrapper    ← Gradle 8.3
```

## Important Notes

- **SQLCipher pin:** `sqflite_sqlcipher: 3.1.0+1` — do NOT upgrade until CI uses Flutter 3.27+
- **DB version:** `catalogDbVersion = 17` — next migration uses `if (oldV < 18)`
- **Migration param:** must be `oldV` (not `oldVersion`) — compile error if wrong
- **XOR encoding:** all API requests/responses are XOR-encrypted — both sides must stay in sync
- **Android 8 compat:** no raw SQL `ON CONFLICT DO UPDATE` — use `ConflictAlgorithm.replace`
- **VideoController:** NEVER add `androidAttachSurfaceAfterVideoParameters: true` (3-5s black screen)
- **JazzDrive Pass3:** Dart backslash-dollar in non-raw strings = literal $, not interpolation — use concatenation
- **Local file quota:** `_checkQuota()` has `&& widget.fileId.isNotEmpty` guard — do not remove

## Test Suite

```bash
# JazzDrive logic (27 tests, no Jazz SIM needed)
node test_suite/jazzdrive_logic_test.js

# Full server integration tests
node test_suite/run_tests.js

# Business logic (pure Dart)
dart run test_suite/logic_tests.dart
```

## Architecture docs

→ [`agent-hub/STREAMING_ARCHITECTURE.md`](../agent-hub/STREAMING_ARCHITECTURE.md)  
→ [`agent-hub/ZERO_RATING_DELTA.md`](../agent-hub/ZERO_RATING_DELTA.md)  
→ [`agent-hub/PLAYER_SPEC.md`](../agent-hub/PLAYER_SPEC.md)
