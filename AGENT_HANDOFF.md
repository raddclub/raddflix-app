# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-29 — all SIMOSA card + subtitle style tasks complete)

All open tasks from the home screen audit (HS-01–HS-11) and BUG-SUB-STYLE-REAPPLY are fully done.

- **BUG-SUB-STYLE-REAPPLY**: All three `_reapplySubtitleStyleAfterLifecycle()` call sites confirmed in code — `stream.tracks.listen` microtask, `_applyCompanionSub()`, `onSubtitleTrackSelected`. No code change needed; marked done.
- **HS-01**: SIMOSA dismiss persists 24 h via SharedPreferences. `_onDismiss()` async, writes `simosa_dismissed_until` (Unix ms + 24 h). `_loadDismissed()` in `initState`. `_onClaim()` clears key.
- **HS-02**: Card height reduced from ~83 px to ~58 px. Inner padding 8→6 px, Claim button vertical 7→5 px, dismiss icon 15→12 px / hit-area padding 4→3 px. Body text `maxLines:1` + `overflow:ellipsis`.
- **HS-03**: Already resolved by HS-06 (96 px bottom clearance, `10aaa85`). Marked done.
- **HS-04–HS-11**: Completed in `10aaa85` (prior session). TASKS.md rows were stale — corrected.

| Status | Count | Task IDs |
|---|---|---|
| ✅ DONE | 14 | HOME-REDESIGN-2026 (`65c5588`), AUTH-UX-2026 (`39343b04`), HS-01–HS-11 (`10aaa85`, `b6934fb`, `b5e83bc`), BUG-SUB-STYLE-REAPPLY (confirmed at HEAD) |
| ✅ DONE — prior audit backlog | 14 | SEC-02, SEC-03, BUG-FREE-EP-02, BUG-DOWNLOAD-SIZE, BUG-CATALOG-LISTENER, BUG-EPISODE-SORT, BUG-BINGE-TIMER, BUG-TIMELINE-SYNC, BUG-DB-DELETE-RISK, BUG-VOICE-STUB, BUG-PLAYER-AUTODISPOSE, BUG-PROFILE-PIN, BUG-LOCAL-MEDIA-IO, BUG-XOR-CLOCK |
| ⛔ BLOCKED — external dependency | 3 | SEC-01 (needs domain + TLS cert), SEC-05 (needs release keystore SHA-256), SEC-04 (vault PIN migration) |

### Blocked tasks (no agent can fix these without external input)

- **SEC-01:** Plain HTTP API. Needs a registered domain + cert provisioned on Oracle. Until then `kBaseUrl` stays HTTP — do NOT flip to HTTPS prematurely.
- **SEC-05:** APK tamper-detection placeholder (`RADDFLIX_CERT_SHA256_PLACEHOLDER`). Needs `keytool -printcert -jarfile app-release.apk` run against the release build.
- **SEC-04:** Vault PIN SHA-256 static salt. Fix requires PBKDF2 + per-user random salt but would break all existing vault PINs — migration decision needed from owner.

### This Session's Commits

| SHA | Description |
|---|---|
| `b6934fb` | HS-01+HS-02 partial: persist SIMOSA dismiss 24h; add maxLines:1 to body text |
| `b5e83bc` | HS-02 complete: reduce inner padding, Claim button padding, dismiss icon size |

**CI:** APK build on `b5e83bc` ✅ success.
No Oracle deployment needed — Flutter code only.

---

> Full session history: `agent-hub/history/TASK_LOG.md`
