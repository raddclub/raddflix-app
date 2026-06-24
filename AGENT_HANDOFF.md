# RaddFlix Agent Handoff

## Current State (2026-06-24)

### Oracle
- Flask: RUNNING ✅ healthz: {"ok":true,"version":"3.0.0"}
- DB: schema current, display_name/email/avatar_color/avatar_emoji columns added (Phase 25)
- Endpoints: PUT /api/auth/profile, POST /api/auth/change-password live

### Flutter / APK
- Latest successful build: run#1267, commit `e20a8df` ✅
- All compile errors resolved
- Phases 17–25 fully merged and building clean

### Open Tasks
None — awaiting next task from user.

### Known Data Issues
- DATA-01: All Of Us Are Dead missing E03/E04/E05/E09 — upload to JazzDrive + sync still needed

### Key Rules Reminder
- Never add `androidAttachSurfaceAfterVideoParameters: true`
- Never upgrade `sqflite_sqlcipher` past `3.1.0+1`
- Oracle git pull: always `git stash && git pull && git stash pop`
- Push files SEQUENTIALLY — never parallel (SHA race)
- Use `db.setting(k)` not `db.get_setting(k)`
- `DebugDiagnosticsScreen` is intentionally NOT gated by `kDebugMode`
