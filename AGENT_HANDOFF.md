# RaddFlix Agent Handoff

> Start at `AGENT_PROMPT.md` first. This file is the canonical "current state" doc — update it
> in place each session instead of creating a new dated handoff/status file.

---

## Current State (2026-07-28 — HS-04–11 home screen bug batch complete)

All 8 pending home screen bugs from the HS-04–HS-11 audit batch are resolved in
`home_screen.dart` (commit `10aaa85`). Fixes: AppBar spacer now uses real device height so greeting
clears the logo; Trending/New Arrivals shelves gated to All tab (no duplicate cards on filter);
bottom clearance raised to 96px; sync banner moved to Positioned overlay over the hero (no layout
shift); hero Transform wrapped in ClipRect (no adjacent-slide bleed); shimmer backdrop added below
hero poster (no black void during load); `_floatCtrl.repeat()` moved to initState (no mid-cycle
jank); category chip row wrapped in ShaderMask right-edge fade (scroll affordance for hidden chips).

| Status | Count | Task IDs |
|---|---|---|
| ✅ DONE | 10 | HOME-REDESIGN-2026 (`65c5588`), AUTH-UX-2026 (`39343b04`), HS-04–HS-11 (`10aaa85`) |
| ✅ DONE — prior audit backlog | 14 | SEC-02, SEC-03, BUG-FREE-EP-02, BUG-DOWNLOAD-SIZE, BUG-CATALOG-LISTENER, BUG-EPISODE-SORT, BUG-BINGE-TIMER, BUG-TIMELINE-SYNC, BUG-DB-DELETE-RISK, BUG-VOICE-STUB, BUG-PLAYER-AUTODISPOSE, BUG-PROFILE-PIN, BUG-LOCAL-MEDIA-IO, BUG-XOR-CLOCK |
| ⛔ BLOCKED — external dependency | 3 | SEC-01 (needs domain + TLS cert), SEC-05 (needs release keystore SHA-256), SEC-04 (vault PIN migration) |

### Blocked tasks (no agent can fix these without external input)

- **SEC-01:** Plain HTTP API. Needs a registered domain + cert provisioned on Oracle. Until then `kBaseUrl` stays HTTP — do NOT flip to HTTPS prematurely.
- **SEC-05:** APK tamper-detection placeholder (`RADDFLIX_CERT_SHA256_PLACEHOLDER`). Needs `keytool -printcert -jarfile app-release.apk` run against the release build to extract the real SHA-256.
- **SEC-04:** Vault PIN SHA-256 static salt. Fix (PBKDF2 + per-user random salt) requires a one-time migration that breaks existing vault PINs — all users would need to re-enter their vault PIN.

### This Session's Commits

| SHA | Description |
|---|---|
| `10aaa85` | HS-04–11: fix 8 pending home screen bugs (AppBar spacer, dupe cards, nav bleed, sync banner, hero clip, shimmer void, float jank, chip fade) |

**CI:** APK build `30384199775` on `10aaa85` ✅ success.
No Oracle deployment needed — Flutter code only.

---

> Full session history: `agent-hub/history/TASK_LOG.md`
