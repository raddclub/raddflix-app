# RaddFlix Agent Task Board

_Last updated: 2026-06-16_

## Completed This Session (2026-06-16)

| ID | Changed | Summary |
|----|---------|---------|
| ✅ BUG-LOGIN-01 | `raddflix_flutter/lib/screens/login_screen.dart` | Wrong password always navigated to home as guest. Root cause: `auth_provider.login()` never throws — catches DioExceptions and sets `state.error`. Fix: added `if (s.error != null) { setState(() { _error = s.error; _loading = false; }); return; }` before navigation. |
| ✅ BUG-CATALOG-STALE | Oracle DB (`settings.catalog_forced_version`) | Stale share_urls / file_ids in users' local SQLite causing "link expired" and missing play buttons. Fix: bumped `catalog_forced_version` to `1781620750` — forces full re-sync on next open. |
| ✅ TASK-DEBUG-01 | `debug_diagnostics_screen.dart`, `profile_screen.dart`, `jazzdrive_service.dart` | Debug screen now accessible in release builds. Entry: tap version text 5× in Profile. Added live JazzDrive chain test (login→media→CDN URL confirmed), JAZZDRIVE log filter, and `JazzDriveService.diagnosticTest()` public method. Build 1053 ✅ |
| ✅ TASK-JD-LIVE | Oracle + JazzDrive API (live test) | Full chain proven with real video bytes: S01E01 and Euphoria both returned HTTP 206 · `video/mp4` · ftyp isom · 65536 bytes. Not fake URLs. |

## Open / In Progress

_No open tasks._

## Pending / Blocked

_Nothing blocked._
