# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-26 — Docs cleanup + 2 more bugs fixed)

All directly-fixable Flutter and server bugs from the 2026-07-26 audit backlog are now resolved or correctly categorised.

| Status | Count | Task IDs |
|---|---|---|
| ✅ DONE (confirmed already fixed in prior sessions) | 7 | SEC-02, SEC-03, BUG-FREE-EP-02, BUG-DOWNLOAD-SIZE, BUG-CATALOG-LISTENER, BUG-EPISODE-SORT, BUG-BINGE-TIMER |
| ✅ DONE (fixed previous session) | 5 | BUG-TIMELINE-SYNC, BUG-DB-DELETE-RISK, BUG-VOICE-STUB, BUG-PLAYER-AUTODISPOSE, BUG-PROFILE-PIN |
| ✅ DONE (fixed this session) | 2 | BUG-LOCAL-MEDIA-IO (`3b23881`), BUG-XOR-CLOCK (already in `request_encoding.py` — verified, no code change needed) |
| ⛔ BLOCKED — external dependency | 3 | SEC-01 (needs domain + TLS cert), SEC-05 (needs release keystore SHA-256), SEC-04 (vault PIN migration — breaks existing PINs) |

### Blocked tasks (no agent can fix these without external input)

- **SEC-01:** Plain HTTP API. Needs a registered domain + cert provisioned on Oracle. Until then `kBaseUrl` stays HTTP — do NOT flip to HTTPS prematurely.
- **SEC-05:** APK tamper-detection placeholder (`RADDFLIX_CERT_SHA256_PLACEHOLDER`). Needs `keytool -printcert -jarfile app-release.apk` run against the release build to extract the real SHA-256.
- **SEC-04:** Vault PIN SHA-256 static salt. Fix (PBKDF2 + per-user random salt) requires a one-time migration that breaks existing vault PINs — all users would need to re-enter their vault PIN.

### This Session's Commits

| SHA | Description |
|---|---|
| `3b23881` | BUG-LOCAL-MEDIA-IO: batch subtitle checks (20 at a time) to avoid I/O storm |
| (docs only) | TASKS.md, infrastructure-constraints.md, AGENT_HANDOFF.md cleanup |

**Oracle:** Deployed to latest after doc commits.

---

> Full session history: `agent-hub/history/TASK_LOG.md`
