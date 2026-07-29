# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-29 — SIMOSA card fixes complete)

All open tasks from the HS-01–HS-11 home screen bug batch and BUG-SUB-STYLE-REAPPLY are now complete.

- **BUG-SUB-STYLE-REAPPLY**: All three `_reapplySubtitleStyleAfterLifecycle()` call sites confirmed present in code — `stream.tracks.listen` microtask (`_ps_playback_mixin.dart`), `_applyCompanionSub()`, and `onSubtitleTrackSelected` (subtitle mixin). Marked done (already implemented in a prior session, not previously marked).
- **HS-01**: `_onDismiss()` now async; writes `simosa_dismissed_until` (Unix ms + 24 h) to SharedPrefs; `_loadDismissed()` called in `initState` to restore state across cold starts; `_onClaim()` clears the key so the card shows "Claimed ✓" after claiming.
- **HS-02**: `maxLines: 1, overflow: TextOverflow.ellipsis` added to body Text widget — no more wrapping on 360dp screens.
- **HS-03**: Already resolved by HS-06 (96px bottom clearance, `10aaa85`).
- **HS-04–HS-11**: All done in `10aaa85` (prior session). TASKS.md rows were still marked PENDING — corrected this session.

| Status | Count | Task IDs |
|---|---|---|
| ✅ DONE | 14 | HOME-REDESIGN-2026 (`65c5588`), AUTH-UX-2026 (`39343b04`), HS-01–HS-11 (`10aaa85`, `b6934fb`), BUG-SUB-STYLE-REAPPLY (confirmed at HEAD) |
| ✅ DONE — prior audit backlog | 14 | SEC-02, SEC-03, BUG-FREE-EP-02, BUG-DOWNLOAD-SIZE, BUG-CATALOG-LISTENER, BUG-EPISODE-SORT, BUG-BINGE-TIMER, BUG-TIMELINE-SYNC, BUG-DB-DELETE-RISK, BUG-VOICE-STUB, BUG-PLAYER-AUTODISPOSE, BUG-PROFILE-PIN, BUG-LOCAL-MEDIA-IO, BUG-XOR-CLOCK |
| ⛔ BLOCKED — external dependency | 3 | SEC-01 (needs domain + TLS cert), SEC-05 (needs release keystore SHA-256), SEC-04 (vault PIN migration) |

### Blocked tasks (no agent can fix these without external input)

- **SEC-01:** Plain HTTP API. Needs a registered domain + cert provisioned on Oracle. Until then `kBaseUrl` stays HTTP — do NOT flip to HTTPS prematurely.
- **SEC-05:** APK tamper-detection placeholder (`RADDFLIX_CERT_SHA256_PLACEHOLDER`). Needs `keytool -printcert -jarfile app-release.apk` run against the release build to extract the real SHA-256.
- **SEC-04:** Vault PIN SHA-256 static salt. Fix (PBKDF2 + per-user random salt) requires a one-time migration that breaks existing vault PINs — all users would need to re-enter their vault PIN.

### This Session's Commits

| SHA | Description |
|---|---|
| `b6934fb` | HS-01+HS-02: persist SIMOSA dismiss 24h via SharedPreferences; add maxLines:1 to body text |

**CI:** APK build on `b6934fb` — in progress at time of doc update (check GitHub Actions).
No Oracle deployment needed — Flutter code only.

---

> Full session history: `agent-hub/history/TASK_LOG.md`
