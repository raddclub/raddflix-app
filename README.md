# RaddFlix

Pakistani streaming platform — zero-rated on Jazz SIM.
Users pay PKR 149–399/month. Content served from JazzDrive CDN.

## Agent Quick-Links

| File | Purpose |
|------|---------|
| [AGENT_HANDOFF.md](AGENT_HANDOFF.md) | **Read this first** — current state, architecture, rules |
| [ONBOARDING.md](ONBOARDING.md) | SSH setup + connection test in 4 steps |
| [AGENT_PROMPT.md](AGENT_PROMPT.md) | Copy-paste prompt to give any new Replit agent instant context |
| [.agents/tasks/BUG_TRACKER.md](.agents/tasks/BUG_TRACKER.md) | All bugs with root causes and fix status |
| [agent-hub/history/TASK_LOG.md](agent-hub/history/TASK_LOG.md) | Session-by-session history |
| [.agents/PROJECT_RULES.md](.agents/PROJECT_RULES.md) | 10 non-negotiable rules every agent must follow |

## Stack

- **Flutter 3.x** · Dart 3 · Riverpod (state management)
- **DB:** SQLCipher — `sqflite_sqlcipher: 3.1.0+1` (**PINNED** — never upgrade)
- **Video:** `media_kit ^1.1.10` + `media_kit_video ^1.2.4`
- **HTTP:** Dio + custom XOR encoding interceptor
- **Backend:** Flask on Oracle Ubuntu VPS (`92.4.95.252`), supervisord managed as `raddflix_radd`

## Build

APK is auto-built on every push to `main` via GitHub Actions (`.github/workflows/build-apk.yml`).

Latest build: commit `96f8cc1` ✅ SUCCESS (2026-06-18)

## Architecture in One Paragraph

All `/api/*` responses are XOR-encoded. Key = SHA-256 of device ID + UTC day + UTC hour,
truncated to 32 bytes. Oracle server strips base64 padding before sending; client must
re-add it before decoding. This was the root cause of all 5 initial critical bugs. The fix
is 2 lines in `request_encoder.dart`.

See [AGENT_HANDOFF.md](AGENT_HANDOFF.md) for full details.

## Current State (2026-06-18)

All critical bugs fixed. **Comprehensive debug logging** now active across all screens:

- `DebugLogger v2`: 5000-entry buffer, 8MB rotation, session ID, auto-flush every 30s
- Global crash handler: `PlatformDispatcher.onError` catches all uncaught Dart errors
- Global nav logging: `_RaddNavObserver` logs every push/pop/replace
- All screens: lifecycle + tap + navigation events logged
- Player: 13 crash-path checkpoints logged (initPlayer, hwdec, vf=, speed, buffering, errors)
- Debug screen accessible: **Profile → Account → Debug Logs** (one tap, always visible)

---

## Security Notes

- Tokens in Android Keystore (flutter_secure_storage)
- SQLCipher encrypted local DB — key tied to device install
- XOR obfuscation layer over HTTPS
- Debug diagnostics screen: intentionally release-accessible (NOT gated by kDebugMode)
- Frida tamper detection (port 27042 check) — intentional, do not remove
