---
name: RaddFlix Project Overview
description: Full architecture, stack, file map, and current server state for RaddFlix
---

# RaddFlix Project Overview

## What It Is
Pakistani streaming platform. Jazz SIM users stream movies/dramas FREE because video is served via JazzDrive (cloud.jazzdrive.com.pk) which Jazz zero-rates at network level.

## Stack
| Layer | Tech |
|-------|------|
| Mobile app | Flutter/Dart, Riverpod, Dio, media_kit, SQLCipher |
| Backend API | Python 3.12, Flask, SQLite (WAL mode) |
| Video CDN | JazzDrive (cloud.jazzdrive.com.pk) |
| Server | Oracle Cloud, ubuntu@92.4.95.252 |
| CI | GitHub Actions (build-apk.yml + ci-tests.yml) |

## Repository Structure
```
raddclub/raddflix-app (main branch)
├── raddflix_flutter/          ← Flutter app (REAL app — use this)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── core/
│   │   │   ├── api/           ← api_client.dart, catalog_api.dart, history_api.dart
│   │   │   ├── db/            ← local_db.dart, sync_service.dart
│   │   │   ├── services/      ← jazzdrive_service.dart, poster_service.dart, etc.
│   │   │   ├── security/      ← app_guard.dart, keystore.dart, device_id.dart
│   │   │   └── constants.dart ← ApiPaths + AppColors (BUG-F02: colors in wrong class)
│   │   ├── providers/         ← catalog_provider.dart, auth_provider.dart
│   │   ├── screens/           ← 23+ screens
│   │   └── widgets/
│   │       └── player/        ← 12 player widgets
│   ├── android/
│   │   └── app/src/main/kotlin/.../MainActivity.kt
│   └── pubspec.yaml
├── radd-hub/                  ← Flask backend
│   └── hub/
│       ├── app.py             ← Flask app + XorWsgiMiddleware
│       ├── db.py              ← DB init + DDL
│       ├── routes/
│       │   ├── catalog_api.py
│       │   ├── library.py
│       │   ├── mobile_api.py
│       │   ├── subscriptions.py
│       │   ├── delta_push.py
│       │   └── request_encoding.py
│       └── _legacy/           ← REQUIRED files (8 files) — missing = ImportError
└── agent-hub/                 ← Agent coordination (on GitHub)
    ├── REINCARNATION.md       ← Full context — read every session
    ├── SKILLS.md              ← Rules + SSH/GitHub patterns
    ├── MASTER_TASKLIST.md     ← Current task queue
    ├── history/TASK_LOG.md    ← Session history
    └── memory/                ← Memory files
```

**WARNING:** Root `lib/` directory = dead JazzMAX/ZENO stubs. Real app = `raddflix_flutter/lib/`

## Current Server State (2026-06-03)
- Oracle commit: `a07e0bf7` — running (pid 593269)
- 24 titles published (is_published=1, is_ready=1): Pathaan, Salaar, Gadar 2, etc.
- 44/45 files have share_url populated (streaming works)
- All 24 titles: is_free=0 (no free content for guests)
- JazzDrive SAPI: 401 in server logs = server cannot upload NEW files (doesn't affect streaming)
- WA Bot: running but WhatsApp pairing pending

## Key Numbers
- Flutter DB version: 16 (next migration: `if (oldV < 17)`)
- APK fingerprint: `BA:4E:41:2D:F4:68:EF:60:41:05:24:CC:A4:24:77:70:83:7F:E9:C1:29:46:D0:18:35:3D:64:88:1C:E5:CD:07`
- Subscription plans: Basic Rs.149/30GB, Standard Rs.249/50GB, Premium Rs.399/100GB

## Known Open Issues (Non-Bug)
| # | Issue | Priority |
|---|-------|----------|
| R1 | Wire accent color + seekBarStyle into player seek bar | High |
| R2 | All 24 titles is_free=0 — no free content for guests | Medium |
| R3 | folder_share_url=NULL for all titles | Low |
| R4 | SSL/HTTPS — self-signed cert — need Let's Encrypt when domain ready | Low |
| R5 | WA Bot WhatsApp pairing pending | Low |
| R6 | JazzDrive SAPI 401 — cannot upload new files (streaming fine) | Low |
| R7 | CI auto-deploy always fails — manually pull on Oracle after every push | Known |
