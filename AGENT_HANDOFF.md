# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-28 — Home screen redesign complete)

The Home screen visual hierarchy reset is complete and pushed. Every item from the
HOME-REDESIGN-2026 brief is addressed: full-bleed hero (232px, background-blended, dots inside
fade, one CTA), Continue Watching directly below the hero, quieter text filters, reduced default
shelves, compact SIMOSA reminder after the first discovery shelf, simplified shelf headers
(accent bar / count badge / bordered See-All removed), and reduced card decoration throughout.
APK CI is running on commit `65c5588`.

| Status | Count | Task IDs |
|---|---|---|
| ✅ DONE | 2 | HOME-REDESIGN-2026 (`65c5588`), AUTH-UX-2026 (`39343b04`; APK CI `30263339764`) |
| ✅ DONE — prior audit backlog | 14 | SEC-02, SEC-03, BUG-FREE-EP-02, BUG-DOWNLOAD-SIZE, BUG-CATALOG-LISTENER, BUG-EPISODE-SORT, BUG-BINGE-TIMER, BUG-TIMELINE-SYNC, BUG-DB-DELETE-RISK, BUG-VOICE-STUB, BUG-PLAYER-AUTODISPOSE, BUG-PROFILE-PIN, BUG-LOCAL-MEDIA-IO, BUG-XOR-CLOCK |
| ⛔ BLOCKED — external dependency | 3 | SEC-01 (needs domain + TLS cert), SEC-05 (needs release keystore SHA-256), SEC-04 (vault PIN migration) |

### Blocked tasks (no agent can fix these without external input)

- **SEC-01:** Plain HTTP API. Needs a registered domain + cert provisioned on Oracle. Until then `kBaseUrl` stays HTTP — do NOT flip to HTTPS prematurely.
- **SEC-05:** APK tamper-detection placeholder (`RADDFLIX_CERT_SHA256_PLACEHOLDER`). Needs `keytool -printcert -jarfile app-release.apk` run against the release build to extract the real SHA-256.
- **SEC-04:** Vault PIN SHA-256 static salt. Fix (PBKDF2 + per-user random salt) requires a one-time migration that breaks existing vault PINs — all users would need to re-enter their vault PIN.

### This Session's Commits

| SHA | Description |
|---|---|
| `65c5588` | HOME-REDESIGN-2026: complete Home screen redesign — full-bleed hero, reordered shelves, simplified headers, quieter cards, compact SIMOSA reminder |
| `39343b04` | AUTH-UX-2026: complete auth accessibility, autofill, reduced-motion, haptic, and focus/error interaction polish |
| `3b23881` | BUG-LOCAL-MEDIA-IO: batch subtitle checks (20 at a time) to avoid I/O storm |

**CI:** APK build for `65c5588` in progress. Previous build `30263339764` (on `39343b04`) passed.
No Oracle deployment needed — this session changed Flutter code and canonical documentation only.

---

> Full session history: `agent-hub/history/TASK_LOG.md`
